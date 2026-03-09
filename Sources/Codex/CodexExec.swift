import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

struct CodexExecArgs: Sendable, Hashable {
    var input: String
    var baseURL: String?
    var apiKey: String?
    var threadID: String?
    var images: [String]
    var model: String?
    var sandboxMode: SandboxMode?
    var workingDirectory: String?
    var additionalDirectories: [String]
    var skipGitRepoCheck: Bool
    var outputSchemaFile: String?
    var modelReasoningEffort: ModelReasoningEffort?
    var networkAccessEnabled: Bool?
    var webSearchMode: WebSearchMode?
    var webSearchEnabled: Bool?
    var approvalPolicy: ApprovalMode?
}

struct CodexExec: Sendable {
    private static let internalOriginatorEnvironmentKey = "CODEX_INTERNAL_ORIGINATOR_OVERRIDE"
    private static let swiftSDKOriginator = "codex_sdk_swift"

    var executablePathOverride: String?
    var environmentOverride: [String: String]?
    var configOverrides: JSONObject?

    func run(args: CodexExecArgs, onLine: @escaping @Sendable (String) async throws -> Void) async throws {
        try Task.checkCancellation()

        let environment = buildEnvironment(baseURL: args.baseURL, apiKey: args.apiKey)
        let executable = try resolveExecutable(in: environment)
        let configuration = Configuration(
            executable: executable,
            arguments: Arguments(try commandArguments(for: args)),
            environment: .custom(subprocessEnvironment(from: environment)),
            workingDirectory: args.workingDirectory.map { FilePath($0) }
        )

        let executionResult = try await Subprocess.run(configuration) { _, standardInput, standardOutput, standardError in
            async let stderr = collect(sequence: standardError)
            async let stdout: Void = {
                for try await line in standardOutput.lines() {
                    try Task.checkCancellation()
                    try await onLine(line)
                }
            }()

            do {
                _ = try await standardInput.write(Data(args.input.utf8))
                try await standardInput.finish()
                try await stdout
                return try await stderr
            } catch {
                _ = try? await stderr
                throw error
            }
        }

        if !executionResult.terminationStatus.isSuccess {
            throw CodexError.fromTerminationStatus(executionResult.terminationStatus, stderr: executionResult.value)
        }
    }

    private func commandArguments(for args: CodexExecArgs) throws -> [String] {
        var commandArgs = ["exec", "--experimental-json"]

        if let configOverrides {
            for override in try CodexConfigSerializer.serialize(configOverrides) {
                commandArgs.append(contentsOf: ["--config", override])
            }
        }

        if let model = args.model {
            commandArgs.append(contentsOf: ["--model", model])
        }

        if let sandboxMode = args.sandboxMode {
            commandArgs.append(contentsOf: ["--sandbox", sandboxMode.rawValue])
        }

        if let workingDirectory = args.workingDirectory {
            commandArgs.append(contentsOf: ["--cd", workingDirectory])
        }

        for directory in args.additionalDirectories {
            commandArgs.append(contentsOf: ["--add-dir", directory])
        }

        if args.skipGitRepoCheck {
            commandArgs.append("--skip-git-repo-check")
        }

        if let outputSchemaFile = args.outputSchemaFile {
            commandArgs.append(contentsOf: ["--output-schema", outputSchemaFile])
        }

        if let effort = args.modelReasoningEffort {
            commandArgs.append(contentsOf: ["--config", #"model_reasoning_effort="\#(effort.rawValue)""#])
        }

        if let networkAccessEnabled = args.networkAccessEnabled {
            commandArgs.append(contentsOf: ["--config", "sandbox_workspace_write.network_access=\(networkAccessEnabled ? "true" : "false")"])
        }

        if let webSearchMode = args.webSearchMode {
            commandArgs.append(contentsOf: ["--config", #"web_search="\#(webSearchMode.rawValue)""#])
        } else if let webSearchEnabled = args.webSearchEnabled {
            commandArgs.append(contentsOf: ["--config", #"web_search="\#(webSearchEnabled ? "live" : "disabled")""#])
        }

        if let approvalPolicy = args.approvalPolicy {
            commandArgs.append(contentsOf: ["--config", #"approval_policy="\#(approvalPolicy.rawValue)""#])
        }

        if let threadID = args.threadID {
            commandArgs.append(contentsOf: ["resume", threadID])
        }

        for image in args.images {
            commandArgs.append(contentsOf: ["--image", image])
        }

        return commandArgs
    }

    private func buildEnvironment(baseURL: String?, apiKey: String?) -> [String: String] {
        var environment = environmentOverride ?? ProcessInfo.processInfo.environment
        if environment[Self.internalOriginatorEnvironmentKey] == nil {
            environment[Self.internalOriginatorEnvironmentKey] = Self.swiftSDKOriginator
        }
        if let baseURL {
            environment["OPENAI_BASE_URL"] = baseURL
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

    private func subprocessEnvironment(from environment: [String: String]) -> [Environment.Key: String] {
        Dictionary(
            uniqueKeysWithValues: environment.compactMap { key, value in
                Environment.Key(rawValue: key).map { ($0, value) }
            }
        )
    }

    private func collect(sequence: AsyncBufferSequence) async throws -> String {
        var chunks: [String] = []
        for try await line in sequence.lines() {
            chunks.append(line)
        }
        return chunks.joined(separator: "\n")
    }
}
