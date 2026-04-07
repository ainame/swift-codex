import Foundation

public protocol RawJSONRepresentable: Codable, Hashable, Sendable {
    var rawJSON: JSONValue { get }
}

public protocol ObjectModel: RawJSONRepresentable {
    var additionalFields: JSONObject { get }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

func decodeJSONValue<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

func encodeJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}

func losslessEncodeJSONValue<T: Encodable>(_ value: T, context: String) -> JSONValue {
    do {
        return try encodeJSONValue(value)
    } catch {
        fatalError("Failed to encode \(context) to JSONValue: \(error)")
    }
}

func decodeJSONObject(from decoder: any Decoder, context: String) throws -> JSONObject {
    let value = try JSONValue(from: decoder)
    guard case .object(let object) = value else {
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "\(context) must decode from a JSON object")
        )
    }
    return object
}

func mergedJSONObject<T: Encodable>(_ payload: T, additionalFields: JSONObject, context: String) -> JSONObject {
    let value = losslessEncodeJSONValue(payload, context: context)
    guard var object = value.objectValue else {
        fatalError("Expected \(context) payload to encode as a JSON object")
    }
    for (key, value) in additionalFields {
        object[key] = value
    }
    return object
}

func encodeJSONObject<T: Encodable>(_ payload: T, additionalFields: JSONObject, context: String, to encoder: any Encoder) throws {
    try JSONValue.object(mergedJSONObject(payload, additionalFields: additionalFields, context: context)).encode(to: encoder)
}
