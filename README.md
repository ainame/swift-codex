# swift-codex

Swift SDK for the [`codex`](https://github.com/openai/codex) CLI.

`swift-codex` now uses the Codex JSON-RPC v2 app-server protocol exclusively. The local `Codex` product starts `codex app-server --listen stdio://` and speaks JSON-RPC over stdio. Remote clients can instead use `CodexBridgeClient`, which talks to a `CodexBridge` HTTP server that runs the Codex CLI on another machine.

This repository still exists as a Swift port of the OpenAI Codex SDK work in [`openai/codex`](https://github.com/openai/codex), with upstream attribution and sync notes recorded in [`NOTICE`](NOTICE), [`LICENSE`](LICENSE), and [`UPSTREAM.md`](UPSTREAM.md).

## Status

Current implementation includes:

- async `Codex`, `CodexThread`, and `CodexTurnHandle`
- low-level `CodexRPCClient`
- a subprocess-free `CodexCore` target shared by local and bridge clients
- `CodexBridgeClient` for HTTP bridge clients that cannot spawn the Codex CLI directly
- a `CodexBridge` executable that exposes HTTP sessions backed by local Codex app-server subprocesses
- typed generated protocol models such as `Thread`, `Turn`, `ThreadItem`, `ModelListResponse`, and `CodexNotificationPayload`
- thread start, resume, fork, archive, unarchive, rename, compact, list, and read
- plugin list retrieval with typed marketplace metadata
- turn start, steer, interrupt, buffered run, and streamed notifications
- typed approval handling for command and file-change requests
- structured input items with text, remote images, local images, skills, and mentions
- transport launch overrides for explicit process `cwd` and full argv replacement
- typed union fallback with `rawJSON`, `additionalFields`, and `.unknown(JSONValue)` support
- parity-focused tests using `swift-testing`

Current scope does not include:

- Windows support
- a Swift MCP dependency
- Node/npm-specific binary discovery

This is still a WIP SDK. Breaking changes are expected while the JSON-RPC surface settles.

## Upstream Basis

- Upstream repository: `openai/codex`
- Vendored upstream checkout: [`vendor/openai-codex`](vendor/openai-codex)
- Vendored upstream commit: `d65ed92a5e440972626965d0af9a6345179783bc` (`rust-v0.121.0`)
- Primary reviewed upstream basis for the current transport and schema:
  - `sdk/python/src/codex_app_server`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

See [`UPSTREAM.md`](UPSTREAM.md) for the exact reviewed files and Swift-specific deviations.

## Requirements

- Swift 6.2
- macOS 15+ for local `Codex` and `CodexBridge` usage
- iOS 17+ for `CodexBridgeClient` usage
- Installed `codex` CLI available on `PATH`, or an explicit binary path in `CodexConfig`, when using the local `Codex` product or running `CodexBridge`
- A reachable `CodexBridge` server when using `CodexBridgeClient` from a remote app

Example installation:

```bash
brew install --cask codex
```

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ainame/swift-codex.git", from: "0.0.3")
]
```

Then choose the product that matches where the Codex CLI runs.

For apps that run on the same Mac as the Codex CLI, depend on `Codex`:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "Codex", package: "swift-codex"),
    ]
)
```

For remote clients that cannot spawn the Codex CLI directly, depend on `CodexBridgeClient` instead. This product re-exports the shared SDK types from `CodexCore` and sends JSON-RPC over HTTP to a `CodexBridge` server:

```swift
.target(
    name: "MyRemoteTarget",
    dependencies: [
        .product(name: "CodexBridgeClient", package: "swift-codex"),
    ]
)
```

If you want to pass a custom `swift-log` logger, also add the `Logging` product from `swift-log` in your target dependencies:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "Codex", package: "swift-codex"),
        .product(name: "Logging", package: "swift-log"),
    ]
)
```

## CodexBridge

`CodexBridge` is an optional HTTP bridge for clients that cannot spawn the `codex` CLI directly. A remote app can call a Mac on the same tailnet while the Mac keeps local `codex app-server --listen stdio://` sessions behind the bridge.

Most Swift apps that run on the same machine as `codex` should use the `Codex` library API directly instead. Use `CodexBridge` when your actual app process is remote from the machine that has the Codex CLI installed.

