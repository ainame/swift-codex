import Foundation
import Testing
@testable import Codex

struct DynamicToolTests {
    @Test(arguments: [JSONValue.string("tool-1"), .number(60)])
    func registersAndAnswersClientTools(requestID: JSONValue) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        let arguments: JSONValue = ["title": "Hello", "extra": [1, true, nil]]
        let call = DynamicToolCallParams(
            arguments: arguments, callId: "call-1", namespace: "ui",
            threadId: "thread_tools", tool: "show_card", turnId: "turn_tools",
            additionalFields: ["futureField": "preserved"]
        )
        let response = DynamicToolCallResponse(contentItems: [
            .inputText(.init(text: "Card displayed", type: .inputText)),
            .inputImage(.init(imageUrl: "data:image/png;base64,AAA", type: .inputImage)),
            .inputAudio(.init(audioUrl: "data:audio/wav;base64,AAA", type: .inputAudio)),
        ], success: true)
        let startedItem = ThreadItem.dynamicToolCall(.init(
            arguments: arguments, id: "call-1", namespace: "ui", status: .inProgress,
            tool: "show_card", type: .dynamicToolCall
        ))
        let completedItem = ThreadItem.dynamicToolCall(.init(
            arguments: arguments, contentItems: response.contentItems, id: "call-1", namespace: "ui",
            status: .completed, success: true, tool: "show_card", type: .dynamicToolCall
        ))
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_tools")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_tools")],
            turnStartSequences: [[
                .notification(method: "item/started", params: jsonObject(ItemStartedNotification(
                    item: startedItem, startedAtMs: 1, threadId: "thread_tools", turnId: "turn_tools"
                ))),
                .request(id: requestID, method: "item/tool/call", params: call.rawJSON),
                .notification(method: "item/completed", params: jsonObject(ItemCompletedNotification(
                    completedAtMs: 2, item: completedItem, threadId: "thread_tools", turnId: "turn_tools"
                ))),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_tools", turnID: "turn_tools")),
            ]]
        ))
        var config = stub.makeConfig()
        config.dynamicToolCallHandler = { request in
            #expect(request == call)
            return response
        }
        let codex = try await Codex(config: config)
        let function = DynamicToolSpec.function(.init(
            description: "Display a card", inputSchema: ["type": "object"],
            name: "show_card", type: .function
        ))
        let namespace = DynamicToolSpec.namespace(.init(
            description: "UI tools", name: "ui", tools: [.function(.init(
                deferLoading: true, description: "Display a card", inputSchema: ["type": "object"],
                name: "show_card", type: .function
            ))], type: .namespace
        ))
        let thread = try await codex.startThread(options: .init(dynamicTools: [function, namespace]))
        let result = try await thread.run("Show a card")
        #expect(result.items == [completedItem])
        let messages = try stub.appServerMessages(forInvocation: 0)
        let params = try #require(messages.first { $0["method"] == "thread/start" }?.objectValue(forKey: "params"))
        #expect(params["dynamicTools"] == .array([function.rawJSON, namespace.rawJSON]))
        #expect(messages.first?["params"]?.objectValue?["capabilities"]?.objectValue?["experimentalApi"] == true)
        let replies = try stub.appServerResponses(forInvocation: 0)
        #expect(replies.first?["id"] == requestID)
        #expect(replies.first?["result"] == response.rawJSON)
        await codex.close()
    }

    @Test(arguments: [false, true])
    func customHandlerPrecedenceAndMissingHandler(custom: Bool) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        let call = DynamicToolCallParams(arguments: .null, callId: "call-2", threadId: "thread_tools", tool: "show_card", turnId: "turn_tools")
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_tools")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_tools")],
            turnStartSequences: [[
                .request(id: 61, method: "item/tool/call", params: call.rawJSON),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_tools", turnID: "turn_tools")),
            ]]
        ))
        var config = stub.makeConfig()
        if custom {
            config.serverRequestHandler = { request in
                guard case .dynamicToolCall(let params) = request else {
                    Issue.record("Expected typed tool call")
                    return .json([:])
                }
                #expect(params == call)
                return .dynamicToolCall(.init(contentItems: [], success: true))
            }
            config.dynamicToolCallHandler = { _ in
                Issue.record("Custom server handler must take precedence")
                return .init(contentItems: [], success: false)
            }
        }
        let codex = try await Codex(config: config)
        let thread = try await codex.startThread()
        _ = try await thread.run("Show a card")
        let replies = try stub.appServerResponses(forInvocation: 0)
        let result = try #require(replies.first?["result"])
        let decoded = try decodeJSONValue(DynamicToolCallResponse.self, from: result)
        #expect(decoded.success == custom)
        if !custom { #expect(!decoded.contentItems.isEmpty) }
        let messages = try stub.appServerMessages(forInvocation: 0)
        #expect(messages.first { $0["method"] == "thread/start" }?.objectValue(forKey: "params")?["dynamicTools"] == nil)
        await codex.close()
    }

    @Test
    func rejectsRegistrationOnResumeAndFork() async throws {
        let client = CodexRPCClient()
        let options = ThreadOptions(dynamicTools: [])
        await #expect(throws: CodexError.self) { try await client.threadResume(threadID: "existing", options: options) }
        await #expect(throws: CodexError.self) { try await client.threadFork(threadID: "existing", options: options) }
    }
}
