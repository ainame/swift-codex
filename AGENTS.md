# AGENTS.md

## Scope
These instructions apply to the entire repository.

## Project Goals
- Port the TypeScript Codex SDK from `https://github.com/openai/codex/tree/main/sdk/typescript` to Swift.
- Preserve TypeScript SDK behavior where practical while keeping the Swift API usable and idiomatic.
- Keep the Swift package focused on wrapping the `codex` CLI rather than reimplementing agent behavior.

## License and Attribution
- This repository is Apache License 2.0 licensed.
- Treat the project as a derivative port of `openai/codex` where applicable.
- Preserve upstream attribution in [`NOTICE`](NOTICE) and keep [`LICENSE`](LICENSE) consistent with Apache License 2.0.
- When importing or closely porting upstream material, do not remove applicable attribution or notice requirements.
- If new third-party derived material is added, update [`NOTICE`](NOTICE) when needed.

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
