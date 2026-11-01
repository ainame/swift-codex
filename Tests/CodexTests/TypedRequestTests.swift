import Testing
@testable import Codex

struct TypedRequestTests {
    @Test(arguments: [nil, "swift-codex-1"] as [String?])
    func cancellingSwiftTaskAlsoCancelsServerSample(requestID: String?) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(holdSampleForCancellation: true))
        let client = CodexRPCClient(config: stub.makeConfig())
        let watchdog = Task { try await Task.sleep(for: .seconds(5)); await client.close() }
        defer { watchdog.cancel() }
        let sample = Task {
            try await client.threadSample(.init(expectedTurnId: "turn", prompt: "sample", threadId: "thread"), requestID: requestID)
        }
        let started = try await client.nextNotification()
        let actualID = try #require(started.rawParams.objectValue?["requestId"])
        // An automatically generated ID must not collide with the explicit ID.
        _ = try await client.modelList()
        sample.cancel()
        await #expect(throws: CancellationError.self) { try await sample.value }
        _ = try await client.modelList()
        let messages = try stub.appServerMessages(forInvocation: 0)
        #expect(messages.first { $0["method"] == "thread/sample/cancel" }?["params"] == ["requestId": actualID])
        let ids = messages.compactMap { $0["id"] }
        #expect(Set(ids).count == ids.count)
        await client.close()
    }

    @Test
    func cancelsAnInFlightSampleByRequestID() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(holdSampleForCancellation: true))
        let client = CodexRPCClient(config: stub.makeConfig())
        let watchdog = Task { try await Task.sleep(for: .seconds(5)); await client.close() }
        defer { watchdog.cancel() }
        let sample = Task {
            try await client.threadSample(.init(expectedTurnId: "turn", prompt: "sample", threadId: "thread"), requestID: "pending-sample")
        }
        let started = try await client.nextNotification()
        #expect(started.rawParams == ["requestId": "pending-sample"])
        _ = try await client.threadSampleCancel(.init(requestId: .string("pending-sample")))
        await #expect(throws: CodexError.self) { try await sample.value }
        await client.close()
    }

    @Test(arguments: [false, true])
    func typedMethodsPreserveWireFields(browserLogin: Bool) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        let switchResult: JSONValue = browserLogin
            ? ["authUrl": "https://example.test/login", "loginId": "login", "future": true]
            : ["activeSessionId": "session", "sessions": [], "future": true]
        let sampleResult: JSONValue = ["responseId": "response", "sourceTurnId": "turn", "text": "sample", "future": true]
        try stub.configureAppServerInvocation(0, scenario: .init(rpcResponses: [
            "thread/sample": sampleResult, "thread/sample/cancel": [:],
            "thread/memory/read": ["summary": "memory", "future": true],
            "account/gcp/setup": ["future": true],
            "accountSession/list": ["activeSessionId": "session", "sessions": [], "future": true],
            "accountSession/switch": switchResult,
            "feedback/save": ["savedPath": "/tmp/feedback.zip", "threadId": "thread", "future": true],
        ]))
        let client = CodexRPCClient(config: stub.makeConfig())
        _ = try await client.initialize()
        let sampleParams = ThreadSampleParams(
            disableMcp: false, effort: .medium, expectedTurnId: "turn", prompt: "sample",
            responsesapiClientMetadata: ["key": "value"], threadId: "thread",
            threadSource: .init(rawValue: "cli"), turnTrigger: "trigger", additionalFields: ["future": true]
        )
        let sample = try await client.threadSample(sampleParams, requestID: "sample-cancel-id")
        #expect(sample.rawJSON == sampleResult)
        _ = try await client.threadSampleCancel(.init(requestId: .string("sample-cancel-id")))
        let memory = try await client.threadMemoryRead(.init(threadId: "thread"))
        #expect(memory.summary == "memory")
        let setup = try await client.gcpSetup(.init(credentialFile: "/tmp/credentials.json", location: "global", projectId: "project"))
        #expect(setup.additionalFields["future"] == true)
        let sessions = try await client.accountSessionList(.init(refreshWorkspaceMetadata: true))
        #expect(sessions.activeSessionId == "session")
        let switched = try await client.accountSessionSwitch(.init(accountId: "workspace", allowBrowserLogin: true, sessionId: "session"))
        if browserLogin {
            guard case .browserLogin(let login) = switched else { Issue.record("Expected browser login"); return }
            #expect(login.loginId == "login")
            #expect(login.authUrl == "https://example.test/login")
        } else {
            guard case .switched(let result) = switched else { Issue.record("Expected switched session"); return }
            #expect(result.activeSessionId == "session")
        }
        #expect(switched.rawJSON == switchResult)
        let feedbackParams = FeedbackSaveParams(classification: "bug", includeLogs: false, savePath: .init(rawValue: "/tmp/feedback.zip"))
        let feedback = try await client.feedbackSave(feedbackParams)
        #expect(feedback.savedPath.rawValue == "/tmp/feedback.zip")
        #expect(feedback.additionalFields["future"] == true)
        let messages = try stub.appServerMessages(forInvocation: 0)
        func sent(_ method: String) throws -> JSONObject {
            try #require(messages.first { $0["method"] == .string(method) })
        }
        #expect(try sent("thread/sample")["params"] == sampleParams.rawJSON)
        #expect(try sent("thread/sample")["id"] == "sample-cancel-id")
        #expect(try sent("thread/sample/cancel")["params"] == ["requestId": "sample-cancel-id"])
        #expect(try sent("thread/memory/read")["params"] == ["threadId": "thread"])
        #expect(try sent("account/gcp/setup")["params"] == ["credentialFile": "/tmp/credentials.json", "location": "global", "projectId": "project"])
        #expect(try sent("accountSession/list")["params"] == ["refreshWorkspaceMetadata": true])
        #expect(try sent("accountSession/switch")["params"] == ["accountId": "workspace", "allowBrowserLogin": true, "sessionId": "session"])
        #expect(try sent("feedback/save")["params"] == feedbackParams.rawJSON)
        #expect(messages.first?["params"]?.objectValue?["capabilities"]?.objectValue?["experimentalApi"] == true)
        await client.close()
    }

    @Test
    func highLevelMethodsAndOmittedOptions() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            rpcResponses: [
                "thread/sample": ["responseId": "response", "sourceTurnId": "turn"],
                "thread/sample/cancel": [:], "thread/memory/read": [:],
                "account/gcp/setup": [:], "accountSession/list": ["sessions": []],
                "accountSession/switch": ["sessions": []],
                "feedback/save": ["savedPath": "/tmp/feedback.zip", "threadId": "thread"],
            ], threadStartResponses: [appServerThreadStartResponse(id: "thread")]
        ))
        let codex = try await Codex(config: stub.makeConfig())
        let thread = try await codex.startThread()
        let sample = try await thread.sample(expectedTurnID: "turn", prompt: "sample", requestID: "sample")
        #expect(sample.text == nil)
        _ = try await codex.cancelSample(requestID: "sample")
        #expect(try await thread.memory().summary == nil)
        _ = try await codex.gcpSetup(.init(projectId: "project"))
        _ = try await codex.accountSessions()
        _ = try await codex.switchAccountSession(.init(accountId: "workspace", sessionId: "session"))
        _ = try await codex.saveFeedback(.init(classification: "bug", savePath: .init(rawValue: "/tmp/feedback.zip")))
        let messages = try stub.appServerMessages(forInvocation: 0)
        #expect(messages.first { $0["method"] == "accountSession/list" }?["params"] == [:])
        #expect(messages.first { $0["method"] == "thread/sample" }?["params"] == ["expectedTurnId": "turn", "prompt": "sample", "threadId": "thread"])
        #expect(messages.first { $0["method"] == "account/gcp/setup" }?["params"] == ["projectId": "project"])
        await codex.close()
    }
}