```bash
swift run CodexBridge --host 127.0.0.1 --port 31337
```

The bridge exposes:

- `GET /healthz`
- `POST /sessions`
- `POST /sessions/{sessionId}/rpc`
- `POST /sessions/{sessionId}/server-requests/{requestId}/response`
- `DELETE /sessions/{sessionId}`

Each bridge session owns one persistent Codex app-server subprocess. `POST /sessions/{sessionId}/rpc` accepts a JSON body with `method`, `params`, and optional `notification`, then streams NDJSON envelopes for the RPC response, notifications, server approval requests, and bridge errors. Sequential calls against the same session can therefore use the same Codex thread; for `turn/start`, the response stream stays open through the matching `turn/completed` notification.

Remote Swift clients should normally use `CodexBridgeClient` instead of calling these endpoints manually. `CodexBridgeClient` creates one bridge session per SDK client instance, buffers streamed notifications so `CodexTurnHandle.stream()` keeps working, and routes server approval requests back to the client-side approval handlers in `CodexConfig`:

```swift
import CodexBridgeClient

let codex = try await Codex(
    bridgeURL: URL(string: "https://satoshis-macbook-pro.example.ts.net")!,
    config: .init()
)

let thread = try await codex.startThread()
let result = try await thread.run("Say hello in one short sentence.")
print(result.finalResponse ?? "")
```

For Tailscale, keep the bridge bound to `127.0.0.1` and publish that local port with `tailscale serve`. The helper script does that wiring for this repository, and you can copy the same pattern into your own app or launch script:

```bash
Scripts/run_codex_bridge_tailscale.sh --port 31337
```

## Quickstart

```swift
import Codex

let codex = try await Codex(config: .init())
let thread = try await codex.startThread(options: .init(
    model: "gpt-5-codex",
    sandbox: .workspaceWrite
))

let result = try await thread.run(
    "Diagnose the failing test and propose a fix.",
    options: .init(summary: .concise)
)

print(result.finalResponse ?? "")
print(result.items.count)

await codex.close()
```

Custom logging:

```swift
import Codex
import Logging

let logger = Logger(label: "com.example.my-app.codex")
let codex = try await Codex(config: .init(), logger: logger)
```

Continue on the same thread:

```swift
let next = try await thread.run("Implement the fix.")
```

Resume or fork an existing thread:

```swift
let resumed = try await codex.resumeThread(id: "thread_123")
let forked = try await codex.forkThread(id: "thread_123")
```

## Streaming

Use `turn(...)` plus `stream()` for incremental notifications:

```swift
let handle = try await thread.turn(
    [.text("Inspect the repository and stream progress.")],
    options: .init(summary: .concise)
)

for try await notification in try await handle.stream() {
    switch notification.payload {
    case .itemCompleted(let payload):
        print(payload.item)
    case .turnCompleted(let payload):
        print(payload.turn.status)
    default:
        break
    }
}
```

Only one active turn consumer is supported per `CodexRPCClient`/`Codex` instance at a time.

## Structured Input

```swift
let input: [InputItem] = [
    .text("Describe these files."),
    .localImage(path: "/tmp/ui.png"),
    .image(url: "https://example.test/diagram.png"),
    .skill(name: "checks", path: "/tmp/checks"),
    .mention(name: "repo", path: "/tmp/repo"),
]

let result = try await thread.run(input)
```

## Configuration

Client-wide configuration:

```swift
let config = CodexConfig(
    codexPathOverride: "/opt/homebrew/bin/codex",
    baseURL: "https://api.example.test",
    apiKey: "test-key",
    config: [
        "approval_policy": .string("never"),
        "sandbox_workspace_write": .object([
            "network_access": .bool(true),
        ]),
    ],
    environment: [
        "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
    ],
    commandApprovalHandler: { request in
        print(request.command ?? "")
        return .approve
    },
    fileChangeApprovalHandler: { request in
        print(request.grantRoot ?? "")
        return .approve
    }
)

let codex = try await Codex(config: config)
```

`baseURL` is serialized into the process config as `openai_base_url`. Thread-level config overrides are sent as JSON-RPC request params.

Thread options:

