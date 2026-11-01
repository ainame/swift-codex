import Testing
@testable import Codex

private struct ServerHandlerFixture: Sendable {
    let method: String
    let params: JSONValue
    let result: JSONValue
}

private let handlerFixtures: [ServerHandlerFixture] = [
    .init(method: "item/tool/requestUserInput", params: [
        "threadId": "thread", "turnId": "turn", "itemId": "item", "isBlocking": true,
        "questions": [["id": "q", "header": "Choice", "question": "Which?", "isOther": false,
                       "options": [["label": "A", "description": "First choice"]]]], "future": true,
    ], result: ["answers": ["q": ["answers": ["A"]]], "future": true]),
    .init(method: "mcpServer/elicitation/request", params: [
        "threadId": "thread", "turnId": "turn", "serverName": "server", "mode": "form",
        "message": "Fill this", "requestedSchema": ["type": "object", "properties": ["future": ["type": "custom-type"]]],
        "_meta": ["arbitrary": [1, true]], "future": true,
    ], result: ["action": "accept", "content": ["values": [1, true, nil]], "_meta": ["arbitrary": true], "future": true]),
    .init(method: "item/permissions/requestApproval", params: [
        "threadId": "thread", "turnId": "turn", "itemId": "item", "cwd": "/tmp",
        "startedAtMs": 123, "permissions": ["network": ["enabled": true]], "future": true,
    ], result: ["permissions": ["network": ["enabled": true]], "scope": "turn", "strictAutoReview": true, "future": true]),
    .init(method: "account/chatgptAuthTokens/refresh", params: [
        "reason": "unauthorized", "previousAccountId": "account", "future": true,
    ], result: ["accessToken": "test-token", "chatgptAccountId": "account", "chatgptPlanType": "plus", "future": true]),
    .init(method: "attestation/generate", params: ["future": true], result: ["token": "test-attestation", "future": true]),
    .init(method: "currentTime/read", params: ["threadId": "thread", "future": true], result: ["currentTimeAt": 1_790_000_000, "future": true]),
]

private struct TestHandlerFailure: Error, CustomStringConvertible {
    var description: String { "secret-must-not-appear-in-rpc-error" }
}

