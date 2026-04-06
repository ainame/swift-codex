import Foundation
import Dispatch
import Network
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

@main
struct CodexBridgeMain {
    static func main() {
        do {
            let options = try BridgeOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            try BridgeServer(options: options).run()
        } catch {
            fputs("CodexBridge: \(error)\n", stderr)
            exit(1)
        }
    }
}

private struct BridgeOptions: Sendable {
    var host: String = "127.0.0.1"
    var port: UInt16 = 31337
    var codexPath: String = "codex"

    static func parse(arguments: [String]) throws -> BridgeOptions {
        var options = BridgeOptions()
        var index = arguments.startIndex

        func requireValue(for flag: String) throws -> String {
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw BridgeError.missingValue(flag)
            }
            index = valueIndex
            return arguments[valueIndex]
        }

        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help":
                print(Self.helpMessage)
                exit(0)
            case "--host":
                options.host = try requireValue(for: argument)
            case "--port":
                let value = try requireValue(for: argument)
                guard let port = UInt16(value) else {
                    throw BridgeError.invalidPort(value)
                }
                options.port = port
            case "--codex":
                options.codexPath = try requireValue(for: argument)
            default:
                throw BridgeError.unknownArgument(argument)
            }
            index = arguments.index(after: index)
        }

        return options
    }

    private static let helpMessage = """
    Usage: CodexBridge [--host HOST] [--port PORT] [--codex PATH]

    Starts a TCP bridge that launches `codex app-server --listen stdio://`
    per connection and forwards newline-delimited JSON-RPC over the socket.
    """
}

private enum BridgeError: LocalizedError {
    case missingValue(String)
    case invalidPort(String)
    case unknownArgument(String)
    case codexNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "missing value for \(flag)"
        case .invalidPort(let value):
            return "invalid port: \(value)"
        case .unknownArgument(let argument):
            return "unknown argument: \(argument)"
        case .codexNotFound(let path):
            return "could not find codex executable: \(path)"
        }
    }
}

private final class BridgeServer {
    private let options: BridgeOptions
    private let queue = DispatchQueue(label: "com.ainame.swift-codex.codex-bridge")
    private var listener: NWListener?

    init(options: BridgeOptions) {
        self.options = options
    }

    func run() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(options.host),
            port: NWEndpoint.Port(rawValue: options.port)!
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let host = options.host
        let port = options.port
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                fputs("CodexBridge listening on \(host):\(port)\n", stderr)
            case .failed(let error):
                fputs("CodexBridge listener failed: \(error)\n", stderr)
                exit(1)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [options] connection in
            Task {
                do {
                    try await Self.handle(connection: connection, options: options)
                } catch {
                    fputs("CodexBridge connection error: \(error)\n", stderr)
                    connection.cancel()
                }
            }
        }
        listener.start(queue: queue)
        dispatchMain()
    }

    private static func handle(connection: NWConnection, options: BridgeOptions) async throws {
        let reader = SocketLineReader(connection: connection)
        let writer = SocketWriter(connection: connection)
        try await runCodexBridge(
            reader: reader,
            writer: writer,
            options: options,
            connection: connection
        )
    }

    private static func runCodexBridge(
        reader: SocketLineReader,
        writer: SocketWriter,
        options: BridgeOptions,
        connection: NWConnection
    ) async throws {
        let executable = try resolveExecutable(path: options.codexPath)
        let configuration = Configuration(
            executable: executable,
            arguments: Arguments(["app-server", "--listen", "stdio://"]),
            environment: .inherit,
            workingDirectory: nil
        )

        _ = try await Subprocess.run(configuration, preferredBufferSize: 1) { _, standardInput, standardOutput, standardError in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    while let line = try await reader.nextLine() {
                        _ = try await standardInput.write(line + "\n", using: UTF8.self)
                    }
                    try await standardInput.finish()
                }

                group.addTask {
                    try await forwardStdout(from: standardOutput, to: writer)
                }

                group.addTask {
                    try await drainStderr(from: standardError)
                }

                try await group.waitForAll()
            }
        }

        await writer.close()
        connection.cancel()
    }

    private static func forwardStdout(
        from standardOutput: AsyncBufferSequence,
        to writer: SocketWriter
    ) async throws {
        var pending = Data()

        for try await chunk in standardOutput {
            let data = chunk.withUnsafeBytes { Data($0) }
            pending.append(data)

            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = pending[..<newlineIndex]
                let line = String(decoding: lineData, as: UTF8.self)
                try await writer.sendLine(line)
                let nextIndex = pending.index(after: newlineIndex)
                pending.removeSubrange(..<nextIndex)
            }
        }

        if !pending.isEmpty {
            let line = String(decoding: pending, as: UTF8.self)
            try await writer.sendLine(line)
        }
    }

    private static func drainStderr(from standardError: AsyncBufferSequence) async throws {
        var pending = Data()

        for try await chunk in standardError {
            let data = chunk.withUnsafeBytes { Data($0) }
            pending.append(data)

            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = pending[..<newlineIndex]
                let line = String(decoding: lineData, as: UTF8.self)
                fputs("[codex] \(line)\n", stderr)
                let nextIndex = pending.index(after: newlineIndex)
                pending.removeSubrange(..<nextIndex)
            }
        }

        if !pending.isEmpty {
            let line = String(decoding: pending, as: UTF8.self)
            fputs("[codex] \(line)\n", stderr)
        }
    }

    private static func resolveExecutable(path: String) throws -> Executable {
        let executable = path.contains("/") ? Executable.path(FilePath(path)) : Executable.name(path)
        do {
            _ = try executable.resolveExecutablePath(in: .inherit)
            return executable
        } catch {
            throw BridgeError.codexNotFound(path)
        }
    }
}

