import Codex
import Foundation

func responseEnvelope(result: JSONValue) -> JSONValue {
    .object([
        "type": .string("response"),
        "result": result,
    ])
}

func notificationEnvelope(_ notification: CodexNotification) -> JSONValue {
    .object([
        "type": .string("notification"),
        "method": .string(notification.method),
        "params": notification.rawParams,
    ])
}

func serverRequestEnvelope(requestID: String, request: ServerRequest) -> JSONValue {
    let method: String
    let params: JSONValue?
    switch request {
    case .commandApproval(let value):
        method = "item/commandExecution/requestApproval"
        params = try? encodeBridgeJSONValue(value)
    case .fileChangeApproval(let value):
        method = "item/fileChange/requestApproval"
        params = try? encodeBridgeJSONValue(value)
    case .unknown(let rawMethod, let rawParams):
        method = rawMethod
        params = rawParams
    }
    return .object([
        "type": .string("serverRequest"),
        "requestId": .string(requestID),
        "method": .string(method),
        "params": params ?? .null,
    ])
}

func errorEnvelope(_ error: any Error) -> JSONValue {
    .object([
        "type": .string("error"),
        "message": .string(error.localizedDescription),
    ])
}

func turnID(fromTurnStartResult result: JSONValue) -> String? {
    result.objectValue(forKey: "turn")?["id"]?.stringValue
        ?? result.stringValue(forKey: "turnId")
}

func encodeBridgeJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}
