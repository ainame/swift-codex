public struct RunResult: Sendable, Hashable {
    public var items: [ThreadItem]
    public var finalResponse: String
    public var usage: Usage?

    public init(items: [ThreadItem], finalResponse: String, usage: Usage?) {
        self.items = items
        self.finalResponse = finalResponse
        self.usage = usage
    }
}

public enum UserInput: Sendable, Hashable {
    case text(String)
    case localImage(path: String)
}

public struct Codex: Sendable {
    private let exec: CodexExec
    private let options: CodexOptions

    public init(options: CodexOptions = .init()) {
        self.options = options
        self.exec = CodexExec(
            executablePathOverride: options.codexPathOverride,
            environmentOverride: options.environment,
            configOverrides: options.config
        )
    }

    public func startThread(options: ThreadOptions = .init()) -> CodexThread {
        CodexThread(exec: exec, codexOptions: self.options, threadOptions: options, threadID: nil)
    }

    public func resumeThread(id: String, options: ThreadOptions = .init()) -> CodexThread {
        CodexThread(exec: exec, codexOptions: self.options, threadOptions: options, threadID: id)
    }
}
