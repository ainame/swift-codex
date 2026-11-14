import Testing
@testable import Codex

struct Upstream0169Tests {
    @Test(arguments: ["audio_url", "file_id"])
    func functionOutputAudioReferencesRoundTrip(source: String) throws {
        let raw: JSONValue = .object([
            "type": "input_audio", source: "audio-source", "futureField": true,
        ])
        let item = try decodeJSONValue(FunctionCallOutputContentItem.self, from: raw)
        guard case .inputAudio(let audio) = item else {
            Issue.record("Expected typed function output audio")
            return
        }
        switch audio {
        case .audioUrlFunctionCallOutputContentItem(let value):
            #expect(source == "audio_url" && value.audioUrl == "audio-source")
        case .fileIdFunctionCallOutputContentItem5(let value):
            #expect(source == "file_id" && value.fileId == "audio-source")
        case .unknown:
            Issue.record("Expected a known audio reference")
        }
        #expect(try encodeJSONValue(item) == raw)
    }
}
