import CodexCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor CodexBridgeHTTPTransport: CodexRPCTransporting {
    private let bridgeURL: URL
    private let config: CodexConfig
    private let urlSession: URLSession
    private var sessionID: String?
    private var requestInFlight = false
    private var pendingNotifications: [CodexNotification] = []
    private var pendingNotificationContinuations: [CheckedContinuation<CodexNotification, Error>] = []
    private var terminalError: Error?

    init(bridgeURL: URL, config: CodexConfig, urlSession: URLSession = .shared) {
        self.bridgeURL = bridgeURL
        self.config = config
        self.urlSession = urlSession
    }

    func start() async throws {
        _ = try await ensureSessionID()
    }

    func close() async {
        guard let sessionID else { return }
        self.sessionID = nil
        var request = URLRequest(url: bridgeURL.appending(path: "sessions/\(sessionID)"))
        request.httpMethod = "DELETE"
        _ = try? await urlSession.data(for: request)
    }

    func request(method: String, params: JSONObject) async throws -> JSONValue {
        if let terminalError {
            throw terminalError
        }
        guard !requestInFlight else {
            throw CodexError.invalidConfig("CodexBridgeClient supports one active RPC stream per session")
        }
        requestInFlight = true

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await self.runRPC(
                    method: method,
                    params: .object(params),
                    isNotification: false,
                    responseContinuation: continuation
                )
            }
        }
    }

    func notify(method: String, params: JSONObject) async throws {
        if let terminalError {
            throw terminalError
        }
        guard !requestInFlight else {
            throw CodexError.invalidConfig("CodexBridgeClient supports one active RPC stream per session")
        }
        requestInFlight = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                await self.runNotification(
                    method: method,
                    params: .object(params),
                    continuation: continuation
                )
            }
        }
    }

    func nextNotification() async throws -> CodexNotification {
        if !pendingNotifications.isEmpty {
            return pendingNotifications.removeFirst()
        }
        if let terminalError {
            throw terminalError
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingNotificationContinuations.append(continuation)
        }
    }

    private func runNotification(
        method: String,
        params: JSONValue,
        continuation: CheckedContinuation<Void, Error>
    ) async {
        do {
            _ = try await drainRPC(method: method, params: params, isNotification: true)
            continuation.resume()
        } catch {
            terminalError = error
            continuation.resume(throwing: error)
        }
        requestInFlight = false
    }

    private func runRPC(
        method: String,
        params: JSONValue,
        isNotification: Bool,
        responseContinuation: CheckedContinuation<JSONValue, Error>
    ) async {
        var didResume = false
        do {
            let result = try await drainRPC(
                method: method,
                params: params,
                isNotification: isNotification
            ) { result in
                guard !didResume else { return }
                didResume = true
                responseContinuation.resume(returning: result)
            }
            if !didResume {
                responseContinuation.resume(returning: result ?? .null)
            }
        } catch {
            terminalError = error
            if !didResume {
                responseContinuation.resume(throwing: error)
            }
            failPendingNotifications(error)
        }
        requestInFlight = false
    }

    private func drainRPC(
        method: String,
        params: JSONValue,
        isNotification: Bool,
        onResponse: ((JSONValue) -> Void)? = nil
    ) async throws -> JSONValue? {
        let sessionID = try await ensureSessionID()
        var request = URLRequest(url: bridgeURL.appending(path: "sessions/\(sessionID)/rpc"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            BridgeRPCRequestBody(method: method, params: params, notification: isNotification)
        )

        let (bytes, response) = try await urlSession.bytes(for: request)
        try validateHTTPResponse(response)

        var result: JSONValue?
        for try await line in bytes.lines {
            guard !line.isEmpty else { continue }
            let envelope = try JSONDecoder().decode(BridgeEnvelope.self, from: Data(line.utf8))
            switch envelope {
            case .response(let value):
                result = value
                onResponse?(value)
            case .notification(let method, let params):
                handleNotification(CodexNotification(method: method, params: params))
            case .serverRequest(let requestID, let method, let params):
                let serverRequest = makeServerRequest(method: method, params: params)
                let requestResult = await resolveServerRequest(serverRequest)
                try await postServerRequestResponse(
                    sessionID: sessionID,
                    requestID: requestID,
                    result: requestResult.jsonValue
                )
            case .error(let message):
                throw CodexError.invalidResponse(message)
            }
        }
        return result
    }

    private func ensureSessionID() async throws -> String {
        if let sessionID {
            return sessionID
        }

        var request = URLRequest(url: bridgeURL.appending(path: "sessions"))
        request.httpMethod = "POST"
        let (data, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response)
        let payload = try JSONDecoder().decode(BridgeCreateSessionResponse.self, from: data)
        sessionID = payload.sessionId
        return payload.sessionId
    }

    private func postServerRequestResponse(
        sessionID: String,
        requestID: String,
        result: JSONValue
    ) async throws {
        var request = URLRequest(url: bridgeURL.appending(path: "sessions/\(sessionID)/server-requests/\(requestID)/response"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(BridgeServerRequestResponse(result: result))
        let (_, response) = try await urlSession.data(for: request)
        try validateHTTPResponse(response)
    }

    private func resolveServerRequest(_ request: ServerRequest) async -> ServerRequestResult {
        if let handler = config.serverRequestHandler {
            return await handler(request)
        }

        switch request {
        case .commandApproval(let request):
            return await .approval(config.commandApprovalHandler(request))
        case .fileChangeApproval(let request):
            return await .approval(config.fileChangeApprovalHandler(request))
        case .unknown:
            return .json(.object([:]))
        }
    }

    private func makeServerRequest(method: String, params: JSONValue?) -> ServerRequest {
        let objectParams = params?.objectValue
        switch method {
        case "item/commandExecution/requestApproval":
            return .commandApproval(
                CommandApprovalRequest(
                    threadID: objectParams?.stringValue(forKey: "threadID") ?? objectParams?.stringValue(forKey: "threadId") ?? "",
                    turnID: objectParams?.stringValue(forKey: "turnID") ?? objectParams?.stringValue(forKey: "turnId") ?? "",
                    itemID: objectParams?.stringValue(forKey: "itemID") ?? objectParams?.stringValue(forKey: "itemId") ?? "",
                    approvalID: objectParams?.stringValue(forKey: "approvalID") ?? objectParams?.stringValue(forKey: "approvalId"),
                    command: objectParams?.stringValue(forKey: "command"),
                    workingDirectory: objectParams?.stringValue(forKey: "workingDirectory") ?? objectParams?.stringValue(forKey: "cwd"),
                    reason: objectParams?.stringValue(forKey: "reason")
                )
            )
        case "item/fileChange/requestApproval":
            return .fileChangeApproval(
                FileChangeApprovalRequest(
                    threadID: objectParams?.stringValue(forKey: "threadID") ?? objectParams?.stringValue(forKey: "threadId") ?? "",
                    turnID: objectParams?.stringValue(forKey: "turnID") ?? objectParams?.stringValue(forKey: "turnId") ?? "",
                    itemID: objectParams?.stringValue(forKey: "itemID") ?? objectParams?.stringValue(forKey: "itemId") ?? "",
                    reason: objectParams?.stringValue(forKey: "reason"),
                    grantRoot: objectParams?.stringValue(forKey: "grantRoot")
                )
            )
        default:
            return .unknown(method: method, params: params)
        }
    }

    private func handleNotification(_ notification: CodexNotification) {
        if !pendingNotificationContinuations.isEmpty {
            pendingNotificationContinuations.removeFirst().resume(returning: notification)
            return
        }
        pendingNotifications.append(notification)
    }

    private func failPendingNotifications(_ error: any Error) {
        for continuation in pendingNotificationContinuations {
            continuation.resume(throwing: error)
        }
        pendingNotificationContinuations.removeAll()
    }
}

private func validateHTTPResponse(_ response: URLResponse) throws {
    guard let response = response as? HTTPURLResponse else {
        throw CodexError.invalidResponse("CodexBridge returned a non-HTTP response")
    }
    guard (200 ..< 300).contains(response.statusCode) else {
        throw CodexError.invalidResponse("CodexBridge returned HTTP \(response.statusCode)")
    }
}
