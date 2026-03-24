# Changelog

All notable changes to this project should be documented in this file.

For upstream parity work, record both the Swift package version and the `openai/codex` `sdk/typescript` basis that the release or unreleased work reflects. Keep detailed provenance in [`UPSTREAM.md`](UPSTREAM.md) and summarize user-visible results here.

The format is based on Keep a Changelog and this project uses tags without a `v` prefix.

## [Unreleased]

### Added

- Added [`UPSTREAM.md`](UPSTREAM.md) to record the exact upstream `openai/codex` commit used for sync work.
- Added explicit upstream sync instructions to [`AGENTS.md`](AGENTS.md).
- Added the upstream `openai/codex` repository as a git submodule at [`vendor/openai-codex`](vendor/openai-codex).
- Added `Scripts/generate_app_server_v2.py` plus checked-in generated `AppServerV2` wrappers and notification registry output for the experimental app-server protocol.
- Added a public low-level `AppServerClient` alongside the high-level `AppServerCodex`, `AppServerThread`, and `AppServerTurnHandle` app-server APIs.
- Added experimental app-server support for thread list/read/fork/archive/unarchive/name/compact, turn steer/run, model list, rich app-server input items, retry helpers, and full typed notification streaming.
- Added app-server transport tests covering initialize, thread and model RPC helpers, default approval behavior, turn steer/interrupt, typed notifications, stderr-tail diagnostics, and turn-consumer exclusivity.

### Changed

- Updated the vendored [`openai/codex`](vendor/openai-codex) submodule to `527244910fb851cea6147334dbc08f8fbce4cb9d`.
- Passed `baseURL` via `--config openai_base_url=...` instead of `OPENAI_BASE_URL` to match the current TypeScript SDK behavior when callers provide a custom environment override.
- Documented that the installation snippet uses version `0.0.1` in [`README.md`](README.md).
- Documented that upstream reference tracking should use an exact `openai/codex` commit instead of the moving `main` branch.
- Kept the existing `Codex` / `CodexThread` exec transport unchanged while expanding the experimental app-server API toward Python `codex_app_server` parity.
- Set a low-latency `swift-subprocess` preferred buffer size for the app-server stdio transport so JSON-RPC responses surface promptly on Darwin.
- Switched the experimental app-server default server-request behavior to match Python: approval requests accept by default and unknown request methods return `{}`.
- Reworked the app-server stream surface so `AppServerTurnHandle.stream()` yields `AppServerNotification`, `AppServerTurnHandle.run()` returns `AppServerV2.Turn`, and `AppServerThread.run()` returns `AppServerRunResult`.
- Promoted transport-closure stderr tail output into a first-class public app-server error when available.

### Upstream Basis

- Swift package version: `0.0.1`
- Vendored upstream checkout: `vendor/openai-codex` at `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Upstream TypeScript SDK basis: `3293538e128e02ca24d5e9913af986ac68405b00`
- Upstream Python app-server basis: `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Notes: latest reviewed stable SDK behavior includes the `openai_base_url` config override parity update. The experimental JSON-RPC app-server API now tracks the upstream Python `codex_app_server` facade and current v2 protocol at the vendored commit above.
