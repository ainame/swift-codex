import Foundation

public protocol CodexRPCTransporting: Sendable {
    func start() async throws
    func close() async
    func request(method: String, params: JSONObject) async throws -> JSONValue
    func notify(method: String, params: JSONObject) async throws
    func nextNotification() async throws -> CodexNotification
}
