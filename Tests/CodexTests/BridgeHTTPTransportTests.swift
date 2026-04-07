import Foundation
import Testing
@testable import CodexBridgeClient
@testable import CodexCore

@Suite(.serialized)
struct BridgeHTTPTransportTests {
    @Test
    func bridgeTransportCreatesSessionAndBuffersStreamedNotifications() async throws {
        let server = MockBridgeHTTPServer(emitsServerRequest: false)
        MockBridgeURLProtocol.handler = { request in
            try server.handle(request)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let session = URLSession(configuration: config)
        let transport = CodexBridgeHTTPTransport(
            bridgeURL: URL(string: "https://bridge.example.test")!,
            config: .init(),
            urlSession: session
        )

        try await transport.start()
        let result = try await transport.request(method: "turn/start", params: ["threadId": .string("thread-1")])
        #expect(result.objectValue?.stringValue(forKey: "ok") == "started")

        let notification = try await transport.nextNotification()
        #expect(notification.method == "turn/completed")
        #expect(notification.rawParams.objectValue?.stringValue(forKey: "turnId") == "turn-1")

        await transport.close()
        #expect(server.requests.map(\.path) == [
            "/sessions",
            "/sessions/session-1/rpc",
            "/sessions/session-1",
        ])
    }

    @Test
    func bridgeTransportRoutesServerRequestsBackToApprovalHandlers() async throws {
        let server = MockBridgeHTTPServer(emitsServerRequest: true)
        MockBridgeURLProtocol.handler = { request in
            try server.handle(request)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockBridgeURLProtocol.self]
        let session = URLSession(configuration: config)
        let transport = CodexBridgeHTTPTransport(
            bridgeURL: URL(string: "https://bridge.example.test")!,
            config: .init(commandApprovalHandler: { request in
                #expect(request.threadID == "thread-1")
                #expect(request.turnID == "turn-1")
                #expect(request.itemID == "item-1")
                return .deny
            }),
            urlSession: session
        )

        _ = try await transport.request(method: "turn/start", params: ["threadId": .string("thread-1")])
        _ = try await transport.nextNotification()
        let postedResponse = try #require(server.serverRequestResponse)
        #expect(postedResponse == .object(["result": .object(["decision": .string("decline")])]))
    }
}

private final class MockBridgeURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> MockBridgeHTTPResponse)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let response = try handler(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct MockBridgeHTTPResponse: Sendable {
    var statusCode: Int
    var headers: [String: String]
    var body: Data
}

private final class MockBridgeHTTPServer: @unchecked Sendable {
    private let emitsServerRequest: Bool
    private let lock = NSLock()
    private var recordedRequests: [RecordedRequest] = []
    private var recordedServerRequestResponse: JSONValue?

    init(emitsServerRequest: Bool) {
        self.emitsServerRequest = emitsServerRequest
    }

    var requests: [RecordedRequest] {
        lock.withLock { recordedRequests }
    }

    var serverRequestResponse: JSONValue? {
        lock.withLock { recordedServerRequestResponse }
    }

    func handle(_ request: URLRequest) throws -> MockBridgeHTTPResponse {
        let path = request.url?.path ?? ""
        lock.withLock {
            recordedRequests.append(RecordedRequest(method: request.httpMethod ?? "", path: path))
        }

        switch (request.httpMethod, path) {
        case ("POST", "/sessions"):
            return json(["sessionId": "session-1"])
        case ("POST", "/sessions/session-1/rpc"):
            var envelopes: [JSONValue] = [
                .object([
                    "type": .string("response"),
                    "result": .object(["ok": .string("started")]),
                ]),
            ]
            if emitsServerRequest {
                envelopes.append(.object([
                    "type": .string("serverRequest"),
                    "requestId": .string("approval-1"),
                    "method": .string("item/commandExecution/requestApproval"),
                    "params": .object([
                        "threadId": .string("thread-1"),
                        "turnId": .string("turn-1"),
                        "itemId": .string("item-1"),
                    ]),
                ]))
            }
            envelopes.append(.object([
                "type": .string("notification"),
                "method": .string("turn/completed"),
                "params": .object([
                    "threadId": .string("thread-1"),
                    "turnId": .string("turn-1"),
                ]),
            ]))
            return ndjson(envelopes)
        case ("POST", "/sessions/session-1/server-requests/approval-1/response"):
            if let body = request.httpBodyStreamBody {
                let payload = try JSONDecoder().decode(JSONValue.self, from: body)
                lock.withLock {
                    recordedServerRequestResponse = payload
                }
            }
            return json(["ok": true])
        case ("DELETE", "/sessions/session-1"):
            return json(["ok": true])
        default:
            return json(["error": .string("unexpected \(request.httpMethod ?? "") \(path)")], statusCode: 404)
        }
    }

    private func json(_ value: JSONValue, statusCode: Int = 200) -> MockBridgeHTTPResponse {
        let body = (try? JSONEncoder().encode(value)) ?? Data()
        return MockBridgeHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    private func ndjson(_ values: [JSONValue]) -> MockBridgeHTTPResponse {
        let body = values
            .compactMap { try? JSONEncoder().encode($0) }
            .reduce(into: Data()) { data, line in
                data.append(line)
                data.append(0x0A)
            }
        return MockBridgeHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/x-ndjson"],
            body: body
        )
    }
}

private struct RecordedRequest: Equatable, Sendable {
    var method: String
    var path: String
}

private extension URLRequest {
    var httpBodyStreamBody: Data? {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            return nil
        }
        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while httpBodyStream.hasBytesAvailable {
            let count = httpBodyStream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
