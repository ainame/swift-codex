import Testing
@testable import Codex

private let nonFiniteNumbers: [Double] = [.nan, .infinity, -.infinity]

private let sampleResult: JSONValue = ["responseId": "response", "sourceTurnId": "turn", "text": "sample"]

struct RequestEncodingTests {
    @Test(arguments: nonFiniteNumbers)
    func typedParamsRejectNonFiniteAdditionalFields(number: Double) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(rpcResponses: ["thread/sample": sampleResult]))
        let client = CodexRPCClient(config: stub.makeConfig())
        await #expect(throws: EncodingError.self) {
            try await client.threadAttachmentAdd(.init(
                attachmentType: "note", identityKey: "key", payload: ["ok": true], threadId: "thread",
                additionalFields: ["future": ["nested": .number(number)]]
            ))
        }
        await #expect(throws: EncodingError.self) {
            try await client.threadAttachmentAdd(.init(
                attachmentType: "note", identityKey: "key", payload: ["nested": [.number(number)]], threadId: "thread"
            ))
        }
        await #expect(throws: EncodingError.self) {
            try await client.threadSample(.init(
                expectedTurnId: "turn", prompt: "sample", threadId: "thread",
                additionalFields: ["future": .number(number)]
            ))
        }
        await #expect(throws: EncodingError.self) {
            try await client.accountRateLimitsRead(params: .init(additionalFields: ["future": .number(number)]))
        }
        _ = try await client.threadSample(.init(expectedTurnId: "turn", prompt: "sample", threadId: "thread"))
        let methods = try stub.appServerMessages(forInvocation: 0).compactMap { $0["method"]?.stringValue }
        #expect(!methods.contains("thread/attachment/add"))
        #expect(!methods.contains("account/rateLimits/read"))
        #expect(methods.filter { $0 == "thread/sample" }.count == 1)
        await client.close()
    }

    @Test(arguments: nonFiniteNumbers)
    func dynamicToolSchemasRejectNonFiniteNumbers(number: Double) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_valid")]
        ))
        let codex = try await Codex(config: stub.makeConfig())
        let schema: JSONValue = ["type": "object", "properties": ["count": ["type": "number", "maximum": .number(number)]]]
        let function = DynamicToolSpec.function(.init(
            description: "Count", inputSchema: schema, name: "count", type: .function
        ))
        let namespace = DynamicToolSpec.namespace(.init(
            description: "Tools", name: "ui", tools: [.function(.init(
                description: "Count", inputSchema: schema, name: "count", type: .function
            ))], type: .namespace
        ))
        for tool in [function, namespace] {
            await #expect(throws: EncodingError.self) {
                try await codex.startThread(options: .init(dynamicTools: [tool]))
            }
        }
        let thread = try await codex.startThread()
        #expect(thread.id == "thread_valid")
        let methods = try stub.appServerMessages(forInvocation: 0).compactMap { $0["method"]?.stringValue }
        #expect(methods.filter { $0 == "thread/start" }.count == 1)
        await codex.close()
    }

    @Test(arguments: nonFiniteNumbers)
    func optionUnionsRejectNonFiniteNumbers(number: Double) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_valid")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_valid")]
        ))
        let client = CodexRPCClient(config: stub.makeConfig())
        let sandbox = SandboxPolicy.dangerFullAccess(.init(type: .dangerFullAccess, additionalFields: ["future": .number(number)]))
        await #expect(throws: EncodingError.self) {
            try await client.threadStart(options: .init(approvalPolicy: .unknown(["future": .number(number)])))
        }
        await #expect(throws: EncodingError.self) {
            try await client.threadResume(threadID: "thread", options: .init(approvalPolicy: .unknown(["future": .number(number)])))
        }
        await #expect(throws: EncodingError.self) {
            try await client.threadFork(threadID: "thread", options: .init(approvalPolicy: .unknown(["future": .number(number)])))
        }
        await #expect(throws: EncodingError.self) {
            try await client.turnStart(threadID: "thread", input: [.text("hi")], options: .init(sandboxPolicy: sandbox))
        }
        _ = try await client.threadStart()
        _ = try await client.turnStart(threadID: "thread_valid", input: [.text("hi")])
        let methods = try stub.appServerMessages(forInvocation: 0).compactMap { $0["method"]?.stringValue }
        #expect(!methods.contains("thread/resume"))
        #expect(!methods.contains("thread/fork"))
        #expect(methods.filter { $0 == "thread/start" }.count == 1)
        #expect(methods.filter { $0 == "turn/start" }.count == 1)
        await client.close()
    }

    @Test(arguments: nonFiniteNumbers)
    func rawRequestsRejectNonFiniteNumbers(number: Double) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(rpcResponses: ["custom/method": ["ok": true]]))
        let client = CodexRPCClient(config: stub.makeConfig())
        await #expect(throws: EncodingError.self) {
            try await client.request("custom/method", params: ["value": .number(number)], responseType: JSONValue.self)
        }
        let response = try await client.request("custom/method", params: ["value": 1], responseType: JSONValue.self)
        #expect(response == ["ok": true])
        let methods = try stub.appServerMessages(forInvocation: 0).compactMap { $0["method"]?.stringValue }
        #expect(methods.filter { $0 == "custom/method" }.count == 1)
        await client.close()
    }

    @Test
    func validUnknownPayloadsAreForwardedUnchanged() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            rpcResponses: ["thread/sample": sampleResult, "thread/goal/clear": ["cleared": true]],
            threadStartResponses: [appServerThreadStartResponse(id: "thread_valid")]
        ))
        let client = CodexRPCClient(config: stub.makeConfig())
        let nested: JSONValue = ["list": [1.5, nil, ["deep": "value"]], "flag": false]
        let approval: JSONValue = ["futurePolicy": nested]
        let schema: JSONValue = ["type": "object", "x-future": nested]
        let tool = DynamicToolSpec.namespace(.init(
            description: "Tools", name: "ui", tools: [.function(.init(
                description: "Count", inputSchema: schema, name: "count", type: .function,
                additionalFields: ["futureTool": nested]
            ))], type: .namespace, additionalFields: ["futureNamespace": nested]
        ))
        _ = try await client.threadStart(options: .init(approvalPolicy: .unknown(approval), dynamicTools: [tool]))
        _ = try await client.threadSample(.init(
            expectedTurnId: "turn", prompt: "sample", threadId: "thread", additionalFields: ["future": nested]
        ))
        _ = try await client.threadGoalClear(threadID: "thread", origin: .unrecognized("futureOrigin"))
        let messages = try stub.appServerMessages(forInvocation: 0)
        func params(_ method: String) throws -> JSONObject {
            try #require(messages.first { $0["method"] == .string(method) }?.objectValue(forKey: "params"))
        }
        let start = try params("thread/start")
        #expect(start["approvalPolicy"] == approval)
        #expect(start["dynamicTools"] == [[
            "type": "namespace", "name": "ui", "description": "Tools", "futureNamespace": nested,
            "tools": [["type": "function", "name": "count", "description": "Count", "inputSchema": schema, "futureTool": nested]],
        ]])
        #expect(try params("thread/sample") == [
            "expectedTurnId": "turn", "prompt": "sample", "threadId": "thread", "future": nested,
        ])
        #expect(try params("thread/goal/clear") == ["threadId": "thread", "origin": "futureOrigin"])
        await client.close()
    }
}
