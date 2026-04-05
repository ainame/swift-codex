import Foundation
import Logging
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

struct CodexRPCExec: Sendable {
    private static let internalOriginatorEnvironmentKey = "CODEX_INTERNAL_ORIGINATOR_OVERRIDE"
    private static let swiftSDKOriginator = "codex_sdk_swift"
    private static let appServerPreferredBufferSize = 1

    var executablePathOverride: String?
    var launchArgsOverride: [String]?
    var environmentOverride: [String: String]?
    var configOverrides: JSONObject?
    var baseURL: String?
    var apiKey: String?
    var workingDirectory: String?
    var logger: Logger

    func runRPCServer(
        outgoingMessages: AsyncStream<String>,
        onStdoutLine: @escaping @Sendable (String) async -> Void,
        onStderrLine: @escaping @Sendable (String) async -> Void
    ) async throws {
        logger.info(
            "Launching Codex app-server process",
            metadata: [
                "launch_mode": .string(launchMode),
                "working_directory": workingDirectory.map(Logger.MetadataValue.string),
            ].compactMapValues { $0 }
        )
        let environment = buildEnvironment()
        let command = try resolveCommand(in: environment)
        logger.debug(
            "Resolved Codex app-server command",
            metadata: [
                "launch_mode": .string(launchMode),
                "argument_count": .string(String(command.arguments.count)),
            ]
        )
        let configuration = Configuration(
            executable: command.executable,
            arguments: Arguments(command.arguments),
            environment: .custom(subprocessEnvironment(from: environment)),
            workingDirectory: workingDirectory.map { FilePath($0) }
        )


        let result = try await Subprocess.run(
            configuration,
            preferredBufferSize: Self.appServerPreferredBufferSize
        ) { _, standardInput, standardOutput, standardError in
            enum ProcessState: Sendable {
                case writerFinished
                case stdoutFinished
                case stderrCaptured(String)
            }

            return try await withThrowingTaskGroup(of: ProcessState.self) { group in
                group.addTask {
                    for await message in outgoingMessages {
                        try Task.checkCancellation()
                        _ = try await standardInput.write(message + "\n", using: UTF8.self)
                    }
                    try await standardInput.finish()
                    return .writerFinished
                }

                group.addTask {
                    try await streamLines(from: standardOutput, onLine: onStdoutLine)
                    return .stdoutFinished
                }

                group.addTask {
                    let stderrLines = try await collectAndForwardLines(from: standardError, onLine: onStderrLine)
                    return .stderrCaptured(stderrLines.joined(separator: "\n"))
                }

                var stderr = ""
                while let state = try await group.next() {
                    switch state {
                    case .writerFinished:
                        break
                    case .stderrCaptured(let captured):
                        stderr = captured
                    case .stdoutFinished:
                        group.cancelAll()
                        return stderr
                    }
                }

                return stderr
            }
        }

        if !result.terminationStatus.isSuccess {
            if Task.isCancelled {
                throw CancellationError()
            }
            logger.error(
                "Codex app-server terminated unsuccessfully",
                metadata: ["termination_status": .string(String(describing: result.terminationStatus))]
            )
            throw CodexError.fromTerminationStatus(result.terminationStatus, stderr: result.value)
        }
    }

    private var launchMode: String {
        if launchArgsOverride != nil {
            return "launch_args_override"
        }
        if executablePathOverride != nil {
            return "executable_path_override"
        }
        return "path_lookup"
    }

    private func commandArguments() throws -> [String] {
        var commandArgs = ["app-server", "--listen", "stdio://"]

        if let configOverrides {
            for override in try CodexConfigSerializer.serialize(configOverrides) {
                commandArgs.append(contentsOf: ["--config", override])
            }
        }

        if let baseURL = baseURL {
            let override = try CodexConfigSerializer.serialize(["openai_base_url": .string(baseURL)])
            if let baseURLOverride = override.first {
                commandArgs.append(contentsOf: ["--config", baseURLOverride])
            }
        }

        return commandArgs
    }

    private func resolveCommand(in environment: [String: String]) throws -> (executable: Executable, arguments: [String]) {
        if let launchArgsOverride {
            guard let executableName = launchArgsOverride.first, !executableName.isEmpty else {
                throw CodexError.invalidConfig("launchArgsOverride must include an executable path or name")
            }
            return (
                executable: try resolveExecutable(named: executableName, in: environment),
                arguments: Array(launchArgsOverride.dropFirst())
            )
        }

        return (
            executable: try resolveExecutable(in: environment),
            arguments: try commandArguments()
        )
    }

    private func buildEnvironment() -> [String: String] {
        var environment = environmentOverride ?? ProcessInfo.processInfo.environment
        if environment[Self.internalOriginatorEnvironmentKey] == nil {
            environment[Self.internalOriginatorEnvironmentKey] = Self.swiftSDKOriginator
        }
        if let apiKey {
            environment["CODEX_API_KEY"] = apiKey
        }
        return environment
    }

    private func resolveExecutable(in environment: [String: String]) throws -> Executable {
        if let executablePathOverride {
            return .path(FilePath(executablePathOverride))
        }

        let executable = Executable.name("codex")
        do {
            _ = try executable.resolveExecutablePath(in: .custom(subprocessEnvironment(from: environment)))
            return executable
        } catch {
            throw CodexError.executableNotFound("codex")
        }
    }

    private func resolveExecutable(named rawValue: String, in environment: [String: String]) throws -> Executable {
        let executable: Executable
        if rawValue.contains("/") {
            executable = .path(FilePath(rawValue))
        } else {
            executable = .name(rawValue)
        }
        do {
            _ = try executable.resolveExecutablePath(in: .custom(subprocessEnvironment(from: environment)))
            return executable
        } catch {
            throw CodexError.executableNotFound(rawValue)
        }
    }

    private func subprocessEnvironment(from environment: [String: String]) -> [Environment.Key: String] {
        Dictionary(
            uniqueKeysWithValues: environment.compactMap { key, value in
                Environment.Key(rawValue: key).map { ($0, value) }
            }
        )
    }

    private func streamLines(
        from sequence: AsyncBufferSequence,
        onLine: @escaping @Sendable (String) async -> Void
    ) async throws {
        _ = try await collectAndForwardLines(from: sequence, onLine: onLine)
    }

    private func collectAndForwardLines(
        from sequence: AsyncBufferSequence,
        onLine: @escaping @Sendable (String) async -> Void
    ) async throws -> [String] {
        var pending = Data()
        var collected: [String] = []

        for try await chunk in sequence {
            let data = chunk.withUnsafeBytes { Data($0) }
            pending.append(data)

            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = pending[..<newlineIndex]
                let line = String(decoding: lineData, as: UTF8.self)
                collected.append(line)
                await onLine(line)

                let nextIndex = pending.index(after: newlineIndex)
                pending.removeSubrange(..<nextIndex)
            }
        }

        if !pending.isEmpty {
            let line = String(decoding: pending, as: UTF8.self)
            collected.append(line)
            await onLine(line)
        }

        return collected
    }
}
