# Upstream Reference

This repository ports the OpenAI Codex SDK work in [`openai/codex`](https://github.com/openai/codex), while the current transport and protocol behavior are reviewed primarily against the vendored Python app-server client and the v2 app-server schema.

## Recorded Upstream Basis

- Upstream repository: `openai/codex`
- Vendored upstream checkout: `vendor/openai-codex`
- Vendored upstream commit: `e9fb49366c93a1478ec71cc41ecee415a197d036`
- Reviewed JSON-RPC basis commit SHA: `e9fb49366c93a1478ec71cc41ecee415a197d036`
- Reviewed JSON-RPC basis commit URL: `https://github.com/openai/codex/commit/e9fb49366c93a1478ec71cc41ecee415a197d036`
- Last reviewed date: `2026-04-23`

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

- Vendored checkout: `vendor/openai-codex` at `e9fb49366c93a1478ec71cc41ecee415a197d036` (`rust-v0.124.0`)
- Reviewed upstream files:
  - `sdk/python/src/codex_app_server/api.py`
  - `sdk/python/src/codex_app_server/async_client.py`
  - `sdk/python/src/codex_app_server/client.py`
  - `sdk/python/src/codex_app_server/errors.py`
  - `sdk/python/src/codex_app_server/generated/v2_all.py`
  - `sdk/python/src/codex_app_server/generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Reviewed upstream features:
  - Python `codex_app_server` thread APIs now expose `session_start_source` on `thread.start` and `sort_direction` on `thread.list`
  - notification registry entries for `externalAgentConfig/import/completed`, `item/fileChange/patchUpdated`, `thread/realtime/transcript/delta`, `thread/realtime/transcript/done`, `thread/realtime/sdp`, and `warning`
  - permission-profile and request-permission schema payloads used by guardian approval reviews
  - remote plugin source variants and expanded plugin marketplace metadata
  - refreshed thread/model/plugin response shapes and rate-limit typing in the generated schema surface
- Parity target:
  - Python SDK parity for the handwritten thread-start and thread-list convenience surface, while continuing to regenerate Swift protocol models directly from the vendored v2 schema and upstream notification registry
- Remaining upstream gaps not ported end to end:
  - the schema and Python SDK now include additional request surfaces such as `thread/turns/list`, `marketplace/remove`, `mcpServer/resource/read`, and `mcpServer/tool/call`, but this repository still only exposes the previously implemented RPC convenience methods
- Intentional Swift-specific deviations:
  - the repository still follows Swift API conventions and async/await rather than Python synchronous wrappers
  - `JSONValue.number(Double)` remains the raw escape hatch type, while generated typed models use integer fields where the schema requires them
  - the SDK keeps explicit `Codex`, `CodexThread`, and `CodexTurnHandle` handle types separate from protocol record types like `Thread` and `Turn`
  - the Swift package still exists as a porting project derived from the broader `openai/codex` SDK work, but runtime semantics now come from the JSON-RPC app-server basis above
