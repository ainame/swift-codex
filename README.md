# swift-codex

Swift SDK for the [`codex`](https://github.com/openai/codex) CLI.

`swift-codex` now uses the Codex JSON-RPC v2 app-server transport exclusively. The SDK starts `codex app-server --listen stdio://`, speaks JSON-RPC over stdio, and exposes both a high-level `Codex` API and a low-level `CodexRPCClient` with typed protocol models generated from the vendored upstream schema.

This repository still exists as a Swift port of the OpenAI Codex SDK work in [`openai/codex`](https://github.com/openai/codex), with upstream attribution and sync notes recorded in [`NOTICE`](NOTICE), [`LICENSE`](LICENSE), and [`UPSTREAM.md`](UPSTREAM.md).

Starting with release `0.130.0`, `swift-codex` version numbers follow the shipped upstream `openai/codex` SDK release number when an upstream sync is released.

## Status

Current implementation includes:

- async `Codex`, `CodexThread`, and `CodexTurnHandle`
- low-level `CodexRPCClient`
- typed generated protocol models such as `Thread`, `Turn`, `ThreadItem`, `ModelListResponse`, `WorkspaceMessage`, and `CodexNotificationPayload`
- thread start, resume, fork, archive, unarchive, rename, compact, list, and read
- thread instruction source metadata, fork/subagent ancestry, multi-cwd list filtering, and typed guardian auto-review payloads from the latest v2 schema
- plugin list retrieval with typed marketplace metadata
- account rate-limit, token-usage, and workspace-message reads plus external-agent import-history reads, thread attachment management, and skills extra-root updates through the low-level RPC client
- turn start, steer, interrupt, buffered run, and streamed notifications
- friendly sandbox presets for thread and turn APIs
- typed goal, model-verification, process, remote-control, moderation-metadata, and guardian-warning notifications from the latest upstream registry
- typed guardian approval actions and collaboration/authentication enum values from the latest reviewed schema
- typed approval handling for command and file-change requests
- experimental client-defined dynamic tools, with function/namespace registration and typed async call handlers
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
- Vendored upstream commit: `83086188ae0614bd882818ff1aa23f3194962012` (`rust-v0.163.0`)
- Primary reviewed upstream basis for the current transport and schema:
  - `sdk/python/src/openai_codex`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

The `rust-v0.163.0` sync adds `ThreadListOptions.excludedThreadIDs` and typed thread read-state notifications, including unread positions and revision tokens. Experimental read-state mutation and item-history read endpoints remain raw-RPC-only; experimental read-state fields on list/read responses remain available through `additionalFields`.

See [`UPSTREAM.md`](UPSTREAM.md) for the exact reviewed files, the raw app-server schema parity target used for this sync, and the remaining schema-only request surfaces not wrapped by the Swift convenience API yet.

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
    .package(url: "https://github.com/ainame/swift-codex.git", from: "0.163.0")
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

## Quickstart

```swift
import Codex

let codex = try await Codex(config: .init())
let thread = try await codex.startThread(options: .init(
    model: "gpt-5-codex",
    sandboxPreset: .workspaceWrite
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
    sandboxPreset: .workspaceWrite,
    sessionStartSource: .startup
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

`Codex` and `CodexRPCClient` both accept a `swift-log` `Logger`. If you omit it, they use `Codex.defaultLogger()` with the label `swift-codex`.

`swift-codex` does not call `LoggingSystem.bootstrap(...)` for you. Applications and test executables should bootstrap their preferred `swift-log` backend at process startup when they want logs routed to a specific sink.

Known inbound approval requests are modeled as:

- `ServerRequest.commandApproval`
- `ServerRequest.fileChangeApproval`

Unknown request methods fall back to:

- `ServerRequest.unknown(method:params:)`

## Client-Defined Tools (Experimental)

Register client tools on a new thread using `ThreadOptions.dynamicTools`, then handle
`item/tool/call` through `CodexConfig.dynamicToolCallHandler`:

```swift
let codex = try await Codex(config: .init(dynamicToolCallHandler: { call in
    guard call.tool == "show_card" else {
        return DynamicToolCallResponse(contentItems: [], success: false)
    }
    // Render call.arguments in your application, on its UI actor if needed.
    return DynamicToolCallResponse(
        contentItems: [.inputText(.init(text: "Card displayed", type: .inputText))],
        success: true
    )
}))
let thread = try await codex.startThread(options: .init(dynamicTools: [
    .function(.init(
        description: "Display a card in the client application",
        inputSchema: ["type": "object", "properties": ["title": ["type": "string"]], "required": ["title"]],
        name: "show_card",
        type: .function
    ))
]))
_ = try await thread.run("Display a card titled Hello")
await codex.close()
```

`show_card` is an application-defined name; the SDK does not render UI itself.
Experimental API negotiation is enabled by default (`experimentalAPI: true`).
Namespaces use `.namespace(...)` with function entries; `deferLoading` controls deferred
exposure and follows upstream constraints. Tools are registered only by `thread/start`;
resume and fork inherit saved definitions and reject a non-nil `dynamicTools` option.
Handlers must be supplied again when connecting to an existing thread.

A custom `serverRequestHandler` takes precedence over specialized handlers and receives
`ServerRequest.dynamicToolCall`. Return `.dynamicToolCall(response)` or `.json(...)`.
Without a handler, the SDK returns a tool failure (`success: false`). Requests preserve
string and integer IDs, arbitrary JSON arguments, and unknown fields. Tool results can
contain text and inline image/audio data URLs; upstream rejects remote image URLs and
non-inline audio URLs. Handlers should complete without awaiting another RPC on the same
client, because server requests currently execute on the transport's input path.

## Generated Models

Generated protocol models live in:

- [`Sources/Codex/RPCModels/Generated`](Sources/Codex/RPCModels/Generated)
- [`Sources/Codex/GeneratedModelSupport.swift`](Sources/Codex/GeneratedModelSupport.swift)

The generator writes one Swift file per generated type plus [`CodexNotificationPayload.swift`](Sources/Codex/RPCModels/Generated/CodexNotificationPayload.swift) so the model layer stays editor-friendly.

Regenerate them with:

```bash
python3 Scripts/generate_app_server_v2.py
```

Audit the complete RPC and experimental-field surface with:

```bash
python3 Scripts/audit_app_server_surface.py > /tmp/swift-codex-surface.md
```

The combined stable schema omits experimental request fields and server requests.
The generator imports the standalone upstream dynamic-tool request/response schemas.
The inventory includes Rust wire declarations and flags source matches for manual
review; generation and source matches do not establish end-to-end support.
See `UPSTREAM.md` for the reviewed coverage and deferred gaps.

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
