import Foundation

actor AppServerTransport {
    private let config: AppServerConfig
    private let exec: AppServerExec
    private var outboundContinuation: AsyncStream<String>.Continuation?
    private var runTask: Task<Void, Never>?
    private var requestCounter = 0
    private var pendingRequests: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var pendingNotifications: [AppServerNotification] = []
    private var pendingNotificationContinuations: [CheckedContinuation<AppServerNotification, Error>] = []
    private var terminalError: Error?
    private var stderrTail: [String] = []

    init(config: AppServerConfig) {
        self.config = config
        self.exec = AppServerExec(
            executablePathOverride: config.codexPathOverride,
            environmentOverride: config.environment,
            configOverrides: config.config,
            baseURL: config.baseURL,
            apiKey: config.apiKey
        )
    }

    func startProcess() async throws {
        if runTask != nil {
            return
        }

        let streamPair = AsyncStream.makeStream(of: String.self)
        outboundContinuation = streamPair.continuation

        let exec = self.exec
        runTask = Task {
            do {
                try await exec.runAppServer(
                    outgoingMessages: streamPair.stream,
                    onStdoutLine: { [weak self] line in
                        guard let self else { return }
                        await self.handleIncomingLine(line)
                    },
                    onStderrLine: { [weak self] line in
                        guard let self else { return }
                        await self.recordStderr(line)
                    }
                )
                finishTransport(error: nil)
            } catch {
                finishTransport(error: error)
            }
        }
    }

    func close() {
        outboundContinuation?.finish()
        outboundContinuation = nil
        runTask?.cancel()
        runTask = nil

        let failure = terminalError ?? makeTransportClosedError()
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: failure)
        }
        pendingRequests.removeAll()

        for continuation in pendingNotificationContinuations {
            continuation.resume(throwing: failure)
        }
        pendingNotificationContinuations.removeAll()
    }

    func request(method: String, params: JSONObject) async throws -> JSONValue {
        if let terminalError {
            throw terminalError
        }

        let id = nextRequestID()
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            do {
                try send(
                    .object([
                        "id": .string(id),
                        "method": .string(method),
                        "params": .object(params),
                    ])
                )
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    func notify(method: String, params: JSONObject) throws {
        try send(
            .object([
                "method": .string(method),
                "params": .object(params),
            ])
        )
    }

    func nextNotification() async throws -> AppServerNotification {
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

    private func send(_ payload: JSONValue) throws {
        guard let continuation = outboundContinuation else {
            throw terminalError ?? makeTransportClosedError()
        }
        let data = try JSONEncoder().encode(payload)
        guard let line = String(data: data, encoding: .utf8) else {
            throw AppServerError.invalidResponse("Failed to encode JSON-RPC payload")
        }
        continuation.yield(line)
    }

    private func nextRequestID() -> String {
        requestCounter += 1
        return "swift-codex-\(requestCounter)"
    }

    private func recordStderr(_ line: String) {
        stderrTail.append(line)
        if stderrTail.count > 400 {
            stderrTail.removeFirst(stderrTail.count - 400)
        }
    }

    private func makeTransportClosedError() -> AppServerError {
        let stderrTail = stderrTailText()
        guard !stderrTail.isEmpty else {
            return .transportClosed
        }
        return .transportClosedWithStderrTail(stderrTail)
    }

    private func stderrTailText() -> String {
        stderrTail.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishTransport(error: Error?) {
        if let error {
            terminalError = error
        } else if terminalError == nil {
            terminalError = makeTransportClosedError()
        }

        let failure = terminalError ?? makeTransportClosedError()

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: failure)
        }
        pendingRequests.removeAll()

        for continuation in pendingNotificationContinuations {
            continuation.resume(throwing: failure)
        }
        pendingNotificationContinuations.removeAll()
    }

    private func handleIncomingLine(_ line: String) async {
        do {
            let data = Data(line.utf8)
            let message = try JSONDecoder().decode(JSONObject.self, from: data)

            if let method = message.stringValue(forKey: "method") {
                if let requestID = message.stringValue(forKey: "id") {
                    try await handleServerRequest(
                        method: method,
                        requestID: requestID,
                        params: message["params"]?.objectValue
                    )
                } else {
                    handleNotification(
                        method: method,
                        params: message["params"] ?? .object([:])
                    )
                }
                return
            }

            guard let requestID = message.stringValue(forKey: "id") else {
                throw AppServerError.invalidRequestID
            }

            if let errorPayload = message["error"] {
                let error = try decode(JSONRPCErrorPayload.self, from: errorPayload)
                pendingRequests.removeValue(forKey: requestID)?.resume(
                    throwing: AppServerErrorMapper.map(code: error.code, message: error.message, data: error.data)
                )
                return
            }

            pendingRequests.removeValue(forKey: requestID)?.resume(returning: message["result"] ?? .null)
        } catch {
            finishTransport(error: error)
        }
    }

    private func handleServerRequest(method: String, requestID: String, params: JSONObject?) async throws {
        let result = await makeServerRequestResult(method: method, params: params)
        try send(
            .object([
                "id": .string(requestID),
                "result": .object(result),
            ])
        )
    }

    private func makeServerRequestResult(method: String, params: JSONObject?) async -> JSONObject {
        if let serverRequestHandler = config.serverRequestHandler {
            return await serverRequestHandler(method, params)
        }

        switch method {
        case "item/commandExecution/requestApproval":
            let request = CommandApprovalRequest(
                threadID: params?.stringValue(forKey: "threadId") ?? "",
                turnID: params?.stringValue(forKey: "turnId") ?? "",
                itemID: params?.stringValue(forKey: "itemId") ?? "",
                approvalID: params?.stringValue(forKey: "approvalId"),
                command: params?.stringValue(forKey: "command"),
                workingDirectory: params?.stringValue(forKey: "cwd"),
                reason: params?.stringValue(forKey: "reason")
            )
            let decision = await config.commandApprovalHandler(request)
            return ["decision": .string(decision == .approve ? "accept" : "decline")]
        case "item/fileChange/requestApproval":
            let request = FileChangeApprovalRequest(
                threadID: params?.stringValue(forKey: "threadId") ?? "",
                turnID: params?.stringValue(forKey: "turnId") ?? "",
                itemID: params?.stringValue(forKey: "itemId") ?? "",
                reason: params?.stringValue(forKey: "reason"),
                grantRoot: params?.stringValue(forKey: "grantRoot")
            )
            let decision = await config.fileChangeApprovalHandler(request)
            return ["decision": .string(decision == .approve ? "accept" : "decline")]
        default:
            return [:]
        }
    }

    private func handleNotification(method: String, params: JSONValue) {
        let notification = AppServerNotification(method: method, params: params)
        if !pendingNotificationContinuations.isEmpty {
            let continuation = pendingNotificationContinuations.removeFirst()
            continuation.resume(returning: notification)
            return
        }
        pendingNotifications.append(notification)
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct JSONRPCErrorPayload: Decodable {
    var code: Int
    var message: String
    var data: JSONValue?
}

enum AppServerErrorMapper {
    static func map(code: Int, message: String, data: JSONValue?) -> AppServerError {
        switch code {
        case -32700:
            return .parseError(message: message, data: data)
        case -32600:
            return .invalidRequest(message: message, data: data)
        case -32601:
            return .methodNotFound(message: message, data: data)
        case -32602:
            return .invalidParams(message: message, data: data)
        case -32603:
            return .internalRPC(message: message, data: data)
        case -32099 ... -32000:
            if containsRetryLimitText(message) {
                return .retryLimitExceeded(message: message, data: data)
            }
            if isServerOverloaded(data) {
                return .serverBusy(message: message, data: data)
            }
            return .jsonRPCError(code: code, message: message, data: data)
        default:
            return .jsonRPCError(code: code, message: message, data: data)
        }
    }

    static func containsRetryLimitText(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("retry limit") || lowered.contains("too many failed attempts")
    }

    static func isServerOverloaded(_ data: JSONValue?) -> Bool {
        guard let data else {
            return false
        }
        switch data {
        case .string(let value):
            return value.lowercased() == "server_overloaded" || value.lowercased() == "serveroverloaded"
        case .object(let object):
            let directKeys = ["codex_error_info", "codexErrorInfo", "errorInfo"]
            for key in directKeys {
                if isServerOverloaded(object[key]) {
                    return true
                }
            }
            for value in object.values where isServerOverloaded(value) {
                return true
            }
            return false
        case .array(let values):
            return values.contains(where: isServerOverloaded)
        default:
            return false
        }
    }
}
