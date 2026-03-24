import Foundation

actor AppServerTransport {
    private struct ActiveConsumer {
        var threadID: String
        var turnID: String
        var continuation: AsyncThrowingStream<AppServerEvent, Error>.Continuation
    }

    private let config: AppServerConfig
    private let exec: AppServerExec
    private var outboundStream: AsyncStream<String>?
    private var outboundContinuation: AsyncStream<String>.Continuation?
    private var runTask: Task<Void, Never>?
    private var requestCounter = 0
    private var pendingRequests: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var pendingEvents: [BufferedEvent] = []
    private var activeConsumer: ActiveConsumer?
    private var terminalError: Error?
    private var metadata: AppServerMetadata?
    private var stderrTail: [String] = []

    init(config: AppServerConfig) {
        self.config = config
        self.exec = AppServerExec(
            executablePathOverride: config.codexPathOverride,
            environmentOverride: config.environment,
            configOverrides: config.config,
            baseURL: config.baseURL,
            apiKey: config.apiKey
        )
    }

    func start() async throws -> AppServerMetadata {
        if let metadata {
            return metadata
        }

        let streamPair = AsyncStream.makeStream(of: String.self)
        outboundStream = streamPair.stream
        outboundContinuation = streamPair.continuation

        let exec = self.exec
        let outgoingMessages = streamPair.stream
        runTask = Task {
            do {
                try await exec.runAppServer(
                    outgoingMessages: outgoingMessages,
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

        let initializeResult = try await request(
            method: "initialize",
            params: .object([
                "clientInfo": .object([
                    "name": .string(config.clientName),
                    "title": .string(config.clientTitle),
                    "version": .string(config.clientVersion),
                ]),
                "capabilities": .object([
                    "experimentalApi": .bool(config.experimentalAPI),
                ]),
            ])
        )
        let initialize = try decode(AppServerInitializeResponse.self, from: initializeResult)
        let metadata = try initialize.normalizedMetadata()
        self.metadata = metadata
        try notify(method: "initialized", params: .object([:]))
        return metadata
    }

    func close() {
        outboundContinuation?.finish()
        outboundContinuation = nil
        outboundStream = nil
        runTask?.cancel()
        runTask = nil
    }

    func startThread(options: AppServerThreadOptions) async throws -> String {
        let response = try await request(
            method: "thread/start",
            params: .object(makeThreadStartParams(options))
        )
        return try decode(AppServerThreadStartResponse.self, from: response).thread.id
    }

    func resumeThread(id: String, options: AppServerThreadOptions) async throws -> String {
        let response = try await request(
            method: "thread/resume",
            params: .object(makeThreadResumeParams(threadID: id, options: options))
        )
        return try decode(AppServerThreadResumeResponse.self, from: response).thread.id
    }

    func startTurn(threadID: String, input: [UserInput], options: TurnOptions) async throws -> String {
        let response = try await request(
            method: "turn/start",
            params: .object(makeTurnStartParams(threadID: threadID, input: input, options: options))
        )
        return try decode(AppServerTurnStartResponse.self, from: response).turn.id
    }

    func openTurnStream(threadID: String, turnID: String) throws -> AsyncThrowingStream<AppServerEvent, Error> {
        if let activeConsumer {
            throw AppServerError.concurrentTurnConsumer(
                activeTurnID: activeConsumer.turnID,
                requestedTurnID: turnID
            )
        }
        if let terminalError {
            throw terminalError
        }

        let buffered = drainBufferedEvents(threadID: threadID, turnID: turnID)
        let hasTerminal = buffered.contains { $0.isTerminal }

        return AsyncThrowingStream { continuation in
            for event in buffered.map(\.event) {
                continuation.yield(event)
            }
            guard !hasTerminal else {
                continuation.finish()
                return
            }
            activeConsumer = ActiveConsumer(
                threadID: threadID,
                turnID: turnID,
                continuation: continuation
            )
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.releaseConsumer(turnID: turnID)
                }
            }
        }
    }

    private func releaseConsumer(turnID: String) {
        guard activeConsumer?.turnID == turnID else {
            return
        }
        activeConsumer = nil
    }

    private func request(method: String, params: JSONValue) async throws -> JSONValue {
        if let terminalError {
            throw terminalError
        }

        let id = nextRequestID()
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            do {
                try send(
                    .object([
                        "id": .string(id),
                        "method": .string(method),
                        "params": params,
                    ])
                )
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func notify(method: String, params: JSONValue) throws {
        try send(
            .object([
                "method": .string(method),
                "params": params,
            ])
        )
    }

    private func send(_ payload: JSONValue) throws {
        guard let continuation = outboundContinuation else {
            throw terminalError ?? AppServerError.transportClosed
        }
        let data = try JSONEncoder().encode(payload)
        guard let line = String(data: data, encoding: .utf8) else {
            throw AppServerError.invalidResponse("Failed to encode JSON-RPC payload")
        }
        continuation.yield(line)
    }

    private func nextRequestID() -> String {
        requestCounter += 1
        return "swift-codex-\(requestCounter)"
    }

    private func finishTransport(error: Error?) {
        if let error {
            terminalError = error
        } else if terminalError == nil {
            terminalError = AppServerError.transportClosed
        }

        let failure = terminalError ?? AppServerError.transportClosed

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: failure)
        }
        pendingRequests.removeAll()

        if let activeConsumer {
            activeConsumer.continuation.finish(throwing: failure)
            self.activeConsumer = nil
        }
    }

    private func recordStderr(_ line: String) {
        stderrTail.append(line)
        if stderrTail.count > 40 {
            stderrTail.removeFirst(stderrTail.count - 40)
        }
    }

    private func handleIncomingLine(_ line: String) async {
        do {
            let data = Data(line.utf8)
            let message = try JSONDecoder().decode(JSONObject.self, from: data)
            if let method = message.string(forKey: "method") {
                if let requestID = message.string(forKey: "id") {
                    try await handleServerRequest(
                        method: method,
                        requestID: requestID,
                        params: message["params"] ?? .object([:])
                    )
                } else {
                    try handleNotification(
                        method: method,
                        params: message["params"] ?? .object([:])
                    )
                }
                return
            }

            guard let requestID = message.string(forKey: "id") else {
                throw AppServerError.invalidRequestID
            }

            if let errorPayload = message["error"] {
                let error = try decode(JSONRPCErrorPayload.self, from: errorPayload)
                pendingRequests.removeValue(forKey: requestID)?.resume(
                    throwing: AppServerError.jsonRPCError(code: error.code, message: error.message)
                )
                return
            }

            pendingRequests.removeValue(forKey: requestID)?.resume(returning: message["result"] ?? .null)
        } catch {
            finishTransport(error: error)
        }
    }

    private func handleServerRequest(method: String, requestID: String, params: JSONValue) async throws {
        switch method {
        case "item/commandExecution/requestApproval":
            let request = try decode(WireCommandApprovalParams.self, from: params).toPublicRequest()
            let decision = await config.commandApprovalHandler(request)
            try send(
                .object([
                    "id": .string(requestID),
                    "result": .object([
                        "decision": .string(decision == .approve ? "accept" : "decline"),
                    ]),
                ])
            )
        case "item/fileChange/requestApproval":
            let request = try decode(WireFileChangeApprovalParams.self, from: params).toPublicRequest()
            let decision = await config.fileChangeApprovalHandler(request)
            try send(
                .object([
                    "id": .string(requestID),
                    "result": .object([
                        "decision": .string(decision == .approve ? "accept" : "decline"),
                    ]),
                ])
            )
        default:
            let error = AppServerError.unsupportedServerRequest(method)
            finishTransport(error: error)
            throw error
        }
    }

    private func handleNotification(method: String, params: JSONValue) throws {
        let bufferedEvent: BufferedEvent?

        switch method {
        case "thread/started":
            let notification = try decode(WireThreadStartedNotification.self, from: params)
            bufferedEvent = .init(
                threadID: notification.thread.id,
                turnID: nil,
                event: .threadStarted(notification.thread.id)
            )
        case "turn/started":
            let notification = try decode(WireTurnStartedNotification.self, from: params)
            bufferedEvent = .init(
                threadID: notification.threadID,
                turnID: notification.turn.id,
                event: .turnStarted(notification.turn.id)
            )
        case "item/started":
            let notification = try decode(WireItemNotification.self, from: params)
            if let item = notification.item.asPublicItem() {
                bufferedEvent = .init(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    event: .itemStarted(item)
                )
            } else {
                bufferedEvent = nil
            }
        case "item/completed":
            let notification = try decode(WireItemNotification.self, from: params)
            if let item = notification.item.asPublicItem() {
                bufferedEvent = .init(
                    threadID: notification.threadID,
                    turnID: notification.turnID,
                    event: .itemCompleted(item)
                )
            } else {
                bufferedEvent = nil
            }
        case "turn/completed":
            let notification = try decode(WireTurnCompletedNotification.self, from: params)
            bufferedEvent = .init(
                threadID: notification.threadID,
                turnID: notification.turn.id,
                event: .turnCompleted
            )
        case "error":
            let notification = try decode(WireErrorNotification.self, from: params)
            bufferedEvent = .init(
                threadID: notification.threadID,
                turnID: notification.turnID,
                event: .turnFailed(notification.error.message)
            )
        default:
            bufferedEvent = nil
        }

        guard let bufferedEvent else {
            return
        }

        if let activeConsumer,
           bufferedEvent.matches(threadID: activeConsumer.threadID, turnID: activeConsumer.turnID) {
            activeConsumer.continuation.yield(bufferedEvent.event)
            if bufferedEvent.isTerminal {
                activeConsumer.continuation.finish()
                self.activeConsumer = nil
            }
            return
        }

        pendingEvents.append(bufferedEvent)
    }

    private func drainBufferedEvents(threadID: String, turnID: String) -> [BufferedEvent] {
        var retained: [BufferedEvent] = []
        var drained: [BufferedEvent] = []

        for event in pendingEvents {
            if event.matches(threadID: threadID, turnID: turnID) {
                drained.append(event)
            } else {
                retained.append(event)
            }
        }

        pendingEvents = retained
        return drained
    }

    private func makeThreadStartParams(_ options: AppServerThreadOptions) -> JSONObject {
        var params: JSONObject = [
            "experimentalRawEvents": false,
            "persistExtendedHistory": false,
        ]
        if let model = options.model {
            params["model"] = .string(model)
        }
        if let sandboxMode = options.sandboxMode {
            params["sandbox"] = .string(sandboxMode.rawValue)
        }
        if let workingDirectory = options.workingDirectory {
            params["cwd"] = .string(workingDirectory)
        }
        if let approvalPolicy = options.approvalPolicy {
            params["approvalPolicy"] = .string(approvalPolicy.rawValue)
        }
        if let config = mergedConfig(with: options.config) {
            params["config"] = .object(config)
        }
        return params
    }

    private func makeThreadResumeParams(threadID: String, options: AppServerThreadOptions) -> JSONObject {
        var params = makeThreadStartParams(options)
        params["threadId"] = .string(threadID)
        params["experimentalRawEvents"] = nil
        return params
    }

    private func makeTurnStartParams(threadID: String, input: [UserInput], options: TurnOptions) -> JSONObject {
        var params: JSONObject = [
            "threadId": .string(threadID),
            "input": .array(input.map(\.appServerValue)),
        ]
        if let outputSchema = options.outputSchema {
            params["outputSchema"] = .object(outputSchema)
        }
        return params
    }

    private func mergedConfig(with overrides: JSONObject?) -> JSONObject? {
        var merged = config.config ?? [:]
        if let baseURL = config.baseURL {
            merged["openai_base_url"] = .string(baseURL)
        }
        if let overrides {
            for (key, value) in overrides {
                merged[key] = value
            }
        }
        return merged.isEmpty ? nil : merged
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct BufferedEvent: Sendable {
    var threadID: String
    var turnID: String?
    var event: AppServerEvent

    var isTerminal: Bool {
        switch event {
        case .turnCompleted, .turnFailed:
            return true
        default:
            return false
        }
    }

    func matches(threadID: String, turnID: String) -> Bool {
        guard self.threadID == threadID else {
            return false
        }
        guard let eventTurnID = self.turnID else {
            return true
        }
        return eventTurnID == turnID
    }
}

private struct JSONRPCErrorPayload: Decodable {
    var code: Int
    var message: String
}

private struct AppServerInitializeResponse: Decodable {
    var serverInfo: AppServerServerInfo?
    var userAgent: String?

    func normalizedMetadata() throws -> AppServerMetadata {
        let userAgent = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let serverName = serverInfo?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let serverVersion = serverInfo?.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !userAgent.isEmpty, !serverName.isEmpty, !serverVersion.isEmpty else {
            throw AppServerError.missingMetadata
        }
        return AppServerMetadata(
            userAgent: userAgent,
            serverName: serverName,
            serverVersion: serverVersion
        )
    }
}

private struct AppServerServerInfo: Decodable {
    var name: String?
    var version: String?
}

private struct AppServerThreadStartResponse: Decodable {
    var thread: WireThread
}

private struct AppServerThreadResumeResponse: Decodable {
    var thread: WireThread
}

private struct AppServerTurnStartResponse: Decodable {
    var turn: WireTurn
}

private struct WireThreadStartedNotification: Decodable {
    var thread: WireThread
}

private struct WireTurnStartedNotification: Decodable {
    var threadID: String
    var turn: WireTurn

    enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turn
    }
}

private struct WireTurnCompletedNotification: Decodable {
    var threadID: String
    var turn: WireTurn

    enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turn
    }
}

private struct WireErrorNotification: Decodable {
    var error: WireTurnError
    var threadID: String
    var turnID: String

    enum CodingKeys: String, CodingKey {
        case error
        case threadID = "threadId"
        case turnID = "turnId"
    }
}

private struct WireItemNotification: Decodable {
    var item: WireThreadItem
    var threadID: String
    var turnID: String

    enum CodingKeys: String, CodingKey {
        case item
        case threadID = "threadId"
        case turnID = "turnId"
    }
}

private struct WireThread: Decodable {
    var id: String
}

private struct WireTurn: Decodable {
    var id: String
}

private struct WireTurnError: Decodable {
    var message: String
}

private struct WireCommandApprovalParams: Decodable {
    var threadID: String
    var turnID: String
    var itemID: String
    var approvalID: String?
    var command: String?
    var cwd: String?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case itemID = "itemId"
        case approvalID = "approvalId"
        case command
        case cwd
        case reason
    }

    func toPublicRequest() -> CommandApprovalRequest {
        CommandApprovalRequest(
            threadID: threadID,
            turnID: turnID,
            itemID: itemID,
            approvalID: approvalID,
            command: command,
            workingDirectory: cwd,
            reason: reason
        )
    }
}

