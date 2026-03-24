import Foundation

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

public enum AppServerInputItem: Sendable, Hashable, Codable {
    case text(String)
    case image(url: String)
    case localImage(path: String)
    case skill(name: String, path: String)
    case mention(name: String, path: String)
}

public struct AppServerThreadOptions: Sendable, Hashable, Codable {
    public var approvalPolicy: AppServerV2.AskForApproval?
    public var approvalsReviewer: AppServerV2.ApprovalsReviewer?
    public var baseInstructions: String?
    public var config: JSONObject?
    public var cwd: String?
    public var developerInstructions: String?
    public var ephemeral: Bool?
    public var model: String?
    public var modelProvider: String?
    public var personality: AppServerV2.Personality?
    public var sandbox: AppServerV2.SandboxMode?
    public var serviceName: String?
    public var serviceTier: AppServerV2.ServiceTier?

    public init(
        approvalPolicy: AppServerV2.AskForApproval? = nil,
        approvalsReviewer: AppServerV2.ApprovalsReviewer? = nil,
        baseInstructions: String? = nil,
        config: JSONObject? = nil,
        cwd: String? = nil,
        developerInstructions: String? = nil,
        ephemeral: Bool? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        personality: AppServerV2.Personality? = nil,
        sandbox: AppServerV2.SandboxMode? = nil,
        serviceName: String? = nil,
        serviceTier: AppServerV2.ServiceTier? = nil
    ) {
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.baseInstructions = baseInstructions
        self.config = config
        self.cwd = cwd
        self.developerInstructions = developerInstructions
        self.ephemeral = ephemeral
        self.model = model
        self.modelProvider = modelProvider
        self.personality = personality
        self.sandbox = sandbox
        self.serviceName = serviceName
        self.serviceTier = serviceTier
    }
}

public struct AppServerThreadListOptions: Sendable, Hashable, Codable {
    public var archived: Bool?
    public var cursor: String?
    public var cwd: String?
    public var limit: Int?
    public var modelProviders: [String]?
    public var searchTerm: String?
    public var sortKey: AppServerV2.ThreadSortKey?
    public var sourceKinds: [AppServerV2.ThreadSourceKind]?

    public init(
        archived: Bool? = nil,
        cursor: String? = nil,
        cwd: String? = nil,
        limit: Int? = nil,
        modelProviders: [String]? = nil,
        searchTerm: String? = nil,
        sortKey: AppServerV2.ThreadSortKey? = nil,
        sourceKinds: [AppServerV2.ThreadSourceKind]? = nil
    ) {
        self.archived = archived
        self.cursor = cursor
        self.cwd = cwd
        self.limit = limit
        self.modelProviders = modelProviders
        self.searchTerm = searchTerm
        self.sortKey = sortKey
        self.sourceKinds = sourceKinds
    }
}

public struct AppServerTurnOptions: Sendable, Hashable, Codable {
    public var approvalPolicy: AppServerV2.AskForApproval?
    public var approvalsReviewer: AppServerV2.ApprovalsReviewer?
    public var cwd: String?
    public var effort: AppServerV2.ReasoningEffort?
    public var model: String?
    public var outputSchema: JSONObject?
    public var personality: AppServerV2.Personality?
    public var sandboxPolicy: AppServerV2.SandboxPolicy?
    public var serviceTier: AppServerV2.ServiceTier?
    public var summary: AppServerV2.ReasoningSummary?

    public init(
        approvalPolicy: AppServerV2.AskForApproval? = nil,
        approvalsReviewer: AppServerV2.ApprovalsReviewer? = nil,
        cwd: String? = nil,
        effort: AppServerV2.ReasoningEffort? = nil,
        model: String? = nil,
        outputSchema: JSONObject? = nil,
        personality: AppServerV2.Personality? = nil,
        sandboxPolicy: AppServerV2.SandboxPolicy? = nil,
        serviceTier: AppServerV2.ServiceTier? = nil,
        summary: AppServerV2.ReasoningSummary? = nil
    ) {
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.cwd = cwd
        self.effort = effort
        self.model = model
        self.outputSchema = outputSchema
        self.personality = personality
        self.sandboxPolicy = sandboxPolicy
        self.serviceTier = serviceTier
        self.summary = summary
    }
}

public struct AppServerRunResult: Sendable, Hashable, Codable {
    public var finalResponse: String?
    public var items: [AppServerV2.ThreadItem]
    public var usage: AppServerV2.ThreadTokenUsage?

