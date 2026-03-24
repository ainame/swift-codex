# TODO

This file tracks follow-up work for the experimental app-server API after the Python-parity work on `codex/app-server-python-parity`.

## Why JSON-RPC Matters

The previous `codex exec` integration was a one-shot process model:

- send input
- stream events
- exit

That shape works for buffered or streamed turns, but it does not support a real back-and-forth protocol with the host while a turn is still running.

The app-server JSON-RPC transport unlocks capabilities that were previously impossible or unreliable:

- Native approval requests before action execution.
  The runtime can pause and ask the host to approve or deny a command or file change before it proceeds.

- Mid-turn host interaction.
  The server can make requests while a turn is in progress rather than forcing everything into pre-turn input or post-turn event interpretation.

- Precise request and response correlation.
  `initialize`, `thread/start`, `thread/resume`, `turn/start`, and approval requests are explicit RPC methods with request ids and typed responses.

- Long-lived session state.
  One app-server process can stay alive across multiple requests and turns, which is a better fit for real session orchestration than repeatedly spawning `codex exec`.

- First-class non-turn operations.
  Thread-level operations such as read, list, fork, archive, rollback, and metadata updates fit naturally into JSON-RPC methods instead of being bolted onto a turn-only API.

- Future host callbacks.
  User-input requests, richer policy gates, host-mediated tools, and realtime notifications all fit the protocol model cleanly.

## Current Scope

The current experimental Swift implementation now covers the main Python `codex_app_server` surface:

- initialize and initialized handshake
- thread start
- thread resume
- thread list
- thread read
- thread fork
- thread archive
- thread unarchive
- thread rename
- thread compact
- turn start
- turn steer
- turn interrupt
- model list
- full notification streaming via `AppServerNotification`
- command approval requests
- file-change approval requests
- generic server-request handling
- stderr-tail diagnostics for transport closure when the app-server exits early
- retry helpers for overload-style JSON-RPC failures
- generated `AppServerV2` wrappers and notification registry output

## Next App-Server Work

- Improve the generated model layer.
  The current generator emits thin `JSONValue` wrappers plus a typed notification registry. This was a deliberate parity shortcut, not the intended steady-state API.
  Current examples like `AppServerV2.AgentPath` are not good public Swift models because they expose transport representation rather than domain semantics.
  The same concern applies to handwritten extension accessors like `InitializeResponse.serverInfo`, `userAgent`, and similar `jsonObject?.stringValue(...)` helpers.
  Those helpers are better than forcing SDK users to dig into `jsonValue`, but they are still dynamic lookup disguised as a typed model.
  The next pass should move toward schema-driven Swift models with stored properties or strongly typed scalar wrappers.
  Prioritize the generated shapes in this order:
  1. scalar aliases and path-like values such as `AgentPath`, `AbsolutePathBuf`, ids, and timestamps
  2. high-value objects returned by the public facade such as `Thread`, `Turn`, `ThreadItem`, `ThreadTokenUsage`, and model-list payloads
  3. frequently consumed notification payloads such as turn, item, diff, plan, and reasoning notifications
  Keep unknown-field preservation available, but as an escape hatch like `rawJSON` or `additionalFields`, not as the primary public API.
  Avoid hand-maintaining hundreds of types; keep this generator-based and prefer schema-driven field generation over adding more handwritten accessors.
  Maintain wire compatibility with the vendored protocol and preserve the current ability to decode newer upstream payloads without immediate breakage.

- Add executable examples.
  A small example should show startup, approval callbacks, thread list/read, and turn streaming.

- Watch for new upstream request and notification methods.
  The current surface tracks the reviewed Python SDK and v2 protocol, but experimental upstream changes may add or rename methods quickly.

- Improve typed accessors for high-value protocol objects.
  `Thread`, `Turn`, `ThreadItem`, usage objects, and notification payloads should gain more convenience accessors as real consumers need them.
  The goal here is to shrink direct `JSONValue` access from app-level code.
  Favor a design where most SDK consumers never touch `jsonValue` for common flows like:
  - reading thread ids, turn ids, status, usage, final responses, and item text
  - inspecting plan, diff, and reasoning notification payloads
  - consuming model-list metadata
  Replace handwritten dynamic helpers like `jsonObject?.valueModel(forKey:)` and `jsonObject?.stringValue(forKey:)` with generated stored properties or generated decoding where the schema is stable enough.
  Treat the current convenience extensions as transitional glue, not the target architecture.
  If a future agent adds stored properties for these models, trim redundant handwritten extension accessors at the same time so the API does not fork into two competing access patterns.

- Simplify notification metadata extraction.
  Helpers like `AppServerNotification.threadID` and `turnID` should not require giant handwritten `switch` statements over every notification case.
  In the short term, prefer generic extraction from `rawParams` using common paths like `threadId`, `thread.id`, `turnId`, and `turn.id`, with a tiny fallback only for genuinely irregular payloads.
  In the longer term, move this logic into generated metadata accessors or generated protocol conformances once the model layer is no longer `JSONValue`-first.
  Avoid maintaining parallel handwritten dispatch logic that must be updated every time upstream adds another notification type.

- Improve approval response modeling.
  If upstream grows richer approval payloads or decision metadata, preserve that structure instead of returning only accept or decline.

- Evaluate whether `preferredBufferSize = 1` should remain fixed.
  It is the safest setting for interactive JSON-RPC latency on Darwin, but a slightly larger value may be acceptable if tests and responsiveness stay reliable.

## Upstream Tracking

- Re-check the upstream app-server protocol whenever this API changes.
  The current compatibility review was against `openai/codex` `origin/main` at `527244910fb851cea6147334dbc08f8fbce4cb9d`.

- If upstream changes request names, notification payloads, or approval payload shapes, update the generator and transport before extending higher-level APIs.

- Re-check generator inputs before changing generated output shape.
  The current generator reads both the vendored Python notification registry and the vendored v2 JSON schema.
  Keep those two inputs aligned: the schema should remain the source of truth for available types, while the Python notification registry should remain the source of truth for the current notification-method mapping used by the higher-level SDK.
