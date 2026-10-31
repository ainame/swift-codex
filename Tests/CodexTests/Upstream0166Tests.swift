import Testing
@testable import Codex

struct Upstream0166Tests {
    @Test
    func migratedImagesPreferFileReferences() throws {
        let raw: JSONValue = .object([
            "type": .string("imageGeneration"), "id": .string("migrated_image"),
            "status": .string("completed"), "fileId": .string("file_166"),
            "result": .string(""),
        ])
        let item = try decodeJSONValue(ThreadItem.self, from: raw)
        guard case .imageGeneration(.fileId(let image)) = item else {
            Issue.record("Expected file reference to take precedence over empty inline result")
            return
        }
        #expect(image.fileId == "file_166")
        #expect(item.rawJSON == raw)
    }

    @Test(arguments: ["fileId", "result"])
    func imageResultsDecodeThroughItemNotifications(source: String) throws {
        let raw: JSONValue = .object([
            "type": .string("imageGeneration"), "id": .string("image_166"),
            "status": .string("completed"), source: .string("image-source"),
            "generationId": .string("generation_166"),
            "startedAtMs": .number(1_790_000_000_000),
            "completedAtMs": .number(1_790_000_000_123),
            "inputImages": .array([.object([
                "path": .string("/tmp/input.png"), "sha256": .string("digest"),
            ])]),
            "futureField": .bool(true),
        ])
        let params: JSONValue = .object([
            "threadId": .string("thread_166"), "turnId": .string("turn_166"), "item": raw,
            "completedAtMs": .number(1_790_000_000_123),
        ])
        let payload = try CodexNotificationPayload(method: "item/completed", params: params)
        guard case .itemCompleted(let notification) = payload,
              case .imageGeneration(let image) = notification.item else {
            Issue.record("Expected typed image generation item")
            return
        }
        switch image {
        case .fileId(let value):
            #expect(source == "fileId")
            #expect(value.fileId == "image-source")
            #expect(value.generationId == "generation_166")
            #expect(value.inputImages?.first?.sha256 == "digest")
            #expect(value.startedAtMs == 1_790_000_000_000)
            #expect(value.completedAtMs == 1_790_000_000_123)
        case .result(let value):
            #expect(source == "result")
            #expect(value.result == "image-source")
            #expect(value.generationId == "generation_166")
            #expect(value.inputImages?.first?.sha256 == "digest")
            #expect(value.startedAtMs == 1_790_000_000_000)
            #expect(value.completedAtMs == 1_790_000_000_123)
        case .unknown:
            Issue.record("Expected a typed image source")
        }
        #expect(image.rawJSON == raw)
        #expect(payload.rawJSON == params)
        let history = try decodeJSONValue(Turn.self, from: .object([
            "id": .string("turn_166"), "status": .string("completed"), "items": .array([raw]),
        ]))
        guard case .imageGeneration(let historyImage) = history.items.first else {
            Issue.record("Expected image generation history")
            return
        }
        #expect(historyImage.rawJSON == raw)
    }

    @Test(arguments: ["item/started", "item/completed"])
    func itemTimestampsSurviveNotificationDispatch(method: String) throws {
        let item: JSONValue = .object([
            "type": .string("agentMessage"), "id": .string("message_166"),
            "text": .string("Hello"), "startedAtMs": .number(1_790_000_000_000),
            "completedAtMs": .number(1_790_000_000_123), "futureField": .bool(true),
        ])
        let params: JSONValue = .object([
            "threadId": .string("thread_166"), "turnId": .string("turn_166"), "item": item,
            method == "item/started" ? "startedAtMs" : "completedAtMs": .number(1_790_000_000_123),
        ])
        let payload = try CodexNotificationPayload(method: method, params: params)
        let decoded: ThreadItem
        switch payload {
        case .itemStarted(let value): decoded = value.item
        case .itemCompleted(let value): decoded = value.item
        default:
            Issue.record("Expected item lifecycle notification")
            return
        }
        guard case .agentMessage(let message) = decoded else {
            Issue.record("Expected agent message")
            return
        }
        #expect(message.startedAtMs == 1_790_000_000_000)
        #expect(message.completedAtMs == 1_790_000_000_123)
        #expect(payload.rawJSON == params)
    }

    @Test(arguments: [true, false, nil] as [Bool?])
    func processExitPreservesDrainStatus(timedOut: Bool?) throws {
        var params: JSONObject = [
            "processHandle": .string("process_166"), "exitCode": .number(0),
            "stdout": .string("output"), "stderr": .string(""),
            "stdoutCapReached": .bool(false), "stderrCapReached": .bool(false),
        ]
        if let timedOut { params["outputDrainTimedOut"] = .bool(timedOut) }
        let payload = try CodexNotificationPayload(method: "process/exited", params: .object(params))
        guard case .processExited(let exit) = payload else {
            Issue.record("Expected process exit notification")
            return
        }
        #expect(exit.outputDrainTimedOut == timedOut)
        #expect(payload.rawJSON == .object(params))
    }

    @Test
    func threadUsageDecodesNativeCost() throws {
        let raw: JSONValue = .object([
            "threadId": .string("thread_166"), "groups": .array([]),
            "estimatedUsageCreditsMicros": .number(100),
            "nativeUsageUsdMicros": .number(42), "futureField": .bool(true),
        ])
        let usage = try decodeJSONValue(ThreadUsage.self, from: raw)
        #expect(usage.nativeUsageUsdMicros == 42)
        #expect(usage.rawJSON == raw)
    }
}
