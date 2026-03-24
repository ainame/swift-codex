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

public typealias ThreadOptions = AppServerThreadOptions
