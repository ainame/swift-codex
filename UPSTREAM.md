# Upstream Reference

This repository ports the OpenAI Codex SDK work in [`openai/codex`](https://github.com/openai/codex), while the current transport and protocol behavior are reviewed primarily against the vendored Python app-server client and the v2 app-server schema.

## Recorded Upstream Basis

- Upstream repository: `openai/codex`
- Vendored upstream checkout: `vendor/openai-codex`
- Vendored upstream commit: `26de83050b20f7e0ee211b9739e52ae00ce8032a`
- Reviewed JSON-RPC basis commit SHA: `26de83050b20f7e0ee211b9739e52ae00ce8032a`
- Reviewed JSON-RPC basis commit URL: `https://github.com/openai/codex/commit/26de83050b20f7e0ee211b9739e52ae00ce8032a`
- Last reviewed date: `2026-07-04`

The vendored submodule commit above identifies which upstream checkout is bundled in this repository. The current Swift runtime transport now follows the vendored Python `openai_codex` client and v2 app-server protocol, not the older `exec` transport.

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

- Vendored checkout: `vendor/openai-codex` at `26de83050b20f7e0ee211b9739e52ae00ce8032a` (`rust-v0.142.5`)
- Reviewed upstream files:
  - `sdk/python/src/openai_codex/_inputs.py`
  - `sdk/python/src/openai_codex/async_client.py`
  - `sdk/python/src/openai_codex/client.py`
  - `sdk/python/src/openai_codex/generated/v2_all.py`
  - `sdk/python/src/openai_codex/generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Reviewed upstream features:
  - no Swift-relevant Python SDK, notification registry, v2 schema JSON, TypeScript schema, SDK example, or SDK test changes since `rust-v0.142.3`
  - workspace message and external-agent import-history response records
  - thread recency ordering metadata and `recency_at` sort key support
  - MCP tool-call app context metadata and plugin dark-logo metadata
  - legacy app path string records, nullable ChatGPT account email, and external-agent import failure error types
- Parity target:
  - focused raw app-server schema parity for the Swift model and low-level RPC surfaces used by this package
- Remaining upstream gaps not ported end to end:
  - the Python SDK's logical goal-operation orchestration, notification coalescing, cancellation recovery, and per-thread start locking are not yet ported; this sync exposes the underlying persisted-goal RPCs only
  - the full `rust-v0.142.5` schema includes broader account, config, model safety-buffering, MCP server status, remote-control, plugin, filesystem, and app-server transport changes that are still not wrapped as Swift convenience APIs
- Intentional Swift-specific deviations:
  - the repository still follows Swift API conventions and async/await rather than upstream TypeScript or Python wrappers
  - persisted goals are exposed as direct actor methods rather than the Python SDK's synchronous and asynchronous logical-turn stream wrappers

### 0.137.0

- Vendored checkout: `vendor/openai-codex` at `f221438b691b8f749d98f22077c93ebe01923fbe` (`rust-v0.137.0`)
- Reviewed upstream files:
  - `codex-rs/app-server-protocol/schema/typescript/ClientRequest.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/ThreadResumeInitialTurnsPageParams.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/TurnsPage.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/RateLimitSnapshot.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/SpendControlLimitSnapshot.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/GetAccountRateLimitsResponse.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/SkillsExtraRootsSetParams.ts`
  - `codex-rs/app-server-protocol/schema/typescript/v2/SkillsExtraRootsSetResponse.ts`
- Reviewed upstream features:
  - `Thread.parentThreadId` for subagent parent linkage
  - `skills/extraRoots/set` request support
  - paginated turn response records for thread history
  - account rate-limit multi-bucket and spend-control metadata
- Parity target:
  - focused raw app-server schema parity for the Swift model and low-level RPC surfaces used by this package
- Remaining upstream gaps not ported end to end:
  - the full `rust-v0.137.0` schema includes broader config, MCP server status, remote-control, plugin, thread-history, and app-server transport changes that are still not wrapped as Swift convenience APIs
- Intentional Swift-specific deviations:
  - the repository still follows Swift API conventions and async/await rather than upstream TypeScript or Python wrappers
  - generated-style model files were refreshed manually for this constrained automation run because the local submodule could not fetch GitHub objects in the sandbox

### 0.135.0

- Vendored checkout: `vendor/openai-codex` at `4daceea869704f9f35e0a3949fc34711ef978a4e` (`rust-v0.135.0`)
- Reviewed upstream files:
  - `sdk/python/src/openai_codex/api.py`
  - `sdk/python/src/openai_codex/async_client.py`
  - `sdk/python/src/openai_codex/client.py`
  - `sdk/python/src/openai_codex/errors.py`
  - `sdk/python/src/openai_codex/_sandbox.py`
  - `sdk/python/src/openai_codex/generated/v2_all.py`
  - `sdk/python/src/openai_codex/generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Reviewed upstream features:
  - Python SDK package rename to `openai_codex`
  - Python SDK `Sandbox` presets for thread lifecycle sandbox modes and turn sandbox policies
  - notification registry entries for `process/exited` and `process/outputDelta`
  - image input detail fields, MCP tool-call plugin IDs, expanded remote-control status payloads, and refreshed plugin share metadata
  - schema additions for permission profiles, plugin installed/share checkout, thread goal requests, additional context, and related app-server configuration records
- Parity target:
  - Python SDK parity for the friendly sandbox preset surface, while continuing to regenerate Swift protocol models directly from the vendored v2 schema and upstream notification registry
- Remaining upstream gaps not ported end to end:
  - the schema and Python SDK now include additional request surfaces such as account login, `hooks/list`, `permissionProfile/list`, `plugin/installed`, `plugin/share/*`, `process/*`, thread goal APIs, `thread/turns/list`, `mcpServer/resource/read`, and `mcpServer/tool/call`, but this repository still only exposes the previously implemented RPC convenience methods plus sandbox presets
- Intentional Swift-specific deviations:
  - the repository still follows Swift API conventions and async/await rather than Python synchronous wrappers
  - `JSONValue.number(Double)` remains the raw escape hatch type, while generated typed models use integer fields where the schema requires them
  - the public Swift `ServiceTier` wrapper remains as a compatibility enum even though the current upstream schema models those request fields as unconstrained strings
  - the SDK keeps explicit `Codex`, `CodexThread`, and `CodexTurnHandle` handle types separate from protocol record types like `Thread` and `Turn`
  - the Swift package still exists as a porting project derived from the broader `openai/codex` SDK work, but runtime semantics now come from the JSON-RPC app-server basis above
