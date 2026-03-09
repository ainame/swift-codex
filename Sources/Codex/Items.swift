public enum CommandExecutionStatus: String, Sendable, Hashable, Codable {
    case inProgress = "in_progress"
    case completed
    case failed
}

public enum PatchChangeKind: String, Sendable, Hashable, Codable {
    case add
    case delete
    case update
}

public enum PatchApplyStatus: String, Sendable, Hashable, Codable {
    case completed
    case failed
}

public enum McpToolCallStatus: String, Sendable, Hashable, Codable {
    case inProgress = "in_progress"
    case completed
    case failed
}

public struct CommandExecutionItem: Sendable, Hashable, Codable {
    public var id: String
    public var type: String = "command_execution"
    public var command: String
    public var aggregatedOutput: String
    public var exitCode: Int?
    public var status: CommandExecutionStatus

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case command
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
        case status
    }
}

public struct FileUpdateChange: Sendable, Hashable, Codable {
    public var path: String
    public var kind: PatchChangeKind
}

public struct FileChangeItem: Sendable, Hashable, Codable {
    public var id: String
    public var type: String = "file_change"
    public var changes: [FileUpdateChange]
    public var status: PatchApplyStatus
}

public struct McpToolCallResult: Sendable, Hashable, Codable {
    public var content: [JSONValue]
    public var structuredContent: JSONValue?

    enum CodingKeys: String, CodingKey {
        case content
        case structuredContent = "structured_content"
    }
}

public struct ItemError: Sendable, Hashable, Codable {
    public var message: String
}

public struct McpToolCallItem: Sendable, Hashable, Codable {
    public var id: String
    public var type: String = "mcp_tool_call"
    public var server: String
    public var tool: String
    public var arguments: JSONValue?
    public var result: McpToolCallResult?
    public var error: ItemError?
    public var status: McpToolCallStatus
}

public struct AgentMessageItem: Sendable, Hashable, Codable {
    public var id: String
    public var type: String = "agent_message"
    public var text: String
}

public struct ReasoningItem: Sendable, Hashable, Codable {
    public var id: String
    public var type: String = "reasoning"
    public var text: String
}

public struct WebSearchItem: Sendable, Hashable, Codable {
    public var id: String
    public var type: String = "web_search"
    public var query: String
}

public struct ErrorItem: Sendable, Hashable, Codable {
    public var id: String
    public var type: String = "error"
    public var message: String
}

public struct TodoItem: Sendable, Hashable, Codable {
    public var text: String
    public var completed: Bool
}

public struct TodoListItem: Sendable, Hashable, Codable {
    public var id: String
    public var type: String = "todo_list"
    public var items: [TodoItem]
}

public enum ThreadItem: Sendable, Hashable, Codable {
    case agentMessage(AgentMessageItem)
    case reasoning(ReasoningItem)
    case commandExecution(CommandExecutionItem)
    case fileChange(FileChangeItem)
    case mcpToolCall(McpToolCallItem)
    case webSearch(WebSearchItem)
    case todoList(TodoListItem)
    case error(ErrorItem)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "agent_message":
            self = .agentMessage(try AgentMessageItem(from: decoder))
        case "reasoning":
            self = .reasoning(try ReasoningItem(from: decoder))
        case "command_execution":
            self = .commandExecution(try CommandExecutionItem(from: decoder))
        case "file_change":
            self = .fileChange(try FileChangeItem(from: decoder))
        case "mcp_tool_call":
            self = .mcpToolCall(try McpToolCallItem(from: decoder))
        case "web_search":
            self = .webSearch(try WebSearchItem(from: decoder))
        case "todo_list":
            self = .todoList(try TodoListItem(from: decoder))
        case "error":
            self = .error(try ErrorItem(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported thread item type"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .agentMessage(let value):
            try value.encode(to: encoder)
        case .reasoning(let value):
            try value.encode(to: encoder)
        case .commandExecution(let value):
            try value.encode(to: encoder)
        case .fileChange(let value):
            try value.encode(to: encoder)
        case .mcpToolCall(let value):
            try value.encode(to: encoder)
        case .webSearch(let value):
            try value.encode(to: encoder)
        case .todoList(let value):
            try value.encode(to: encoder)
        case .error(let value):
            try value.encode(to: encoder)
        }
    }
}
