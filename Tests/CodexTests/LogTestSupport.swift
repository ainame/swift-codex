import Foundation
import Logging

final class TestLogRecorder: @unchecked Sendable {
    struct Entry: Sendable {
        var label: String
        var level: Logger.Level
        var message: String
        var metadata: [String: String]
    }

    private let lock = NSLock()
    private var storedEntries: [Entry] = []

    func record(_ entry: Entry) {
        lock.lock()
        storedEntries.append(entry)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        storedEntries.removeAll()
        lock.unlock()
    }

    func entries() -> [Entry] {
        lock.lock()
        let entries = storedEntries
        lock.unlock()
        return entries
    }
}

struct TestLogHandler: LogHandler {
    let label: String
    let recorder: TestLogRecorder
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: Logging.LogEvent) {
        var mergedMetadata = metadata
        if let explicitMetadata = event.metadata {
            for (key, value) in explicitMetadata {
                mergedMetadata[key] = value
            }
        }
        recorder.record(
            .init(
                label: label,
                level: event.level,
                message: event.message.description,
                metadata: mergedMetadata.mapValues(\.description)
            )
        )
    }
}

enum TestLogging {
    static let recorder = TestLogRecorder()
    private static let bootstrap = LoggingBootstrap()

    static func install() {
        bootstrap.bootstrapIfNeeded(recorder: recorder)
        recorder.reset()
    }
}

private final class LoggingBootstrap: @unchecked Sendable {
    private let lock = NSLock()
    private var installed = false

    func bootstrapIfNeeded(recorder: TestLogRecorder) {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else {
            return
        }
        LoggingSystem.bootstrap { label in
            TestLogHandler(label: label, recorder: recorder)
        }
        installed = true
    }
}
