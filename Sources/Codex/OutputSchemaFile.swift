import Foundation

struct OutputSchemaFile: Sendable {
    var schemaPath: String?
    var cleanup: @Sendable () async -> Void
}

enum OutputSchemaFileFactory {
    static func make(schema: JSONObject?) async throws -> OutputSchemaFile {
        guard let schema else {
            return OutputSchemaFile(schemaPath: nil, cleanup: {})
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-output-schema-\(UUID().uuidString)", isDirectory: true)
        let schemaURL = directoryURL.appendingPathComponent("schema.json")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        do {
            let data = try JSONEncoder().encode(schema)
            try data.write(to: schemaURL)
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }

        return OutputSchemaFile(
            schemaPath: schemaURL.path(),
            cleanup: {
                try? FileManager.default.removeItem(at: directoryURL)
            }
        )
    }
}