struct ServerHandlerTests {
    @Test
    func nonFiniteHandlerResultDoesNotCloseTransport() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            threadStartResponses: [appServerThreadStartResponse(id: "thread")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn")],
            turnStartSequences: [[
                .request(id: 100, method: "test/nonfinite", params: [:]),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread", turnID: "turn")),
            ]]
        ))
        let config = stub.makeConfig(serverRequestHandler: { _ in .json(.number(.nan)) })
        let codex = try await Codex(config: config)
        let thread = try await codex.startThread()
        _ = try await thread.run("test")
        _ = try await codex.models()
        #expect(try stub.appServerResponses(forInvocation: 0).first?["error"] == ["code": -32603, "message": "Server request handler failed"])
        await codex.close()
    }

    @Test
    func genericHandlerCanAdvertiseCapabilitiesAndReturnAnError() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            threadStartResponses: [appServerThreadStartResponse(id: "thread")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn")],
            turnStartSequences: [[
                .request(id: 99, method: "attestation/generate", params: [:]),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread", turnID: "turn")),
            ]]
        ))
        var config = stub.makeConfig()
        config.requestAttestation = true
        config.mcpExtensions = ["openai/form": [:]]
        config.serverRequestHandler = { _ in .error(code: -32000, message: "Unavailable", data: ["retryable": true]) }
        let codex = try await Codex(config: config)
        let thread = try await codex.startThread()
        _ = try await thread.run("test")
        let messages = try stub.appServerMessages(forInvocation: 0)
        #expect(messages.first?["params"]?.objectValue?["capabilities"] == [
            "experimentalApi": true, "requestAttestation": true, "extensions": ["openai/form": [:]],
        ])
        let replies = try stub.appServerResponses(forInvocation: 0)
        #expect(replies.first?["error"] == ["code": -32000, "message": "Unavailable", "data": ["retryable": true]])
        #expect(replies.first?["result"] == nil)
        await codex.close()
    }

    @Test(arguments: handlerFixtures)
    private func dedicatedHandlersAndErrorResponses(fixture: ServerHandlerFixture) async throws {
        for mode in ["specialized", "generic", "missing", "throwing", "malformed"] {
            let stub = try CodexStub()
            defer { stub.cleanup() }
            let params: JSONValue = mode == "malformed" ? .null : fixture.params
            try stub.configureAppServerInvocation(0, scenario: .init(
                threadStartResponses: [appServerThreadStartResponse(id: "thread")],
                turnStartResponses: [appServerTurnStartResponse(id: "turn")],
                turnStartSequences: [[
                    .request(id: "request-string", method: fixture.method, params: params),
                    .request(id: 77, method: fixture.method, params: params),
                    .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread", turnID: "turn")),
                ]]
            ))
            @Sendable func respond<T: Decodable>(_ request: JSONValue, as type: T.Type) throws -> T {
                #expect(request == fixture.params)
                if mode == "throwing" { throw TestHandlerFailure() }
                #expect(mode != "generic", "Generic handler must take precedence")
                return try decodeJSONValue(type, from: fixture.result)
            }
            var config = stub.makeConfig()
            if mode != "missing" {
                config.userInputHandler = { try respond($0.rawJSON, as: ToolRequestUserInputResponse.self) }
                config.mcpElicitationHandler = { try respond($0.rawJSON, as: McpServerElicitationRequestResponse.self) }
                config.permissionsApprovalHandler = { try respond($0.rawJSON, as: PermissionsRequestApprovalResponse.self) }
                config.authTokensRefreshHandler = { try respond($0.rawJSON, as: ChatgptAuthTokensRefreshResponse.self) }
                config.attestationHandler = { try respond($0.rawJSON, as: AttestationGenerateResponse.self) }
                config.currentTimeHandler = { try respond($0.rawJSON, as: CurrentTimeReadResponse.self) }
            }
            if mode == "generic" {
                config.serverRequestHandler = { request in
                    do {
                        switch request {
                        case .userInput(let value):
                            #expect(value.rawJSON == fixture.params)
                            return .userInput(try decodeJSONValue(ToolRequestUserInputResponse.self, from: fixture.result))
                        case .mcpElicitation(let value):
                            #expect(value.rawJSON == fixture.params)
                            return .mcpElicitation(try decodeJSONValue(McpServerElicitationRequestResponse.self, from: fixture.result))
                        case .permissionsApproval(let value):
                            #expect(value.rawJSON == fixture.params)
                            return .permissionsApproval(try decodeJSONValue(PermissionsRequestApprovalResponse.self, from: fixture.result))
                        case .authTokensRefresh(let value):
                            #expect(value.rawJSON == fixture.params)
                            return .authTokensRefresh(try decodeJSONValue(ChatgptAuthTokensRefreshResponse.self, from: fixture.result))
                        case .attestation(let value):
                            #expect(value.rawJSON == fixture.params)
                            return .attestation(try decodeJSONValue(AttestationGenerateResponse.self, from: fixture.result))
                        case .currentTime(let value):
                            #expect(value.rawJSON == fixture.params)
                            return .currentTime(try decodeJSONValue(CurrentTimeReadResponse.self, from: fixture.result))
                        default: Issue.record("Expected typed server request")
                        }
                    } catch { Issue.record(error) }
                    return .json(.null)
                }
            }
            let codex = try await Codex(config: config)
            let messages = try stub.appServerMessages(forInvocation: 0)
            #expect(messages.first?["params"]?.objectValue?["capabilities"]?.objectValue?["requestAttestation"] == (mode == "missing" ? nil : true))
            let thread = try await codex.startThread()
            _ = try await thread.run("test")
            let replies = try stub.appServerResponses(forInvocation: 0)
            #expect(replies.count == 2)
            #expect(replies.map { $0["id"] } == ["request-string", 77])
            let rawInput = try stub.appServerRawInput(forInvocation: 0)
            #expect(rawInput.contains("\"id\":77,") || rawInput.contains("\"id\":77}"), "Integer request IDs must serialize as integer JSON tokens")
            for reply in replies {
                switch mode {
                case "specialized", "generic":
                    #expect(reply["result"] == fixture.result)
                    #expect(reply["error"] == nil)
                default:
                    let error = try #require(reply["error"]?.objectValue)
                    let expectedCode = mode == "missing" ? -32601 : mode == "malformed" ? -32602 : -32603
                    #expect(error["code"] == .number(Double(expectedCode)))
                    #expect(error["message"]?.stringValue?.contains("secret") == false)
                    #expect(reply["result"] == nil)
                }
            }
            await codex.close()
        }
    }

    @Test(arguments: ["form", "openai/form", "openaiForm", "url", "openai/userVerification"])
    func elicitationModesRetainArbitraryJSON(mode: String) throws {
        var object: JSONObject = [
            "serverName": "server", "threadId": "thread", "mode": .string(mode),
            "message": "Ask", "future": true,
        ]
        if mode == "url" { object["url"] = "https://example.test"; object["elicitationId"] = "id" }
        else if mode == "openai/userVerification" {
            object["challenge"] = "challenge"; object["description"] = "Approve"; object["title"] = "Approval"
        } else { object["requestedSchema"] = ["arbitrary": [nil, true, 4]] }
        let request = try decodeJSONValue(McpServerElicitationRequestParams.self, from: .object(object))
        switch (mode, request) {
        case ("form", .form), ("openai/form", .openaiForm), ("openaiForm", .legacyOpenaiForm),
             ("url", .url), ("openai/userVerification", .userVerification): break
        default: Issue.record("Expected exact elicitation mode")
        }
        #expect(request.rawJSON == .object(object))
    }
}


extension ServerHandlerTests {
    @Test(arguments: ["future/mode", "openai/userVerification"])
    func unsupportedOrMalformedElicitationDoesNotBecomeAForm(mode: String) throws {
        let raw: JSONValue = ["mode": .string(mode), "serverName": "server", "threadId": "thread",
                              "message": "Not a valid known form", "requestedSchema": ["type": "object"]]
        let request = try decodeJSONValue(McpServerElicitationRequestParams.self, from: raw)
        guard case .unknown(let preserved) = request else {
            Issue.record("Unknown or malformed elicitation must not fall back to a different consent flow")
            return
        }
        #expect(preserved == raw)
    }
}
