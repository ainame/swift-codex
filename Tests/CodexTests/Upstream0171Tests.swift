import Testing
@testable import Codex

struct Upstream0171Tests {
    @Test(arguments: ["show", "hide"])
    func displayModesPreserveVersionAndUnknownFields(mode: String) throws {
        var fields: JSONObject = ["mode": .string(mode), "version": .string("1"), "future": .bool(true)]
        if mode == "show" { fields["trustedContacts"] = .string("skip") }
        else { fields["replacement"] = .object(["kind": .string("futureReplacement")]) }
        let raw = JSONValue.object(fields)
        let display = try decodeJSONValue(AgentMessageDisplay.self, from: raw)
        switch display {
        case .agentMessageDisplayVariant1(let value): #expect(value.version == .value1)
        case .agentMessageDisplayVariant2(let value): #expect(value.version == .value1)
        default: Issue.record("Expected typed display mode")
        }
        #expect(display.rawJSON == raw)
    }

    @Test(arguments: [JSONValue.string("search"), .number(42)])
    func searchPartialDispatchPreservesRequestID(id: JSONValue) throws {
        let raw: JSONValue = .object(["requestId": id, "data": .array([]), "future": .bool(true)])
        let payload = try CodexNotificationPayload(method: "thread/search/partial", params: raw)
        guard case .threadSearchPartial = payload else {
            Issue.record("Expected typed partial search notification")
            return
        }
        #expect(payload.rawJSON == raw)
    }
}
