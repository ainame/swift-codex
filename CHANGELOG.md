# Changelog

All notable changes to this project should be documented in this file.

For upstream parity work, record both the Swift package version and the reviewed `openai/codex` basis. Keep detailed provenance in [`UPSTREAM.md`](UPSTREAM.md).

The format is based on Keep a Changelog and this project uses tags without a `v` prefix.

## [Unreleased]

### Added

- Added a typed JSON-RPC v2 model layer generated into [`Sources/Codex/RPCModelsGenerated.swift`](Sources/Codex/RPCModelsGenerated.swift).
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

### Removed

- Removed the legacy `codex exec` transport and its event/item model family.
- Removed the `AppServerClient`, `AppServerCodex`, `AppServerThread`, `AppServerTurnHandle`, `AppServerNotification`, and `AppServerV2` public surfaces.
- Removed the transitional `AppServerV2ValueModel` / handwritten `JSONValue` accessor layer.

### Upstream Basis

- Swift package version: `0.0.1`
- Vendored upstream checkout: `vendor/openai-codex` at `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Reviewed upstream JSON-RPC basis: `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Notes: the Swift SDK now treats the vendored Python app-server client and v2 protocol schema as the runtime source of truth. The old `exec` transport is no longer part of the public SDK.
