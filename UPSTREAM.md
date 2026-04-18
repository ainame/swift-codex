# Upstream Reference

This repository ports the OpenAI Codex SDK work in [`openai/codex`](https://github.com/openai/codex), while the current transport and protocol behavior are reviewed primarily against the vendored Python app-server client and the v2 app-server schema.

## Recorded Upstream Basis

- Upstream repository: `openai/codex`
- Vendored upstream checkout: `vendor/openai-codex`
- Vendored upstream commit: `d65ed92a5e440972626965d0af9a6345179783bc`
- Reviewed JSON-RPC basis commit SHA: `d65ed92a5e440972626965d0af9a6345179783bc`
- Reviewed JSON-RPC basis commit URL: `https://github.com/openai/codex/commit/d65ed92a5e440972626965d0af9a6345179783bc`
- Last reviewed date: `2026-04-18`

The vendored submodule commit above identifies which upstream checkout is bundled in this repository. The current Swift runtime transport now follows the vendored Python `codex_app_server` client and v2 app-server protocol, not the older `exec` transport.

## How To Keep This In Sync

When porting new behavior from upstream or validating parity:

1. Identify the exact `openai/codex` commit used as the basis.
2. Review the relevant files from the vendored checkout in `vendor/openai-codex`.
3. Update this file with:
   - the exact commit SHA
   - a GitHub commit URL
   - the review date
   - the specific upstream files or features reviewed
   - any intentional Swift-specific deviations
4. Update [`README.md`](README.md) if the public status or supported behavior changed.
5. Update [`CHANGELOG.md`](CHANGELOG.md) with user-visible changes.
6. Update [`NOTICE`](NOTICE) only if attribution requirements change or additional derived material is imported.

## Sync Notes

### Unreleased

- Vendored checkout: `vendor/openai-codex` at `d65ed92a5e440972626965d0af9a6345179783bc` (`rust-v0.121.0`)
- Reviewed upstream files:
  - `sdk/python/src/codex_app_server/api.py`
  - `sdk/python/src/codex_app_server/async_client.py`
  - `sdk/python/src/codex_app_server/client.py`
  - `sdk/python/src/codex_app_server/errors.py`
  - `sdk/python/src/codex_app_server/generated/v2_all.py`
  - `sdk/python/src/codex_app_server/generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Reviewed upstream features:
  - Python `codex_app_server` client surface remained unchanged between `rust-v0.118.0` and `rust-v0.121.0`
  - thread response metadata for `instructionSources` and thread records for `forkedFromId`
  - guardian auto-review payload typing for `action`, `decisionSource`, `reviewId`, and `userAuthorization`
  - `PlanType.prolite`
  - `Model.additionalSpeedTiers`
  - `_meta` on `McpToolCallResult`
  - path-valued schema fields now emitted as `AbsolutePathBuf`
  - realtime transcript schema moved from `thread/realtime/transcriptUpdated` to `thread/realtime/transcript/delta|done` plus `thread/realtime/sdp`
- Parity target:
  - Raw app-server schema parity for generated Swift models, while keeping notification decoding bounded by the upstream `notification_registry.py` mapping
- Remaining upstream gaps not ported end to end:
  - the vendored `notification_registry.py` at `rust-v0.121.0` still does not expose the newer realtime transcript or SDP notifications, so the Swift SDK currently treats those methods as unknown notifications even though the schema contains typed payload definitions
  - the schema now includes additional request surfaces such as `thread/inject_items`, `marketplace/add`, `mcpServer/resource/read`, and `mcpServer/tool/call`, but this repository still only exposes the previously implemented RPC convenience methods
- Intentional Swift-specific deviations:
  - the repository still follows Swift API conventions and async/await rather than Python synchronous wrappers
  - `JSONValue.number(Double)` remains the raw escape hatch type, while generated typed models use integer fields where the schema requires them
  - the SDK keeps explicit `Codex`, `CodexThread`, and `CodexTurnHandle` handle types separate from protocol record types like `Thread` and `Turn`
  - the Swift package still exists as a porting project derived from the broader `openai/codex` SDK work, but runtime semantics now come from the JSON-RPC app-server basis above
