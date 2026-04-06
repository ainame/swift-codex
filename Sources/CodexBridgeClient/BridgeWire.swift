import CodexCore
import Foundation

struct BridgeCreateSessionResponse: Decodable {
    let sessionId: String
}

struct BridgeRPCRequestBody: Encodable {
    let method: String
    let params: JSONValue
    let notification: Bool
}

struct BridgeServerRequestResponse: Encodable {
    let result: JSONValue
}

enum BridgeEnvelope: Decodable {
    case response(JSONValue)
    case notification(method: String, params: JSONValue)
    case serverRequest(requestID: String, method: String, params: JSONValue?)
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case result
        case method
        case params
        case requestId
        case message
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "response":
            self = .response(try container.decode(JSONValue.self, forKey: .result))
        case "notification":
            self = .notification(
                method: try container.decode(String.self, forKey: .method),
                params: try container.decode(JSONValue.self, forKey: .params)
            )
        case "serverRequest":
            self = .serverRequest(
                requestID: try container.decode(String.self, forKey: .requestId),
                method: try container.decode(String.self, forKey: .method),
                params: try container.decodeIfPresent(JSONValue.self, forKey: .params)
            )
        case "error":
            self = .error(try container.decode(String.self, forKey: .message))
        default:
            throw CodexError.invalidResponse("Unknown CodexBridge envelope type: \(type)")
        }
    }
}
