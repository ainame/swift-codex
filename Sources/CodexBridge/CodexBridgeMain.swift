import ArgumentParser

@main
struct CodexBridgeMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "CodexBridge",
        abstract: "Starts an HTTP bridge for `codex app-server --listen stdio://`."
    )

    @Option(help: "Bind host.")
    var host = "127.0.0.1"

    @Option(help: "Bind port.")
    var port: UInt16 = 31337

    @Option(name: .customLong("codex"), help: "Path to codex executable.")
    var codexPath = "codex"

    func run() async throws {
        try await CodexBridgeServer(
            host: host,
            port: port,
            codexPath: codexPath
        ).run()
    }
}
