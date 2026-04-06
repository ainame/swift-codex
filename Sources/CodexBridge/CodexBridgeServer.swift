import Foundation
import Hummingbird

struct CodexBridgeServer {
    var host: String
    var port: UInt16
    var codexPath: String

    func run() async throws {
        let sessions = CodexBridgeSessions(codexPath: codexPath)
        let router = Router()

        router.get("healthz") { _, _ in
            try jsonResponse(["ok": true])
        }

        router.post("sessions") { _, _ in
            let sessionID = try await sessions.create()
            return try jsonResponse(BridgeCreateSessionResponse(sessionId: sessionID))
        }

        router.post("sessions/:sessionId/rpc") { request, context -> Response in
            let sessionID = try context.parameters.require("sessionId")
            let bridge = try await sessions.get(sessionID)
            let payload = try await decodeRequest(BridgeRPCRequest.self, from: request)
            let stream = await (payload.notification == true
                ? bridge.streamNotification(method: payload.method, params: payload.params ?? .object([:]))
                : bridge.streamRPC(method: payload.method, params: payload.params ?? .object([:])))
            return ndjsonResponse(stream)
        }

        router.post("sessions/:sessionId/server-requests/:requestId/response") { request, context -> Response in
            let sessionID = try context.parameters.require("sessionId")
            let requestID = try context.parameters.require("requestId")
            let bridge = try await sessions.get(sessionID)
            let payload = try await decodeRequest(BridgeServerRequestResponse.self, from: request)
            await bridge.resolveServerRequest(requestID: requestID, result: payload.result)
            return try jsonResponse(["ok": true])
        }

        router.delete("sessions/:sessionId") { _, context -> Response in
            let sessionID = try context.parameters.require("sessionId")
            try await sessions.close(sessionID)
            return try jsonResponse(["ok": true])
        }

        var app = Application(
            responder: router.buildResponder(),
            configuration: .init(
                address: .hostname(host, port: Int(port)),
                serverName: "CodexBridge"
            )
        )
        app.logger.logLevel = .info
        fputs("CodexBridge listening on http://\(host):\(port)\n", stderr)
        try await app.runService()
    }
}

actor CodexBridgeSessions {
    let codexPath: String
    private var sessions: [String: CodexHTTPBridge] = [:]

    init(codexPath: String) {
        self.codexPath = codexPath
    }

    func create() async throws -> String {
        let sessionID = UUID().uuidString
        let session = CodexHTTPBridge(codexPath: codexPath)
        try await session.start()
        sessions[sessionID] = session
        return sessionID
    }

    func get(_ sessionID: String) throws -> CodexHTTPBridge {
        guard let session = sessions[sessionID] else {
            throw HTTPError(.notFound, message: "unknown CodexBridge session")
        }
        return session
    }

    func close(_ sessionID: String) async throws {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            throw HTTPError(.notFound, message: "unknown CodexBridge session")
        }
        await session.close()
    }
}
