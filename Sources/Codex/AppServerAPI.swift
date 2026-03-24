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

public struct AppServerMetadata: Sendable, Hashable, Codable {
    public var userAgent: String
    public var serverName: String
    public var serverVersion: String

    public init(userAgent: String, serverName: String, serverVersion: String) {
        self.userAgent = userAgent
        self.serverName = serverName
        self.serverVersion = serverVersion
    }
}

public struct AppServerThreadOptions: Sendable, Hashable, Codable {
    public var model: String?
    public var sandboxMode: SandboxMode?
    public var workingDirectory: String?
    public var approvalPolicy: ApprovalMode?
    public var config: JSONObject?

    public init(
        model: String? = nil,
        sandboxMode: SandboxMode? = nil,
        workingDirectory: String? = nil,
        approvalPolicy: ApprovalMode? = nil,
        config: JSONObject? = nil
    ) {
        self.model = model
        self.sandboxMode = sandboxMode
        self.workingDirectory = workingDirectory
        self.approvalPolicy = approvalPolicy
        self.config = config
    }
}

public enum AppServerEvent: Sendable, Hashable, Codable {
    case threadStarted(String)
    case turnStarted(String)
    case itemStarted(ThreadItem)
    case itemCompleted(ThreadItem)
    case turnCompleted
    case turnFailed(String)
}

public enum AppServerError: Error, Sendable, Hashable {
    case transportClosed
    case transportClosedWithStderrTail(String)
    case invalidResponseLine(String)
    case invalidResponse(String)
    case invalidRequestID
    case missingMetadata
    case jsonRPCError(code: Int, message: String)
    case unsupportedServerRequest(String)
    case concurrentTurnConsumer(activeTurnID: String, requestedTurnID: String)
    case turnFailed(String)
}

public struct AppServerConfig: Sendable {
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
        commandApprovalHandler: @escaping CommandApprovalHandler = { _ in .deny },
        fileChangeApprovalHandler: @escaping FileChangeApprovalHandler = { _ in .deny }
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
        self.commandApprovalHandler = commandApprovalHandler
        self.fileChangeApprovalHandler = fileChangeApprovalHandler
    }
}

public actor AppServerCodex {
    private let transport: AppServerTransport
    private let startupMetadata: AppServerMetadata

    public init(config: AppServerConfig = .init()) async throws {
        let transport = AppServerTransport(config: config)
        self.transport = transport
        self.startupMetadata = try await transport.start()
    }

    deinit {
        let transport = self.transport
        Task {
            await transport.close()
        }
    }

    public func metadata() -> AppServerMetadata {
        startupMetadata
    }

    public func close() async {
        await transport.close()
    }

    public func startThread(options: AppServerThreadOptions = .init()) async throws -> AppServerThread {
        let threadID = try await transport.startThread(options: options)
        return AppServerThread(transport: transport, id: threadID)
    }

    public func resumeThread(id: String, options: AppServerThreadOptions = .init()) async throws -> AppServerThread {
        let threadID = try await transport.resumeThread(id: id, options: options)
        return AppServerThread(transport: transport, id: threadID)
    }
}

public struct AppServerThread: Sendable {
    private let transport: AppServerTransport
    public let id: String

    init(transport: AppServerTransport, id: String) {
        self.transport = transport
        self.id = id
    }

    public func turn(_ input: String, options: TurnOptions = .init()) async throws -> AppServerTurnHandle {
        try await turn([.text(input)], options: options)
    }

    public func turn(_ input: [UserInput], options: TurnOptions = .init()) async throws -> AppServerTurnHandle {
        let turnID = try await transport.startTurn(threadID: id, input: input, options: options)
        return AppServerTurnHandle(transport: transport, threadID: id, turnID: turnID)
    }

    public func run(_ input: String, options: TurnOptions = .init()) async throws -> RunResult {
        try await turn(input, options: options).run()
    }

    public func run(_ input: [UserInput], options: TurnOptions = .init()) async throws -> RunResult {
        try await turn(input, options: options).run()
    }
}

public struct AppServerTurnHandle: Sendable {
    private let transport: AppServerTransport
    private let threadID: String
    public let id: String

    init(transport: AppServerTransport, threadID: String, turnID: String) {
        self.transport = transport
        self.threadID = threadID
        self.id = turnID
    }

    public func stream() async throws -> AsyncThrowingStream<AppServerEvent, Error> {
        try await transport.openTurnStream(threadID: threadID, turnID: id)
    }

    public func interrupt() async throws {
        try await transport.interruptTurn(threadID: threadID, turnID: id)
    }

    public func run() async throws -> RunResult {
        let stream = try await stream()
        var items: [ThreadItem] = []
        var finalResponse = ""

        for try await event in stream {
            switch event {
            case .itemCompleted(let item):
                items.append(item)
                if case .agentMessage(let message) = item {
                    finalResponse = message.text
                }
            case .turnFailed(let message):
                throw AppServerError.turnFailed(message)
            default:
                break
            }
        }

        return RunResult(items: items, finalResponse: finalResponse, usage: nil)
    }
}
