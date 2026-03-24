# swift-codex

Swift SDK for the [`codex`](https://github.com/openai/codex) CLI.

This project ports the TypeScript Codex SDK in [`openai/codex/sdk/typescript`](https://github.com/openai/codex/tree/main/sdk/typescript) to Swift. It stays intentionally thin: it spawns the `codex` CLI with `swift-subprocess`, exchanges JSONL events over stdin/stdout, and exposes a Swift-first API for threads, turns, and streamed events.

## Attribution

This project derives part of its design and implementation from the OpenAI Codex repository, especially the TypeScript SDK in [`openai/codex/sdk/typescript`](https://github.com/openai/codex/tree/main/sdk/typescript), which is licensed under Apache License 2.0.

See [`NOTICE`](NOTICE), [`LICENSE`](LICENSE), and [`UPSTREAM.md`](UPSTREAM.md) for attribution and upstream reference details.

## Upstream Reference

This repository tracks the TypeScript SDK in [`openai/codex/sdk/typescript`](https://github.com/openai/codex/tree/main/sdk/typescript) by repository commit, not by the moving `main` branch alone.

- Upstream repository: `openai/codex`
- Upstream SDK path: `sdk/typescript`
- Vendored upstream checkout: [`vendor/openai-codex`](vendor/openai-codex)
- Vendored upstream commit: `527244910fb851cea6147334dbc08f8fbce4cb9d`
- Current recorded references:
  - stable `exec` transport: `sdk/typescript` at `3293538e128e02ca24d5e9913af986ac68405b00`
  - experimental app-server transport: `sdk/python/src/codex_app_server` and app-server v2 protocol at `527244910fb851cea6147334dbc08f8fbce4cb9d`

Use [`UPSTREAM.md`](UPSTREAM.md) to distinguish the vendored upstream checkout from the exact commit SHA the Swift port has been reviewed or synced against.

## License

This repository is licensed under Apache License 2.0.

Because this project ports functionality from the OpenAI Codex repository, it preserves Apache-2.0 licensing and repository-level attribution via [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Status

Current implementation includes:

- `Codex` client with `startThread()` and `resumeThread(id:)`
- buffered `run()` and streamed `runStreamed()`
- typed thread events and items
- structured input with text and local images
- output schema temp-file forwarding
- config override flattening to CLI `--config key=value`
- explicit CLI path override or `PATH` lookup
- experimental app-server client that tracks the upstream Python `codex_app_server` SDK
- generated `AppServerV2` protocol wrappers and notification registry
- parity-focused tests with `swift-testing`

Current scope does not include:

- Windows support
- a Swift MCP dependency
- Node/npm-specific binary discovery

## Requirements

- Swift 6.2
- Installed `codex` CLI available on `PATH`, or pass an explicit binary path

Codex CLI installation is external to this package. For example:

```bash
brew install --cask codex
```

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ainame/swift-codex.git", from: "0.0.1")
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

## Quickstart

```swift
import Codex

let codex = Codex()
let thread = codex.startThread()
let turn = try await thread.run("Diagnose the test failure and propose a fix")

print(turn.finalResponse)
print(turn.items)
```

Reuse the same thread to continue the conversation:

```swift
let nextTurn = try await thread.run("Implement the fix")
```

Resume an existing thread by id:

```swift
let resumed = codex.resumeThread(id: "thread_123")
let turn = try await resumed.run("Continue")
```

## Streaming

Use `runStreamed()` when you want incremental progress:

```swift
let stream = await thread.runStreamed("Diagnose the failure")

for try await event in stream {
    switch event {
    case .itemCompleted(let completed):
        print(completed.item)
    case .turnCompleted(let completed):
        print(completed.usage)
    default:
        break
    }
}
```

## Structured Input

Text segments are joined with blank lines. Images are forwarded as repeated `--image` flags:

```swift
let input: [UserInput] = [
    .text("Describe these screenshots"),
    .localImage(path: "/tmp/ui.png"),
    .localImage(path: "/tmp/diagram.jpg"),
]

let turn = try await thread.run(input)
```

## Configuration

Client-wide options:

```swift
let codex = Codex(options: CodexOptions(
    codexPathOverride: "/opt/homebrew/bin/codex",
    baseURL: "https://api.example.test",
    apiKey: "test-key",
    config: [
        "approval_policy": "never",
        "sandbox_workspace_write": [
            "network_access": true,
        ],
    ],
    environment: [
        "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
    ]
))
```

When `baseURL` is set, the SDK passes it through `--config openai_base_url=...`. A custom
`environment` map stays isolated except for required SDK variables such as `CODEX_API_KEY`
and `CODEX_INTERNAL_ORIGINATOR_OVERRIDE`.

Thread options:

```swift
let thread = codex.startThread(options: ThreadOptions(
    model: "gpt-5-codex",
    sandboxMode: .workspaceWrite,
    workingDirectory: "/path/to/repo",
    additionalDirectories: ["/tmp/shared"],
    skipGitRepoCheck: true,
    modelReasoningEffort: .high,
    networkAccessEnabled: true,
    webSearchMode: .cached,
    approvalPolicy: .onRequest
))
```

Turn options with an output schema:

```swift
let schema: JSONObject = [
    "type": "object",
    "properties": [
        "summary": ["type": "string"],
        "status": [
            "type": "string",
            "enum": ["ok", "action_required"],
        ],
    ],
    "required": ["summary", "status"],
    "additionalProperties": false,
]

let turn = try await thread.run(
    "Summarize repository status",
    options: TurnOptions(outputSchema: schema)
)
```

## Examples

A standalone example package lives in [`Examples`](Examples):

```bash
cd Examples
swift build
swift run basic-example
```

It depends on the root package by local path and demonstrates both buffered and streamed execution.

## Experimental App-Server API

`swift-codex` also exposes an experimental JSON-RPC app-server client that tracks the upstream Python `codex_app_server` SDK while keeping the stable `Codex` / `CodexThread` `exec` transport unchanged.

This experimental surface is intentionally separate from the stable `exec` API:

- `AppServerClient`
- `AppServerCodex`
- `AppServerThread`
- `AppServerTurnHandle`
- `AppServerNotification`
- `AppServerV2`
- `CommandApprovalRequest`
- `FileChangeApprovalRequest`
- `ApprovalDecision`

Current app-server coverage includes:

- startup, initialize, and shutdown
- thread start, resume, list, read, fork, archive, unarchive, rename, and compact
- turn start, steer, stream, run, and interrupt
- model listing
- generated notification payload decoding via `AppServerNotification`
- native command and file-change approval requests plus generic server-request handling
- stderr-tail transport diagnostics when the app-server exits early
- retry helpers for overload-style JSON-RPC failures

`AppServerThread.run(...)` returns `AppServerRunResult`, `AppServerTurnHandle.run()` returns `AppServerV2.Turn`, and `AppServerTurnHandle.stream()` yields full typed `AppServerNotification` values.

Approval handlers default to `.approve`, and unknown inbound server requests default to `{}` to match the current Python client behavior:

```swift
let client = try await AppServerCodex(config: AppServerConfig(
    commandApprovalHandler: { request in
        print(request.command ?? "")
        return .approve
    },
    fileChangeApprovalHandler: { request in
        print(request.grantRoot ?? "")
        return .approve
    }
))

let thread = try await client.startThread(options: AppServerThreadOptions(
    model: "gpt-5-codex",
    sandbox: .workspaceWrite,
    cwd: "/path/to/repo",
    approvalPolicy: .mode(.onRequest)
))

let handle = try await thread.turn([
    .text("Inspect the repository and propose a patch"),
    .localImage(path: "/tmp/ui.png"),
], options: AppServerTurnOptions(summary: .concise))

for try await notification in try await handle.stream() {
    print(notification.method)
}

try await handle.interrupt()

let result = try await thread.run("Summarize the approved changes")
print(result.finalResponse ?? "")
```

Only one active turn consumer is supported per `AppServerCodex` instance, matching the current upstream experimental SDK behavior.

Generated `AppServerV2` protocol wrappers live in [`Sources/Codex/AppServerV2.swift`](Sources/Codex/AppServerV2.swift) and [`Sources/Codex/AppServerV2Generated.swift`](Sources/Codex/AppServerV2Generated.swift). Regenerate them with:

```bash
python3 Scripts/generate_app_server_v2.py
```

## Testing

Run the main package tests:

```bash
swift test
```

The test suite uses `swift-testing` and a stub `codex` executable to verify CLI arguments, environment handling, schema cleanup, thread resume behavior, streamed events, and failure propagation.

## Repository Layout

- [`Sources/Codex`](Sources/Codex): SDK implementation
- [`Tests/CodexTests`](Tests/CodexTests): parity-focused tests and stub CLI harness
- [`Scripts/generate_app_server_v2.py`](Scripts/generate_app_server_v2.py): app-server v2 wrapper generator
- [`Examples`](Examples): standalone executable examples package
- [`AGENTS.md`](AGENTS.md): repository instructions for coding agents
