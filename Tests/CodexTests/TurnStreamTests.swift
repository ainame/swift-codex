import Foundation
import Testing
@testable import Codex

private func message(_ method: String, _ params: JSONObject) -> JSONObject {
    ["method": .string(method), "params": .object(params)]
}

private func delta(thread: String, turn: String, _ text: String) -> JSONObject {
    message("item/agentMessage/delta", [
        "threadId": .string(thread), "turnId": .string(turn), "itemId": "msg", "delta": .string(text),
    ])
}

private func completed(thread: String, turn: String) -> JSONObject {
    message("turn/completed", appServerTurnCompleted(threadID: thread, turnID: turn))
}

private func collect(_ stream: AsyncThrowingStream<CodexNotification, Error>) async throws -> [CodexNotification] {
    var notifications: [CodexNotification] = []
    for try await notification in stream {
        notifications.append(notification)
    }
    return notifications
}

private func deltas(_ notifications: [CodexNotification]) -> [String] {
    notifications.compactMap {
        if case .agentMessageDelta(let payload) = $0.payload { return payload.delta }
        return nil
    }
}

/// A stream releases its turn asynchronously after termination.
private func streamWhenReleased(_ handle: CodexTurnHandle) async throws -> AsyncThrowingStream<CodexNotification, Error> {
    for _ in 0..<500 {
        do {
            return try await handle.stream()
        } catch CodexError.concurrentTurnConsumer {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    throw CodexError.invalidResponse("turn stream was never released")
}

private func expectUnavailable(_ reason: TurnStreamUnavailableReason, _ body: () async throws -> Void) async {
    do {
        try await body()
        Issue.record("Expected turnStreamUnavailable(\(reason))")
    } catch CodexError.turnStreamUnavailable(_, _, let actual) {
        #expect(actual == reason)
    } catch {
        Issue.record("Expected turnStreamUnavailable(\(reason)), got \(error)")
    }
}

@Suite(.serialized)
struct TurnStreamTests {
    @Test(arguments: [false, true])
    func cancelledHighLevelRunsThrowCancellationError(useHandle: Bool) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            threadStartResponses: [appServerThreadStartResponse(id: "thread")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn")],
            turnStartSequences: [[.request(id: "running", method: "test/running", params: [:])]]
        ))
        let started = AsyncStream.makeStream(of: Void.self)
        let config = stub.makeConfig(serverRequestHandler: { _ in started.continuation.yield(()); return .json([:]) })
        let codex = try await Codex(config: config)
        let watchdog = Task { try await Task.sleep(for: .seconds(5)); await codex.close(); started.continuation.finish() }
        defer { watchdog.cancel(); started.continuation.finish() }
        let thread = try await codex.startThread()
        let handle = useHandle ? try await thread.turn("test") : nil
        let run = Task {
            if let handle { _ = try await handle.run() }
            else { _ = try await thread.run("test") }
        }
        var iterator = started.stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        _ = try await codex.models()
        await codex.close()
    }

    @Test
    func completionAfterConsumerTerminationIsStillReplayable() async throws {
        var router = TurnStreamRouter()
        let key = TurnKey(threadID: "thread", turnID: "turn")
        router.beginTurnStart(requestID: "start", threadID: key.threadID)
        router.completeTurnStart(requestID: "start", key: key)
        let old = AsyncThrowingStream.makeStream(of: CodexNotification.self)
        try router.attach(key, token: UUID(), continuation: old.continuation)
        router.route(CodexNotification(method: "item/agentMessage/delta", params: ["threadId": "thread", "turnId": "turn", "itemId": "item", "delta": "early"]))
        // Simulate cancellation before the actor processes onTermination's detach.
        old.continuation.finish()
        router.route(CodexNotification(method: "turn/completed", params: .object(appServerTurnCompleted(threadID: "thread", turnID: "turn"))))
        let replacement = AsyncThrowingStream.makeStream(of: CodexNotification.self)
        try router.attach(key, token: UUID(), continuation: replacement.continuation)
        let events = try await collect(replacement.stream)
        #expect(events.map(\.method) == ["item/agentMessage/delta", "turn/completed"])
        #expect(deltas(events) == ["early"])
        _ = old.stream
    }

    @Test
    func unrelatedPendingTurnsDoNotExhaustTheRequestedTurnsBuffer() async throws {
        var limits = NotificationBufferLimits()
        limits.maxNotificationsPerTurn = 2
        var router = TurnStreamRouter(limits: limits)
        let key = TurnKey(threadID: "thread", turnID: "target")
        router.beginTurnStart(requestID: "start", threadID: key.threadID)
        for _ in 0..<5 {
            router.route(CodexNotification(method: "item/agentMessage/delta", params: ["threadId": "thread", "turnId": "sibling", "itemId": "item", "delta": "unrelated"]))
        }
        router.route(CodexNotification(method: "item/agentMessage/delta", params: ["threadId": "thread", "turnId": "target", "itemId": "item", "delta": "target"]))
        router.route(CodexNotification(method: "turn/completed", params: .object(appServerTurnCompleted(threadID: "thread", turnID: "target"))))
        router.completeTurnStart(requestID: "start", key: key)
        let stream = AsyncThrowingStream.makeStream(of: CodexNotification.self)
        try router.attach(key, token: UUID(), continuation: stream.continuation)
        #expect(deltas(try await collect(stream.stream)) == ["target"])
    }

    @Test
    func concurrentStreamsOnTwoThreadsSharingATurnIDStayIsolated() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        let interleaved: [JSONObject] = [
            delta(thread: "thread_a", turn: "turn_shared", "a1"),
            delta(thread: "thread_b", turn: "turn_shared", "b1"),
            message("thread/custom", ["threadId": "thread_a", "future": true]),
            message("test/global", ["future": true]),
            message("item/completed", appServerItemCompleted(threadID: "thread_a", turnID: "turn_shared", item: appServerAgentMessageItem(text: "A"))),
            message("thread/tokenUsage/updated", appServerThreadTokenUsageUpdated(threadID: "thread_b", turnID: "turn_shared")),
            delta(thread: "thread_a", turn: "turn_shared", "a2"),
            message("item/completed", appServerItemCompleted(threadID: "thread_b", turnID: "turn_shared", item: appServerAgentMessageItem(text: "B"))),
            completed(thread: "thread_b", turn: "turn_shared"),
            delta(thread: "thread_a", turn: "turn_shared", "a3"),
            completed(thread: "thread_a", turn: "turn_shared"),
        ]
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            rpcResponses: ["model/list": ["data": []]],
            threadStartResponses: [appServerThreadStartResponse(id: "thread_a"), appServerThreadStartResponse(id: "thread_b")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_shared"), appServerTurnStartResponse(id: "turn_shared")],
            turnStartSequences: [[], []]
        ).emitting(["model/list": [interleaved]]))

        let codex = try await Codex(config: stub.makeConfig())
        let threadA = try await codex.startThread()
        let threadB = try await codex.startThread()
        let handleA = try await threadA.turn("A")
        let handleB = try await threadB.turn("B")
        // Both streams are attached before any event is emitted.
        let streamA = try await handleA.stream()
        let streamB = try await handleB.stream()
        async let collectedA = collect(streamA)
        async let collectedB = collect(streamB)
        _ = try await codex.models()
        let (eventsA, eventsB) = try await (collectedA, collectedB)

        #expect(deltas(eventsA) == ["a1", "a2", "a3"])
        #expect(deltas(eventsB) == ["b1"])
        #expect(eventsA.allSatisfy { $0.threadID == "thread_a" })
        #expect(eventsB.allSatisfy { $0.threadID == "thread_b" })
        #expect(eventsA.map(\.method) == [
            "item/agentMessage/delta", "thread/custom", "item/completed", "item/agentMessage/delta",
            "item/agentMessage/delta", "turn/completed",
        ])
        #expect(eventsB.map(\.method) == [
            "item/agentMessage/delta", "thread/tokenUsage/updated", "item/completed", "turn/completed",
        ])
        // Thread-scoped unknown notifications keep their payload and metadata.
        let custom = try #require(eventsA.first { $0.method == "thread/custom" })
        #expect(custom.rawParams == ["threadId": "thread_a", "future": true])
        guard case .unknown(let method, _) = custom.payload else {
            Issue.record("Expected unknown payload")
            return
        }
        #expect(method == "thread/custom")
        await codex.close()
    }

    @Test
    func concurrentRunsOnOneClientReturnPerTurnResults() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        // Whichever turn/start arrives second emits both turns' events, so at
        // least one run observes events that arrived before it registered.
        let events: [AppServerScriptStep] = [
            .notification(method: "item/completed", params: appServerItemCompleted(
                threadID: "thread_b", turnID: "turn_same", item: appServerAgentMessageItem(text: "B final", phase: .finalAnswer))),
            .notification(method: "item/completed", params: appServerItemCompleted(
                threadID: "thread_a", turnID: "turn_same", item: appServerAgentMessageItem(text: "A final", phase: .finalAnswer))),
            .notification(method: "thread/tokenUsage/updated", params: appServerThreadTokenUsageUpdated(threadID: "thread_a", turnID: "turn_same")),
            .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_a", turnID: "turn_same")),
            .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_b", turnID: "turn_same")),
        ]
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_a"), appServerThreadStartResponse(id: "thread_b")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_same"), appServerTurnStartResponse(id: "turn_same")],
            turnStartSequences: [[], events]
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let threadA = try await codex.startThread()
        let threadB = try await codex.startThread()
        async let runA = threadA.run("A")
        async let runB = threadB.run("B")
        let (resultA, resultB) = try await (runA, runB)

        #expect(resultA.finalResponse == "A final")
        #expect(resultB.finalResponse == "B final")
        #expect(resultA.items.count == 1)
        #expect(resultB.items.count == 1)
        #expect(resultA.usage?.total.totalTokens == 3)
        #expect(resultB.usage == nil)
        await codex.close()
    }

    @Test
    func rawReaderAndTurnStreamDoNotStealFromEachOther() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            turnStartResponses: [appServerTurnStartResponse(id: "turn_raw")],
            turnStartSequences: [[]]
        ))
        let client = CodexRPCClient(config: stub.makeConfig())
        let watchdog = Task { try await Task.sleep(for: .seconds(10)); await client.close() }
        defer { watchdog.cancel() }
        _ = try await client.initialize()
        _ = try await client.turnStart(threadID: "thread_raw", input: [.text("go")])
        let stream = try await client.turnStream(threadID: "thread_raw", turnID: "turn_raw")
        let raw = Task {
            var methods: [String] = []
            while methods.last != "turn/completed" {
                methods.append(try await client.nextNotification().method)
            }
            return methods
        }
        async let streamed = collect(stream)
        try await client.notify("test/emit", params: ["messages": .array([
            .object(message("test/global", [:])),
            .object(delta(thread: "thread_raw", turn: "turn_raw", "x")),
            .object(delta(thread: "thread_other", turn: "turn_raw", "other")),
            .object(completed(thread: "thread_raw", turn: "turn_raw")),
        ])])

        #expect(try await streamed.map(\.method) == ["item/agentMessage/delta", "turn/completed"])
        #expect(try await raw.value == ["test/global", "item/agentMessage/delta", "item/agentMessage/delta", "turn/completed"])
        await client.close()
    }

    @Test
    func turnEventsBeforeTheResponseAndAfterCompletionAreReplayed() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_early")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_early")],
            turnStartSequences: [[
                .notification(method: "item/completed", params: appServerItemCompleted(
                    threadID: "thread_early", turnID: "turn_early", item: appServerAgentMessageItem(text: "Early", phase: .finalAnswer))),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_early", turnID: "turn_early")),
            ]]
        ).preluding([[
            message("turn/started", appServerTurnStarted(threadID: "thread_early", turnID: "turn_early")),
            message("turn/started", appServerTurnStarted(threadID: "thread_early", turnID: "turn_unrelated")),
        ]]))

        let codex = try await Codex(config: stub.makeConfig())
        let thread = try await codex.startThread()
        let handle = try await thread.turn("Early")
        // The model/list response follows all prior notifications on stdout.
        _ = try await codex.models()

        let events = try await collect(handle.stream())
        #expect(events.map(\.method) == ["turn/started", "item/completed", "turn/completed"])
        #expect(events.map(\.turnID) == ["turn_early", "turn_early", "turn_early"])
        // A consumed turn cannot be streamed again with a partial history.
        await expectUnavailable(.alreadyConsumed) { _ = try await handle.stream() }
        await codex.close()
    }

    @Test
    func duplicateConsumersForTheSameTurnAreRejected() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            rpcResponses: ["model/list": ["data": []]],
            threadStartResponses: [appServerThreadStartResponse(id: "thread_dup")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_dup")],
            turnStartSequences: [[
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_dup", turnID: "turn_dup")),
            ]]
        ).emitting(["model/list": [[completed(thread: "thread_dup", turn: "turn_dup")]]]))

        let codex = try await Codex(config: stub.makeConfig())
        let thread = try await codex.startThread()
        let handle = try await thread.turn("Duplicate")
        let first = try await handle.stream()
        do {
            _ = try await handle.stream()
            Issue.record("Expected duplicate same-turn consumer rejection")
        } catch CodexError.concurrentTurnConsumer(let activeTurnID, let requestedTurnID) {
            #expect(activeTurnID == "turn_dup")
            #expect(requestedTurnID == "turn_dup")
        }
        _ = try await codex.models()
        #expect(try await collect(first).map(\.method) == ["turn/started", "turn/completed"])
        await codex.close()
    }

    @Test
    func cancellingOneStreamDoesNotDisturbAnotherAndCanBeReplaced() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            rpcResponses: ["model/list": ["data": []]],
            threadStartResponses: [appServerThreadStartResponse(id: "thread_a"), appServerThreadStartResponse(id: "thread_b")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_a"), appServerTurnStartResponse(id: "turn_b")],
            turnStartSequences: [[], []]
        ).emitting(["model/list": [
            [delta(thread: "thread_a", turn: "turn_a", "a1"), delta(thread: "thread_b", turn: "turn_b", "b1")],
            [
                delta(thread: "thread_b", turn: "turn_b", "b2"), delta(thread: "thread_a", turn: "turn_a", "a2"),
                completed(thread: "thread_b", turn: "turn_b"), completed(thread: "thread_a", turn: "turn_a"),
            ],
        ]]))

        let codex = try await Codex(config: stub.makeConfig())
        let threadA = try await codex.startThread()
        let threadB = try await codex.startThread()
        let handleA = try await threadA.turn("A")
        let handleB = try await threadB.turn("B")
        let streamB = try await handleB.stream()
        async let eventsB = collect(streamB)

        let received = AsyncStream.makeStream(of: String.self)
        let consumerA = Task {
            for try await notification in try await handleA.stream() {
                if case .agentMessageDelta(let payload) = notification.payload {
                    received.continuation.yield(payload.delta)
                }
            }
        }
        _ = try await codex.models()
        var iterator = received.stream.makeAsyncIterator()
        #expect(await iterator.next() == "a1")
        consumerA.cancel()
        _ = try? await consumerA.value

        // The replacement replays the turn from its start.
        let replacement = try await streamWhenReleased(handleA)
        async let eventsA = collect(replacement)
        _ = try await codex.models()

        #expect(deltas(try await eventsA) == ["a1", "a2"])
        #expect(deltas(try await eventsB) == ["b1", "b2"])
        received.continuation.finish()
        await codex.close()
    }

    @Test(arguments: ["close", "exit"])
    func closeAndEOFTerminateInProgressStreams(action: String) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            rpcResponses: ["model/list": ["data": []]],
            threadStartResponses: [appServerThreadStartResponse(id: "thread_open"), appServerThreadStartResponse(id: "thread_done")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_open"), appServerTurnStartResponse(id: "turn_done")],
            turnStartSequences: [
                [.notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_open", turnID: "turn_open"))],
                [.notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_done", turnID: "turn_done"))],
            ]
        ).emitting(["model/list": [[["exit": true]]]]))

        let codex = try await Codex(config: stub.makeConfig())
        let open = try await codex.startThread()
        let done = try await codex.startThread()
        let openHandle = try await open.turn("Open")
        let doneHandle = try await done.turn("Done")
        let stream = try await openHandle.stream()
        let consumer = Task { try await collect(stream) }
        if action == "close" {
            await codex.close()
        } else {
            _ = try await codex.models()
        }
        await #expect(throws: CodexError.self) { try await consumer.value }
        // A turn that completed before EOF keeps its full history.
        if action == "exit" {
            #expect(try await collect(doneHandle.stream()).map(\.method) == ["turn/completed"])
        }
        await #expect(throws: CodexError.self) { _ = try await openHandle.stream() }
        await codex.close()
    }

    @Test
    func reopeningDoesNotLetOldStreamsAffectNewRoutes() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        for index in 0..<2 {
            try stub.configureAppServerInvocation(index, scenario: AppServerScenario(
                turnStartResponses: [appServerTurnStartResponse(id: "turn_reused")],
                turnStartSequences: [[]]
            ))
        }
        let client = CodexRPCClient(config: stub.makeConfig())
        let watchdog = Task { try await Task.sleep(for: .seconds(10)); await client.close() }
        defer { watchdog.cancel() }
        _ = try await client.initialize()
        _ = try await client.turnStart(threadID: "thread_reused", input: [.text("old")])
        let old = try await client.turnStream(threadID: "thread_reused", turnID: "turn_reused")
        await client.close()
        await #expect(throws: CodexError.self) { _ = try await collect(old) }

        _ = try await client.initialize()
        _ = try await client.turnStart(threadID: "thread_reused", input: [.text("new")])
        let new = try await client.turnStream(threadID: "thread_reused", turnID: "turn_reused")
        async let events = collect(new)
        try await client.notify("test/emit", params: ["messages": .array([
            .object(delta(thread: "thread_reused", turn: "turn_reused", "new")),
            .object(completed(thread: "thread_reused", turn: "turn_reused")),
        ])])
        #expect(deltas(try await events) == ["new"])
        await client.close()
    }

    @Test
    func unknownEvictedAndOverflowedTurnsFailExplicitly() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        let early: (String) -> [AppServerScriptStep] = { turn in [
            .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread", turnID: turn)),
            .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread", turnID: turn)),
        ] }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            turnStartResponses: ["first", "second", "third"].map { appServerTurnStartResponse(id: $0) },
            turnStartSequences: [early("first"), early("second"), [
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread", turnID: "third")),
                .notification(method: "item/started", params: appServerItemStarted(threadID: "thread", turnID: "third", item: appServerAgentMessageItem(text: "x"))),
                .notification(method: "item/completed", params: appServerItemCompleted(threadID: "thread", turnID: "third", item: appServerAgentMessageItem(text: "x"))),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread", turnID: "third")),
            ]]
        ))
        var config = stub.makeConfig()
        config.notificationBufferLimits.maxUnclaimedCompletedTurns = 1
        config.notificationBufferLimits.maxNotificationsPerTurn = 3
        config.notificationBufferLimits.maxRawBacklog = 4
        let client = CodexRPCClient(config: config)
        _ = try await client.initialize()
        await expectUnavailable(.unknownTurn) { _ = try await client.turnStream(threadID: "thread", turnID: "never") }

        _ = try await client.turnStart(threadID: "thread", input: [.text("1")])
        _ = try await client.turnStart(threadID: "thread", input: [.text("2")])
        _ = try await client.turnStart(threadID: "thread", input: [.text("3")])
        _ = try await client.modelList() // all scripted notifications are processed
        await expectUnavailable(.evicted) { _ = try await client.turnStream(threadID: "thread", turnID: "first") }
        await expectUnavailable(.bufferLimitExceeded) { _ = try await client.turnStream(threadID: "thread", turnID: "third") }
        #expect(try await collect(client.turnStream(threadID: "thread", turnID: "second")).count == 2)

        // Eight raw notifications with a backlog of four: report, then continue.
        do {
            _ = try await client.nextNotification()
            Issue.record("Expected raw backlog overflow")
        } catch CodexError.notificationBacklogOverflow(let droppedCount) {
            #expect(droppedCount == 4)
        }
        #expect(try await client.nextNotification().turnID == "third")
        await client.close()
    }
}

