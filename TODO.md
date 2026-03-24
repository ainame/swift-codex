# TODO

This file tracks follow-up work for the experimental app-server API added on `codex/app-server-approval-api`.

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

The current experimental Swift implementation intentionally supports only the minimum subset needed to replace prompt-based approval handling:

- initialize and initialized handshake
- thread start
- thread resume
- turn start
- turn interrupt
- event streaming
- command approval requests
- file-change approval requests
- stderr-tail diagnostics for transport closure when the app-server exits early

## Next App-Server Work

- Add typed support for more thread operations.
  Start with `thread/read`, `thread/list`, `thread/fork`, `thread/archive`, and `thread/rollback`.

- Add typed support for more turn operations.
  Evaluate `turn/steer` next because it is a natural fit for long-lived session control.

- Promote more notifications into the Swift event surface.
  Candidates include status changes, plan updates, diff updates, reasoning deltas, and realtime notifications.

- Support additional server request types.
  The current implementation rejects unsupported server requests clearly; add typed handling only as specific runtime use cases require it.

- Improve approval response modeling.
  If upstream grows richer approval payloads or decision metadata, preserve that structure instead of returning only accept or decline.

- Evaluate whether `preferredBufferSize = 1` should remain fixed.
  It is the safest setting for interactive JSON-RPC latency on Darwin, but a slightly larger value may be acceptable if tests and responsiveness stay reliable.

- Add an executable app-server example.
  A small example should show startup, approval callbacks, and turn streaming.

## Upstream Tracking

- Re-check the upstream app-server protocol whenever this API changes.
  The current compatibility review was against `openai/codex` `origin/main` at `527244910fb851cea6147334dbc08f8fbce4cb9d`.

- Watch for protocol changes outside the currently implemented subset.
  The Python SDK and generated v2 protocol already support far more than this Swift client currently exposes.

- If upstream changes the approval methods or payload shapes, update the Swift transport before extending higher-level APIs.
