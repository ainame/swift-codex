import Foundation
import Logging

public enum ApprovalDecision: String, Sendable, Hashable, Codable {
    case approve
    case deny
}

public struct CommandApprovalRequest: Sendable, Hashable, Codable {
    public var threadID: String
    public var turnID: String
    public var itemID: String
    public var approvalID: String?
    public var command: String?
    public var workingDirectory: String?
    public var reason: String?

    public init(
        threadID: String,
        turnID: String,
        itemID: String,
        approvalID: String? = nil,
        command: String? = nil,
        workingDirectory: String? = nil,
        reason: String? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.approvalID = approvalID
        self.command = command
        self.workingDirectory = workingDirectory
        self.reason = reason
    }
}

public struct FileChangeApprovalRequest: Sendable, Hashable, Codable {
    public var threadID: String
    public var turnID: String
    public var itemID: String
    public var reason: String?
    public var grantRoot: String?

    public init(
        threadID: String,
        turnID: String,
        itemID: String,
        reason: String? = nil,
        grantRoot: String? = nil
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.reason = reason
        self.grantRoot = grantRoot
    }
}

public enum ServerRequest: Sendable, Hashable, Codable {
    case commandApproval(CommandApprovalRequest)
    case fileChangeApproval(FileChangeApprovalRequest)
    case unknown(method: String, params: JSONValue?)
}

public enum ServerRequestResult: Sendable, Hashable, Codable {
    case approval(ApprovalDecision)
    case json(JSONValue)

    var jsonValue: JSONValue {
        switch self {
        case .approval(let decision):
            return .object(["decision": .string(decision == .approve ? "accept" : "decline")])
        case .json(let value):
            return value
        }
    }
}

public struct RunResult: Sendable, Hashable, Codable {
    public var finalResponse: String?
    public var items: [ThreadItem]
    public var usage: ThreadTokenUsage?

    public init(
        finalResponse: String?,
        items: [ThreadItem],
        usage: ThreadTokenUsage?
    ) {
        self.finalResponse = finalResponse
        self.items = items
        self.usage = usage
    }
}

public struct CodexConfig: Sendable {
    public typealias ServerRequestHandler = @Sendable (ServerRequest) async -> ServerRequestResult
    public typealias CommandApprovalHandler = @Sendable (CommandApprovalRequest) async -> ApprovalDecision
    public typealias FileChangeApprovalHandler = @Sendable (FileChangeApprovalRequest) async -> ApprovalDecision

    public var codexPathOverride: String?
    public var launchArgsOverride: [String]?
    public var baseURL: String?
    public var apiKey: String?
    public var config: JSONObject?
    public var workingDirectory: String?
    public var environment: [String: String]?
    public var clientName: String
    public var clientTitle: String
    public var clientVersion: String
    public var experimentalAPI: Bool
    public var serverRequestHandler: ServerRequestHandler?
    public var commandApprovalHandler: CommandApprovalHandler
    public var fileChangeApprovalHandler: FileChangeApprovalHandler

    public init(
        codexPathOverride: String? = nil,
        launchArgsOverride: [String]? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        config: JSONObject? = nil,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        clientName: String = "swift-codex",
        clientTitle: String = "swift-codex",
        clientVersion: String = "dev",
        experimentalAPI: Bool = true,
        serverRequestHandler: ServerRequestHandler? = nil,
        commandApprovalHandler: @escaping CommandApprovalHandler = { _ in .approve },
        fileChangeApprovalHandler: @escaping FileChangeApprovalHandler = { _ in .approve }
    ) {
        self.codexPathOverride = codexPathOverride
        self.launchArgsOverride = launchArgsOverride
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.config = config
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.clientName = clientName
        self.clientTitle = clientTitle
        self.clientVersion = clientVersion
        self.experimentalAPI = experimentalAPI
        self.serverRequestHandler = serverRequestHandler
        self.commandApprovalHandler = commandApprovalHandler
        self.fileChangeApprovalHandler = fileChangeApprovalHandler
    }
}