    public init(
        finalResponse: String?,
        items: [AppServerV2.ThreadItem],
        usage: AppServerV2.ThreadTokenUsage?
    ) {
        self.finalResponse = finalResponse
        self.items = items
        self.usage = usage
    }
}

public enum AppServerError: Error, Sendable, Hashable {
    case transportClosed
    case transportClosedWithStderrTail(String)
    case invalidResponseLine(String)
    case invalidResponse(String)
    case invalidRequestID
    case missingMetadata
    case parseError(message: String, data: JSONValue?)
    case invalidRequest(message: String, data: JSONValue?)
    case methodNotFound(message: String, data: JSONValue?)
    case invalidParams(message: String, data: JSONValue?)
    case internalRPC(message: String, data: JSONValue?)
    case serverBusy(message: String, data: JSONValue?)
    case retryLimitExceeded(message: String, data: JSONValue?)
    case jsonRPCError(code: Int, message: String, data: JSONValue?)
    case concurrentTurnConsumer(activeTurnID: String, requestedTurnID: String)
    case turnFailed(String)
}

public struct AppServerConfig: Sendable {
    public typealias ServerRequestHandler = @Sendable (String, JSONObject?) async -> JSONObject
    public typealias CommandApprovalHandler = @Sendable (CommandApprovalRequest) async -> ApprovalDecision
    public typealias FileChangeApprovalHandler = @Sendable (FileChangeApprovalRequest) async -> ApprovalDecision

    public var codexPathOverride: String?
    public var baseURL: String?
    public var apiKey: String?
    public var config: JSONObject?
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
        baseURL: String? = nil,
        apiKey: String? = nil,
        config: JSONObject? = nil,
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
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.config = config
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

public actor AppServerClient {
    private let config: AppServerConfig
    private let transport: AppServerTransport
    private var initializePayload: AppServerV2.InitializeResponse?
    private var activeTurnConsumer: String?

    public init(config: AppServerConfig = .init()) {
        self.config = config
        self.transport = AppServerTransport(config: config)
    }

    public func start() async throws {
        try await transport.startProcess()
    }

    public func initialize() async throws -> AppServerV2.InitializeResponse {
        if let initializePayload {
            return initializePayload
        }

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
            responseType: AppServerV2.InitializeResponse.self
        )
        let normalized = try normalizedInitializePayload(payload)
        try await notify("initialized")
        initializePayload = normalized
        return normalized
    }

    public func metadata() -> AppServerV2.InitializeResponse? {
        initializePayload
    }

