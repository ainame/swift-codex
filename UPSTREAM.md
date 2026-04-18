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
  - `sdk/python/examples/01_quickstart_constructor/sync.py`
  - `sdk/python/examples/02_turn_run/sync.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Reviewed upstream features:
  - confirmed no handwritten Python `codex_app_server` client changes between `rust-v0.118.0` and `rust-v0.121.0`
  - confirmed no generated Python `v2_all.py` / `notification_registry.py` API surface changes between `rust-v0.118.0` and `rust-v0.121.0`
  - initialize, thread, turn, model, and notification method shapes exposed by the Python SDK
  - typed response payloads and notification payload mapping exposed by the Python SDK
  - default approval behavior for known approval requests
  - empty-object responses for interrupt/archive/name/compact style methods
  - `data` collection fields on thread/model list responses
  - server metadata normalization from initialize payloads
  - process launch config parity for explicit `cwd` and full argv override
  - typed plugin marketplace response support via `plugin/list`
  - `PlanType.selfServeBusinessUsageBased` and `PlanType.enterpriseCbpUsageBased`
  - raw v2 schema additions in `rust-v0.121.0`, including unstable realtime transcript event renames, `thread/inject_items`, `marketplace/add`, and `mcpServer/resource/read`
- Parity target:
  - Python SDK parity, with the vendored raw v2 schema reviewed separately for features not yet surfaced by the Python app-server SDK
- Intentional Swift-specific deviations:
  - the repository still follows Swift API conventions and async/await rather than Python synchronous wrappers
  - `JSONValue.number(Double)` remains the raw escape hatch type, while generated typed models use integer fields where the schema requires them
  - the SDK keeps explicit `Codex`, `CodexThread`, and `CodexTurnHandle` handle types separate from protocol record types like `Thread` and `Turn`
  - the Swift package splits shared protocol/client code into `CodexCore`, keeps local subprocess launch in the `Codex` product, and adds `CodexBridgeClient`/`CodexBridge` for HTTP remote-client usage
  - the Swift package still exists as a porting project derived from the broader `openai/codex` SDK work, but runtime semantics now come from the JSON-RPC app-server basis above
  - the Swift SDK does not yet expose raw-schema-only `rust-v0.121.0` additions when upstream Python `codex_app_server` generated models and notification registry still expose the older surface