public struct CodexNotification: Sendable, Hashable, Codable {
    public var method: String
    public var payload: CodexNotificationPayload
    public var rawParams: JSONValue

    init(method: String, params: JSONValue) {
        self.method = method
        self.rawParams = params
        self.payload = (try? CodexNotificationPayload(method: method, params: params))
            ?? .unknown(method: method, rawJSON: params)
    }

    public var threadID: String? {
        payload.threadID
    }

    public var turnID: String? {
        payload.turnID
    }
}

public actor CodexRPCClient {
    private let config: CodexConfig
    private let logger: Logger
    private let transport: CodexRPCTransport
    private var initializePayload: InitializeResponse?
    private var activeTurnConsumer: String?

    public init(config: CodexConfig = .init(), logger: Logger) {
        self.config = config
        self.logger = logger.codexScope("rpc")
        self.transport = CodexRPCTransport(config: config, logger: logger.codexScope("transport"))
    }

    public init(config: CodexConfig = .init()) {
        self.init(config: config, logger: Codex.defaultLogger())
    }

    public func start() async throws {
        try await transport.startProcess()
    }

    public func initialize() async throws -> InitializeResponse {
        if let initializePayload {
            return initializePayload
        }

        logger.info("Initializing Codex RPC client")
        try await start()
        let payload = try await request(
            "initialize",
            params: [
                "clientInfo": .object([
                    "name": .string(config.clientName),
                    "title": .string(config.clientTitle),
                    "version": .string(config.clientVersion),
                ]),
                "capabilities": .object([
                    "experimentalApi": .bool(config.experimentalAPI),
                ]),
            ],
            responseType: InitializeResponse.self
        )
        let normalized = try normalizedInitializePayload(payload, logger: logger)
        try await notify("initialized")
        initializePayload = normalized
        logger.info(
            "Initialized Codex RPC client",
            metadata: [
                "server_name": normalized.serverInfo?.name.map(Logger.MetadataValue.string),
                "server_version": normalized.serverInfo?.version.map(Logger.MetadataValue.string),
            ].compactMapValues { $0 }
        )
        return normalized
    }

    public func metadata() -> InitializeResponse? {
        initializePayload
    }

    public func close() async {
        logger.info("Closing Codex RPC client")
        await transport.close()
        initializePayload = nil
        activeTurnConsumer = nil
    }

    public func request<T: Decodable>(
        _ method: String,
        params: JSONObject = [:],
        responseType: T.Type
    ) async throws -> T {
        try await start()
        let value = try await transport.request(method: method, params: params)
        return try decodeResponse(T.self, from: value)
    }

    public func notify(_ method: String, params: JSONObject = [:]) async throws {
        try await start()
        try await transport.notify(method: method, params: params)
    }

    public func nextNotification() async throws -> CodexNotification {
        try await transport.nextNotification()
    }

    public func acquireTurnConsumer(turnID: String) throws {
        if let activeTurnConsumer {
            logger.warning(
                "Attempted to acquire a second active turn consumer",
                metadata: [
                    "active_turn_id": .string(activeTurnConsumer),
                    "requested_turn_id": .string(turnID),
                ]
            )
            throw CodexError.concurrentTurnConsumer(
                activeTurnID: activeTurnConsumer,
                requestedTurnID: turnID
            )
        }
        activeTurnConsumer = turnID
    }

    public func releaseTurnConsumer(turnID: String) {
        guard activeTurnConsumer == turnID else {
            return
        }
        activeTurnConsumer = nil
    }

    public func threadStart(options: ThreadOptions = .init()) async throws -> ThreadStartResponse {
        try await request("thread/start", params: makeThreadStartParams(options), responseType: ThreadStartResponse.self)
    }

    public func threadResume(threadID: String, options: ThreadOptions = .init()) async throws -> ThreadResumeResponse {
        var params = makeThreadStartParams(options)
        params["threadId"] = .string(threadID)
        return try await request("thread/resume", params: params, responseType: ThreadResumeResponse.self)
    }

    public func threadList(options: ThreadListOptions = .init()) async throws -> ThreadListResponse {
        try await request("thread/list", params: makeThreadListParams(options), responseType: ThreadListResponse.self)
    }

    public func threadRead(threadID: String, includeTurns: Bool = false) async throws -> ThreadReadResponse {
        try await request(
            "thread/read",
            params: [
                "threadId": .string(threadID),
                "includeTurns": .bool(includeTurns),
            ],
            responseType: ThreadReadResponse.self
        )
    }

    public func threadFork(threadID: String, options: ThreadOptions = .init()) async throws -> ThreadForkResponse {
        var params = makeThreadStartParams(options)
        params["threadId"] = .string(threadID)
        return try await request("thread/fork", params: params, responseType: ThreadForkResponse.self)
    }

    public func threadArchive(threadID: String) async throws -> ThreadArchiveResponse {
        try await request("thread/archive", params: ["threadId": .string(threadID)], responseType: ThreadArchiveResponse.self)
    }

    public func threadUnarchive(threadID: String) async throws -> ThreadUnarchiveResponse {
        try await request("thread/unarchive", params: ["threadId": .string(threadID)], responseType: ThreadUnarchiveResponse.self)
    }

    public func threadSetName(threadID: String, name: String) async throws -> ThreadSetNameResponse {
        try await request(
            "thread/name/set",
            params: [
                "threadId": .string(threadID),
                "name": .string(name),
            ],
            responseType: ThreadSetNameResponse.self
        )
    }

    public func threadCompact(threadID: String) async throws -> ThreadCompactStartResponse {
        try await request(
            "thread/compact/start",
            params: ["threadId": .string(threadID)],
            responseType: ThreadCompactStartResponse.self
        )
    }

    public func turnStart(
        threadID: String,
        input: [InputItem],
        options: TurnOptions = .init()
    ) async throws -> TurnStartResponse {
        try await request(
            "turn/start",
            params: makeTurnStartParams(threadID: threadID, input: input, options: options),
            responseType: TurnStartResponse.self
        )
    }

    public func turnSteer(
        threadID: String,
        expectedTurnID: String,
        input: [InputItem]
    ) async throws -> TurnSteerResponse {
        try await request(
            "turn/steer",
            params: [
                "threadId": .string(threadID),
                "expectedTurnId": .string(expectedTurnID),
                "input": .array(input.map(\.jsonValue)),
            ],
            responseType: TurnSteerResponse.self
        )
    }

    public func turnInterrupt(threadID: String, turnID: String) async throws -> TurnInterruptResponse {
        try await request(
            "turn/interrupt",
            params: [
                "threadId": .string(threadID),
                "turnId": .string(turnID),
            ],
            responseType: TurnInterruptResponse.self
        )
    }

    public func modelList(includeHidden: Bool = false) async throws -> ModelListResponse {
        try await request(
            "model/list",
            params: ["includeHidden": .bool(includeHidden)],
            responseType: ModelListResponse.self
        )
    }

    public func pluginList() async throws -> PluginListResponse {
        try await request("plugin/list", responseType: PluginListResponse.self)
    }

    private func makeThreadStartParams(_ options: ThreadOptions) -> JSONObject {
        var params: JSONObject = [:]
        if let approvalPolicy = options.approvalPolicy {
            params["approvalPolicy"] = approvalPolicy.rawJSON
        }
        if let approvalsReviewer = options.approvalsReviewer {
            params["approvalsReviewer"] = approvalsReviewer.rawJSON
        }
        if let baseInstructions = options.baseInstructions {
            params["baseInstructions"] = .string(baseInstructions)
        }
        if let config = mergedConfig(with: options.config) {
            params["config"] = .object(config)
        }
        if let cwd = options.cwd {
            params["cwd"] = .string(cwd)
        }
        if let developerInstructions = options.developerInstructions {
            params["developerInstructions"] = .string(developerInstructions)
        }
        if let ephemeral = options.ephemeral {
            params["ephemeral"] = .bool(ephemeral)
        }
        if let model = options.model {
            params["model"] = .string(model)
        }
        if let modelProvider = options.modelProvider {
            params["modelProvider"] = .string(modelProvider)
        }
        if let personality = options.personality {
            params["personality"] = personality.rawJSON
        }
        if let sandbox = options.sandbox {
            params["sandbox"] = sandbox.rawJSON
        }
        if let serviceName = options.serviceName {
            params["serviceName"] = .string(serviceName)
        }
        if let serviceTier = options.serviceTier {
            params["serviceTier"] = serviceTier.rawJSON
        }
        return params
    }

    private func makeThreadListParams(_ options: ThreadListOptions) -> JSONObject {
        var params: JSONObject = [:]
        if let archived = options.archived {
            params["archived"] = .bool(archived)
        }
        if let cursor = options.cursor {
            params["cursor"] = .string(cursor)
        }
        if let cwd = options.cwd {
            params["cwd"] = .string(cwd)
        }
        if let limit = options.limit {
            params["limit"] = .number(Double(limit))
        }
        if let modelProviders = options.modelProviders {
            params["modelProviders"] = .array(modelProviders.map(JSONValue.string))
        }
        if let searchTerm = options.searchTerm {
            params["searchTerm"] = .string(searchTerm)
        }
        if let sortKey = options.sortKey {
            params["sortKey"] = sortKey.rawJSON
        }
        if let sourceKinds = options.sourceKinds {
            params["sourceKinds"] = .array(sourceKinds.map(\.rawJSON))
        }
        return params
    }

    private func makeTurnStartParams(threadID: String, input: [InputItem], options: TurnOptions) -> JSONObject {
        var params: JSONObject = [
            "threadId": .string(threadID),
            "input": .array(input.map(\.jsonValue)),
        ]
        if let approvalPolicy = options.approvalPolicy {
            params["approvalPolicy"] = approvalPolicy.rawJSON
        }
        if let approvalsReviewer = options.approvalsReviewer {
            params["approvalsReviewer"] = approvalsReviewer.rawJSON
        }
        if let cwd = options.cwd {
            params["cwd"] = .string(cwd)
        }
        if let effort = options.effort {
            params["effort"] = effort.rawJSON
        }
        if let model = options.model {
            params["model"] = .string(model)
        }
        if let outputSchema = options.outputSchema {
            params["outputSchema"] = .object(outputSchema)
        }
        if let personality = options.personality {
            params["personality"] = personality.rawJSON
        }
        if let sandboxPolicy = options.sandboxPolicy {
            params["sandboxPolicy"] = sandboxPolicy.rawJSON
        }
        if let serviceTier = options.serviceTier {
            params["serviceTier"] = serviceTier.rawJSON
        }
        if let summary = options.summary {
            params["summary"] = summary.rawJSON
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
}

public actor Codex {
    private let client: CodexRPCClient
    private let initializePayload: InitializeResponse
    private let logger: Logger

    public init(config: CodexConfig = .init(), logger: Logger) async throws {
        self.logger = logger.codexScope("codex")
        let client = CodexRPCClient(config: config, logger: logger)
        self.client = client
        self.initializePayload = try await client.initialize()
        self.logger.info("Codex session ready")
    }

    public init(config: CodexConfig = .init()) async throws {
        try await self.init(config: config, logger: Self.defaultLogger())
    }

    public static func defaultLogger() -> Logger {
        CodexLogging.makeDefaultLogger()
    }

    public static func defaultLogger(label: String) -> Logger {
        CodexLogging.makeDefaultLogger(label: label)
    }

    deinit {
        let client = self.client
        Task {
            await client.close()
        }
    }

    public func metadata() -> InitializeResponse {
        initializePayload
    }

    public func close() async {
        logger.info("Closing Codex session")
        await client.close()
    }

    public func startThread(options: ThreadOptions = .init()) async throws -> CodexThread {
        let response = try await client.threadStart(options: options)
        logger.info("Started thread", metadata: ["thread_id": .string(response.thread.id)])
        return CodexThread(
            client: client,
            id: response.thread.id,
            logger: logger.codexScope("thread", metadata: ["thread_id": .string(response.thread.id)])
        )
    }

    public func resumeThread(id: String, options: ThreadOptions = .init()) async throws -> CodexThread {
        let response = try await client.threadResume(threadID: id, options: options)
        logger.info("Resumed thread", metadata: ["thread_id": .string(response.thread.id)])
        return CodexThread(
            client: client,
            id: response.thread.id,
            logger: logger.codexScope("thread", metadata: ["thread_id": .string(response.thread.id)])
        )
    }

    public func forkThread(id: String, options: ThreadOptions = .init()) async throws -> CodexThread {
        let response = try await client.threadFork(threadID: id, options: options)
        logger.info("Forked thread", metadata: ["thread_id": .string(response.thread.id)])
        return CodexThread(
            client: client,
            id: response.thread.id,
            logger: logger.codexScope("thread", metadata: ["thread_id": .string(response.thread.id)])
        )
    }

    public func listThreads(options: ThreadListOptions = .init()) async throws -> ThreadListResponse {
        try await client.threadList(options: options)
    }

    public func archiveThread(id: String) async throws -> ThreadArchiveResponse {
        let response = try await client.threadArchive(threadID: id)
        logger.info("Archived thread", metadata: ["thread_id": .string(id)])
        return response
    }

    public func unarchiveThread(id: String) async throws -> CodexThread {
        let response = try await client.threadUnarchive(threadID: id)
        logger.info("Unarchived thread", metadata: ["thread_id": .string(response.thread.id)])
        return CodexThread(
            client: client,
            id: response.thread.id,
            logger: logger.codexScope("thread", metadata: ["thread_id": .string(response.thread.id)])
        )
    }

    public func models(includeHidden: Bool = false) async throws -> ModelListResponse {
        try await client.modelList(includeHidden: includeHidden)
    }

    public func plugins() async throws -> PluginListResponse {
        try await client.pluginList()
    }
}

public struct CodexThread: Sendable {
    private let client: CodexRPCClient
    private let logger: Logger
    public let id: String

    init(client: CodexRPCClient, id: String, logger: Logger) {
        self.client = client
        self.id = id
        self.logger = logger
    }

    public func run(_ input: String, options: TurnOptions = .init()) async throws -> RunResult {
        try await run(.text(input), options: options)
    }

    public func run(_ input: InputItem, options: TurnOptions = .init()) async throws -> RunResult {
        try await run([input], options: options)
    }

    public func run(_ input: [InputItem], options: TurnOptions = .init()) async throws -> RunResult {
        logger.info("Running turn", metadata: ["thread_id": .string(id)])
        let handle = try await turn(input, options: options)
        let stream = try await handle.stream()
        var completedTurn: Turn?
        var usage: ThreadTokenUsage?
        var items: [ThreadItem] = []

        for try await notification in stream {
            switch notification.payload {
            case .itemCompleted(let payload):
                if payload.turnId == handle.id {
                    items.append(payload.item)
                }
            case .threadTokenUsageUpdated(let payload):
                if payload.turnId == handle.id {
                    usage = payload.tokenUsage
                }
            case .turnCompleted(let payload):
                if payload.turn.id == handle.id {
                    completedTurn = payload.turn
                }
            default:
                break
            }
        }

        guard let completedTurn else {
            logger.error("Turn run did not receive completion event", metadata: ["thread_id": .string(id)])
            throw CodexError.invalidResponse("turn completed event not received")
        }
        if completedTurn.status == .failed {
            logger.error(
                "Turn run failed",
                metadata: [
                    "thread_id": .string(id),
                    "turn_id": .string(handle.id),
                ]
            )
            throw CodexError.turnFailed(completedTurn.error?.message ?? "turn failed")
        }

        logger.info(
            "Turn run completed",
            metadata: [
                "thread_id": .string(id),
                "turn_id": .string(handle.id),
            ]
        )
        return RunResult(
            finalResponse: finalAssistantResponse(from: items),
            items: items,
            usage: usage
        )
    }

    public func turn(_ input: String, options: TurnOptions = .init()) async throws -> CodexTurnHandle {
        try await turn([.text(input)], options: options)
    }

    public func turn(_ input: InputItem, options: TurnOptions = .init()) async throws -> CodexTurnHandle {
        try await turn([input], options: options)
    }

    public func turn(_ input: [InputItem], options: TurnOptions = .init()) async throws -> CodexTurnHandle {
        let response = try await client.turnStart(threadID: id, input: input, options: options)
        logger.info(
            "Started turn",
            metadata: [
                "thread_id": .string(id),
                "turn_id": .string(response.turn.id),
            ]
        )
        return CodexTurnHandle(
            client: client,
            threadID: id,
            id: response.turn.id,
            logger: logger.codexScope("turn", metadata: [
                "thread_id": .string(id),
                "turn_id": .string(response.turn.id),
            ])
        )
    }

    public func read(includeTurns: Bool = false) async throws -> ThreadReadResponse {
        try await client.threadRead(threadID: id, includeTurns: includeTurns)
    }

    public func setName(_ name: String) async throws -> ThreadSetNameResponse {
        try await client.threadSetName(threadID: id, name: name)
    }

    public func compact() async throws -> ThreadCompactStartResponse {
        try await client.threadCompact(threadID: id)
    }
}

public struct CodexTurnHandle: Sendable {
    private let client: CodexRPCClient
    private let threadID: String
    private let logger: Logger
    public let id: String

    init(client: CodexRPCClient, threadID: String, id: String, logger: Logger) {
        self.client = client
        self.threadID = threadID
        self.id = id
        self.logger = logger
    }

    public func steer(_ input: String) async throws -> TurnSteerResponse {
        try await steer(.text(input))
    }

    public func steer(_ input: InputItem) async throws -> TurnSteerResponse {
        let response = try await client.turnSteer(threadID: threadID, expectedTurnID: id, input: [input])
        logger.info("Steered turn")
        return response
    }

    public func steer(_ input: [InputItem]) async throws -> TurnSteerResponse {
        let response = try await client.turnSteer(threadID: threadID, expectedTurnID: id, input: input)
        logger.info("Steered turn")
        return response
    }

    public func interrupt() async throws -> TurnInterruptResponse {
        let response = try await client.turnInterrupt(threadID: threadID, turnID: id)
        logger.info("Interrupted turn")
        return response
    }

    public func stream() async throws -> AsyncThrowingStream<CodexNotification, Error> {
        try await client.acquireTurnConsumer(turnID: id)
        logger.debug("Starting turn stream")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while true {
                        let notification = try await client.nextNotification()
                        continuation.yield(notification)
                        if notification.method == "turn/completed",
                           case .turnCompleted(let payload) = notification.payload,
                           payload.turn.id == id {
                            logger.info("Turn stream completed")
                            continuation.finish()
                            break
                        }
                    }
                } catch {
                    logger.error("Turn stream failed")
                    continuation.finish(throwing: error)
                }
                await client.releaseTurnConsumer(turnID: id)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task {
                    await client.releaseTurnConsumer(turnID: id)
                }
            }
        }
    }

    public func run() async throws -> Turn {
        let stream = try await stream()
        var completedTurn: Turn?
        for try await notification in stream {
            if case .turnCompleted(let payload) = notification.payload, payload.turn.id == id {
                completedTurn = payload.turn
            }
        }
        guard let completedTurn else {
            logger.error("Turn completion event not received")
            throw CodexError.invalidResponse("turn completed event not received")
        }
        logger.info("Turn finished")
        return completedTurn
    }
}