private struct WireFileChangeApprovalParams: Decodable {
    var threadID: String
    var turnID: String
    var itemID: String
    var reason: String?
    var grantRoot: String?

    enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
        case turnID = "turnId"
        case itemID = "itemId"
        case reason
        case grantRoot
    }

    func toPublicRequest() -> FileChangeApprovalRequest {
        FileChangeApprovalRequest(
            threadID: threadID,
            turnID: turnID,
            itemID: itemID,
            reason: reason,
            grantRoot: grantRoot
        )
    }
}

private enum WireThreadItem: Decodable {
    case agentMessage(WireAgentMessageItem)
    case reasoning(WireReasoningItem)
    case commandExecution(WireCommandExecutionItem)
    case fileChange(WireFileChangeItem)
    case mcpToolCall(WireMCPToolCallItem)
    case webSearch(WireWebSearchItem)
    case unsupported(id: String, type: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "agentMessage":
            self = .agentMessage(try WireAgentMessageItem(from: decoder))
        case "reasoning":
            self = .reasoning(try WireReasoningItem(from: decoder))
        case "commandExecution":
            self = .commandExecution(try WireCommandExecutionItem(from: decoder))
        case "fileChange":
            self = .fileChange(try WireFileChangeItem(from: decoder))
        case "mcpToolCall":
            self = .mcpToolCall(try WireMCPToolCallItem(from: decoder))
        case "webSearch":
            self = .webSearch(try WireWebSearchItem(from: decoder))
        default:
            let id = try container.decode(String.self, forKey: .id)
            self = .unsupported(id: id, type: type)
        }
    }

    func asPublicItem() -> ThreadItem? {
        switch self {
        case .agentMessage(let item):
            return .agentMessage(AgentMessageItem(id: item.id, text: item.text))
        case .reasoning(let item):
            let text = item.content.isEmpty ? item.summary.joined(separator: "\n") : item.content.joined(separator: "\n")
            return .reasoning(ReasoningItem(id: item.id, text: text))
        case .commandExecution(let item):
            return .commandExecution(CommandExecutionItem(
                id: item.id,
                command: item.command,
                aggregatedOutput: item.aggregatedOutput ?? "",
                exitCode: item.exitCode,
                status: item.status.publicStatus
            ))
        case .fileChange(let item):
            return .fileChange(FileChangeItem(
                id: item.id,
                changes: item.changes.map { .init(path: $0.path, kind: $0.kind.publicKind) },
                status: item.status.publicStatus
            ))
        case .mcpToolCall(let item):
            return .mcpToolCall(McpToolCallItem(
                id: item.id,
                server: item.server,
                tool: item.tool,
                arguments: item.arguments,
                result: item.result.map { .init(content: $0.content, structuredContent: $0.structuredContent) },
                error: item.error.map { .init(message: $0.message) },
                status: item.status.publicStatus
            ))
        case .webSearch(let item):
            return .webSearch(WebSearchItem(id: item.id, query: item.query))
        case .unsupported:
            return nil
        }
    }
}

