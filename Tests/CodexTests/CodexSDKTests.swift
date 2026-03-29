import Darwin
import Foundation
import Testing
@testable import Codex

@Suite(.serialized)
struct CodexSDKTests {
    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    @Test
    func typedModelsPreserveAdditionalFieldsAndRoundTrip() throws {
        var raw = jsonObject(makeThread(id: "thread_extra"))
        raw["futureField"] = JSONValue.string("future")

        let decoded = try decodeJSONValue(Thread.self, from: .object(raw))
        #expect(decoded.additionalFields["futureField"] == JSONValue.string("future"))
        #expect(decoded.rawJSON.objectValue?["futureField"] == JSONValue.string("future"))
    }

    @Test
    func unionModelsDecodeUnknownFallback() throws {
        let unknownItem = try decodeJSONValue(ThreadItem.self, from: .number(1))
        if case .unknown(let rawJSON) = unknownItem {
            #expect(rawJSON == .number(1))
        } else {
            Issue.record("Expected ThreadItem.unknown")
        }

        let unknownStatus = try decodeJSONValue(ThreadStatus.self, from: .number(2))
        if case .unknown(let rawJSON) = unknownStatus {
            #expect(rawJSON == .number(2))
        } else {
            Issue.record("Expected ThreadStatus.unknown")
        }

        let unknownSource = try decodeJSONValue(
            SessionSource.self,
            from: .object([
                "mystery": .string("source"),
            ])
        )
        if case .unknown(let rawJSON) = unknownSource {
            #expect(rawJSON.objectValue?["mystery"] == .string("source"))
        } else {
            Issue.record("Expected SessionSource.unknown")
        }

        let unknownPhase = try decodeJSONValue(MessagePhase.self, from: .string("side_channel"))
        if case .unknown(let rawJSON) = unknownPhase {
            #expect(rawJSON == .string("side_channel"))
        } else {
            Issue.record("Expected MessagePhase.unknown")
        }
    }

    @Test
    func threadResponsesDefaultMissingApprovalsReviewerForOlderRuntimes() throws {
        var startRaw = appServerThreadStartResponse(id: "thread_start_compat")
        startRaw.removeValue(forKey: "approvalsReviewer")
        let start = try decodeJSONValue(ThreadStartResponse.self, from: .object(startRaw))
        #expect(start.approvalsReviewer == .user)

        var resumeRaw = appServerThreadResumeResponse(id: "thread_resume_compat")
        resumeRaw.removeValue(forKey: "approvalsReviewer")
        let resume = try decodeJSONValue(ThreadResumeResponse.self, from: .object(resumeRaw))
        #expect(resume.approvalsReviewer == .user)

        var forkRaw = appServerThreadForkResponse(id: "thread_fork_compat")
        forkRaw.removeValue(forKey: "approvalsReviewer")
        let fork = try decodeJSONValue(ThreadForkResponse.self, from: .object(forkRaw))
        #expect(fork.approvalsReviewer == .user)
    }

    @Test
    func threadDefaultsMissingEphemeralForOlderRuntimes() throws {
        var raw = jsonObject(makeThread(id: "thread_ephemeral_compat"))
        raw.removeValue(forKey: "ephemeral")

        let decoded = try decodeJSONValue(Thread.self, from: .object(raw))
        #expect(decoded.ephemeral == false)
    }

    @Test
    func threadDefaultsMissingStatusForOlderRuntimes() throws {
        var raw = jsonObject(makeThread(id: "thread_status_compat"))
        raw.removeValue(forKey: "status")

        let decoded = try decodeJSONValue(Thread.self, from: .object(raw))
        if case .idle(let payload) = decoded.status {
            #expect(payload.type == .idle)
        } else {
            Issue.record("Expected missing thread status to default to idle")
        }
    }

