# swift-codex

Swift SDK for the [`codex`](https://github.com/openai/codex) CLI.

`swift-codex` now uses the Codex JSON-RPC v2 app-server transport exclusively. The SDK starts `codex app-server --listen stdio://`, speaks JSON-RPC over stdio, and exposes both a high-level `Codex` API and a low-level `CodexRPCClient` with typed protocol models generated from the vendored upstream schema.

This repository still exists as a Swift port of the OpenAI Codex SDK work in [`openai/codex`](https://github.com/openai/codex), with upstream attribution and sync notes recorded in [`NOTICE`](NOTICE), [`LICENSE`](LICENSE), and [`UPSTREAM.md`](UPSTREAM.md).

## Status

Current implementation includes:

- async `Codex`, `CodexThread`, and `CodexTurnHandle`
- low-level `CodexRPCClient`
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
- Vendored upstream commit: `b630ce9a4e754d35a1f33e4366ba638d18626142` (`rust-v0.118.0`)
- Primary reviewed upstream basis for the current transport and schema:
  - `sdk/python/src/codex_app_server`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

See [`UPSTREAM.md`](UPSTREAM.md) for the exact reviewed files and Swift-specific deviations.

## Requirements

- Swift 6.2
- Installed `codex` CLI available on `PATH`, or an explicit binary path in `CodexConfig`

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

Then depend on the `Codex` product:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "Codex", package: "swift-codex"),
    ]
)
```

## CodexBridge

`CodexBridge` is a small TCP bridge that runs `codex app-server --listen stdio://` per connection and forwards line-delimited JSON-RPC.

```bash
swift run CodexBridge --port 31337 --token "$BRIDGE_TOKEN"
```

If you want to reach it from iPhone over Tailscale, expose the local port with `tailscale serve`.

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

`CodexRPCClient` exposes the raw JSON-RPC method surface with typed request and response models:

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

Known inbound approval requests are modeled as:

- `ServerRequest.commandApproval`
- `ServerRequest.fileChangeApproval`

Unknown request methods fall back to:

- `ServerRequest.unknown(method:params:)`

## Generated Models

Generated protocol models live in:

- [`Sources/Codex/RPCModels/Generated`](Sources/Codex/RPCModels/Generated)
- [`Sources/Codex/GeneratedModelSupport.swift`](Sources/Codex/GeneratedModelSupport.swift)

The generator writes one Swift file per generated type plus [`CodexNotificationPayload.swift`](Sources/Codex/RPCModels/Generated/CodexNotificationPayload.swift) so the model layer stays editor-friendly.

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

- [`Sources/Codex`](Sources/Codex): SDK implementation
- [`Tests/CodexTests`](Tests/CodexTests): tests and stub transport harness
- [`Scripts/generate_app_server_v2.py`](Scripts/generate_app_server_v2.py): typed model generator
- [`Examples`](Examples): executable example package
- [`AGENTS.md`](AGENTS.md): repository instructions for coding agents
