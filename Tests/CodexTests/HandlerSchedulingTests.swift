import Testing
import Logging
@testable import Codex

private actor HandlerClientReference {
    var client: CodexRPCClient?
    func set(_ client: CodexRPCClient) { self.client = client }
}

private actor NonCancellingHandlerGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(started: AsyncStream<Void>.Continuation) async {
        await withCheckedContinuation {
            continuation = $0
            started.yield(())
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

private struct DiscardedHandlerLog: LogHandler {
    let discarded: AsyncStream<Void>.Continuation
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
    func log(event: Logging.LogEvent) {
        if event.message.description == "Discarding cancelled server request response" { discarded.yield(()) }
    }
}

struct HandlerSchedulingTests {
    @Test
    func duplicateActiveServerIDsFailTransport() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            concurrentServerRequests: true,
            turnStartResponses: [appServerTurnStartResponse(id: "turn")],
            turnStartSequences: [[
                .request(id: 1, method: "test/wait", params: [:]),
                .request(id: 1, method: "test/wait", params: [:]),
            ]]
        ))
        var config = stub.makeConfig()
        config.serverRequestHandler = { _ in
            try? await Task.sleep(for: .seconds(60))
            return .json(.null)
        }
        let client = CodexRPCClient(config: config)
        let watchdog = Task { try await Task.sleep(for: .seconds(5)); await client.close() }
        defer { watchdog.cancel() }
        _ = try await client.turnStart(threadID: "thread", input: [.text("test")])
        do {
            _ = try await client.nextNotification()
            Issue.record("Expected duplicate request ID failure")
        } catch CodexError.invalidResponse(let message) {
            #expect(message == "Duplicate active server request ID")
        }
        await client.close()
    }

    @Test
    func reopeningIgnoresOldProcessAndLateHandlerReplies() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        for index in 0..<2 {
            try stub.configureAppServerInvocation(index, scenario: .init(
                concurrentServerRequests: true,
                turnStartResponses: [appServerTurnStartResponse(id: "turn")],
                turnStartSequences: [[.request(id: "same-server-id", method: "test/held", params: ["old": .bool(index == 0)])]]
            ))
        }
        let gate = NonCancellingHandlerGate()
        let started = AsyncStream.makeStream(of: Void.self)
        let discarded = AsyncStream.makeStream(of: Void.self)
        var config = stub.makeConfig()
        config.serverRequestHandler = { request in
            if case .unknown(_, let params) = request, params?.objectValue?["old"] == true {
                // This gate intentionally ignores cancellation to test late replies.
                await gate.wait(started: started.continuation)
                return .json(["old": true])
            }
            return .json(["new": true])
        }
        let client = CodexRPCClient(config: config, logger: Logger(label: "reopen") { _ in DiscardedHandlerLog(discarded: discarded.continuation) })
        let watchdog = Task {
            try await Task.sleep(for: .seconds(5))
            await gate.release()
            await client.close()
            started.continuation.finish(); discarded.continuation.finish()
        }
        defer { watchdog.cancel(); started.continuation.finish(); discarded.continuation.finish() }
        _ = try await client.initialize()
        _ = try await client.turnStart(threadID: "thread", input: [.text("test")])
        var startIterator = started.stream.makeAsyncIterator()
        #expect(await startIterator.next() != nil)
        await client.close()
        _ = try await client.initialize()
        _ = try await client.turnStart(threadID: "thread", input: [.text("test")])
        let reply = try await client.nextNotification()
        #expect(reply.rawParams.objectValue?["result"] == ["new": true])
        await gate.release()
        var discardIterator = discarded.stream.makeAsyncIterator()
        #expect(await discardIterator.next() != nil)
        _ = try await client.modelList()
        #expect(try stub.appServerResponses(forInvocation: 1).map { $0["result"] } == [["new": true]])
        await client.close()
    }

    @Test
    func cancelledNotificationWaitDoesNotConsumeLaterEvents() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        let client = CodexRPCClient(config: stub.makeConfig())
        _ = try await client.initialize()
        let watchdog = Task { try await Task.sleep(for: .seconds(5)); await client.close() }
        defer { watchdog.cancel() }
        let waiting = Task { try await client.nextNotification() }
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        try await client.notify("test/resolve", params: ["requestId": 999, "threadId": "thread"])
        let notification = try await client.nextNotification()
        #expect(notification.method == "serverRequest/resolved")
        await client.close()
    }

    @Test
    func handlersCanCallSameClientAndCompleteOutOfOrder() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            concurrentServerRequests: true,
            turnStartResponses: [appServerTurnStartResponse(id: "turn")],
            turnStartSequences: [[
                .request(id: "slow", method: "test/slow", params: [:]),
                .request(id: 9, method: "test/nested", params: [:]),
            ]]
        ))
        let reference = HandlerClientReference()
        let release = AsyncStream.makeStream(of: Void.self)
        var config = stub.makeConfig()
        config.serverRequestHandler = { request in
            guard case .unknown(let method, _) = request else { return .json(.null) }
            if method == "test/slow" {
                for await _ in release.stream { break }
            } else {
                do {
                    let client = try #require(await reference.client)
                    let response = try await client.modelList()
                    #expect(response.data.isEmpty)
                } catch { Issue.record(error) }
                release.continuation.yield(())
            }
            return .json(["method": .string(method)])
        }
        let client = CodexRPCClient(config: config)
        await reference.set(client)
        let watchdog = Task { try await Task.sleep(for: .seconds(5)); await client.close() }
        defer { watchdog.cancel(); release.continuation.finish() }
        _ = try await client.turnStart(threadID: "thread", input: [.text("test")])
        var ids = Set<JSONValue>()
        for _ in 0..<2 {
            let reply = try await client.nextNotification()
            #expect(reply.method == "test/serverResponse")
            ids.insert(try #require(reply.rawParams.objectValue?["id"]))
        }
        #expect(ids == ["slow", 9])
        await client.close()
    }

    @Test(arguments: ["close", "resolved", "exit"])
    func shutdownAndResolutionCancelHandlers(action: String) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: .init(
            concurrentServerRequests: true,
            turnStartResponses: [appServerTurnStartResponse(id: "turn")],
            turnStartSequences: [[.request(id: 10, method: "test/wait", params: [:])]]
        ))
        let started = AsyncStream.makeStream(of: Void.self)
        let cancelled = AsyncStream.makeStream(of: Void.self)
        let discarded = AsyncStream.makeStream(of: Void.self)
        var config = stub.makeConfig()
        config.serverRequestHandler = { _ in
            started.continuation.yield(())
            do { try await Task.sleep(for: .seconds(60)) }
            catch { cancelled.continuation.yield(()) }
            // Deliberately return after cancellation: transport must discard it.
            return .json(["late": true])
        }
        let client = CodexRPCClient(config: config, logger: Logger(label: "cancel") { _ in DiscardedHandlerLog(discarded: discarded.continuation) })
        let watchdog = Task {
            try await Task.sleep(for: .seconds(5))
            await client.close()
            started.continuation.finish()
            cancelled.continuation.finish()
            discarded.continuation.finish()
        }
        defer {
            watchdog.cancel()
            started.continuation.finish()
            cancelled.continuation.finish()
            discarded.continuation.finish()
        }
        _ = try await client.turnStart(threadID: "thread", input: [.text("test")])
        var startIterator = started.stream.makeAsyncIterator()
        #expect(await startIterator.next() != nil)
        switch action {
        case "close": await client.close()
        case "exit": try await client.notify("test/exit")
        default:
            try await client.notify("test/resolve", params: ["requestId": 10, "threadId": "thread"])
            let notification = try await client.nextNotification()
            #expect(notification.method == "serverRequest/resolved")
        }
        var cancelIterator = cancelled.stream.makeAsyncIterator()
        #expect(await cancelIterator.next() != nil)
        var discardIterator = discarded.stream.makeAsyncIterator()
        #expect(await discardIterator.next() != nil)
        if action == "resolved" {
            // Establish that input processing remains usable after cancellation.
            _ = try await client.modelList()
            #expect(try stub.appServerMessages(forInvocation: 0).allSatisfy { $0["result"] == nil })
        }
        await client.close()
    }
}
