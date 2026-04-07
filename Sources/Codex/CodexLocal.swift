#if os(macOS)
import CodexCore
import Logging

public extension CodexRPCClient {
    init(config: CodexConfig = .init(), logger: Logger) {
        self.init(
            config: config,
            logger: logger,
            transport: LocalCodexRPCTransport(config: config, logger: logger.codexScope("transport"))
        )
    }

    init(config: CodexConfig = .init()) {
        self.init(config: config, logger: Codex.defaultLogger())
    }
}

public extension Codex {
    init(config: CodexConfig = .init(), logger: Logger) async throws {
        try await self.init(
            config: config,
            logger: logger,
            transport: LocalCodexRPCTransport(config: config, logger: logger.codexScope("transport"))
        )
    }

    init(config: CodexConfig = .init()) async throws {
        try await self.init(config: config, logger: Self.defaultLogger())
    }
}
#endif
