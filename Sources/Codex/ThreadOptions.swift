public enum ApprovalMode: String, Sendable, Hashable, Codable {
    case never
    case onRequest = "on-request"
    case onFailure = "on-failure"
    case untrusted
}

public enum SandboxMode: String, Sendable, Hashable, Codable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

public enum ModelReasoningEffort: String, Sendable, Hashable, Codable {
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public enum WebSearchMode: String, Sendable, Hashable, Codable {
    case disabled
    case cached
    case live
}

public struct ThreadOptions: Sendable, Hashable {
    public var model: String?
    public var sandboxMode: SandboxMode?
    public var workingDirectory: String?
    public var skipGitRepoCheck: Bool
    public var modelReasoningEffort: ModelReasoningEffort?
    public var networkAccessEnabled: Bool?
    public var webSearchMode: WebSearchMode?
    public var webSearchEnabled: Bool?
    public var approvalPolicy: ApprovalMode?
    public var additionalDirectories: [String]

    public init(
        model: String? = nil,
        sandboxMode: SandboxMode? = nil,
        workingDirectory: String? = nil,
        skipGitRepoCheck: Bool = false,
        modelReasoningEffort: ModelReasoningEffort? = nil,
        networkAccessEnabled: Bool? = nil,
        webSearchMode: WebSearchMode? = nil,
        webSearchEnabled: Bool? = nil,
        approvalPolicy: ApprovalMode? = nil,
        additionalDirectories: [String] = []
    ) {
        self.model = model
        self.sandboxMode = sandboxMode
        self.workingDirectory = workingDirectory
        self.skipGitRepoCheck = skipGitRepoCheck
        self.modelReasoningEffort = modelReasoningEffort
        self.networkAccessEnabled = networkAccessEnabled
        self.webSearchMode = webSearchMode
        self.webSearchEnabled = webSearchEnabled
        self.approvalPolicy = approvalPolicy
        self.additionalDirectories = additionalDirectories
    }
}
