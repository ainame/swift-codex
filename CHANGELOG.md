# Changelog

All notable changes to this project should be documented in this file.

For upstream parity work, record both the Swift package version and the `openai/codex` `sdk/typescript` basis that the release or unreleased work reflects. Keep detailed provenance in [`UPSTREAM.md`](UPSTREAM.md) and summarize user-visible results here.

The format is based on Keep a Changelog and this project uses tags without a `v` prefix.

## [Unreleased]

### Added

- Added [`UPSTREAM.md`](UPSTREAM.md) to record the exact upstream `openai/codex` commit used for sync work.
- Added explicit upstream sync instructions to [`AGENTS.md`](AGENTS.md).
- Added the upstream `openai/codex` repository as a git submodule at [`vendor/openai-codex`](vendor/openai-codex).
- Added an experimental app-server SDK surface with `AppServerCodex`, `AppServerThread`, `AppServerTurnHandle`, typed approval requests, and typed app-server lifecycle events.
- Added app-server transport tests covering initialize, thread start/resume, approval accept/deny flows, unsupported server requests, and turn-consumer exclusivity.

### Changed

- Updated the vendored [`openai/codex`](vendor/openai-codex) submodule to `06e06ab173a7912de1661f6678eaf8d1c04da170`.
- Passed `baseURL` via `--config openai_base_url=...` instead of `OPENAI_BASE_URL` to match the current TypeScript SDK behavior when callers provide a custom environment override.
- Documented that the installation snippet uses version `0.0.1` in [`README.md`](README.md).
- Documented that upstream reference tracking should use an exact `openai/codex` commit instead of the moving `main` branch.
- Kept the existing `Codex` / `CodexThread` exec transport unchanged while adding the experimental app-server client as a separate API path.
- Set a low-latency `swift-subprocess` preferred buffer size for the app-server stdio transport so JSON-RPC responses surface promptly on Darwin.
- Reviewed the latest upstream app-server protocol on `origin/main` and confirmed the currently implemented request and notification subset remains compatible.

### Upstream Basis

- Swift package version: `0.0.1`
- Vendored upstream checkout: `vendor/openai-codex` at `06e06ab173a7912de1661f6678eaf8d1c04da170`
- Upstream TypeScript SDK basis: `3293538e128e02ca24d5e9913af986ac68405b00`
- Notes: latest reviewed SDK behavior includes the `openai_base_url` config override parity update. Experimental app-server compatibility was separately reviewed against `openai/codex` `origin/main` at `527244910fb851cea6147334dbc08f8fbce4cb9d`; earlier historical basis before this sync remains unrecorded.
