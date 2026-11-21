import Testing
@testable import Codex

struct ThreadHistoryTests {
    @Test
    func forwardsHistoryCursorsAndItemAnchor() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        let item: JSONValue = [
            "type": "agentMessage", "id": "item-2", "text": "Saved message",
            "moderation": ["moderated": true, "display": ["action": "futureAction"]],
        ]
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread-history")],
            threadTurnPages: [
                ["data": [makeTurn(id: "turn-1").rawJSON], "nextCursor": "next/turn==", "backwardsCursor": "back/turn=="],
                ["data": [], "nextCursor": nil, "backwardsCursor": nil],
            ],
            threadItemPages: [
                ["data": [["turnId": "turn-1", "item": item, "startedAtMs": 42]], "nextCursor": "next/item=="],
                ["data": [], "nextCursor": nil],
            ]
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let thread = try await codex.startThread()
        let turns = try await thread.listTurns(itemsView: .summary, limit: 1, sortDirection: .desc)
        #expect(turns.data.map(\.id) == ["turn-1"])
        #expect(turns.nextCursor == "next/turn==")
        let backwards = try #require(turns.backwardsCursor)
        let reversed = try await thread.listTurns(cursor: backwards, sortDirection: .asc)
        #expect(reversed.nextCursor == nil)

        let items = try await thread.listItems(
            turnID: "turn-1",
            cursor: .threadItemsListAnchor(.item(.init(itemId: "item-1", type: .item)))
        )
        let entry = try #require(items.data.first)
        #expect(items.data.count == 1)
        #expect(entry.turnId == "turn-1")
        #expect(entry.startedAtMs == 42)
        guard case .agentMessage(let message) = entry.item else {
            Issue.record("Expected an agent message")
            return
        }
        #expect(message.moderation?.display?.rawJSON == .object(["action": .string("futureAction")]))
        let cursor = try #require(items.nextCursor)
        let end = try await thread.listItems(turnID: "turn-1", cursor: .string(cursor))
        #expect(end.data.isEmpty)
        #expect(end.nextCursor == nil)

        let messages = try stub.appServerMessages(forInvocation: 0)
        let turnParams = messages.filter { $0["method"] == "thread/turns/list" }.compactMap { $0.objectValue(forKey: "params") }
        #expect(turnParams == [
            ["threadId": "thread-history", "itemsView": "summary", "limit": 1, "sortDirection": "desc"],
            ["threadId": "thread-history", "cursor": "back/turn==", "sortDirection": "asc"],
        ])
        let itemParams = messages.filter { $0["method"] == "thread/items/list" }.compactMap { $0.objectValue(forKey: "params") }
        #expect(itemParams == [
            ["threadId": "thread-history", "turnId": "turn-1", "cursor": ["type": "item", "itemId": "item-1"]],
            ["threadId": "thread-history", "turnId": "turn-1", "cursor": "next/item=="],
        ])
        await codex.close()
    }
}
