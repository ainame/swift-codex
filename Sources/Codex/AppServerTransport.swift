import Foundation
import Logging

actor CodexRPCTransport {
    private let config: CodexConfig
    private let logger: Logger
    private let exec: CodexRPCExec
    private var outboundContinuation: AsyncStream<String>.Continuation?
    private var runTask: Task<Void, Never>?
    private var processGeneration = UUID()
    private var requestCounter = 0
    private var callerRequestIDs: Set<String> = []
    private struct PendingRequest {
        let token: UUID
        let continuation: CheckedContinuation<JSONValue, Error>
        /// Set for `turn/start`, whose response opens a turn stream route.
        var turnStartThreadID: String?
    }
    private var pendingRequests: [String: PendingRequest] = [:]
    // Handlers outlive the input callback, so the transport owns and cancels
    // these tasks explicitly. All registry access remains actor-isolated.
    private var serverRequestTasks: [JSONValue: (token: UUID, task: Task<Void, Never>)] = [:]
    // Raw notification queue. Every notification is copied here and, when
    // thread scoped, into the turn router; neither consumer drains the other.
    private var pendingNotifications: [CodexNotification] = []
    private var droppedRawNotifications = 0
    private var pendingNotificationContinuations: [(token: UUID, continuation: CheckedContinuation<CodexNotification, Error>)] = []
    private var turnRouter: TurnStreamRouter
    private var terminalError: Error?
    private var stderrTail: [String] = []
    private var isClosing = false

    init(config: CodexConfig, logger: Logger) {
        self.config = config
        self.logger = logger
        self.turnRouter = TurnStreamRouter(limits: config.notificationBufferLimits)
        self.exec = CodexRPCExec(
            executablePathOverride: config.codexPathOverride,
            launchArgsOverride: config.launchArgsOverride,
            environmentOverride: config.environment,
            configOverrides: config.config,
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            workingDirectory: config.workingDirectory,
            logger: logger.codexScope("exec")
        )
    }

    func startProcess() async throws {
        if runTask != nil {
            if let terminalError { throw terminalError }
            logger.debug("RPC transport already running")
            return
        }
        isClosing = false
        processGeneration = UUID()
        terminalError = nil
        stderrTail.removeAll()
        pendingNotifications.removeAll()
        droppedRawNotifications = 0
        callerRequestIDs.removeAll()
        logger.info("Starting RPC transport")

        let streamPair = AsyncStream.makeStream(of: String.self)
        outboundContinuation = streamPair.continuation

        let exec = self.exec
        let generation = processGeneration
        runTask = Task {
            do {
                try await exec.runRPCServer(
                    outgoingMessages: streamPair.stream,
                    onStdoutLine: { [weak self] line in
                        guard let self else { return }
                        await self.handleIncomingLine(line, generation: generation)
                    },
                    onStderrLine: { [weak self] line in
                        guard let self else { return }
                        await self.recordStderr(line, generation: generation)
                    }
                )
                finishTransport(error: nil, generation: generation)
            } catch {
                finishTransport(error: error, generation: generation)
            }
        }
    }

    func close() {
        isClosing = true
        processGeneration = UUID()
        cancelServerRequests()
        logger.info("Closing RPC transport")
        outboundContinuation?.finish()
        outboundContinuation = nil
        runTask?.cancel()
        runTask = nil

        let failure = terminalError ?? makeTransportClosedError()
        terminalError = failure
        for entry in pendingRequests.values {
            entry.continuation.resume(throwing: failure)
        }
        pendingRequests.removeAll()

        for entry in pendingNotificationContinuations {
            entry.continuation.resume(throwing: failure)
        }
        pendingNotificationContinuations.removeAll()
        turnRouter.failAll(failure)
    }

    func request(method: String, params: JSONObject, requestID: String? = nil, cancelOnCancellation: String? = nil) async throws -> JSONValue {
        if let terminalError {
            throw terminalError
        }

        let id = requestID ?? nextRequestID()
        guard pendingRequests[id] == nil else {
            throw CodexError.invalidResponse("Duplicate active client request ID: \(id)")
        }
        if let requestID, requestID.hasPrefix("swift-codex-") { callerRequestIDs.insert(requestID) }
        let token = UUID()
        logger.debug(
            "Sending RPC request",
            metadata: [
                "method": .string(method),
                "request_id": .string(id),
            ]
        )
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let turnStartThreadID = method == "turn/start" ? params.stringValue(forKey: "threadId") : nil
                pendingRequests[id] = PendingRequest(token: token, continuation: continuation, turnStartThreadID: turnStartThreadID)
                if let turnStartThreadID {
                    turnRouter.beginTurnStart(requestID: id, threadID: turnStartThreadID)
                }
                do {
                    try send(
                        .object([
                            "id": .string(id),
                            "method": .string(method),
                            "params": .object(params),
                        ])
                    )
                } catch {
                    pendingRequests.removeValue(forKey: id)
                    turnRouter.cancelTurnStart(requestID: id)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelRequest(id, token: token, cancelMethod: cancelOnCancellation) }
        }
    }

    private func cancelRequest(_ id: String, token: UUID, cancelMethod: String?) {
        guard pendingRequests[id]?.token == token else { return }
        turnRouter.cancelTurnStart(requestID: id)
        pendingRequests.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
        if let cancelMethod {
            // Best effort control RPC, on this same process only. Its reply needs
            // no waiter; closing/reopening cannot resurrect the cancelled work.
            try? send(["id": .string(nextRequestID()), "method": .string(cancelMethod), "params": ["requestId": .string(id)]])
        }
    }

    private func cancelServerRequests() {
        for entry in serverRequestTasks.values { entry.task.cancel() }
        serverRequestTasks.removeAll()
    }

    func notify(method: String, params: JSONObject) throws {
        logger.debug("Sending RPC notification", metadata: ["method": .string(method)])
        try send(
            .object([
                "method": .string(method),
                "params": .object(params),
            ])
        )
    }

    func nextNotification() async throws -> CodexNotification {
        try Task.checkCancellation()
        if droppedRawNotifications > 0 {
            let dropped = droppedRawNotifications
            droppedRawNotifications = 0
            throw CodexError.notificationBacklogOverflow(droppedCount: dropped)
        }
        if !pendingNotifications.isEmpty {
            return pendingNotifications.removeFirst()
        }
        if let terminalError {
            throw terminalError
        }

        let token = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pendingNotificationContinuations.append((token, continuation))
            }
        } onCancel: {
            Task { await self.cancelNotificationWait(token) }
        }
    }

    /// Attaches `continuation` as the only consumer of a turn's notifications,
    /// replaying anything buffered since the `turn/start` response.
    func attachTurnStream(_ key: TurnKey, continuation: TurnStreamRouter.Continuation) throws {
        let token = UUID()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.detachTurnStream(key, token: token) }
        }
        do {
            try turnRouter.attach(key, token: token, continuation: continuation)
        } catch CodexError.turnStreamUnavailable(_, _, let reason)
            where (reason == .unknownTurn || reason == .transportClosed) && terminalError != nil {
            // A closed transport explains an unknown or interrupted turn better.
            throw terminalError ?? CodexError.transportClosed
        }
        logger.debug("Attached turn stream", metadata: ["thread_id": .string(key.threadID), "turn_id": .string(key.turnID)])
    }

    private func detachTurnStream(_ key: TurnKey, token: UUID) {
        turnRouter.detach(key, token: token)
    }

    private func cancelNotificationWait(_ token: UUID) {
        guard let index = pendingNotificationContinuations.firstIndex(where: { $0.token == token }) else { return }
        pendingNotificationContinuations.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func send(_ payload: JSONValue) throws {
        guard let continuation = outboundContinuation else {
            throw terminalError ?? makeTransportClosedError()
        }
        let data = try JSONEncoder().encode(payload)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CodexError.invalidResponse("Failed to encode JSON-RPC payload")
        }
        continuation.yield(line)
    }

    private func nextRequestID() -> String {
        repeat { requestCounter += 1 } while callerRequestIDs.contains("swift-codex-\(requestCounter)") || pendingRequests["swift-codex-\(requestCounter)"] != nil
        return "swift-codex-\(requestCounter)"
    }

    private func recordStderr(_ line: String, generation: UUID) {
        guard processGeneration == generation else { return }
        logger.debug("RPC stderr", metadata: ["stderr_line": .string(line)])
        stderrTail.append(line)
        if stderrTail.count > 400 {
            stderrTail.removeFirst(stderrTail.count - 400)
        }
    }

    private func makeTransportClosedError() -> CodexError {
        let stderrTail = stderrTailText()
        guard !stderrTail.isEmpty else {
            return .transportClosed
        }
        return .transportClosedWithStderrTail(stderrTail)
    }

    private func stderrTailText() -> String {
        stderrTail.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishTransport(error: Error?, generation: UUID? = nil) {
        if let generation, processGeneration != generation { return }
        if generation == nil { runTask?.cancel() }
        cancelServerRequests()
        outboundContinuation?.finish()
        outboundContinuation = nil
        if isClosing {
            terminalError = terminalError ?? makeTransportClosedError()
        } else if let error {
            terminalError = error
            logger.error("RPC transport failed", metadata: ["error": .string(String(describing: error))])
        } else if terminalError == nil {
            terminalError = makeTransportClosedError()
            logger.warning("RPC transport closed unexpectedly", metadata: stderrTailLogMetadata())
        }

        let failure = terminalError ?? makeTransportClosedError()

        for entry in pendingRequests.values {
            entry.continuation.resume(throwing: failure)
        }
        pendingRequests.removeAll()

        for entry in pendingNotificationContinuations {
            entry.continuation.resume(throwing: failure)
        }
        pendingNotificationContinuations.removeAll()
        turnRouter.failAll(failure)
    }

    private func handleIncomingLine(_ line: String, generation: UUID) async {
        guard processGeneration == generation, terminalError == nil, !isClosing else { return }
        do {
            let data = Data(line.utf8)
            let message = try JSONDecoder().decode(JSONObject.self, from: data)

            if let method = message.stringValue(forKey: "method") {
                if let requestID = message["id"] {
                    guard isValidServerRequestID(requestID) else {
                        throw CodexError.invalidRequestID
                    }
                    scheduleServerRequest(
                        method: method,
                        requestID: requestID,
                        params: message["params"]
                    )
                } else {
                    handleNotification(
                        method: method,
                        params: message["params"] ?? .object([:])
                    )
                }
                return
            }

            guard let requestID = message.stringValue(forKey: "id") else {
                throw CodexError.invalidRequestID
            }

            if let errorPayload = message["error"] {
                let error = try decode(JSONRPCErrorPayload.self, from: errorPayload)
                logger.error(
                    "Received JSON-RPC error response",
                    metadata: [
                        "request_id": .string(requestID),
                        "error_code": .string(String(error.code)),
                        "error_message": .string(error.message),
                    ]
                )
                turnRouter.cancelTurnStart(requestID: requestID)
                pendingRequests.removeValue(forKey: requestID)?.continuation.resume(
                    throwing: CodexRPCErrorMapper.map(code: error.code, message: error.message, data: error.data)
                )
                return
            }

            logger.debug("Received RPC response", metadata: ["request_id": .string(requestID)])
            let result = message["result"] ?? .null
            guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
            if let threadID = pending.turnStartThreadID {
                // Open the route before any later input line is processed, so
                // early turn events are replayed to a stream attached later.
                if let turnID = result.objectValue?["turn"]?.objectValue?.stringValue(forKey: "id") {
                    turnRouter.completeTurnStart(requestID: requestID, key: TurnKey(threadID: threadID, turnID: turnID))
                } else {
                    turnRouter.cancelTurnStart(requestID: requestID)
                }
            }
            pending.continuation.resume(returning: result)
        } catch {
            finishTransport(error: error)
        }
    }

    private func isValidServerRequestID(_ id: JSONValue) -> Bool {
        switch id {
        case .string: return true
        case .number(let value):
            return value.isFinite && value.rounded() == value
        default: return false
        }
    }

    private func scheduleServerRequest(method: String, requestID: JSONValue, params: JSONValue?) {
        guard serverRequestTasks[requestID] == nil else {
            finishTransport(error: CodexError.invalidResponse("Duplicate active server request ID"))
            return
        }
        let token = UUID()
        let task = Task {
            await handleServerRequest(method: method, requestID: requestID, params: params, token: token)
        }
        serverRequestTasks[requestID] = (token, task)
    }

    private func handleServerRequest(method: String, requestID: JSONValue, params: JSONValue?, token: UUID) async {
        logger.debug(
            "Handling server request",
            metadata: [
                "method": .string(method),
                "request_id": .string(String(describing: requestID)),
            ]
        )
        let result = await makeServerRequestResult(method: method, params: params)
        // A handler may ignore cancellation. Never let it reply after close,
        // resolution by another client, or replacement of its registry entry.
        guard !Task.isCancelled, serverRequestTasks[requestID]?.token == token else {
            logger.debug("Discarding cancelled server request response", metadata: ["method": .string(method)])
            return
        }
        serverRequestTasks.removeValue(forKey: requestID)
        do { try send(
            .object([
                "id": requestID,
                result.isError ? "error" : "result": result.jsonValue,
            ])
        ) } catch {
            // An invalid handler payload (for example NaN) must fail only this
            // request. A failure to send even the error closes the transport.
            do {
                try send(["id": requestID, "error": ["code": -32603, "message": "Server request handler failed"]])
            } catch { finishTransport(error: error) }
        }
    }

    private func makeServerRequestResult(method: String, params: JSONValue?) async -> ServerRequestResult {
        if let serverRequestHandler = config.serverRequestHandler {
            let request = makeServerRequest(method: method, params: params)
            logger.info("Dispatching custom server request handler", metadata: ["method": .string(method)])
            return await serverRequestHandler(request)
        }

        let typedRequest: ServerRequest?
        do {
            typedRequest = try decodeAdditionalServerRequest(method: method, params: params)
        } catch {
            return .error(code: -32602, message: "Invalid params for \(method)")
        }
        if let typedRequest {
            do { return try await dispatchAdditionalServerRequest(typedRequest, method: method) }
            catch { return .error(code: -32603, message: "Server request handler failed") }
        }

        if method == "item/tool/call" {
            guard let params, let request = try? decode(DynamicToolCallParams.self, from: params) else {
                return .dynamicToolCall(DynamicToolCallResponse(contentItems: [], success: false))
            }
            if let handler = config.dynamicToolCallHandler {
                return .dynamicToolCall(await handler(request))
            }
            return .dynamicToolCall(DynamicToolCallResponse(
                contentItems: [.inputText(InputTextDynamicToolCallOutputContentItem(
                    text: "No dynamic tool handler registered for \(request.tool)", type: .inputText
                ))], success: false
            ))
        }
        let objectParams = params?.objectValue
        switch method {
        case "item/commandExecution/requestApproval":
            let request = CommandApprovalRequest(
                threadID: objectParams?.stringValue(forKey: "threadId") ?? "",
                turnID: objectParams?.stringValue(forKey: "turnId") ?? "",
                itemID: objectParams?.stringValue(forKey: "itemId") ?? "",
                approvalID: objectParams?.stringValue(forKey: "approvalId"),
                command: objectParams?.stringValue(forKey: "command"),
                workingDirectory: objectParams?.stringValue(forKey: "cwd"),
                reason: objectParams?.stringValue(forKey: "reason")
            )
            let decision = await config.commandApprovalHandler(request)
            logger.info(
                "Resolved command approval request",
                metadata: [
                    "thread_id": .string(request.threadID),
                    "turn_id": .string(request.turnID),
                    "item_id": .string(request.itemID),
                    "approval_id": request.approvalID.map(Logger.MetadataValue.string),
                    "decision": .string(decision.rawValue),
                ].compactMapValues { $0 }
            )
            return .approval(decision)
        case "item/fileChange/requestApproval":
            let request = FileChangeApprovalRequest(
                threadID: objectParams?.stringValue(forKey: "threadId") ?? "",
                turnID: objectParams?.stringValue(forKey: "turnId") ?? "",
                itemID: objectParams?.stringValue(forKey: "itemId") ?? "",
                reason: objectParams?.stringValue(forKey: "reason"),
                grantRoot: objectParams?.stringValue(forKey: "grantRoot")
            )
            let decision = await config.fileChangeApprovalHandler(request)
            logger.info(
                "Resolved file change approval request",
                metadata: [
                    "thread_id": .string(request.threadID),
                    "turn_id": .string(request.turnID),
                    "item_id": .string(request.itemID),
                    "decision": .string(decision.rawValue),
                ]
            )
            return .approval(decision)
        default:
            logger.warning("Returning default empty response for unknown server request", metadata: ["method": .string(method)])
            return .json(.object([:]))
        }
    }

    private func handleNotification(method: String, params: JSONValue) {
        if method == "serverRequest/resolved", let id = params.objectValue?["requestId"] {
            serverRequestTasks.removeValue(forKey: id)?.task.cancel()
        }
        let notification = CodexNotification(method: method, params: params)
        logNotification(notification)
        turnRouter.route(notification)
        if !pendingNotificationContinuations.isEmpty {
            let continuation = pendingNotificationContinuations.removeFirst()
            continuation.continuation.resume(returning: notification)
            return
        }
        pendingNotifications.append(notification)
        let overflow = pendingNotifications.count - turnRouter.limits.maxRawBacklog
        if overflow > 0 {
            if droppedRawNotifications == 0 {
                logger.debug("Raw notification backlog is full; dropping oldest unread notifications")
            }
            pendingNotifications.removeFirst(overflow)
            droppedRawNotifications += overflow
        }
    }

    private func logNotification(_ notification: CodexNotification) {
        let metadata = [
            "method": Logger.MetadataValue.string(notification.method),
            "thread_id": notification.threadID.map(Logger.MetadataValue.string),
            "turn_id": notification.turnID.map(Logger.MetadataValue.string),
            "item_id": notification.itemID.map(Logger.MetadataValue.string),
            "item_type": notification.itemType.map(Logger.MetadataValue.string),
        ].compactMapValues { $0 }

        switch notificationLevel(for: notification.method) {
        case .error:
            logger.error("Received RPC notification", metadata: metadata)
        case .warning:
            logger.warning("Received RPC notification", metadata: metadata)
        case .info:
            logger.info("Received RPC notification", metadata: metadata)
        default:
            logger.debug("Received RPC notification", metadata: metadata)
        }
    }

    private func notificationLevel(for method: String) -> Logger.Level {
        if method.contains("error") {
            return .error
        }
        if method.contains("warning") {
            return .warning
        }
        return .debug
    }

    private func stderrTailLogMetadata() -> Logger.Metadata {
        let stderrTail = stderrTailText()
        if stderrTail.isEmpty {
            return [:]
        }
        return ["stderr_tail": .string(stderrTail)]
    }

    private func decodeAdditionalServerRequest(method: String, params: JSONValue?) throws -> ServerRequest? {
        let value = params ?? .null
        switch method {
        case "item/tool/requestUserInput": return .userInput(try decode(ToolRequestUserInputParams.self, from: value))
        case "mcpServer/elicitation/request":
            let request = try decode(McpServerElicitationRequestParams.self, from: value)
            if case .unknown = request { throw CodexError.invalidResponse("Unsupported elicitation params") }
            return .mcpElicitation(request)
        case "item/permissions/requestApproval": return .permissionsApproval(try decode(PermissionsRequestApprovalParams.self, from: value))
        case "account/chatgptAuthTokens/refresh": return .authTokensRefresh(try decode(ChatgptAuthTokensRefreshParams.self, from: value))
        case "attestation/generate": return .attestation(try decode(AttestationGenerateParams.self, from: value))
        case "currentTime/read": return .currentTime(try decode(CurrentTimeReadParams.self, from: value))
        default: return nil
        }
    }

    private func dispatchAdditionalServerRequest(_ request: ServerRequest, method: String) async throws -> ServerRequestResult {
        switch request {
        case .userInput(let params):
            if let handler = config.userInputHandler { return .userInput(try await handler(params)) }
        case .mcpElicitation(let params):
            if let handler = config.mcpElicitationHandler { return .mcpElicitation(try await handler(params)) }
        case .permissionsApproval(let params):
            if let handler = config.permissionsApprovalHandler { return .permissionsApproval(try await handler(params)) }
        case .authTokensRefresh(let params):
            if let handler = config.authTokensRefreshHandler { return .authTokensRefresh(try await handler(params)) }
        case .attestation(let params):
            if let handler = config.attestationHandler { return .attestation(try await handler(params)) }
        case .currentTime(let params):
            if let handler = config.currentTimeHandler { return .currentTime(try await handler(params)) }
        default: break
        }
        return .error(code: -32601, message: "No handler registered for \(method)")
    }

    private func makeServerRequest(method: String, params: JSONValue?) -> ServerRequest {
        if let request = try? decodeAdditionalServerRequest(method: method, params: params) { return request }
        let objectParams = params?.objectValue
        switch method {
        case "item/commandExecution/requestApproval":
            return .commandApproval(
                CommandApprovalRequest(
                    threadID: objectParams?.stringValue(forKey: "threadId") ?? "",
                    turnID: objectParams?.stringValue(forKey: "turnId") ?? "",
                    itemID: objectParams?.stringValue(forKey: "itemId") ?? "",
                    approvalID: objectParams?.stringValue(forKey: "approvalId"),
                    command: objectParams?.stringValue(forKey: "command"),
                    workingDirectory: objectParams?.stringValue(forKey: "cwd"),
                    reason: objectParams?.stringValue(forKey: "reason")
                )
            )
        case "item/tool/call":
            if let params, let request = try? decode(DynamicToolCallParams.self, from: params) {
                return .dynamicToolCall(request)
            }
            return .unknown(method: method, params: params)
        case "item/fileChange/requestApproval":
            return .fileChangeApproval(
                FileChangeApprovalRequest(
                    threadID: objectParams?.stringValue(forKey: "threadId") ?? "",
                    turnID: objectParams?.stringValue(forKey: "turnId") ?? "",
                    itemID: objectParams?.stringValue(forKey: "itemId") ?? "",
                    reason: objectParams?.stringValue(forKey: "reason"),
                    grantRoot: objectParams?.stringValue(forKey: "grantRoot")
                )
            )
        default:
            return .unknown(method: method, params: params)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct JSONRPCErrorPayload: Decodable {
    var code: Int
    var message: String
    var data: JSONValue?
}

enum CodexRPCErrorMapper {
    static func map(code: Int, message: String, data: JSONValue?) -> CodexError {
        switch code {
        case -32700:
            return .parseError(message: message, data: data)
        case -32600:
            return .invalidRequest(message: message, data: data)
        case -32601:
            return .methodNotFound(message: message, data: data)
        case -32602:
            return .invalidParams(message: message, data: data)
        case -32603:
            return .internalRPC(message: message, data: data)
        case -32099 ... -32000:
            if containsRetryLimitText(message) {
                return .retryLimitExceeded(message: message, data: data)
            }
            if isServerOverloaded(data) {
                return .serverBusy(message: message, data: data)
            }
            return .jsonRPCError(code: code, message: message, data: data)
        default:
            return .jsonRPCError(code: code, message: message, data: data)
        }
    }

    static func containsRetryLimitText(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("retry limit") || lowered.contains("too many failed attempts")
    }

    static func isServerOverloaded(_ data: JSONValue?) -> Bool {
        guard let data else {
            return false
        }
        switch data {
        case .string(let value):
            return value.lowercased() == "server_overloaded" || value.lowercased() == "serveroverloaded"
        case .object(let object):
            let directKeys = ["codex_error_info", "codexErrorInfo", "errorInfo"]
            for key in directKeys {
                if isServerOverloaded(object[key]) {
                    return true
                }
            }
            for value in object.values where isServerOverloaded(value) {
                return true
            }
            return false
        case .array(let values):
            return values.contains(where: isServerOverloaded)
        default:
            return false
        }
    }
}
