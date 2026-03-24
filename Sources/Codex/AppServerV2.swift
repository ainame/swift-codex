import Foundation

public enum AppServerV2 {}

public protocol AppServerV2ValueModel: Sendable, Hashable, Codable {
    var jsonValue: JSONValue { get set }
    init(jsonValue: JSONValue)
}

extension AppServerV2ValueModel {
    public init(from decoder: any Decoder) throws {
        self.init(jsonValue: try JSONValue(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try jsonValue.encode(to: encoder)
    }

    public var jsonObject: JSONObject? {
        jsonValue.objectValue
    }

    public var stringValue: String? {
        jsonValue.stringValue
    }
}

extension AppServerV2 {
    public enum ApprovalsReviewer: String, Sendable, Hashable, Codable {
        case user
        case guardianSubagent = "guardian_subagent"
    }

    public enum Personality: String, Sendable, Hashable, Codable {
        case none
        case friendly
        case pragmatic
    }

    public enum ReasoningEffort: String, Sendable, Hashable, Codable {
        case none
        case minimal
        case low
        case medium
        case high
        case xhigh
    }

    public enum ReasoningSummary: String, Sendable, Hashable, Codable {
        case none
        case auto
        case concise
        case detailed
    }

    public enum SandboxMode: String, Sendable, Hashable, Codable {
        case readOnly = "read-only"
        case workspaceWrite = "workspace-write"
        case dangerFullAccess = "danger-full-access"
    }

    public enum ServiceTier: String, Sendable, Hashable, Codable {
        case fast
        case flex
    }

    public enum ThreadSortKey: String, Sendable, Hashable, Codable {
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public enum ThreadSourceKind: String, Sendable, Hashable, Codable {
        case cli
        case vscode
        case exec
        case appServer = "appServer"
        case subAgent = "subAgent"
        case subAgentReview = "subAgentReview"
        case subAgentCompact = "subAgentCompact"
        case subAgentThreadSpawn = "subAgentThreadSpawn"
        case subAgentOther = "subAgentOther"
        case unknown
    }

    public enum TurnStatus: String, Sendable, Hashable, Codable {
        case completed
        case interrupted
        case failed
        case inProgress = "inProgress"
    }

    public enum PlanType: String, Sendable, Hashable, Codable {
        case free
        case go
        case plus
        case pro
        case team
        case business
        case enterprise
        case edu
        case unknown
    }

    public enum AskForApproval: Sendable, Hashable, Codable {
        case mode(ApprovalMode)
        case granular(JSONObject)

        public init(from decoder: any Decoder) throws {
            let value = try JSONValue(from: decoder)
            switch value {
            case .string(let raw):
                guard let mode = ApprovalMode(rawValue: raw) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "Unsupported approval mode: \(raw)")
                    )
                }
                self = .mode(mode)
            case .object(let object):
                self = .granular(object)
            default:
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unsupported approval payload")
                )
            }
        }

        public func encode(to encoder: any Encoder) throws {
            switch self {
            case .mode(let mode):
                try JSONValue.string(mode.rawValue).encode(to: encoder)
            case .granular(let object):
                try JSONValue.object(object).encode(to: encoder)
            }
        }

        public var jsonValue: JSONValue {
            switch self {
            case .mode(let mode):
                return .string(mode.rawValue)
            case .granular(let object):
                return .object(object)
            }
        }

        public init(_ mode: ApprovalMode) {
            self = .mode(mode)
        }
    }

    public struct SandboxPolicy: AppServerV2ValueModel {
        public var jsonValue: JSONValue

        public init(jsonValue: JSONValue) {
            self.jsonValue = jsonValue
        }
    }
}

public struct AppServerNotification: Sendable, Hashable, Codable {
    public var method: String
    public var payload: AppServerNotificationPayload
    public var rawParams: JSONValue

    init(method: String, params: JSONValue) {
        self.method = method
        self.payload = AppServerNotificationPayload(method: method, params: params)
        self.rawParams = params
    }
}

