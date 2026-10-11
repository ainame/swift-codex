# Upstream Reference

This repository ports the OpenAI Codex SDK work in [`openai/codex`](https://github.com/openai/codex), while the current transport and protocol behavior are reviewed primarily against the vendored Python app-server client and the v2 app-server schema.

## Recorded Upstream Basis

- Upstream repository: `openai/codex`
- Vendored upstream checkout: `vendor/openai-codex`
- Vendored upstream commit: `092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`
- Reviewed JSON-RPC basis commit SHA: `092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`
- Reviewed JSON-RPC basis commit URL: `https://github.com/openai/codex/commit/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`
- Last reviewed date: `2026-10-11`

The vendored submodule commit above identifies which upstream checkout is bundled in this repository. The current Swift runtime transport now follows the vendored Python `openai_codex` client and v2 app-server protocol, not the older `exec` transport.

## Coverage Audit (2026-10-11)

Basis remains `rust-v0.162.1` at `092d3acd6bec3e3a14bdc7e7a2810ab628ab759d`;
GitHub's latest stable release was checked again on 2026-10-11. This follow-up
adds raw app-server experimental dynamic tools, not a new upstream basis.

Generate the complete inventory with `python3 Scripts/audit_app_server_surface.py`.
It currently enumerates 173 client methods and 11 server methods from stable JSON
exports plus Rust wire declarations. Source matches indicate candidates for review,
not implemented feature counts. Check the inventory on each sync and carry these
unresolved gaps forward, even when upstream has not changed them.

| Reviewed feature | Status and evidence |
| --- | --- |
| `thread/start.dynamicTools` | Implemented: function/namespace specs, deferred tool flag, public thread options, start-only serialization; resume/fork reject attempts to replace saved tools. |
| `item/tool/call` | Implemented: generated params/results from standalone upstream exports, typed handler and generic handler dispatch, failure response without a handler, text/image/audio results, arbitrary JSON and unknown-field preservation. |
| Server request IDs | Implemented: string/integer IDs accepted and echoed with their original JSON type; regression tests cover both. Outbound SDK requests still use string IDs. |
| Async server handler scheduling | Deferred: handlers run on the input path and must not await another RPC on the same client. Independent handler dispatch/cancellation is not yet implemented. |
| Approval request extensions | Deferred: existing command/file approval wrappers omit newer metadata and decision variants; the generic handler retains existing raw-JSON escape hatches. |
| Other server methods | Deferred: `account/chatgptAuthTokens/refresh`, `attestation/generate`, `currentTime/read`, `item/permissions/requestApproval`, `item/tool/requestUserInput`, and `mcpServer/elicitation/request` have no dedicated Swift handlers. |
| Legacy server approvals | Intentionally unsupported by specialized handlers: `applyPatchApproval` and `execCommandApproval` belong to legacy turn APIs; use the generic handler if required. |
| Other client request surfaces | Deferred: broader account/auth/configuration, environment, plugin sharing, permission profiles, process/fs, realtime, thread-history/settings, MCP read/call and other unwrapped methods remain raw-RPC-only. Run the inventory for the full method/field list; do not infer convenience support from generated models. |
| Other experimental request fields | Deferred: fields such as thread runtime workspace roots, permission profiles, history mode, environments, selected capability roots, and daybreak options remain outside the existing Swift convenience APIs. |
| Python SDK orchestration | Deferred: prior notification coalescing, cancellation recovery, thread start locking, logical goal operations, independent turn streams and history cursor/anchor gaps remain. |

Reviewed source files include `app-server-protocol/src/protocol/{common.rs,v2/thread.rs,v2/item.rs}`,
`schema/json/{ServerRequest,DynamicToolCallParams,DynamicToolCallResponse}.json`,
`protocol/src/dynamic_tools.rs`, and `app-server/src/{dynamic_tools,outgoing_message}.rs`.
Stable `ThreadStartParams` omits `dynamicTools`, and the combined v2 schema omits
server-call params/results, so stable-only schema regeneration cannot port this flow.
Verification: local SDK tests cover registration, typed dispatch, original request IDs,
responses and item lifecycle. The upstream `0.162.1` app-server accepted function and
namespace registration with `experimentalApi: true` in an isolated ephemeral thread.
That registration smoke test used direct JSON-RPC; live model-driven invocation and
application UI rendering have not been verified.

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

- Vendored checkout: `vendor/openai-codex` at `092d3acd6bec3e3a14bdc7e7a2810ab628ab759d` (`rust-v0.162.1`), verified as the latest stable GitHub release on 2026-10-10 the release branch diverges from the previous pin at `c248f6d48b97eb4a2aa56147a0b11b7d763278b9`. The reviewed delta retains prior generated features apart from the documented skill path wrapper change.
- Reviewed upstream files:
  - `sdk/typescript/src/{exec,thread,turnOptions,index}.ts` and `sdk/typescript/tests/run.test.ts`
  - `sdk/python/src/openai_codex/generated/v2_all.py` and `generated/notification_registry.py`
  - `sdk/python/src/openai_codex` handwritten runtime files (unchanged from the prior basis)
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- Parity target: focused raw app-server schema parity for generated models and existing RPC APIs; TypeScript's per-turn cyber selection is exposed through the app-server transport.
- Generated additions: thread prediction notifications/results, partial-answer phases, turn root IDs, subagent model/reasoning metadata, MCP OAuth login IDs, misalignment review targets, and goal mutation origins.
- Existing turn APIs now accept per-turn cyber selection and parent/root turn IDs. Existing goal set/clear APIs forward optional explicit provenance; omitted provenance does not supply user authorization.
- Skill paths changed from `AbsolutePathBuf` to `LegacyAppPathString`, matching upstream's legacy path support. Callers constructing typed skill paths may need to update their wrapper type.
- The schema's new unconstrained error branch uses Swift's existing `.unknown(JSONValue)` fallback, preserving round trips and known-case decoding.
- Remaining schema-only gaps: attachment-owner lookup, environment skill requirements, browser extension headers, independent speed-mode requirements, additional-tools raw response items, and broader request surfaces are not exposed by new convenience APIs. Previously recorded Python orchestration, item-history cursor/anchor, and MCP server-name filtering gaps remain.
- Intentional Swift-specific deviations: Swift API conventions and async/await remain unchanged; cyber selections use app-server camel-case wire values rather than exec CLI snake-case flags. Model generation remains limited to the roots in `Scripts/generate_app_server_v2.py` and notification registry.

### 0.160.0

- Vendored checkout: `vendor/openai-codex` at `a956835d020762cb2b570053af06f643a11c0ecc` (`rust-v0.160.0`)
- Reviewed upstream files:
  - `sdk/python/src/openai_codex/generated/v2_all.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
  - `sdk/python/src/openai_codex/api.py` and `sdk/python/src/openai_codex/generated/notification_registry.py` (unchanged from the prior basis)
  - `sdk/typescript` (unchanged from the prior basis)
- Parity target: focused raw app-server schema parity for the generated Swift model roots.
- Generated additions: `flexUnavailable` and `tooManyDenials` error cases, and the `promax` plan type.
- The stable release was cut from a branch that diverged before the prior vendored commit. Its schema removes plugin extension definitions and the typed `PluginSummary.extensions` field. Unknown plugin fields continue to round-trip through `additionalFields`; callers using the removed generated types or property must migrate.
- Remaining schema-only gaps: `ListMcpServerStatusParams.serverName` and the item-history cursor/anchor additions have no Swift convenience API. The previously recorded Python SDK and broader request-surface gaps also remain.
- Intentional Swift-specific deviations: Swift API conventions and async/await remain unchanged; the generated model scope stays limited to the roots in `Scripts/generate_app_server_v2.py`.

### 0.157.1

- Vendored checkout: `vendor/openai-codex` at `36650394c5b38c2990ccf2a3457165ca3e9d9726` (`rust-v0.157.1`)
- Reviewed upstream files:
  - `sdk/python/src/openai_codex/api.py`
  - `sdk/python/src/openai_codex/_inputs.py`
  - `sdk/python/src/openai_codex/_message_router.py`
  - `sdk/python/src/openai_codex/generated/notification_registry.py`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
  - `sdk/python/src/openai_codex/generated/v2_all.py`
- Reviewed generator behavior:
  - `Scripts/generate_app_server_v2.py` regenerates Swift v2 models from the vendored schema
- Reviewed upstream features:
  - file-ID image sources for user input and tool output, with shared discriminator/detail fields and existing realtime session IDs preserved by the generator
  - gateway OAuth status notifications, model access programs, plugin extensions, and MCP app UI metadata
  - disabled plugin IDs on thread lifecycle responses/settings and collaboration mode on resume responses
  - reviewed Python API documentation changes; TypeScript SDK has no changes since the previous basis
  - added typed low-level `thread/attachment/add`, `thread/attachment/list`, and `thread/attachment/remove` requests plus attachment lifecycle notifications
  - refreshed generated registry coverage for project, queue, revert, realtime, MCP event-stream, strict-review, and auth-recovery notifications
  - reviewed Python SDK external-message inputs, resumed-thread turn-history selection, per-turn options, and independently subscribable turn streams
- Parity target:
  - focused raw app-server schema parity for the Swift model and low-level RPC surfaces used by this package
- Remaining upstream gaps not ported end to end:
  - gateway OAuth request helpers, MCP resource-read parameters, and broader account/configuration request additions remain outside the focused generated roots and convenience API
  - the Python SDK's logical goal-operation orchestration, notification coalescing, cancellation recovery, and per-thread start locking are not yet ported; this sync exposes the underlying persisted-goal RPCs only
  - Python's external-message input, resumed-thread turn-history selection, per-turn options, and independently subscribable turn streams remain unported from the high-level Swift API
  - pagination, revert, plugin-reconcile, realtime, and MCP event-stream request endpoints remain schema-only because the current Swift convenience API does not expose them end to end
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
