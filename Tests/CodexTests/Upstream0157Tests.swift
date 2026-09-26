import Testing
@testable import Codex

struct Upstream0157Tests {
    @Test(arguments: ["url", "fileId"])
    func imageSourcesPreserveSharedFields(source: String) throws {
        let raw: JSONValue = .object([
            "type": .string("image"), "detail": .string("high"),
            source: .string("image-source"), "futureField": .bool(true),
        ])
        let input = try decodeJSONValue(UserInput.self, from: raw)
        guard case .image(let image) = input else {
            Issue.record("Expected image input")
            return
        }
        switch image {
        case .urlUserInput(let value):
            #expect(source == "url")
            #expect(value.detail == .high)
            #expect(value.type.rawValue == "image")
        case .fileIdUserInput(let value):
            #expect(source == "fileId")
            #expect(value.detail == .high)
            #expect(value.type.rawValue == "image")
        case .unknown:
            Issue.record("Expected a typed image source")
        }
        #expect(input.rawJSON == raw)
    }

    @Test(arguments: ["image_url", "file_id"])
    func toolOutputImagesPreserveSharedFields(source: String) throws {
        let raw: JSONValue = .object([
            "type": .string("input_image"), "detail": .string("high"),
            source: .string("image-source"),
        ])
        let output = try decodeJSONValue(InputImageFunctionCallOutputContentItem.self, from: raw)
        switch output {
        case .imageUrlFunctionCallOutputContentItem(let value):
            #expect(source == "image_url")
            #expect(value.detail == .high)
            #expect(value.type.rawValue == "input_image")
        case .fileIdFunctionCallOutputContentItem(let value):
            #expect(source == "file_id")
            #expect(value.detail == .high)
            #expect(value.type.rawValue == "input_image")
        case .unknown:
            Issue.record("Expected a typed tool image source")
        }
        #expect(output.rawJSON == raw)
    }

    @Test
    func gatewayNotificationUsesTypedRegistry() throws {
        let raw: JSONValue = .object([
            "providerId": .string("gateway"), "status": .string("started"),
            "authUrl": .string("https://example.test/auth"),
        ])
        let payload = try CodexNotificationPayload(method: "account/gatewayOAuth/changed", params: raw)
        guard case .gatewayOAuthChanged(let notification) = payload else {
            Issue.record("Expected gateway OAuth notification")
            return
        }
        #expect(notification.status == .started)
        #expect(notification.providerId == "gateway")
        #expect(payload.rawJSON == raw)
    }
}
