import Foundation
import Testing
@testable import Codex

@Suite(.serialized)
struct AppServerSDKTests {
    @Test
    func appServerInitializesAndStreamsTypedNotifications() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_app")],
            turnStartResponses: [appServerTurnResponse(id: "turn_app")],
            turnStartSequences: [[
                .notification(method: "thread/started", params: appServerThreadStarted(threadID: "thread_app")),
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_app", turnID: "turn_app")),
                .notification(
                    method: "item/completed",
                    params: appServerItemNotification(
                        threadID: "thread_app",
                        turnID: "turn_app",
                        item: appServerAgentMessageItem(text: "Done")
                    )
                ),
                .notification(method: "turn/completed", params: [
                    "threadId": .string("thread_app"),
                    "turn": .object(appServerTurnObject(id: "turn_app")),
                ]),
            ]]
        ))

        let codex = try await makeAppServerCodex(stub: stub)
        let metadata = await codex.metadata()
        #expect(metadata.serverName == "codex")
        #expect(metadata.serverVersion == "test")

        let thread = try await codex.startThread()
        let handle = try await thread.turn("Hello")
        let stream = try await handle.stream()

        var methods: [String] = []
        for try await notification in stream {
            methods.append(notification.method)
        }

        #expect(methods == ["thread/started", "turn/started", "item/completed", "turn/completed"])
        await codex.close()
    }

    @Test
    func appServerThreadRunCollectsFinalResponseAndUsage() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_run")],
            turnStartResponses: [appServerTurnResponse(id: "turn_run")],
            turnStartSequences: [[
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_run", turnID: "turn_run")),
                .notification(
                    method: "item/completed",
                    params: appServerItemNotification(
                        threadID: "thread_run",
                        turnID: "turn_run",
                        item: appServerAgentMessageItem(text: "Interim", phase: nil)
                    )
                ),
                .notification(
                    method: "item/completed",
                    params: appServerItemNotification(
                        threadID: "thread_run",
                        turnID: "turn_run",
                        item: appServerAgentMessageItem(text: "Final", phase: "final_answer")
                    )
                ),
                .notification(
                    method: "thread/tokenUsage/updated",
                    params: appServerThreadTokenUsageUpdated(threadID: "thread_run", turnID: "turn_run")
                ),
                .notification(method: "turn/completed", params: [
                    "threadId": .string("thread_run"),
                    "turn": .object(appServerTurnObject(id: "turn_run")),
                ]),
            ]]
        ))

        let codex = try await makeAppServerCodex(stub: stub)
        let thread = try await codex.startThread()
        let result = try await thread.run("Hello")

        #expect(result.finalResponse == "Final")
        #expect(result.items.count == 2)
        #expect(result.usage != nil)
        await codex.close()
    }

    @Test
    func appServerDefaultApprovalAcceptsAndUnknownServerRequestsReturnEmptyObject() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_cmd")],
            turnStartResponses: [appServerTurnResponse(id: "turn_cmd")],
            turnStartSequences: [[
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
                .request(
                    id: "unknown-1",
                    method: "item/tool/requestUserInput",
                    params: [
                        "threadId": .string("thread_cmd"),
                        "turnId": .string("turn_cmd"),
                    ]
                ),
                .notification(method: "turn/completed", params: [
                    "threadId": .string("thread_cmd"),
                    "turn": .object(appServerTurnObject(id: "turn_cmd")),
                ]),
            ]]
        ))

        let codex = try await makeAppServerCodex(stub: stub)
        let thread = try await codex.startThread()
        _ = try await thread.run("Approve it")

        let responses = try stub.appServerResponses(forInvocation: 0)
        let approval = try #require(responses.first?["result"]?.objectValue)
        #expect(approval["decision"] == .string("accept"))
        let fallback = try #require(responses.dropFirst().first?["result"]?.objectValue)
        #expect(fallback == [:])
        await codex.close()
    }

    @Test
    func appServerLowLevelClientCoversThreadAndModelHelpers() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_start")],
            threadResumeResponses: [appServerThreadResponse(id: "thread_resume")],
            threadListResponses: [appServerThreadListResponse(threads: [appServerThreadObject(id: "thread_listed")])],
            threadReadResponses: [appServerThreadReadResponse(thread: appServerThreadObject(id: "thread_read", turns: [appServerTurnObject(id: "turn_old")]))],
            threadForkResponses: [appServerThreadResponse(id: "thread_fork")],
            threadArchiveResponses: [appServerEmptyResponse()],
            threadUnarchiveResponses: [appServerThreadResponse(id: "thread_unarchived")],
            threadSetNameResponses: [appServerEmptyResponse()],
            threadCompactResponses: [appServerEmptyResponse()],
            modelListResponses: [["models": []]]
        ))

        let client = AppServerClient(config: makeAppServerConfig(stub: stub))
        let initialize = try await client.initialize()
        #expect(initialize.serverName == "codex")

        let started = try await client.threadStart(options: .init(model: "gpt-5"))
        #expect(started.thread?.id == "thread_start")
        let resumed = try await client.threadResume(threadID: "thread_resume")
        #expect(resumed.thread?.id == "thread_resume")
        let listed = try await client.threadList()
        if case .array(let threads)? = listed.jsonObject?["threads"] {
            #expect(threads.count == 1)
        } else {
            Issue.record("Expected thread/list response to contain threads array")
        }
        let read = try await client.threadRead(threadID: "thread_read", includeTurns: true)
        #expect(read.jsonObject?.valueModel(forKey: "thread") as AppServerV2.Thread? != nil)
        let forked = try await client.threadFork(threadID: "thread_resume")
        #expect(forked.thread?.id == "thread_fork")
        _ = try await client.threadArchive(threadID: "thread_resume")
        let unarchived = try await client.threadUnarchive(threadID: "thread_resume")
        #expect(unarchived.thread?.id == "thread_unarchived")
        _ = try await client.threadSetName(threadID: "thread_resume", name: "Renamed")
        _ = try await client.threadCompact(threadID: "thread_resume")
        _ = try await client.modelList()

        let methods = try stub.appServerMessages(forInvocation: 0).compactMap { $0.string(forKey: "method") }
        #expect(methods == [
            "initialize",
            "initialized",
            "thread/start",
            "thread/resume",
            "thread/list",
            "thread/read",
            "thread/fork",
            "thread/archive",
            "thread/unarchive",
            "thread/name/set",
            "thread/compact/start",
            "model/list",
        ])
        await client.close()
    }

    @Test
    func appServerTurnSteerAndInterruptUseExpectedMethods() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadResponse(id: "thread_control")],
            turnStartResponses: [appServerTurnResponse(id: "turn_control")],
            turnStartSequences: [[]],
            turnSteerResponses: [appServerTurnSteerResponse(turnID: "turn_control")],
            turnInterruptResponses: [appServerEmptyResponse()]
        ))

        let codex = try await makeAppServerCodex(stub: stub)
        let thread = try await codex.startThread()
        let handle = try await thread.turn([.text("Hello"), .image(url: "https://example.test/a.png"), .skill(name: "checks", path: "/tmp/checks"), .mention(name: "repo", path: "/tmp/repo")])
        let steer = try await handle.steer(.localImage(path: "/tmp/local.png"))
        #expect(steer.turnID == "turn_control")
        _ = try await handle.interrupt()

        let messages = try stub.appServerMessages(forInvocation: 0)
        let methods = messages.compactMap { $0.string(forKey: "method") }
        #expect(methods == ["initialize", "initialized", "thread/start", "turn/start", "turn/steer", "turn/interrupt"])

        let turnStartInput = try #require(messages.first { $0.string(forKey: "method") == "turn/start" }?["params"]?.objectValue?["input"])
        if case .array(let items) = turnStartInput {
            #expect(items.count == 4)
        } else {
            Issue.record("Expected turn/start input array")
        }

        let steerInput = try #require(messages.first { $0.string(forKey: "method") == "turn/steer" }?["params"]?.objectValue?["input"])
        if case .array(let items) = steerInput {
            #expect(items.count == 1)
        } else {
            Issue.record("Expected turn/steer input array")
        }

        await codex.close()
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

        let codex = try await makeAppServerCodex(stub: stub)
        let thread = try await codex.startThread()
        let handle = try await thread.turn("Concurrent")
        let first = try await handle.stream()
        _ = first

        do {
            _ = try await handle.stream()
            Issue.record("Expected concurrent turn consumer rejection")
        } catch let error as AppServerError {
            #expect(error == .concurrentTurnConsumer(activeTurnID: "turn_concurrent", requestedTurnID: "turn_concurrent"))
        }

        await codex.close()
    }

    @Test
    func appServerInitializeClosureIncludesStderrTail() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            initializeCloseStderr: [
                "fatal: initialize failed",
                "hint: app-server exited early",
            ]
        ))

        do {
            _ = try await makeAppServerCodex(stub: stub)
            Issue.record("Expected transport closure during initialize")
        } catch let error as AppServerError {
            if case .transportClosedWithStderrTail(let stderrTail) = error {
                #expect(stderrTail.contains("fatal: initialize failed"))
                #expect(stderrTail.contains("hint: app-server exited early"))
            } else {
                Issue.record("Expected transportClosedWithStderrTail, got \(error)")
            }
        }
    }
}

private func makeAppServerConfig(
    stub: CodexStub,
    serverRequestHandler: AppServerConfig.ServerRequestHandler? = nil
) -> AppServerConfig {
    AppServerConfig(
        codexPathOverride: stub.executableURL.path(),
        environment: [
            "CODEX_TEST_STATE_DIR": stub.rootURL.path(),
        ],
        serverRequestHandler: serverRequestHandler
    )
}

private func makeAppServerCodex(
    stub: CodexStub,
    serverRequestHandler: AppServerConfig.ServerRequestHandler? = nil
) async throws -> AppServerCodex {
    try await AppServerCodex(config: makeAppServerConfig(stub: stub, serverRequestHandler: serverRequestHandler))
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