    @Test
    func unknownNotificationFallbackStillExtractsMetadata() {
        let notification = CodexNotification(
            method: "future/event",
            params: .object([
                "threadId": .string("thread_future"),
                "turn": .object([
                    "id": .string("turn_future"),
                ]),
            ])
        )

        #expect(notification.threadID == "thread_future")
        #expect(notification.turnID == "turn_future")
        if case .unknown(let method, let rawJSON) = notification.payload {
            #expect(method == "future/event")
            #expect(rawJSON.objectValue?["threadId"] == .string("thread_future"))
        } else {
            Issue.record("Expected unknown payload")
        }
    }

    @Test
    func retryOnOverloadRetriesUntilSuccess() async throws {
        actor AttemptCounter {
            var value = 0

            func next() -> Int {
                value += 1
                return value
            }

            func current() -> Int {
                value
            }
        }

        let attempts = AttemptCounter()

        let value = try await retryOnOverload(
            maxAttempts: 3,
            initialDelaySeconds: 0,
            maxDelaySeconds: 0
        ) {
            let attempt = await attempts.next()
            if attempt < 3 {
                throw CodexError.serverBusy(message: "busy", data: nil)
            }
            return "ok"
        }

        #expect(value == "ok")
        #expect(await attempts.current() == 3)
    }

    @Test
    func pathLookupAndConfigSerializationUseRPCTransport() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_env")]
        ))
        setenv("CODEX_ENV_SHOULD_NOT_LEAK", "leak", 1)
        defer { unsetenv("CODEX_ENV_SHOULD_NOT_LEAK") }

        let environment = [
            "PATH": "\(stub.rootURL.path()):/usr/bin:/bin:/usr/sbin:/sbin",
            "CUSTOM_ENV": "custom",
        ]

        let codex = try await Codex(config: stub.makePathLookupConfig(
            environment: environment,
            workingDirectory: stub.rootURL.path()
        ))
        _ = try await codex.startThread(options: ThreadOptions(
            approvalPolicy: .onRequest,
            config: [
                "custom_override": .string("enabled"),
            ],
            cwd: "/tmp/workspace",
            model: "gpt-test",
            sandbox: .workspaceWrite
        ))

        let env = try stub.environment(forInvocation: 0)
        let args = try stub.arguments(forInvocation: 0)
        let processWorkingDirectory = try stub.workingDirectory(forInvocation: 0)
        let messages = try stub.appServerMessages(forInvocation: 0)
        #expect(env["CUSTOM_ENV"] == "custom")
        #expect(env["CODEX_ENV_SHOULD_NOT_LEAK"] == "")
        #expect(env["CODEX_API_KEY"] == "test-key")
        #expect(env["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] == "codex_sdk_swift")
        #expect(Array(args.prefix(3)) == ["app-server", "--listen", "stdio://"])
        #expect(args.contains("--config"))
        #expect(args.contains(#"openai_base_url="https:\/\/example.test""#))
        #expect(normalizedPath(processWorkingDirectory) == normalizedPath(stub.rootURL.path()))

        let threadStartParams = try #require(
            messages.first { $0.stringValue(forKey: "method") == "thread/start" }?.objectValue(forKey: "params")
        )
        #expect(threadStartParams.objectValue(forKey: "config")?["custom_override"] == .string("enabled"))
        await codex.close()
    }

    @Test
    func launchArgsOverrideTakesPrecedence() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_override")]
        ))

        let config = stub.makeConfig(
            launchArgsOverride: [stub.executableURL.path(), "app-server", "--listen", "stdio://", "--custom-flag"],
            workingDirectory: stub.rootURL.path()
        )

        let codex = try await Codex(config: config)
        _ = try await codex.startThread()

        let args = try stub.arguments(forInvocation: 0)
        let processWorkingDirectory = try stub.workingDirectory(forInvocation: 0)
        #expect(args == ["app-server", "--listen", "stdio://", "--custom-flag"])
        #expect(normalizedPath(processWorkingDirectory) == normalizedPath(stub.rootURL.path()))
        await codex.close()
    }
}
