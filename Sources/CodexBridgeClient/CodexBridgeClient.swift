@_exported import CodexCore
import Foundation
import Logging

public extension CodexRPCClient {
    init(bridgeURL: URL, config: CodexConfig = .init(), logger: Logger) {
        self.init(
            config: config,
            logger: logger,
            transport: CodexBridgeHTTPTransport(bridgeURL: bridgeURL, config: config)
        )
    }

    init(bridgeURL: URL, config: CodexConfig = .init()) {
        self.init(bridgeURL: bridgeURL, config: config, logger: Codex.defaultLogger())
    }
}

public extension Codex {
    init(bridgeURL: URL, config: CodexConfig = .init(), logger: Logger) async throws {
        try await self.init(
            config: config,
            logger: logger,
            transport: CodexBridgeHTTPTransport(bridgeURL: bridgeURL, config: config)
        )
    }

    init(bridgeURL: URL, config: CodexConfig = .init()) async throws {
        try await self.init(bridgeURL: bridgeURL, config: config, logger: Self.defaultLogger())
    }
}
