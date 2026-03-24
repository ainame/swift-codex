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
  The current generator emits thin `JSONValue` wrappers plus a typed notification registry. If the protocol stabilizes, consider generating more field-level accessors directly from the schema.

- Add executable examples.
  A small example should show startup, approval callbacks, thread list/read, and turn streaming.

- Watch for new upstream request and notification methods.
  The current surface tracks the reviewed Python SDK and v2 protocol, but experimental upstream changes may add or rename methods quickly.

- Improve typed accessors for high-value protocol objects.
  `Thread`, `Turn`, `ThreadItem`, usage objects, and notification payloads should gain more convenience accessors as real consumers need them.

- Improve approval response modeling.
  If upstream grows richer approval payloads or decision metadata, preserve that structure instead of returning only accept or decline.

- Evaluate whether `preferredBufferSize = 1` should remain fixed.
  It is the safest setting for interactive JSON-RPC latency on Darwin, but a slightly larger value may be acceptable if tests and responsiveness stay reliable.

## Upstream Tracking

- Re-check the upstream app-server protocol whenever this API changes.
  The current compatibility review was against `openai/codex` `origin/main` at `527244910fb851cea6147334dbc08f8fbce4cb9d`.

- If upstream changes request names, notification payloads, or approval payload shapes, update the generator and transport before extending higher-level APIs.
