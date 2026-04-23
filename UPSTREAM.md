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
  - `sdk/python/examples/README.md`
  - `sdk/python/tests/test_artifact_workflow_and_binaries.py`
  - `sdk/python/tests/test_client_rpc_methods.py`
  - `sdk/python/tests/test_public_api_signatures.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Reviewed upstream features:
  - generated thread-start parity for `sessionStartSource`
  - generated thread-list parity for `sortDirection`
  - typed `thread/realtime/sdp`, `thread/realtime/transcript/delta`, and `thread/realtime/transcript/done` payloads via the upstream notification registry
  - guardian approval review action typing, permission-profile models, and remote plugin source variants from the updated schema
  - plugin marketplace response updates including remote source metadata and larger result surfaces
  - response payload additions across `Thread`, `Turn`, `Model`, and `PluginListResponse`
- Parity target:
  - Python SDK parity, with typed model generation refreshed from the vendored v2 schema used by the Python app-server
- Remaining upstream gaps not ported end to end:
  - the schema and generated models now include additional permission-profile and filesystem-special-path shapes, but this repository still exposes them through typed RPC records rather than new handwritten convenience wrappers
  - upstream plugin marketplace and artifact workflow additions are represented in generated models only; the Swift package still provides the existing `pluginList()` convenience method rather than higher-level workflow helpers
- Intentional Swift-specific deviations:
  - the repository still follows Swift API conventions and async/await rather than Python synchronous wrappers
  - `JSONValue.number(Double)` remains the raw escape hatch type, while generated typed models use integer fields where the schema requires them
  - the SDK keeps explicit `Codex`, `CodexThread`, and `CodexTurnHandle` handle types separate from protocol record types like `Thread` and `Turn`
  - the Swift package still exists as a porting project derived from the broader `openai/codex` SDK work, but runtime semantics now come from the JSON-RPC app-server basis above
