# Changelog

All notable changes to this project should be documented in this file.

For upstream parity work, record both the Swift package version and the reviewed `openai/codex` basis. Keep detailed provenance in [`UPSTREAM.md`](UPSTREAM.md).

The format is based on Keep a Changelog and this project uses tags without a `v` prefix.

## [Unreleased]

## [0.144.1] - 2026-07-11

### Changed

- Synced focused app-server schema additions through `rust-v0.144.1`, including plugin app icon assets, npm plugin source records, plugin install policy source metadata, MCP startup failure reasons, MCP app context fields, auth-header mode, session-budget errors, and account rate-limit reset-credit details. [#18](https://github.com/ainame/swift-codex/pull/18)
- Updated the vendored upstream checkout to `rust-v0.144.1` (`44918ea10c0f99151c6710411b4322c2f5c96bea`) and refreshed generated v2 models, upstream metadata, README status notes, and generated-model coverage. [#18](https://github.com/ainame/swift-codex/pull/18)
- Updated the vendored upstream checkout to `rust-v0.142.5` (`26de83050b20f7e0ee211b9739e52ae00ce8032a`) as an intermediate metadata-only sync before the `rust-v0.144.1` release. [#17](https://github.com/ainame/swift-codex/pull/17)

## [0.142.3] - 2026-07-01

### Added

- Synced focused app-server schema additions through `rust-v0.142.3`, including workspace message records, external-agent import histories, thread recency metadata, MCP tool-call app context, and plugin dark-logo metadata. [#16](https://github.com/ainame/swift-codex/pull/16)
- Added low-level `CodexRPCClient.accountWorkspaceMessagesRead()` and `CodexRPCClient.externalAgentConfigImportHistoriesRead()` helpers for the newly wrapped app-server RPCs. [#16](https://github.com/ainame/swift-codex/pull/16)

### Changed

- Updated the vendored upstream checkout to `rust-v0.142.3` (`e2b60462a7321517895dd94920661599303a7539`) and refreshed generated v2 models, upstream metadata, and README status notes. [#16](https://github.com/ainame/swift-codex/pull/16)

## [0.141.0] - 2026-06-20

### Added

- Synced focused app-server schema additions through `rust-v0.141.0`, including account token-usage and rate-limit reset-credit records, plugin detail models, thread settings, sleep items, and subagent activity items. [#15](https://github.com/ainame/swift-codex/pull/15)
- Added low-level thread deletion and persisted-goal helpers, with matching `Codex` and `CodexThread` convenience APIs. [#15](https://github.com/ainame/swift-codex/pull/15)
- Added low-level `CodexRPCClient.accountTokenUsageRead()` for the wrapped `account/tokenUsage/read` app-server RPC. [#15](https://github.com/ainame/swift-codex/pull/15)
- Updated the model generator's root set so low-level RPC response models remain reproducible across schema refreshes. [#15](https://github.com/ainame/swift-codex/pull/15)

### Changed

- Updated the vendored upstream checkout to `rust-v0.141.0` (`3fb81667d30d9d24297216ea61fbfcc4351b2aa9`) and refreshed upstream metadata plus README status notes. [#15](https://github.com/ainame/swift-codex/pull/15)
- Constrained `swift-subprocess` to the compatible `0.4.x` line so the independent Examples package does not resolve the incompatible `0.5.0` manifest. [#15](https://github.com/ainame/swift-codex/pull/15)

## [0.137.0] - 2026-06-07

### Added

- Synced focused app-server schema additions from `rust-v0.137.0`, including `Thread.parentThreadId`, paginated turn response models, and account rate-limit spend-control metadata. [#14](https://github.com/ainame/swift-codex/pull/14)
- Added low-level `CodexRPCClient.accountRateLimitsRead()` and `CodexRPCClient.skillsExtraRootsSet(_:)` helpers for the newly wrapped app-server RPCs. [#14](https://github.com/ainame/swift-codex/pull/14)

### Changed

- Updated the vendored upstream checkout to `rust-v0.137.0` (`f221438b691b8f749d98f22077c93ebe01923fbe`) and refreshed upstream metadata plus README version references. [#14](https://github.com/ainame/swift-codex/pull/14)
- Tightened the upstream sync skill so sync runs that produce changes must commit, push, and open a PR before finishing when credentials and network allow it. [#14](https://github.com/ainame/swift-codex/pull/14)

## [0.135.0] - 2026-05-30

### Added

- Synced the app-server schema to `rust-v0.135.0`, adding typed process notifications, image detail fields, plugin share metadata, MCP tool plugin IDs, and remote-control status metadata. [#13](https://github.com/ainame/swift-codex/pull/13)
- Added friendly `Sandbox` presets for thread and turn APIs, matching the upstream Python SDK's `read_only`, `workspace_write`, and `full_access` presets. [#13](https://github.com/ainame/swift-codex/pull/13)

### Changed

- Updated the vendored upstream checkout to `rust-v0.135.0` (`4daceea869704f9f35e0a3949fc34711ef978a4e`). [#13](https://github.com/ainame/swift-codex/pull/13)
- Updated the schema generator and sync workflow to handle the upstream Python package rename from `codex_app_server` to `openai_codex`, and to repair empty submodule checkouts before falling back to external local checkouts. [#13](https://github.com/ainame/swift-codex/pull/13)
- Updated the Swift toolchain pin to `6.3.2`. [#13](https://github.com/ainame/swift-codex/pull/13)

## [0.130.0] - 2026-05-09

Starting with `0.130.0`, `swift-codex` release versions follow the shipped upstream `openai/codex` SDK release number when an upstream sync is released.

### Added

- Added `swift-log` logger injection and structured lifecycle logging across the RPC client, transport, exec, thread, and turn layers. [#5](https://github.com/ainame/swift-codex/pull/5)

### Changed

- Synced the app-server schema to `rust-v0.121.0`, adding typed instruction sources, fork metadata, guardian auto-review payloads, and path-typed `cwd` fields. [#8](https://github.com/ainame/swift-codex/pull/8)
- Synced the app-server schema to `rust-v0.124.0`, adding `ThreadOptions.sessionStartSource`, `ThreadListOptions.sortDirection`, permission-profile payloads, and broader notification-registry coverage. [#10](https://github.com/ainame/swift-codex/pull/10)
- Synced the app-server schema to `rust-v0.130.0`, adding multi-path `thread.list` cwd filters, `useStateDBOnly`, plugin share metadata, thread goal and model-verification notifications, and a `.swift-version` pin for Swift `6.3.1`. [#11](https://github.com/ainame/swift-codex/pull/11)

## [0.0.3] - 2026-03-29

### Added

- Added `CodexRPCClient.pluginList()` / `Codex.plugins()` with typed plugin marketplace models generated from the vendored app-server schema.
- Added `CodexConfig.launchArgsOverride` and `CodexConfig.workingDirectory` to mirror Python app-server launch configuration controls.
- Added regression coverage for plugin-list decoding and transport launch override behavior.

### Changed

- Updated `vendor/openai-codex` to `rust-v0.117.0` (`4c70bff480af37b1bf1a9b352b8341060fe55755`).
- Regenerated app-server v2 models against the updated release schema, including `HookEventName.postToolUse` and plugin marketplace support.
- Moved the `codex-sdk-upstream-sync` skill into this repository and updated it to target Python app-server parity instead of the older TypeScript SDK basis.

## [0.0.2] - 2026-03-29

### Added

- Added a typed JSON-RPC v2 model layer generated into [`Sources/Codex/RPCModels/Generated`](Sources/Codex/RPCModels/Generated).
- Added generated model support for `rawJSON`, `additionalFields`, and union `.unknown(JSONValue)` fallback in [`Sources/Codex/GeneratedModelSupport.swift`](Sources/Codex/GeneratedModelSupport.swift).
- Added `CodexRPCClient` as the low-level JSON-RPC client.
- Added RPC-focused regression tests for typed model round-tripping, unknown union fallback, notification metadata fallback, retry behavior, initialize normalization, approval handling, and thread/turn lifecycle operations.
- Added an updated executable example for startup, approvals, thread list/read, and streamed notifications.

### Changed

- Replaced the old dual-surface SDK with a single JSON-RPC v2 transport based on `codex app-server --listen stdio://`.
- Promoted the RPC-backed API to the primary public surface: `Codex`, `CodexThread`, `CodexTurnHandle`, `CodexConfig`, `ThreadOptions`, `ThreadListOptions`, `TurnOptions`, `RunResult`, `CodexNotification`, and `CodexNotificationPayload`.
- Replaced JSONValue-wrapper protocol models with stored-property generated types such as `Thread`, `Turn`, `ThreadItem`, `ModelListResponse`, `ThreadListResponse`, and `ThreadReadResponse`.
- Aligned response shapes with the vendored schema, including `ThreadListResponse.data`, `ModelListResponse.data`, integer token counts, typed `MessagePhase`, and empty typed interrupt/archive/name/compact responses.
- Switched final-response extraction and notification metadata handling to the typed model layer.
- Updated README, UPSTREAM notes, tests, and examples to document the RPC-only API.
- Split generated RPC v2 models into one file per type under [`Sources/Codex/RPCModels/Generated`](Sources/Codex/RPCModels/Generated) so editors no longer need to open a single 17k+ line file.

### Removed

- Removed the legacy `codex exec` transport and its event/item model family.
- Removed the `AppServerClient`, `AppServerCodex`, `AppServerThread`, `AppServerTurnHandle`, `AppServerNotification`, and `AppServerV2` public surfaces.
- Removed the transitional `AppServerV2ValueModel` / handwritten `JSONValue` accessor layer.

### Upstream Basis

- Swift package version: `0.0.1`
- Vendored upstream checkout: `vendor/openai-codex` at `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Reviewed upstream JSON-RPC basis: `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Notes: the Swift SDK now treats the vendored Python app-server client and v2 protocol schema as the runtime source of truth. The old `exec` transport is no longer part of the public SDK.
