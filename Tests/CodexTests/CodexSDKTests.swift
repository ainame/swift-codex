import Foundation
import Testing
@testable import Codex

@Suite(.serialized)
struct CodexSDKTests {
    @Test
    func runReturnsBufferedResultAndThreadID() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureInvocation(0, outputLines: [
            threadStarted("thread_1"),
            turnStarted(),
            reasoningMessage(text: "Inspecting"),
            assistantMessage(text: "Hi!"),
            turnCompleted(),
        ])

        let client = Codex(options: stub.explicitOptions())
        let thread = client.startThread()
        let result = try await thread.run("Hello, world!")

        #expect(await thread.id == "thread_1")
        #expect(result.finalResponse == "Hi!")
        #expect(result.usage == Usage(inputTokens: 42, cachedInputTokens: 12, outputTokens: 5))
        #expect(result.items.count == 2)
        #expect(Array(try stub.arguments(forInvocation: 0).prefix(2)) == ["exec", "--experimental-json"])
    }

    @Test
    func runStreamedYieldsTypedEventsInOrder() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureInvocation(0, outputLines: [
            threadStarted("thread_stream"),
            turnStarted(),
            assistantMessage(text: "Streaming"),
            turnCompleted(),
        ])

        let client = Codex(options: stub.explicitOptions())
        let thread = client.startThread()
        let stream = await thread.runStreamed("Describe")

        var events: [ThreadEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 4)
        #expect(await thread.id == "thread_stream")
        if case .threadStarted(let started) = try #require(events.first) {
            #expect(started.threadID == "thread_stream")
        } else {
            Issue.record("First event should be thread.started")
        }
    }

    @Test
    func structuredInputImagesAndResumeAreForwarded() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureInvocation(0, outputLines: [
            threadStarted("resume_me"),
            turnStarted(),
            assistantMessage(text: "First"),
            turnCompleted(),
        ])
        try stub.configureInvocation(1, outputLines: [
            turnStarted(),
            assistantMessage(text: "Second"),
            turnCompleted(),
        ])

        let client = Codex(options: stub.explicitOptions())
        let thread = client.startThread(options: ThreadOptions(
            model: "gpt-test",
            sandboxMode: .workspaceWrite,
            additionalDirectories: ["../backend", "/tmp/shared"]
        ))

        let firstInput: [UserInput] = [
            .text("Describe file changes"),
            .text("Focus on tests"),
            .localImage(path: "/tmp/one.png"),
            .localImage(path: "/tmp/two.jpg"),
        ]
        _ = try await thread.run(firstInput)
        let secondInput: [UserInput] = [
            .text("Continue"),
            .localImage(path: "/tmp/three.png"),
        ]
        _ = try await thread.run(secondInput)

        #expect(try stub.input(forInvocation: 0) == "Describe file changes\n\nFocus on tests")
        let firstArgs = try stub.arguments(forInvocation: 0)
        #expect(firstArgs.contains("--model"))
        #expect(firstArgs.contains("gpt-test"))
        #expect(firstArgs.contains("--sandbox"))
        #expect(firstArgs.contains("workspace-write"))
        #expect(firstArgs.filter { $0 == "--add-dir" }.count == 2)

        let imageIndices = firstArgs.enumerated().compactMap { index, value in
            value == "--image" ? index : nil
        }
        #expect(imageIndices.count == 2)
        #expect(firstArgs[imageIndices[0] + 1] == "/tmp/one.png")
        #expect(firstArgs[imageIndices[1] + 1] == "/tmp/two.jpg")

        let secondArgs = try stub.arguments(forInvocation: 1)
        let resumeIndex = try #require(secondArgs.firstIndex(of: "resume"))
        #expect(secondArgs[resumeIndex + 1] == "resume_me")
        let resumedImageIndex = try #require(secondArgs.firstIndex(of: "--image"))
        #expect(resumeIndex < resumedImageIndex)
        #expect(secondArgs[resumedImageIndex + 1] == "/tmp/three.png")
    }

    @Test
    func configOverridesThreadFlagsSchemaAndWorkingDirectoryAreApplied() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureInvocation(0, outputLines: [
            threadStarted("thread_cfg"),
            assistantMessage(text: "Configured"),
            turnCompleted(),
        ])

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-codex-working-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let client = Codex(options: stub.explicitOptions(config: [
            "approval_policy": "never",
            "sandbox_workspace_write": ["network_access": true],
            "retry_budget": 3,
            "tool_rules": ["allow": ["git status", "git diff"]],
        ]))

        let thread = client.startThread(options: ThreadOptions(
            workingDirectory: workingDirectory.path(),
            skipGitRepoCheck: true,
            modelReasoningEffort: .high,
            networkAccessEnabled: true,
            webSearchMode: .cached,
            approvalPolicy: .onRequest
        ))
        let schema: JSONObject = [
            "type": "object",
            "properties": [
                "answer": ["type": "string"],
            ],
            "required": ["answer"],
            "additionalProperties": false,
        ]
        _ = try await thread.run("Configured", options: TurnOptions(outputSchema: schema))

        let args = try stub.arguments(forInvocation: 0)
        let approvalValues = collectConfigValues(args: args, key: "approval_policy")
        #expect(approvalValues == [#"approval_policy="never""#, #"approval_policy="on-request""#])
        #expect(args.contains("--skip-git-repo-check"))
        #expect(args.contains("--cd"))
        #expect(args.contains(workingDirectory.path()))
        #expect(args.contains("--output-schema"))
        #expect(args.contains(#"model_reasoning_effort="high""#))
        #expect(args.contains("sandbox_workspace_write.network_access=true"))
        #expect(args.contains(#"web_search="cached""#))
        let actualWorkingDirectory = try URL(fileURLWithPath: stub.workingDirectory(forInvocation: 0))
            .resolvingSymlinksInPath()
            .path()
        let expectedWorkingDirectory = workingDirectory.resolvingSymlinksInPath().path()
        #expect(actualWorkingDirectory == expectedWorkingDirectory)

        let schemaIndex = try #require(args.firstIndex(of: "--output-schema"))
        let schemaPath = args[schemaIndex + 1]
        #expect(!FileManager.default.fileExists(atPath: schemaPath))
    }

    @Test
    func environmentOverrideAndPathLookupWork() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureInvocation(0, outputLines: [
            threadStarted("thread_env"),
            assistantMessage(text: "Env"),
            turnCompleted(),
        ])
        setenv("CODEX_ENV_SHOULD_NOT_LEAK", "leak", 1)
        defer { unsetenv("CODEX_ENV_SHOULD_NOT_LEAK") }

        let environment = [
            "PATH": stub.rootURL.path(),
            "CUSTOM_ENV": "custom",
        ]
        let client = Codex(options: stub.pathLookupOptions(environment: environment))
        let thread = client.startThread()
        _ = try await thread.run("From PATH")

        let env = try stub.environment(forInvocation: 0)
        #expect(env["CUSTOM_ENV"] == "custom")
        #expect(env["CODEX_ENV_SHOULD_NOT_LEAK"] == "")
        #expect(env["OPENAI_BASE_URL"] == "https://example.test")
        #expect(env["CODEX_API_KEY"] == "test-key")
        #expect(env["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] == "codex_sdk_swift")
    }

    @Test
    func processFailureAndTurnFailureThrow() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureInvocation(0, outputLines: [], exitCode: 2, stderr: "boom")
        try stub.configureInvocation(1, outputLines: [
            threadStarted("thread_fail"),
            turnFailed("rate limit exceeded"),
        ])

        let client = Codex(options: stub.explicitOptions())
        let thread = client.startThread()

        await #expect(throws: Error.self) {
            _ = try await thread.run("boom")
        }

        let resumed = client.startThread()
        await #expect(throws: Error.self) {
            _ = try await resumed.run("turn failure")
        }
    }
}

private func collectConfigValues(args: [String], key: String) -> [String] {
    var values: [String] = []
    for index in args.indices where args[index] == "--config" {
        let valueIndex = index + 1
        if valueIndex < args.count, args[valueIndex].hasPrefix("\(key)=") {
            values.append(args[valueIndex])
        }
    }
    return values
}