extension AppServerNotification {
    var threadID: String? {
        switch payload {
        case .threadStarted(let payload):
            return payload.thread?.id
        case .threadStatusChanged(let payload):
            return payload.threadID
        case .threadArchived(let payload):
            return payload.threadID
        case .threadUnarchived(let payload):
            return payload.threadID
        case .threadClosed(let payload):
            return payload.threadID
        case .threadNameUpdated(let payload):
            return payload.threadID
        case .threadTokenUsageUpdated(let payload):
            return payload.threadID
        case .turnStarted(let payload):
            return payload.threadID
        case .turnCompleted(let payload):
            return payload.threadID
        case .turnDiffUpdated(let payload):
            return payload.threadID
        case .turnPlanUpdated(let payload):
            return payload.threadID
        case .itemStarted(let payload):
            return payload.threadID
        case .itemCompleted(let payload):
            return payload.threadID
        case .agentMessageDelta(let payload):
            return payload.threadID
        case .planDelta(let payload):
            return payload.threadID
        case .commandExecutionOutputDelta(let payload):
            return payload.threadID
        case .terminalInteraction(let payload):
            return payload.threadID
        case .fileChangeOutputDelta(let payload):
            return payload.threadID
        case .serverRequestResolved(let payload):
            return payload.threadID
        case .mcpToolCallProgress(let payload):
            return payload.threadID
        case .reasoningSummaryTextDelta(let payload):
            return payload.threadID
        case .reasoningSummaryPartAdded(let payload):
            return payload.threadID
        case .reasoningTextDelta(let payload):
            return payload.threadID
        case .contextCompacted(let payload):
            return payload.threadID
        case .threadRealtimeStarted(let payload):
            return payload.threadID
        case .threadRealtimeItemAdded(let payload):
            return payload.threadID
        case .threadRealtimeOutputAudioDelta(let payload):
            return payload.threadID
        case .threadRealtimeError(let payload):
            return payload.threadID
        case .threadRealtimeClosed(let payload):
            return payload.threadID
        case .unknown:
            return rawParams.objectValue?.stringValue(forKey: "threadId")
        default:
            return nil
        }
    }

    var turnID: String? {
        switch payload {
        case .threadTokenUsageUpdated(let payload):
            return payload.turnID
        case .turnStarted(let payload):
            return payload.turn?.id
        case .turnCompleted(let payload):
            return payload.turn?.id
        case .turnDiffUpdated(let payload):
            return payload.turnID
        case .turnPlanUpdated(let payload):
            return payload.turnID
        case .itemStarted(let payload):
            return payload.turnID
        case .itemCompleted(let payload):
            return payload.turnID
        case .agentMessageDelta(let payload):
            return payload.turnID
        case .planDelta(let payload):
            return payload.turnID
        case .commandExecutionOutputDelta(let payload):
            return payload.turnID
        case .terminalInteraction(let payload):
            return payload.turnID
        case .fileChangeOutputDelta(let payload):
            return payload.turnID
        case .serverRequestResolved(let payload):
            return payload.turnID
        case .mcpToolCallProgress(let payload):
            return payload.turnID
        case .reasoningSummaryTextDelta(let payload):
            return payload.turnID
        case .reasoningSummaryPartAdded(let payload):
            return payload.turnID
        case .reasoningTextDelta(let payload):
            return payload.turnID
        case .contextCompacted(let payload):
            return payload.turnID
        case .unknown:
            return rawParams.objectValue?.stringValue(forKey: "turnId")
        default:
            return nil
        }
    }
}

public extension AppServerV2.InitializeResponse {
    var serverInfo: AppServerV2.ServerInfo? { jsonObject?.valueModel(forKey: "serverInfo") }
    var userAgent: String? { jsonObject?.stringValue(forKey: "userAgent") }
    var platformFamily: String? { jsonObject?.stringValue(forKey: "platformFamily") }
    var platformOS: String? { jsonObject?.stringValue(forKey: "platformOs") }
    var serverName: String? { serverInfo?.name }
    var serverVersion: String? { serverInfo?.version }
}

public extension AppServerV2.ServerInfo {
    var name: String? { jsonObject?.stringValue(forKey: "name") }
    var version: String? { jsonObject?.stringValue(forKey: "version") }
}

public extension AppServerV2.Thread {
    var id: String? { jsonObject?.stringValue(forKey: "id") }
    var turns: [AppServerV2.Turn] {
        jsonObject?.valueModels(forKey: "turns") ?? []
    }
}

public extension AppServerV2.ThreadStartResponse {
    var thread: AppServerV2.Thread? { jsonObject?.valueModel(forKey: "thread") }
}

