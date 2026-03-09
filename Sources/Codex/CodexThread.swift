import Foundation

public actor CodexThread {
    private let exec: CodexExec
    private let codexOptions: CodexOptions
    private let threadOptions: ThreadOptions
    private var storedThreadID: String?

    public var id: String? {
        storedThreadID
    }

    init(exec: CodexExec, codexOptions: CodexOptions, threadOptions: ThreadOptions, threadID: String?) {
        self.exec = exec
        self.codexOptions = codexOptions
        self.threadOptions = threadOptions
        self.storedThreadID = threadID
    }

    public func run(_ input: String, options: TurnOptions = .init()) async throws -> RunResult {
        try await run(normalizedInput: .text(input), options: options)
    }

    public func run(_ input: [UserInput], options: TurnOptions = .init()) async throws -> RunResult {
        try await run(normalizedInput: .structured(input), options: options)
    }

    public func runStreamed(_ input: String, options: TurnOptions = .init()) -> AsyncThrowingStream<ThreadEvent, Error> {
        stream(for: .text(input), options: options)
    }

    public func runStreamed(_ input: [UserInput], options: TurnOptions = .init()) -> AsyncThrowingStream<ThreadEvent, Error> {
        stream(for: .structured(input), options: options)
    }

    private func run(normalizedInput: NormalizedInput, options: TurnOptions) async throws -> RunResult {
        let events = stream(for: normalizedInput, options: options)
        var items: [ThreadItem] = []
        var finalResponse = ""
        var usage: Usage?
        var turnFailure: ThreadError?

        for try await event in events {
            switch event {
            case .itemCompleted(let completed):
                if case .agentMessage(let item) = completed.item {
                    finalResponse = item.text
                }
                items.append(completed.item)
            case .turnCompleted(let completed):
                usage = completed.usage
            case .turnFailed(let failed):
                turnFailure = failed.error
            default:
                break
            }
        }

        if let turnFailure {
            throw CodexError.turnFailed(turnFailure.message)
        }

        return RunResult(items: items, finalResponse: finalResponse, usage: usage)
    }

    private func stream(for input: NormalizedInput, options: TurnOptions) -> AsyncThrowingStream<ThreadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let schemaFile = try await OutputSchemaFileFactory.make(schema: options.outputSchema)
                defer {
                    schemaFile.cleanup()
                }

                let args = self.makeExecArgs(input: input, outputSchemaPath: schemaFile.schemaPath)

                do {
                    try await exec.run(args: args) { line in
                        let event = try Self.decodeEvent(from: line)
                        if case .threadStarted(let started) = event {
                            await self.setThreadID(started.threadID)
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func makeExecArgs(input: NormalizedInput, outputSchemaPath: String?) -> CodexExecArgs {
        let normalized = normalizeInput(input)
        return CodexExecArgs(
            input: normalized.prompt,
            baseURL: codexOptions.baseURL,
            apiKey: codexOptions.apiKey,
            threadID: storedThreadID,
            images: normalized.images,
            model: threadOptions.model,
            sandboxMode: threadOptions.sandboxMode,
            workingDirectory: threadOptions.workingDirectory,
            additionalDirectories: threadOptions.additionalDirectories,
            skipGitRepoCheck: threadOptions.skipGitRepoCheck,
            outputSchemaFile: outputSchemaPath,
            modelReasoningEffort: threadOptions.modelReasoningEffort,
            networkAccessEnabled: threadOptions.networkAccessEnabled,
            webSearchMode: threadOptions.webSearchMode,
            webSearchEnabled: threadOptions.webSearchEnabled,
            approvalPolicy: threadOptions.approvalPolicy
        )
    }

    private nonisolated static func decodeEvent(from line: String) throws -> ThreadEvent {
        do {
            return try JSONDecoder().decode(ThreadEvent.self, from: Data(line.utf8))
        } catch {
            throw CodexError.invalidResponseLine(line)
        }
    }

    private func setThreadID(_ id: String) {
        storedThreadID = id
    }
}

private enum NormalizedInput: Sendable, Hashable {
    case text(String)
    case structured([UserInput])
}

private extension CodexThread {
    func normalizeInput(_ input: NormalizedInput) -> (prompt: String, images: [String]) {
        switch input {
        case .text(let prompt):
            return (prompt, [])
        case .structured(let items):
            var promptParts: [String] = []
            var images: [String] = []
            for item in items {
                switch item {
                case .text(let text):
                    promptParts.append(text)
                case .localImage(let path):
                    images.append(path)
                }
            }
            return (promptParts.joined(separator: "\n\n"), images)
        }
    }
}
