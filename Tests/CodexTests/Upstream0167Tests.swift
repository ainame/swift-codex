import Testing
@testable import Codex

struct Upstream0167Tests {
    @Test(arguments: ["url", "fileId"])
    func audioReferencesRoundTrip(source: String) throws {
        let raw: JSONValue = .object([
            "type": .string("audio"), source: .string("audio-source"),
            "futureField": .bool(true),
        ])
        let input = try decodeJSONValue(UserInput.self, from: raw)
        guard case .audio(let audio) = input else {
            Issue.record("Expected typed audio input")
            return
        }
        switch audio {
        case .urlUserInput5(let value): #expect(source == "url" && value.url == "audio-source")
        case .fileIdUserInput5(let value): #expect(source == "fileId" && value.fileId == "audio-source")
        case .unknown: Issue.record("Expected known audio reference")
        }
        #expect(try encodeJSONValue(input) == raw)
    }

    @Test(arguments: [JSONValue.string("section-167"), .null])
    func sectionChangesPreserveRemovalAndExtensions(section: JSONValue) throws {
        let raw: JSONValue = .object([
            "threadId": .string("thread-167"), "sectionId": section,
            "futureField": .bool(true),
        ])
        let payload = try CodexNotificationPayload(method: "thread/section/changed", params: raw)
        guard case .threadSectionChanged(let notification) = payload else {
            Issue.record("Expected typed section notification")
            return
        }
        #expect(notification.threadId == "thread-167")
        #expect(payload.rawJSON == raw)
        #expect(payload.threadID == "thread-167")
    }
}
