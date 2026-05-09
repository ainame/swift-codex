# Upstream Reference

This repository ports the OpenAI Codex SDK work in [`openai/codex`](https://github.com/openai/codex), while the current transport and protocol behavior are reviewed primarily against the vendored Python app-server client and the v2 app-server schema.

## Recorded Upstream Basis

- Upstream repository: `openai/codex`
- Vendored upstream checkout: `vendor/openai-codex`
- Vendored upstream commit: `58573da43ab697e8b79f152c53df4b42230395a8`
- Reviewed JSON-RPC basis commit SHA: `58573da43ab697e8b79f152c53df4b42230395a8`
- Reviewed JSON-RPC basis commit URL: `https://github.com/openai/codex/commit/58573da43ab697e8b79f152c53df4b42230395a8`
- Last reviewed date: `2026-05-09`

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

- Vendored checkout: `vendor/openai-codex` at `58573da43ab697e8b79f152c53df4b42230395a8` (`rust-v0.130.0`)
- Reviewed upstream files:
  - `sdk/python/src/codex_app_server/api.py`
  - `sdk/python/src/codex_app_server/async_client.py`
  - `sdk/python/src/codex_app_server/client.py`
  - `sdk/python/src/codex_app_server/errors.py`
  - `sdk/python/src/codex_app_server/generated/v2_all.py`
  - `sdk/python/src/codex_app_server/generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Reviewed upstream features:
  - Python `codex_app_server` `thread.list` now accepts `ThreadListCwdFilter` plus `use_state_db_only`, while `thread.start` continues to expose `session_start_source`
  - notification registry entries for `guardianWarning`, `model/verification`, `remoteControl/status/changed`, `thread/goal/cleared`, and `thread/goal/updated`
  - refreshed thread payloads now include `sessionId` and `threadSource`
  - plugin marketplace models now include availability, share context, and keyword metadata
  - model metadata now includes service-tier records and the schema continues to widen raw string compatibility in a few request fields
- Parity target:
  - Python SDK parity for the handwritten thread-start and thread-list convenience surface, while continuing to regenerate Swift protocol models directly from the vendored v2 schema and upstream notification registry
- Remaining upstream gaps not ported end to end:
  - the schema and Python SDK now include additional request surfaces such as `hooks/list`, `marketplace/upgrade`, `plugin/share/*`, `process/*`, `thread/turns/list`, `mcpServer/resource/read`, and `mcpServer/tool/call`, but this repository still only exposes the previously implemented RPC convenience methods
- Intentional Swift-specific deviations:
  - the repository still follows Swift API conventions and async/await rather than Python synchronous wrappers
  - `JSONValue.number(Double)` remains the raw escape hatch type, while generated typed models use integer fields where the schema requires them
  - the public Swift `ServiceTier` wrapper remains as a compatibility enum even though the current upstream schema models those request fields as unconstrained strings
  - the SDK keeps explicit `Codex`, `CodexThread`, and `CodexTurnHandle` handle types separate from protocol record types like `Thread` and `Turn`
  - the Swift package still exists as a porting project derived from the broader `openai/codex` SDK work, but runtime semantics now come from the JSON-RPC app-server basis above