struct TurnStreamRouterTests {
    @Test
    func routesByThreadAndTurnAndScopesDetachToTokens() async throws {
        var router = TurnStreamRouter()
        let keyA = TurnKey(threadID: "a", turnID: "same")
        let keyB = TurnKey(threadID: "b", turnID: "same")
        router.beginTurnStart(requestID: "1", threadID: "a")
        router.completeTurnStart(requestID: "1", key: keyA)
        router.beginTurnStart(requestID: "2", threadID: "b")
        router.completeTurnStart(requestID: "2", key: keyB)

        let (oldStream, oldContinuation) = AsyncThrowingStream.makeStream(of: CodexNotification.self)
        let oldToken = UUID()
        try router.attach(keyA, token: oldToken, continuation: oldContinuation)
        router.detach(keyA, token: oldToken)
        _ = oldStream

        let (newStream, newContinuation) = AsyncThrowingStream.makeStream(of: CodexNotification.self)
        try router.attach(keyA, token: UUID(), continuation: newContinuation)
        // A late termination of the old consumer must not detach the replacement.
        router.detach(keyA, token: oldToken)
        do {
            try router.attach(keyA, token: UUID(), continuation: AsyncThrowingStream.makeStream(of: CodexNotification.self).continuation)
            Issue.record("Expected the replacement consumer to remain attached")
        } catch CodexError.concurrentTurnConsumer {}

        router.route(CodexNotification(method: "turn/completed", params: .object(appServerTurnCompleted(threadID: "b", turnID: "same"))))
        router.route(CodexNotification(method: "thread/custom", params: ["threadId": "a"]))
        router.route(CodexNotification(method: "item/agentMessage/delta", params: ["threadId": "c", "turnId": "same", "itemId": "i", "delta": "c"]))
        router.route(CodexNotification(method: "turn/completed", params: .object(appServerTurnCompleted(threadID: "a", turnID: "same"))))
        #expect(router.openRouteCount == 1) // b completed but unclaimed; a consumed
        let events = try await collect(newStream)
        #expect(events.map(\.method) == ["thread/custom", "turn/completed"])
        #expect(events.allSatisfy { $0.threadID == "a" })
    }
}

private extension AppServerScenario {
    func emitting(_ sequences: [String: [[JSONObject]]]) -> Self {
        var copy = self
        copy.emitSequences = sequences
        return copy
    }

    func preluding(_ preludes: [[JSONObject]]) -> Self {
        var copy = self
        copy.turnStartPreludes = preludes
        return copy
    }
}
