public struct Usage: Sendable, Hashable, Codable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
    }
}

public struct ThreadError: Sendable, Hashable, Codable {
    public var message: String
}

public struct ThreadStartedEvent: Sendable, Hashable, Codable {
    public var type: String = "thread.started"
    public var threadID: String

    enum CodingKeys: String, CodingKey {
        case type
        case threadID = "thread_id"
    }
}

public struct TurnStartedEvent: Sendable, Hashable, Codable {
    public var type: String = "turn.started"
}

public struct TurnCompletedEvent: Sendable, Hashable, Codable {
    public var type: String = "turn.completed"
    public var usage: Usage
}

public struct TurnFailedEvent: Sendable, Hashable, Codable {
    public var type: String = "turn.failed"
    public var error: ThreadError
}

public struct ItemStartedEvent: Sendable, Hashable, Codable {
    public var type: String = "item.started"
    public var item: ThreadItem
}

public struct ItemUpdatedEvent: Sendable, Hashable, Codable {
    public var type: String = "item.updated"
    public var item: ThreadItem
}

public struct ItemCompletedEvent: Sendable, Hashable, Codable {
    public var type: String = "item.completed"
    public var item: ThreadItem
}

public struct ThreadStreamErrorEvent: Sendable, Hashable, Codable {
    public var type: String = "error"
    public var message: String
}

public enum ThreadEvent: Sendable, Hashable, Codable {
    case threadStarted(ThreadStartedEvent)
    case turnStarted(TurnStartedEvent)
    case turnCompleted(TurnCompletedEvent)
    case turnFailed(TurnFailedEvent)
    case itemStarted(ItemStartedEvent)
    case itemUpdated(ItemUpdatedEvent)
    case itemCompleted(ItemCompletedEvent)
    case error(ThreadStreamErrorEvent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "thread.started":
            self = .threadStarted(try ThreadStartedEvent(from: decoder))
        case "turn.started":
            self = .turnStarted(try TurnStartedEvent(from: decoder))
        case "turn.completed":
            self = .turnCompleted(try TurnCompletedEvent(from: decoder))
        case "turn.failed":
            self = .turnFailed(try TurnFailedEvent(from: decoder))
        case "item.started":
            self = .itemStarted(try ItemStartedEvent(from: decoder))
        case "item.updated":
            self = .itemUpdated(try ItemUpdatedEvent(from: decoder))
        case "item.completed":
            self = .itemCompleted(try ItemCompletedEvent(from: decoder))
        case "error":
            self = .error(try ThreadStreamErrorEvent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported thread event type"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .threadStarted(let value):
            try value.encode(to: encoder)
        case .turnStarted(let value):
            try value.encode(to: encoder)
        case .turnCompleted(let value):
            try value.encode(to: encoder)
        case .turnFailed(let value):
            try value.encode(to: encoder)
        case .itemStarted(let value):
            try value.encode(to: encoder)
        case .itemUpdated(let value):
            try value.encode(to: encoder)
        case .itemCompleted(let value):
            try value.encode(to: encoder)
        case .error(let value):
            try value.encode(to: encoder)
        }
    }
}
