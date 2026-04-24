import Foundation
import Logging

actor CodexRPCTransport {
    private let config: CodexConfig
    private let logger: Logger
    private let exec: CodexRPCExec
    private var outboundContinuation: AsyncStream<String>.Continuation?
    private var runTask: Task<Void, Never>?
    private var requestCounter = 0
    private var pendingRequests: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var pendingNotifications: [CodexNotification] = []
    private var pendingNotificationContinuations: [CheckedContinuation<CodexNotification, Error>] = []
    private var terminalError: Error?
    private var stderrTail: [String] = []
    private var isClosing = false

    init(config: CodexConfig, logger: Logger) {
        self.config = config
        self.logger = logger
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
            logger.debug("RPC transport already running")
            return
        }
        isClosing = false
        logger.info("Starting RPC transport")

        let streamPair = AsyncStream.makeStream(of: String.self)
        outboundContinuation = streamPair.continuation

        let exec = self.exec
        runTask = Task {
            do {
                try await exec.runRPCServer(
                    outgoingMessages: streamPair.stream,
                    onStdoutLine: { [weak self] line in
                        guard let self else { return }
                        await self.handleIncomingLine(line)
                    },
                    onStderrLine: { [weak self] line in
                        guard let self else { return }
                        await self.recordStderr(line)
                    }
                )
                finishTransport(error: nil)
            } catch {
                finishTransport(error: error)
            }
        }
    }

    func close() {
        isClosing = true
        logger.info("Closing RPC transport")
        outboundContinuation?.finish()
        outboundContinuation = nil
        runTask?.cancel()
        runTask = nil

        let failure = terminalError ?? makeTransportClosedError()
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: failure)
        }
        pendingRequests.removeAll()

        for continuation in pendingNotificationContinuations {
            continuation.resume(throwing: failure)
        }
        pendingNotificationContinuations.removeAll()
    }

    func request(method: String, params: JSONObject) async throws -> JSONValue {
        if let terminalError {
            throw terminalError
        }

        let id = nextRequestID()
        logger.debug(
            "Sending RPC request",
            metadata: [
                "method": .string(method),
                "request_id": .string(id),
            ]
        )
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
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
                continuation.resume(throwing: error)
            }
        }
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
        if !pendingNotifications.isEmpty {
            return pendingNotifications.removeFirst()
        }
        if let terminalError {
            throw terminalError
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingNotificationContinuations.append(continuation)
        }
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
        requestCounter += 1
        return "swift-codex-\(requestCounter)"
    }

    private func recordStderr(_ line: String) {
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

    private func finishTransport(error: Error?) {
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

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: failure)
        }
        pendingRequests.removeAll()

        for continuation in pendingNotificationContinuations {
            continuation.resume(throwing: failure)
        }
        pendingNotificationContinuations.removeAll()
    }

    private func handleIncomingLine(_ line: String) async {
        do {
            let data = Data(line.utf8)
            let message = try JSONDecoder().decode(JSONObject.self, from: data)

            if let method = message.stringValue(forKey: "method") {
                if let requestID = message.stringValue(forKey: "id") {
                    try await handleServerRequest(
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
                pendingRequests.removeValue(forKey: requestID)?.resume(
                    throwing: CodexRPCErrorMapper.map(code: error.code, message: error.message, data: error.data)
                )
                return
            }

            logger.debug("Received RPC response", metadata: ["request_id": .string(requestID)])
            pendingRequests.removeValue(forKey: requestID)?.resume(returning: message["result"] ?? .null)
        } catch {
            finishTransport(error: error)
        }
    }

    private func handleServerRequest(method: String, requestID: String, params: JSONValue?) async throws {
        logger.debug(
            "Handling server request",
            metadata: [
                "method": .string(method),
                "request_id": .string(requestID),
            ]
        )
        let result = await makeServerRequestResult(method: method, params: params)
        try send(
            .object([
                "id": .string(requestID),
                "result": result.jsonValue,
            ])
        )
    }

    private func makeServerRequestResult(method: String, params: JSONValue?) async -> ServerRequestResult {
        if let serverRequestHandler = config.serverRequestHandler {
            let request = makeServerRequest(method: method, params: params)
            logger.info("Dispatching custom server request handler", metadata: ["method": .string(method)])
            return await serverRequestHandler(request)
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
        let notification = CodexNotification(method: method, params: params)
        logNotification(notification)
        if !pendingNotificationContinuations.isEmpty {
            let continuation = pendingNotificationContinuations.removeFirst()
            continuation.resume(returning: notification)
            return
        }
        pendingNotifications.append(notification)
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

    private func makeServerRequest(method: String, params: JSONValue?) -> ServerRequest {
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
