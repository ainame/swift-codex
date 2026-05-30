public enum Sandbox: String, Sendable, Hashable, Codable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case fullAccess = "full-access"

    public var threadMode: SandboxMode {
        switch self {
        case .readOnly:
            return .readOnly
        case .workspaceWrite:
            return .workspaceWrite
        case .fullAccess:
            return .dangerFullAccess
        }
    }

    public var turnPolicy: SandboxPolicy {
        switch self {
        case .readOnly:
            return .readOnly(ReadOnlySandboxPolicy(type: .readOnly))
        case .workspaceWrite:
            return .workspaceWrite(WorkspaceWriteSandboxPolicy(type: .workspaceWrite))
        case .fullAccess:
            return .dangerFullAccess(DangerFullAccessSandboxPolicy(type: .dangerFullAccess))
        }
    }
}