public func isRetryableError(_ error: any Error) -> Bool {
    guard let error = error as? CodexError else {
        return false
    }
    switch error {
    case .serverBusy, .retryLimitExceeded:
        return true
    case .jsonRPCError(_, _, let data):
        return CodexRPCErrorMapper.isServerOverloaded(data)
    default:
        return false
    }
}

public func retryOnOverload<T: Sendable>(
    maxAttempts: Int = 3,
    initialDelaySeconds: Double = 0.25,
    maxDelaySeconds: Double = 2.0,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    precondition(maxAttempts > 0, "maxAttempts must be greater than zero")

    var attempt = 0
    var delay = initialDelaySeconds
    while true {
        attempt += 1
        do {
            return try await operation()
        } catch {
            guard attempt < maxAttempts, isRetryableError(error) else {
                throw error
            }
            let jitter = Double.random(in: 0.85 ... 1.15)
            let sleepSeconds = min(delay * jitter, maxDelaySeconds)
            try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
            delay = min(delay * 2, maxDelaySeconds)
        }
    }
}

private func decodeResponse<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    try decodeJSONValue(T.self, from: value)
}

private func normalizedInitializePayload(_ payload: InitializeResponse, logger: Logger) throws -> InitializeResponse {
    let userAgent = payload.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
    var serverName = payload.serverInfo?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var serverVersion = payload.serverInfo?.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if (serverName.isEmpty || serverVersion.isEmpty), let userAgent, !userAgent.isEmpty {
        logger.warning("Falling back to userAgent to normalize initialize metadata")
        let parsed = splitUserAgent(userAgent)
        if serverName.isEmpty {
            serverName = parsed.name ?? ""
        }
        if serverVersion.isEmpty {
            serverVersion = parsed.version ?? ""
        }
    }

    guard !serverName.isEmpty, !serverVersion.isEmpty else {
        throw CodexError.missingMetadata
    }

    return InitializeResponse(
        serverInfo: ServerInfo(name: serverName, version: serverVersion),
        userAgent: userAgent?.isEmpty == false ? userAgent : nil,
        platformFamily: payload.platformFamily,
        platformOs: payload.platformOs,
        additionalFields: payload.additionalFields
    )
}

