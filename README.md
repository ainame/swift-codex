# swift-codex

Swift SDK for the [`codex`](https://github.com/openai/codex) CLI.

This project ports the TypeScript Codex SDK in [`openai/codex/sdk/typescript`](https://github.com/openai/codex/tree/main/sdk/typescript) to Swift. It stays intentionally thin: it spawns the `codex` CLI with `swift-subprocess`, exchanges JSONL events over stdin/stdout, and exposes a Swift-first API for threads, turns, and streamed events.

## Attribution

This project derives part of its design and implementation from the OpenAI Codex repository, especially the TypeScript SDK in [`openai/codex/sdk/typescript`](https://github.com/openai/codex/tree/main/sdk/typescript), which is licensed under Apache License 2.0.

See [`NOTICE`](NOTICE) and [`LICENSE`](LICENSE) for attribution and license details.

## Status

Current implementation includes:

- `Codex` client with `startThread()` and `resumeThread(id:)`
- buffered `run()` and streamed `runStreamed()`
- typed thread events and items
- structured input with text and local images
- output schema temp-file forwarding
- config override flattening to CLI `--config key=value`
- explicit CLI path override or `PATH` lookup
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
    .package(url: "https://github.com/ainame/swift-codex.git", from: "0.1.0")
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

## Testing

Run the main package tests:

```bash
swift test
```

The test suite uses `swift-testing` and a stub `codex` executable to verify CLI arguments, environment handling, schema cleanup, thread resume behavior, streamed events, and failure propagation.

## Repository Layout

- [`Sources/Codex`](Sources/Codex): SDK implementation
- [`Tests/CodexTests`](Tests/CodexTests): parity-focused tests and stub CLI harness
- [`Examples`](Examples): standalone executable examples package
- [`AGENTS.md`](AGENTS.md): repository instructions for coding agents
