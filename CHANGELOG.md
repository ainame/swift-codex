# Changelog

All notable changes to this project should be documented in this file.

For upstream parity work, record both the Swift package version and the reviewed `openai/codex` basis. Keep detailed provenance in [`UPSTREAM.md`](UPSTREAM.md).

The format is based on Keep a Changelog and this project uses tags without a `v` prefix.

## [Unreleased]

### Added

- Synced the app-server schema to `rust-v0.135.0`, adding typed process notifications, image detail fields, plugin share metadata, MCP tool plugin IDs, and remote-control status metadata.
- Added friendly `Sandbox` presets for thread and turn APIs, matching the upstream Python SDK's `read_only`, `workspace_write`, and `full_access` presets.

### Changed

- Updated the vendored upstream checkout to `rust-v0.135.0` (`4daceea869704f9f35e0a3949fc34711ef978a4e`).
- Updated the schema generator and sync workflow to handle the upstream Python package rename from `codex_app_server` to `openai_codex`, and to repair empty submodule checkouts before falling back to external local checkouts.

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