private func splitUserAgent(_ userAgent: String) -> (name: String?, version: String?) {
    let raw = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
        return (nil, nil)
    }
    if let separator = raw.firstIndex(of: "/") {
        let name = String(raw[..<separator])
        let version = String(raw[raw.index(after: separator)...])
        return (name.isEmpty ? nil : name, version.isEmpty ? nil : version)
    }

    let parts = raw.split(maxSplits: 1, whereSeparator: \.isWhitespace)
    if parts.count == 2 {
        let name = String(parts[0])
        let version = String(parts[1])
        return (name.isEmpty ? nil : name, version.isEmpty ? nil : version)
    }
    return (raw, nil)
}

private func finalAssistantResponse(from items: [ThreadItem]) -> String? {
    var lastUnknownPhase: String?

    for item in items.reversed() {
        guard case .agentMessage(let message) = item else {
            continue
        }
        if message.phase == .finalAnswer {
            return message.text
        }
        if message.phase == nil, lastUnknownPhase == nil {
            lastUnknownPhase = message.text
        }
    }

    return lastUnknownPhase
}

private extension InputItem {
    var jsonValue: JSONValue {
        switch self {
        case .text(let text):
            return .object([
                "type": .string("text"),
                "text": .string(text),
            ])
        case .image(let url):
            return .object([
                "type": .string("image"),
                "url": .string(url),
            ])
        case .localImage(let path):
            return .object([
                "type": .string("localImage"),
                "path": .string(path),
            ])
        case .skill(let name, let path):
            return .object([
                "type": .string("skill"),
                "name": .string(name),
                "path": .string(path),
            ])
        case .mention(let name, let path):
            return .object([
                "type": .string("mention"),
                "name": .string(name),
                "path": .string(path),
            ])
        }
    }
}