private actor SocketLineReader {
    private let connection: NWConnection
    private var buffer = Data()
    private var pendingLines: [String] = []
    private var waiting: [CheckedContinuation<String?, Error>] = []
    private var started = false
    private var finished = false
    private var receiveQueue = DispatchQueue(label: "com.ainame.swift-codex.codex-bridge.receive")

    init(connection: NWConnection) {
        self.connection = connection
    }

    func nextLine() async throws -> String? {
        startIfNeeded()

        if !pendingLines.isEmpty {
            return pendingLines.removeFirst()
        }

        if finished {
            return nil
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append(continuation)
            }
        } onCancel: {
            Task {
                await self.cancelPendingRead()
            }
        }
    }

    private func startIfNeeded() {
        guard !started else {
            return
        }
        started = true
        connection.start(queue: receiveQueue)
        receiveNext()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }
            Task {
                await self.handleReceive(data: data, isComplete: isComplete, error: error)
            }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            finish(error: error)
            return
        }

        if let data, !data.isEmpty {
            buffer.append(data)
            drainBuffer()
        }

        if isComplete {
            finishEOF()
        } else {
            receiveNext()
        }
    }

    private func drainBuffer() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            let line = String(decoding: lineData, as: UTF8.self)
            enqueue(line)
            let nextIndex = buffer.index(after: newlineIndex)
            buffer.removeSubrange(..<nextIndex)
        }
    }

    private func enqueue(_ line: String) {
        if let waiter = waiting.first {
            waiting.removeFirst()
            waiter.resume(returning: line)
        } else {
            pendingLines.append(line)
        }
    }

    private func finishEOF() {
        guard !finished else { return }
        if !buffer.isEmpty {
            let line = String(decoding: buffer, as: UTF8.self)
            enqueue(line)
            buffer.removeAll(keepingCapacity: true)
        }
        finished = true
        drainWaiters(with: nil)
    }

    private func finish(error: Error) {
        guard !finished else { return }
        finished = true
        connection.cancel()
        drainWaiters(throwing: error)
    }

    private func cancelPendingRead() {
        finish(error: CancellationError())
    }

    private func drainWaiters(with value: String?) {
        while let waiter = waiting.first {
            waiting.removeFirst()
            waiter.resume(returning: value)
        }
    }

    private func drainWaiters(throwing error: Error) {
        while let waiter = waiting.first {
            waiting.removeFirst()
            waiter.resume(throwing: error)
        }
    }
}

private actor SocketWriter {
    private let connection: NWConnection
    private var isClosed = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func sendLine(_ line: String) async throws {
        guard !isClosed else {
            return
        }
        let payload = Data((line + "\n").utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
    }
}
