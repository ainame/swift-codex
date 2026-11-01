import Testing
@testable import Codex

private actor HandlerClientReference {
    var client: CodexRPCClient?
    func set(_ client: CodexRPCClient) { self.client = client }
}

struct HandlerSchedulingTests {
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
        var config = stub.makeConfig()
        config.serverRequestHandler = { _ in
            started.continuation.yield(())
            do { try await Task.sleep(for: .seconds(60)) }
            catch { cancelled.continuation.yield(()) }
            // Deliberately return after cancellation: transport must discard it.
            return .json(["late": true])
        }
        let client = CodexRPCClient(config: config)
        let watchdog = Task {
            try await Task.sleep(for: .seconds(5))
            await client.close()
            started.continuation.finish()
            cancelled.continuation.finish()
        }
        defer {
            watchdog.cancel()
            started.continuation.finish()
            cancelled.continuation.finish()
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
        if action == "resolved" {
            // Establish that input processing remains usable after cancellation.
            _ = try await client.modelList()
            #expect(try stub.appServerMessages(forInvocation: 0).allSatisfy { $0["result"] == nil })
        }
        await client.close()
    }
}
