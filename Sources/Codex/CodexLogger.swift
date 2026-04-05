import Logging

enum CodexLogging {
    static let defaultLabel = "swift-codex"

    static func makeDefaultLogger(label: String = defaultLabel) -> Logger {
        Logger(label: label)
    }
}

extension Logger {
    func codexScope(_ scope: String, metadata: Logger.Metadata = [:]) -> Logger {
        var logger = self
        logger[metadataKey: "codex_scope"] = .string(scope)
        for (key, value) in metadata {
            logger[metadataKey: key] = value
        }
        return logger
    }
}