public extension AppServerV2.ThreadResumeResponse {
    var thread: AppServerV2.Thread? { jsonObject?.valueModel(forKey: "thread") }
}

public extension AppServerV2.ThreadForkResponse {
    var thread: AppServerV2.Thread? { jsonObject?.valueModel(forKey: "thread") }
}

public extension AppServerV2.ThreadUnarchiveResponse {
    var thread: AppServerV2.Thread? { jsonObject?.valueModel(forKey: "thread") }
}

public extension AppServerV2.TurnStartResponse {
    var turn: AppServerV2.Turn? { jsonObject?.valueModel(forKey: "turn") }
}

public extension AppServerV2.TurnSteerResponse {
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.TurnInterruptResponse {
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.Turn {
    var id: String? { jsonObject?.stringValue(forKey: "id") }
    var status: AppServerV2.TurnStatus? { jsonObject?.stringValue(forKey: "status").flatMap(AppServerV2.TurnStatus.init(rawValue:)) }
    var error: AppServerV2.TurnError? { jsonObject?.valueModel(forKey: "error") }
    var items: [AppServerV2.ThreadItem] {
        jsonObject?.valueModels(forKey: "items") ?? []
    }
}

public extension AppServerV2.TurnError {
    var message: String? { jsonObject?.stringValue(forKey: "message") }
}

public extension AppServerV2.ThreadItem {
    var id: String? { jsonObject?.stringValue(forKey: "id") }
    var type: String? { jsonObject?.stringValue(forKey: "type") }
    var text: String? { jsonObject?.stringValue(forKey: "text") }
    var phase: String? { jsonObject?.stringValue(forKey: "phase") }
}

public extension AppServerV2.ThreadStartedNotification {
    var thread: AppServerV2.Thread? { jsonObject?.valueModel(forKey: "thread") }
}

public extension AppServerV2.ThreadStatusChangedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

public extension AppServerV2.ThreadArchivedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

public extension AppServerV2.ThreadUnarchivedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var thread: AppServerV2.Thread? { jsonObject?.valueModel(forKey: "thread") }
}

public extension AppServerV2.ThreadClosedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

public extension AppServerV2.ThreadNameUpdatedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

public extension AppServerV2.ThreadTokenUsageUpdatedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
    var tokenUsage: AppServerV2.ThreadTokenUsage? { jsonObject?.valueModel(forKey: "tokenUsage") }
}

public extension AppServerV2.TurnStartedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turn: AppServerV2.Turn? { jsonObject?.valueModel(forKey: "turn") }
}

public extension AppServerV2.TurnCompletedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turn: AppServerV2.Turn? { jsonObject?.valueModel(forKey: "turn") }
}

public extension AppServerV2.TurnDiffUpdatedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.TurnPlanUpdatedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.ItemStartedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
    var item: AppServerV2.ThreadItem? { jsonObject?.valueModel(forKey: "item") }
}

public extension AppServerV2.ItemCompletedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
    var item: AppServerV2.ThreadItem? { jsonObject?.valueModel(forKey: "item") }
}

public extension AppServerV2.AgentMessageDeltaNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.PlanDeltaNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.CommandExecutionOutputDeltaNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.TerminalInteractionNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.FileChangeOutputDeltaNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.ServerRequestResolvedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.McpToolCallProgressNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.ReasoningSummaryTextDeltaNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.ReasoningSummaryPartAddedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.ReasoningTextDeltaNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.ContextCompactedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
    var turnID: String? { jsonObject?.stringValue(forKey: "turnId") }
}

public extension AppServerV2.ThreadRealtimeStartedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

public extension AppServerV2.ThreadRealtimeItemAddedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

public extension AppServerV2.ThreadRealtimeOutputAudioDeltaNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

public extension AppServerV2.ThreadRealtimeErrorNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

public extension AppServerV2.ThreadRealtimeClosedNotification {
    var threadID: String? { jsonObject?.stringValue(forKey: "threadId") }
}

extension JSONValue {
    var objectValue: JSONObject? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(forKey key: String) -> String? {
        self[key]?.stringValue
    }

    func valueModel<T: AppServerV2ValueModel>(forKey key: String) -> T? {
        self[key].map(T.init(jsonValue:))
    }

    func valueModels<T: AppServerV2ValueModel>(forKey key: String) -> [T] {
        guard let values = self[key]?.arrayValue else {
            return []
        }
        return values.map(T.init(jsonValue:))
    }
}
