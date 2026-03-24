import Foundation
import Testing
@testable import Codex

@Suite(.serialized)
struct AppServerSDKTests {
    @Test
    func appServerInitializesAndStreamsTurnEvents() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_app")],
            turnStartResponses: [appServerTurnResponse(id: "turn_app")],
            turnStartSequences: [[
                .notification(method: "thread/started", params: appServerThreadStarted(threadID: "thread_app")),
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_app", turnID: "turn_app")),
                .notification(
                    method: "item/started",
                    params: appServerItemNotification(
                        threadID: "thread_app",
                        turnID: "turn_app",
                        item: appServerAgentMessageItem(text: "Working")
                    )
                ),
                .notification(
                    method: "item/completed",
                    params: appServerItemNotification(
                        threadID: "thread_app",
                        turnID: "turn_app",
                        item: appServerAgentMessageItem(text: "Done")
                    )
                ),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_app", turnID: "turn_app")),
            ]]
        ))

        let client = try await makeAppServerClient(stub: stub)
        let metadata = await client.metadata()
        #expect(metadata.serverName == "codex")
        #expect(metadata.serverVersion == "test")

        let thread = try await client.startThread()
        let handle = try await thread.turn("Hello")
        let stream = try await handle.stream()

        var events: [AppServerEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(thread.id == "thread_app")
        #expect(events.count == 5)
        if case .threadStarted(let threadID) = try #require(events.first) {
            #expect(threadID == "thread_app")
        } else {
            Issue.record("Expected first event to be thread started")
        }

        let methods = try stub.appServerMessages(forInvocation: 0).compactMap { $0.string(forKey: "method") }
        #expect(methods == ["initialize", "initialized", "thread/start", "turn/start"])
        await client.close()
    }

    @Test
    func appServerResumeThreadUsesResumeMethod() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadResumeResponses: [appServerThreadResponse(id: "thread_resume")]
        ))

        let client = try await makeAppServerClient(stub: stub)
        let thread = try await client.resumeThread(id: "thread_resume")

        #expect(thread.id == "thread_resume")
        let methods = try stub.appServerMessages(forInvocation: 0).compactMap { $0.string(forKey: "method") }
        #expect(methods == ["initialize", "initialized", "thread/resume"])
        await client.close()
    }

    @Test
    func appServerCommandApprovalRespondsAccept() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_cmd")],
            turnStartResponses: [appServerTurnResponse(id: "turn_cmd")],
            turnStartSequences: [[
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_cmd", turnID: "turn_cmd")),
                .request(
                    id: "approval-1",
                    method: "item/commandExecution/requestApproval",
                    params: appServerCommandApprovalParams(
                        threadID: "thread_cmd",
                        turnID: "turn_cmd",
                        itemID: "cmd_1",
                        approvalID: "approval_1",
                        command: "git push",
                        cwd: "/tmp/repo",
                        reason: "requires approval"
                    )
                ),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_cmd", turnID: "turn_cmd")),
            ]]
        ))

        let client = try await makeAppServerClient(
            stub: stub,
            commandApprovalHandler: { request in
                #expect(request.itemID == "cmd_1")
                #expect(request.command == "git push")
                return .approve
            }
        )

        let thread = try await client.startThread()
        _ = try await thread.run("Approve it")

        let responses = try stub.appServerResponses(forInvocation: 0)
        let result = try #require(responses.first?["result"]?.objectValue)
        #expect(result["decision"] == .string("accept"))
        await client.close()
    }

    @Test
    func appServerFileChangeApprovalRespondsDeclineAndTurnFails() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_patch")],
            turnStartResponses: [appServerTurnResponse(id: "turn_patch")],
            turnStartSequences: [[
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_patch", turnID: "turn_patch")),
                .request(
                    id: "approval-2",
                    method: "item/fileChange/requestApproval",
                    params: appServerFileChangeApprovalParams(
                        threadID: "thread_patch",
                        turnID: "turn_patch",
                        itemID: "patch_1",
                        reason: "extra write access needed",
                        grantRoot: "/tmp/other"
                    )
                ),
                .notification(
                    method: "error",
                    params: appServerErrorNotification(
                        threadID: "thread_patch",
                        turnID: "turn_patch",
                        message: "write denied"
                    )
                ),
            ]]
        ))

        let client = try await makeAppServerClient(
            stub: stub,
            fileChangeApprovalHandler: { request in
                #expect(request.itemID == "patch_1")
                #expect(request.grantRoot == "/tmp/other")
                return .deny
            }
        )

        let thread = try await client.startThread()
        do {
            _ = try await thread.run("Patch it")
            Issue.record("Expected turn failure after declined file-change approval")
        } catch let error as AppServerError {
            #expect(error == .turnFailed("write denied"))
        }

        let responses = try stub.appServerResponses(forInvocation: 0)
        let result = try #require(responses.first?["result"]?.objectValue)
        #expect(result["decision"] == .string("decline"))
        await client.close()
    }

    @Test
    func appServerUnsupportedServerRequestFailsClearly() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_bad")],
            turnStartResponses: [appServerTurnResponse(id: "turn_bad")],
            turnStartSequences: [[
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_bad", turnID: "turn_bad")),
                .request(
                    id: "unsupported-1",
                    method: "item/tool/requestUserInput",
                    params: ["threadId": "thread_bad", "turnId": "turn_bad"]
                ),
            ]]
        ))

        let client = try await makeAppServerClient(stub: stub)
        let thread = try await client.startThread()

        do {
            _ = try await thread.run("Unsupported")
            Issue.record("Expected unsupported server request error")
        } catch let error as AppServerError {
            #expect(error == .unsupportedServerRequest("item/tool/requestUserInput"))
        }

        await client.close()
    }

    @Test
    func appServerRejectsConcurrentTurnConsumers() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_concurrent")],
            turnStartResponses: [appServerTurnResponse(id: "turn_concurrent")],
            turnStartSequences: [[
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_concurrent", turnID: "turn_concurrent")),
            ]]
        ))

        let client = try await makeAppServerClient(stub: stub)
        let thread = try await client.startThread()
        let handle = try await thread.turn("Concurrent")
        let first = try await handle.stream()
        _ = first

        do {
            _ = try await handle.stream()
            Issue.record("Expected concurrent turn consumer rejection")
        } catch let error as AppServerError {
            #expect(error == .concurrentTurnConsumer(activeTurnID: "turn_concurrent", requestedTurnID: "turn_concurrent"))
        }

        await client.close()
    }
}

private func makeAppServerClient(
    stub: CodexStub,
    commandApprovalHandler: @escaping AppServerConfig.CommandApprovalHandler = { _ in .deny },
    fileChangeApprovalHandler: @escaping AppServerConfig.FileChangeApprovalHandler = { _ in .deny }
) async throws -> AppServerCodex {
    try await AppServerCodex(config: AppServerConfig(
        codexPathOverride: stub.executableURL.path(),
        environment: [
            "CODEX_TEST_STATE_DIR": stub.rootURL.path(),
        ],
        commandApprovalHandler: commandApprovalHandler,
        fileChangeApprovalHandler: fileChangeApprovalHandler
    ))
}

private extension JSONValue {
    var objectValue: JSONObject? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }
}

private extension JSONObject {
    func string(forKey key: String) -> String? {
        guard case .string(let value) = self[key] else {
            return nil
        }
        return value
    }
}
