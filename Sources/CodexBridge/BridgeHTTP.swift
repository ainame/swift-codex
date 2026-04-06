import Codex
import Foundation
import Hummingbird

enum BridgeError: LocalizedError {
    case invalidRequestBody(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequestBody(let description):
            return "invalid request body: \(description)"
        }
    }
}

struct BridgeRPCRequest: Decodable {
    let method: String
    let params: JSONValue?
    let notification: Bool?
}

struct BridgeCreateSessionResponse: Encodable {
    let sessionId: String
}

struct BridgeServerRequestResponse: Decodable {
    let result: JSONValue
}

func decodeRequest<T: Decodable>(_ type: T.Type, from request: Request) async throws -> T {
    var request = request
    let buffer = try await request.collectBody(upTo: 1_048_576)
    let data = Data(buffer.readableBytesView)
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw BridgeError.invalidRequestBody(error.localizedDescription)
    }
}

func ndjsonResponse<S: AsyncSequence & Sendable>(_ stream: S) -> Response where S.Element == ByteBuffer {
    var headers = HTTPFields()
    headers[.contentType] = "application/x-ndjson"
    return Response(status: .ok, headers: headers, body: .init(asyncSequence: stream))
}

func jsonResponse<T: Encodable>(_ value: T) throws -> Response {
    let data = try JSONEncoder().encode(value)
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    return Response(status: .ok, headers: headers, body: .init(byteBuffer: buffer))
}

func encodeJSONLine(_ value: JSONValue) throws -> ByteBuffer {
    let data = try JSONEncoder().encode(value)
    var buffer = ByteBufferAllocator().buffer(capacity: data.count + 1)
    buffer.writeBytes(data)
    buffer.writeInteger(UInt8(ascii: "\n"))
    return buffer
}
