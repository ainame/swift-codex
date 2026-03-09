# Changelog

All notable changes to this project should be documented in this file.

For upstream parity work, record both the Swift package version and the `openai/codex` `sdk/typescript` basis that the release or unreleased work reflects. Keep detailed provenance in [`UPSTREAM.md`](UPSTREAM.md) and summarize user-visible results here.

The format is based on Keep a Changelog and this project uses tags without a `v` prefix.

## [Unreleased]

### Added

- Added [`UPSTREAM.md`](UPSTREAM.md) to record the exact upstream `openai/codex` commit used for sync work.
- Added explicit upstream sync instructions to [`AGENTS.md`](AGENTS.md).
- Added the upstream `openai/codex` repository as a git submodule at [`vendor/openai-codex`](vendor/openai-codex).

### Changed

- Documented that the installation snippet uses version `0.0.1` in [`README.md`](README.md).
- Documented that upstream reference tracking should use an exact `openai/codex` commit instead of the moving `main` branch.

### Upstream Basis

- Swift package version: `0.0.1`
- Vendored upstream checkout: `vendor/openai-codex` at `c1defcc98cf9c6b9001e86d8d13e5b5ec9488510`
- Upstream TypeScript SDK basis: not yet recorded
- Notes: historical upstream basis was not recorded before `UPSTREAM.md` and this changelog were added.