```swift
let thread = try await codex.startThread(options: .init(
    approvalPolicy: .onRequest,
    cwd: "/path/to/repo",
    model: "gpt-5-codex",
    sandbox: .workspaceWrite
))
```

Turn options with an output schema:

```swift
let schema: JSONObject = [
    "type": .string("object"),
    "properties": .object([
        "summary": .object(["type": .string("string")]),
        "status": .object([
            "type": .string("string"),
            "enum": .array([.string("ok"), .string("action_required")]),
        ]),
    ]),
    "required": .array([.string("summary"), .string("status")]),
    "additionalProperties": .bool(false),
]

let result = try await thread.run(
    "Summarize the repository status.",
    options: .init(
        effort: .high,
        outputSchema: schema,
        summary: .concise
    )
)
```

## Low-Level RPC Client

`CodexRPCClient` exposes the raw JSON-RPC method surface with typed request and response models. With the `Codex` product it uses a local stdio app-server transport; with `CodexBridgeClient` it uses the HTTP bridge transport:

```swift
let client = CodexRPCClient(config: .init())
let initialize = try await client.initialize()
print(initialize.serverInfo?.name ?? "")

let started = try await client.threadStart(options: .init(model: "gpt-5-codex"))
let listed = try await client.threadList()
let read = try await client.threadRead(threadID: started.thread.id, includeTurns: true)
let models = try await client.modelList()

print(listed.data.count)
print(read.thread.id)
print(models.data.map(\.id))

await client.close()
```

`Codex` and `CodexRPCClient` both accept a `swift-log` `Logger`. If you omit it, they use `Codex.defaultLogger()` with the label `swift-codex`.

`swift-codex` does not call `LoggingSystem.bootstrap(...)` for you. Applications and test executables should bootstrap their preferred `swift-log` backend at process startup when they want logs routed to a specific sink.

Known inbound approval requests are modeled as:

- `ServerRequest.commandApproval`
- `ServerRequest.fileChangeApproval`

Unknown request methods fall back to:

- `ServerRequest.unknown(method:params:)`

## Generated Models

Generated protocol models live in:

- [`Sources/CodexCore/RPCModels/Generated`](Sources/CodexCore/RPCModels/Generated)
- [`Sources/CodexCore/GeneratedModelSupport.swift`](Sources/CodexCore/GeneratedModelSupport.swift)

The generator writes one Swift file per generated type plus [`CodexNotificationPayload.swift`](Sources/CodexCore/RPCModels/Generated/CodexNotificationPayload.swift) so the model layer stays editor-friendly.

Regenerate them with:

```bash
python3 Scripts/generate_app_server_v2.py
```

Forward-compatibility hooks:

- `rawJSON` on generated models and enums
- `additionalFields` on object models
- `.unknown(JSONValue)` on generated unions

## Examples

A standalone example package lives in [`Examples`](Examples):

```bash
cd Examples
swift build
swift run basic-example
```

The example demonstrates startup, approvals, thread list/read, and streamed notifications using the current RPC API.

## Testing

Run the package tests:

```bash
swift test
```

The suite uses `swift-testing` and a stub `codex` binary that simulates the JSON-RPC app-server protocol.

## Repository Layout

- [`Sources/CodexCore`](Sources/CodexCore): subprocess-free shared SDK API, RPC client, config, JSON model support, and generated protocol models
- [`Sources/Codex`](Sources/Codex): macOS local subprocess transport and `Codex` product re-export
- [`Sources/CodexBridgeClient`](Sources/CodexBridgeClient): HTTP bridge client transport and `CodexBridgeClient` product re-export
- [`Sources/CodexBridge`](Sources/CodexBridge): Hummingbird HTTP bridge executable for remote clients
- [`Tests/CodexTests`](Tests/CodexTests): tests and stub transport harness
- [`Scripts/generate_app_server_v2.py`](Scripts/generate_app_server_v2.py): typed model generator
- [`Scripts/run_codex_bridge_tailscale.sh`](Scripts/run_codex_bridge_tailscale.sh): local bridge launcher and Tailscale Serve helper
- [`Examples`](Examples): executable example package
- [`AGENTS.md`](AGENTS.md): repository instructions for coding agents
