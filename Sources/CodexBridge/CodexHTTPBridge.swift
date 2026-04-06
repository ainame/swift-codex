import Codex
import Foundation
import Hummingbird

actor CodexHTTPBridge {
    let codexPath: String
    private var client: CodexRPCClient?
    private var requestInFlight = false
    private var currentEmit: (@Sendable (JSONValue) -> Void)?
    private var pendingServerRequests: [String: CheckedContinuation<ServerRequestResult, Never>] = [:]

    init(codexPath: String) {
        self.codexPath = codexPath
    }

    func start() async throws {
        let client = try await rpcClient()
        try await client.start()
    }

    func streamRPC(method: String, params: JSONValue) -> AsyncThrowingStream<ByteBuffer, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await handleRPC(method: method, params: params, isNotification: false) { payload in
                        if let buffer = try? encodeJSONLine(payload) {
                            continuation.yield(buffer)
                        }
                    }
                } catch {
                    if let buffer = try? encodeJSONLine(errorEnvelope(error)) {
                        continuation.yield(buffer)
                    }
                }
                continuation.finish()
            }
        }
    }

    func streamNotification(method: String, params: JSONValue) -> AsyncThrowingStream<ByteBuffer, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await handleRPC(method: method, params: params, isNotification: true) { payload in
                        if let buffer = try? encodeJSONLine(payload) {
                            continuation.yield(buffer)
                        }
                    }
                } catch {
                    if let buffer = try? encodeJSONLine(errorEnvelope(error)) {
                        continuation.yield(buffer)
                    }
                }
                continuation.finish()
            }
        }
    }

    func resolveServerRequest(requestID: String, result: JSONValue) {
        pendingServerRequests.removeValue(forKey: requestID)?.resume(returning: .json(result))
    }

    func close() async {
        if let client {
            await client.close()
        }
        client = nil
        requestInFlight = false
        currentEmit = nil
        for (_, continuation) in pendingServerRequests {
            continuation.resume(returning: .json(.object([:])))
        }
        pendingServerRequests.removeAll()
    }

    private func handleRPC(
        method: String,
        params: JSONValue,
        isNotification: Bool,
        emit: @escaping @Sendable (JSONValue) -> Void
    ) async throws {
        guard !requestInFlight else {
            throw BridgeError.invalidRequestBody("CodexBridge currently supports one active /rpc request at a time")
        }
        requestInFlight = true
        currentEmit = emit
        defer {
            requestInFlight = false
            currentEmit = nil
        }

        guard let params = params.objectValue else {
            throw BridgeError.invalidRequestBody("params must be a JSON object")
        }

        let client = try await rpcClient()
        if isNotification {
            // The bridged client's initialize call already sends this to the
            // underlying app-server through CodexRPCClient.initialize().
            if method != "initialized" {
                try await client.notify(method, params: params)
            }
            emit(responseEnvelope(result: .null))
            return
        }

        if method == "initialize" {
            let response = try await client.initialize()
            emit(responseEnvelope(result: try encodeBridgeJSONValue(response)))
            return
        }

        let result = try await client.request(method, params: params, responseType: JSONValue.self)
        emit(responseEnvelope(result: result))

        if method == "turn/start", let turnID = turnID(fromTurnStartResult: result) {
            try await streamNotifications(untilTurnCompleted: turnID, from: client, emit: emit)
        }
    }

    private func rpcClient() async throws -> CodexRPCClient {
        if let client {
            return client
        }
        let config = CodexConfig(
            codexPathOverride: codexPath == "codex" ? nil : codexPath,
            clientName: "codex_bridge_http",
            clientTitle: "CodexBridge HTTP",
            clientVersion: "0.1.0",
            serverRequestHandler: { [weak self] request in
                guard let self else {
                    return .json(.object([:]))
                }
                return await self.handleServerRequest(request)
            }
        )
        let client = CodexRPCClient(config: config)
        self.client = client
        return client
    }

    private func streamNotifications(
        untilTurnCompleted turnID: String,
        from client: CodexRPCClient,
        emit: @Sendable (JSONValue) -> Void
    ) async throws {
        while true {
            let notification = try await client.nextNotification()
            emit(notificationEnvelope(notification))
            if notification.method == "turn/completed", notification.turnID == turnID {
                return
            }
        }
    }

    private func handleServerRequest(_ request: ServerRequest) async -> ServerRequestResult {
        guard let currentEmit else {
            return .json(.object([:]))
        }
        let requestID = UUID().uuidString
        currentEmit(serverRequestEnvelope(requestID: requestID, request: request))
        return await withCheckedContinuation { continuation in
            pendingServerRequests[requestID] = continuation
        }
    }
}