    public func close() async {
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

    public func nextNotification() async throws -> AppServerNotification {
        try await transport.nextNotification()
    }

    public func acquireTurnConsumer(turnID: String) throws {
        if let activeTurnConsumer {
            throw AppServerError.concurrentTurnConsumer(
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

    public func threadStart(options: AppServerThreadOptions = .init()) async throws -> AppServerV2.ThreadStartResponse {
        try await request("thread/start", params: makeThreadStartParams(options), responseType: AppServerV2.ThreadStartResponse.self)
    }

    public func threadResume(threadID: String, options: AppServerThreadOptions = .init()) async throws -> AppServerV2.ThreadResumeResponse {
        var params = makeThreadStartParams(options)
        params["threadId"] = .string(threadID)
        return try await request("thread/resume", params: params, responseType: AppServerV2.ThreadResumeResponse.self)
    }

    public func threadList(options: AppServerThreadListOptions = .init()) async throws -> AppServerV2.ThreadListResponse {
        try await request("thread/list", params: makeThreadListParams(options), responseType: AppServerV2.ThreadListResponse.self)
    }

    public func threadRead(threadID: String, includeTurns: Bool = false) async throws -> AppServerV2.ThreadReadResponse {
        try await request(
            "thread/read",
            params: [
                "threadId": .string(threadID),
                "includeTurns": .bool(includeTurns),
            ],
            responseType: AppServerV2.ThreadReadResponse.self
        )
    }

    public func threadFork(threadID: String, options: AppServerThreadOptions = .init()) async throws -> AppServerV2.ThreadForkResponse {
        var params = makeThreadStartParams(options)
        params["threadId"] = .string(threadID)
        return try await request("thread/fork", params: params, responseType: AppServerV2.ThreadForkResponse.self)
    }

    public func threadArchive(threadID: String) async throws -> AppServerV2.ThreadArchiveResponse {
        try await request("thread/archive", params: ["threadId": .string(threadID)], responseType: AppServerV2.ThreadArchiveResponse.self)
    }

    public func threadUnarchive(threadID: String) async throws -> AppServerV2.ThreadUnarchiveResponse {
        try await request("thread/unarchive", params: ["threadId": .string(threadID)], responseType: AppServerV2.ThreadUnarchiveResponse.self)
    }

    public func threadSetName(threadID: String, name: String) async throws -> AppServerV2.ThreadSetNameResponse {
        try await request(
            "thread/name/set",
            params: [
                "threadId": .string(threadID),
                "name": .string(name),
            ],
            responseType: AppServerV2.ThreadSetNameResponse.self
        )
    }

    public func threadCompact(threadID: String) async throws -> AppServerV2.ThreadCompactStartResponse {
        try await request(
            "thread/compact/start",
            params: ["threadId": .string(threadID)],
            responseType: AppServerV2.ThreadCompactStartResponse.self
        )
    }

    public func turnStart(
        threadID: String,
        input: [AppServerInputItem],
        options: AppServerTurnOptions = .init()
    ) async throws -> AppServerV2.TurnStartResponse {
        try await request(
            "turn/start",
            params: makeTurnStartParams(threadID: threadID, input: input, options: options),
            responseType: AppServerV2.TurnStartResponse.self
        )
    }

    public func turnSteer(
        threadID: String,
        expectedTurnID: String,
        input: [AppServerInputItem]
    ) async throws -> AppServerV2.TurnSteerResponse {
        try await request(
            "turn/steer",
            params: [
                "threadId": .string(threadID),
                "expectedTurnId": .string(expectedTurnID),
                "input": .array(input.map(\.jsonValue)),
            ],
            responseType: AppServerV2.TurnSteerResponse.self
        )
    }

    public func turnInterrupt(threadID: String, turnID: String) async throws -> AppServerV2.TurnInterruptResponse {
        try await request(
            "turn/interrupt",
            params: [
                "threadId": .string(threadID),
                "turnId": .string(turnID),
            ],
            responseType: AppServerV2.TurnInterruptResponse.self
        )
    }

    public func modelList(includeHidden: Bool = false) async throws -> AppServerV2.ModelListResponse {
        try await request(
            "model/list",
            params: ["includeHidden": .bool(includeHidden)],
            responseType: AppServerV2.ModelListResponse.self
        )
    }

    private func makeThreadStartParams(_ options: AppServerThreadOptions) -> JSONObject {
        var params: JSONObject = [:]
        if let approvalPolicy = options.approvalPolicy {
            params["approvalPolicy"] = approvalPolicy.jsonValue
        }
        if let approvalsReviewer = options.approvalsReviewer {
            params["approvalsReviewer"] = .string(approvalsReviewer.rawValue)
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
            params["personality"] = .string(personality.rawValue)
        }
        if let sandbox = options.sandbox {
            params["sandbox"] = .string(sandbox.rawValue)
        }
        if let serviceName = options.serviceName {
            params["serviceName"] = .string(serviceName)
        }
        if let serviceTier = options.serviceTier {
            params["serviceTier"] = .string(serviceTier.rawValue)
        }
        return params
    }

    private func makeThreadListParams(_ options: AppServerThreadListOptions) -> JSONObject {
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
            params["sortKey"] = .string(sortKey.rawValue)
        }
        if let sourceKinds = options.sourceKinds {
            params["sourceKinds"] = .array(sourceKinds.map { .string($0.rawValue) })
        }
        return params
    }

    private func makeTurnStartParams(threadID: String, input: [AppServerInputItem], options: AppServerTurnOptions) -> JSONObject {
        var params: JSONObject = [
            "threadId": .string(threadID),
            "input": .array(input.map(\.jsonValue)),
        ]
        if let approvalPolicy = options.approvalPolicy {
            params["approvalPolicy"] = approvalPolicy.jsonValue
        }
        if let approvalsReviewer = options.approvalsReviewer {
            params["approvalsReviewer"] = .string(approvalsReviewer.rawValue)
        }
        if let cwd = options.cwd {
            params["cwd"] = .string(cwd)
        }
        if let effort = options.effort {
            params["effort"] = .string(effort.rawValue)
        }
        if let model = options.model {
            params["model"] = .string(model)
        }
        if let outputSchema = options.outputSchema {
            params["outputSchema"] = .object(outputSchema)
        }
        if let personality = options.personality {
            params["personality"] = .string(personality.rawValue)
        }
        if let sandboxPolicy = options.sandboxPolicy {
            params["sandboxPolicy"] = sandboxPolicy.jsonValue
        }
        if let serviceTier = options.serviceTier {
            params["serviceTier"] = .string(serviceTier.rawValue)
        }
        if let summary = options.summary {
            params["summary"] = .string(summary.rawValue)
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

public actor AppServerCodex {
    private let client: AppServerClient
    private let initializePayload: AppServerV2.InitializeResponse

    public init(config: AppServerConfig = .init()) async throws {
        let client = AppServerClient(config: config)
        self.client = client
        self.initializePayload = try await client.initialize()
    }

    deinit {
        let client = self.client
        Task {
            await client.close()
        }
    }

    public func metadata() -> AppServerV2.InitializeResponse {
        initializePayload
    }

    public func close() async {
        await client.close()
    }

    public func startThread(options: AppServerThreadOptions = .init()) async throws -> AppServerThread {
        let response = try await client.threadStart(options: options)
        guard let threadID = response.thread?.id else {
            throw AppServerError.invalidResponse("thread/start response missing thread id")
        }
        return AppServerThread(client: client, id: threadID)
    }

    public func resumeThread(id: String, options: AppServerThreadOptions = .init()) async throws -> AppServerThread {
        let response = try await client.threadResume(threadID: id, options: options)
        guard let threadID = response.thread?.id else {
            throw AppServerError.invalidResponse("thread/resume response missing thread id")
        }
        return AppServerThread(client: client, id: threadID)
    }

    public func forkThread(id: String, options: AppServerThreadOptions = .init()) async throws -> AppServerThread {
        let response = try await client.threadFork(threadID: id, options: options)
        guard let threadID = response.thread?.id else {
            throw AppServerError.invalidResponse("thread/fork response missing thread id")
        }
        return AppServerThread(client: client, id: threadID)
    }

    public func listThreads(options: AppServerThreadListOptions = .init()) async throws -> AppServerV2.ThreadListResponse {
        try await client.threadList(options: options)
    }

    public func archiveThread(id: String) async throws -> AppServerV2.ThreadArchiveResponse {
        try await client.threadArchive(threadID: id)
    }

    public func unarchiveThread(id: String) async throws -> AppServerThread {
        let response = try await client.threadUnarchive(threadID: id)
        guard let threadID = response.thread?.id else {
            throw AppServerError.invalidResponse("thread/unarchive response missing thread id")
        }
        return AppServerThread(client: client, id: threadID)
    }

    public func models(includeHidden: Bool = false) async throws -> AppServerV2.ModelListResponse {
        try await client.modelList(includeHidden: includeHidden)
    }
}

public struct AppServerThread: Sendable {
    private let client: AppServerClient
    public let id: String

    init(client: AppServerClient, id: String) {
        self.client = client
        self.id = id
    }

    public func run(_ input: String, options: AppServerTurnOptions = .init()) async throws -> AppServerRunResult {
        try await run(.text(input), options: options)
    }

    public func run(_ input: AppServerInputItem, options: AppServerTurnOptions = .init()) async throws -> AppServerRunResult {
        try await run([input], options: options)
    }

    public func run(_ input: [AppServerInputItem], options: AppServerTurnOptions = .init()) async throws -> AppServerRunResult {
        let handle = try await turn(input, options: options)
        let stream = try await handle.stream()
        var completedTurn: AppServerV2.Turn?
        var usage: AppServerV2.ThreadTokenUsage?
        var items: [AppServerV2.ThreadItem] = []

        for try await notification in stream {
            switch notification.payload {
            case .itemCompleted(let payload):
                if payload.turnID == handle.id, let item = payload.item {
                    items.append(item)
                }
            case .threadTokenUsageUpdated(let payload):
                if payload.turnID == handle.id {
                    usage = payload.tokenUsage
                }
            case .turnCompleted(let payload):
                if payload.turn?.id == handle.id {
                    completedTurn = payload.turn
                }
            default:
                break
            }
        }

        guard let completedTurn else {
            throw AppServerError.invalidResponse("turn completed event not received")
        }
        if completedTurn.status == .failed {
            throw AppServerError.turnFailed(completedTurn.error?.message ?? "turn failed")
        }

        return AppServerRunResult(
            finalResponse: finalAssistantResponse(from: items),
            items: items,
            usage: usage
        )
    }

    public func turn(_ input: String, options: AppServerTurnOptions = .init()) async throws -> AppServerTurnHandle {
        try await turn([.text(input)], options: options)
    }

    public func turn(_ input: AppServerInputItem, options: AppServerTurnOptions = .init()) async throws -> AppServerTurnHandle {
        try await turn([input], options: options)
    }

    public func turn(_ input: [AppServerInputItem], options: AppServerTurnOptions = .init()) async throws -> AppServerTurnHandle {
        let response = try await client.turnStart(threadID: id, input: input, options: options)
        guard let turnID = response.turn?.id else {
            throw AppServerError.invalidResponse("turn/start response missing turn id")
        }
        return AppServerTurnHandle(client: client, threadID: id, id: turnID)
    }

    public func read(includeTurns: Bool = false) async throws -> AppServerV2.ThreadReadResponse {
        try await client.threadRead(threadID: id, includeTurns: includeTurns)
    }

    public func setName(_ name: String) async throws -> AppServerV2.ThreadSetNameResponse {
        try await client.threadSetName(threadID: id, name: name)
    }

    public func compact() async throws -> AppServerV2.ThreadCompactStartResponse {
        try await client.threadCompact(threadID: id)
    }
}

public struct AppServerTurnHandle: Sendable {
    private let client: AppServerClient
    private let threadID: String
    public let id: String

    init(client: AppServerClient, threadID: String, id: String) {
        self.client = client
        self.threadID = threadID
        self.id = id
    }

    public func steer(_ input: String) async throws -> AppServerV2.TurnSteerResponse {
        try await steer(.text(input))
    }

    public func steer(_ input: AppServerInputItem) async throws -> AppServerV2.TurnSteerResponse {
        try await client.turnSteer(threadID: threadID, expectedTurnID: id, input: [input])
    }

    public func steer(_ input: [AppServerInputItem]) async throws -> AppServerV2.TurnSteerResponse {
        try await client.turnSteer(threadID: threadID, expectedTurnID: id, input: input)
    }

    public func interrupt() async throws -> AppServerV2.TurnInterruptResponse {
        try await client.turnInterrupt(threadID: threadID, turnID: id)
    }

    public func stream() async throws -> AsyncThrowingStream<AppServerNotification, Error> {
        try await client.acquireTurnConsumer(turnID: id)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while true {
                        let notification = try await client.nextNotification()
                        continuation.yield(notification)
                        if notification.method == "turn/completed",
                           case .turnCompleted(let payload) = notification.payload,
                           payload.turn?.id == id {
                            continuation.finish()
                            break
                        }
                    }
                } catch {
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

    public func run() async throws -> AppServerV2.Turn {
        let stream = try await stream()
        var completedTurn: AppServerV2.Turn?
        for try await notification in stream {
            if case .turnCompleted(let payload) = notification.payload, payload.turn?.id == id {
                completedTurn = payload.turn
            }
        }
        guard let completedTurn else {
            throw AppServerError.invalidResponse("turn completed event not received")
        }
        return completedTurn
    }
}

public func isRetryableError(_ error: any Error) -> Bool {
    guard let error = error as? AppServerError else {
        return false
    }
    switch error {
    case .serverBusy, .retryLimitExceeded:
        return true
    case .jsonRPCError(_, _, let data):
        return AppServerErrorMapper.isServerOverloaded(data)
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
    if let modelType = T.self as? any AppServerV2ValueModel.Type {
        return modelType.init(jsonValue: value) as! T
    }
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

private func normalizedInitializePayload(_ payload: AppServerV2.InitializeResponse) throws -> AppServerV2.InitializeResponse {
    let userAgent = payload.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var serverName = payload.serverInfo?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var serverVersion = payload.serverInfo?.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if (serverName.isEmpty || serverVersion.isEmpty), !userAgent.isEmpty {
        let parsed = splitUserAgent(userAgent)
        if serverName.isEmpty {
            serverName = parsed.name ?? ""
        }
        if serverVersion.isEmpty {
            serverVersion = parsed.version ?? ""
        }
    }

    guard !userAgent.isEmpty, !serverName.isEmpty, !serverVersion.isEmpty else {
        throw AppServerError.missingMetadata
    }

    var object = payload.jsonObject ?? [:]
    object["userAgent"] = .string(userAgent)
    object["serverInfo"] = .object([
        "name": .string(serverName),
        "version": .string(serverVersion),
    ])
    return AppServerV2.InitializeResponse(jsonValue: .object(object))
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

private func finalAssistantResponse(from items: [AppServerV2.ThreadItem]) -> String? {
    var lastUnknownPhase: String?

    for item in items.reversed() {
        guard item.type == "agentMessage" else {
            continue
        }
        if item.phase == "final_answer" {
            return item.text
        }
        if item.phase == nil, lastUnknownPhase == nil {
            lastUnknownPhase = item.text
        }
    }

    return lastUnknownPhase
}

private extension AppServerInputItem {
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