private struct WireAgentMessageItem: Decodable {
    var id: String
    var text: String
}

private struct WireReasoningItem: Decodable {
    var id: String
    var summary: [String]
    var content: [String]
}

private struct WireCommandExecutionItem: Decodable {
    var id: String
    var command: String
    var aggregatedOutput: String?
    var exitCode: Int?
    var status: WireCommandExecutionStatus

    enum CodingKeys: String, CodingKey {
        case id
        case command
        case aggregatedOutput
        case exitCode
        case status
    }
}

private enum WireCommandExecutionStatus: String, Decodable {
    case inProgress
    case completed
    case failed

    var publicStatus: CommandExecutionStatus {
        switch self {
        case .inProgress:
            return .inProgress
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }
}

private struct WireFileChangeItem: Decodable {
    var id: String
    var changes: [WireFileUpdateChange]
    var status: WirePatchApplyStatus
}

private struct WireFileUpdateChange: Decodable {
    var path: String
    var kind: WirePatchChangeKind
}

private enum WirePatchChangeKind: String, Decodable {
    case add
    case delete
    case update

    var publicKind: PatchChangeKind {
        switch self {
        case .add:
            return .add
        case .delete:
            return .delete
        case .update:
            return .update
        }
    }
}

private enum WirePatchApplyStatus: String, Decodable {
    case completed
    case failed

