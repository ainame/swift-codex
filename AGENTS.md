# AGENTS.md

## Scope
These instructions apply to the entire repository.

## Project Goals
- Port the TypeScript Codex SDK from `../../openai/codex/sdk/typescript` to Swift.
- Preserve TypeScript SDK behavior where practical while keeping the Swift API usable and idiomatic.
- Keep the Swift package focused on wrapping the `codex` CLI rather than reimplementing agent behavior.

## Dependencies
- Use `swift-subprocess` for subprocess execution.
- Use `swift-testing` by default for tests in this repository.
- Avoid adding new dependencies unless they provide clear value beyond small in-repo helpers.

## Implementation Rules
- Keep CLI discovery Node-independent.
  - Prefer explicit binary override when provided.
  - Otherwise resolve `codex` from `PATH`.
- Model MCP payloads generically unless stronger typing is required by a concrete use case.
- Keep config override serialization compatible with Codex CLI `--config key=value` behavior.
- Preserve important CLI argument ordering when behavior depends on it.

## Verification
- Run `swift build` or `swift test` when changes are in a verifiable state.
- Prefer `swift test` for behavior changes.
- Keep the `Examples` package buildable independently.

## Git Workflow
- Make git commits for each meaningful change.
- Do not squash unrelated work into one commit.
- If tags are created for versions, use tags without a `v` prefix.

## GitHub Actions
- Never use `swift-actions/setup-swift@v2`.