    var publicStatus: PatchApplyStatus {
        switch self {
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }
}

private struct WireMCPToolCallItem: Decodable {
    var id: String
    var server: String
    var tool: String
    var arguments: JSONValue?
    var result: WireMCPToolCallResult?
    var error: WireItemError?
    var status: WireMCPToolCallStatus
}

private struct WireMCPToolCallResult: Decodable {
    var content: [JSONValue]
    var structuredContent: JSONValue?

    enum CodingKeys: String, CodingKey {
        case content
        case structuredContent = "structuredContent"
    }
}

private struct WireItemError: Decodable {
    var message: String
}

private enum WireMCPToolCallStatus: String, Decodable {
    case inProgress
    case completed
    case failed

    var publicStatus: McpToolCallStatus {
        switch self {
        case .inProgress:
            return .inProgress
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }
}

private struct WireWebSearchItem: Decodable {
    var id: String
    var query: String
}

private extension JSONObject {
    func string(forKey key: String) -> String? {
        guard case .string(let value) = self[key] else {
            return nil
        }
        return value
    }
}

private extension UserInput {
    var appServerValue: JSONValue {
        switch self {
        case .text(let text):
            return .object([
                "type": .string("text"),
                "text": .string(text),
                "text_elements": .array([]),
            ])
        case .localImage(let path):
            return .object([
                "type": .string("localImage"),
                "path": .string(path),
            ])
        }
    }
}
