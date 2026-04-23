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
    func threadResponsesDecodeInstructionSourcesAndForkMetadata() throws {
        var startRaw = appServerThreadStartResponse(id: "thread_start_paths")
        startRaw["instructionSources"] = .array([
            .string("/tmp/project/AGENTS.md"),
            .string("/tmp/project/.codex/agents.md"),
        ])
        if var thread = startRaw["thread"]?.objectValue {
            thread["forkedFromId"] = .string("thread_parent")
            startRaw["thread"] = .object(thread)
        }

        let start = try decodeJSONValue(ThreadStartResponse.self, from: .object(startRaw))
        #expect(start.instructionSources == [
            AbsolutePathBuf(rawValue: "/tmp/project/AGENTS.md"),
            AbsolutePathBuf(rawValue: "/tmp/project/.codex/agents.md"),
        ])
        #expect(start.thread.forkedFromId == "thread_parent")

        let resumed = try decodeJSONValue(ThreadResumeResponse.self, from: .object(startRaw))
        #expect(resumed.instructionSources == [
            AbsolutePathBuf(rawValue: "/tmp/project/AGENTS.md"),
            AbsolutePathBuf(rawValue: "/tmp/project/.codex/agents.md"),
        ])

        let forked = try decodeJSONValue(ThreadForkResponse.self, from: .object(startRaw))
        #expect(forked.instructionSources == [
            AbsolutePathBuf(rawValue: "/tmp/project/AGENTS.md"),
            AbsolutePathBuf(rawValue: "/tmp/project/.codex/agents.md"),
        ])
    }

    @Test
    func guardianApprovalReviewNotificationsDecodeLatestFields() throws {
        let notification = CodexNotification(
            method: "item/autoApprovalReview/completed",
            params: .object([
                "action": .object([
                    "type": .string("command"),
                    "command": .string("git status"),
                    "cwd": .string("/tmp/project"),
                    "source": .string("shell"),
                ]),
                "decisionSource": .string("agent"),
                "review": .object([
                    "status": .string("approved"),
                    "riskLevel": .string("medium"),
                    "rationale": .string("Requires confirmation"),
                    "userAuthorization": .string("medium"),
                ]),
                "reviewId": .string("review_123"),
                "targetItemId": .string("item_123"),
                "threadId": .string("thread_guardian"),
                "turnId": .string("turn_guardian"),
            ])
        )

        if case .itemGuardianApprovalReviewCompleted(let payload) = notification.payload {
            #expect(payload.decisionSource == .agent)
            #expect(payload.reviewId == "review_123")
            #expect(payload.targetItemId == "item_123")
            #expect(payload.review.userAuthorization == .medium)
            if case .command(let action) = payload.action {
                #expect(action.cwd == AbsolutePathBuf(rawValue: "/tmp/project"))
                #expect(action.command == "git status")
                #expect(action.source == .shell)
            } else {
                Issue.record("Expected command guardian review action")
            }
        } else {
            Issue.record("Expected guardian approval review completed payload")
        }
        #expect(notification.threadID == "thread_guardian")
        #expect(notification.turnID == "turn_guardian")
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
    func latestKnownNotificationPayloadsDecodeFromRegistry() throws {
        let fsChanged = CodexNotification(
            method: "fs/changed",
            params: .object([
                "changedPaths": .array([.string("/tmp/project/file.txt")]),
                "watchId": .string("watch_123"),
            ])
        )
        if case .fsChanged(let payload) = fsChanged.payload {
            #expect(payload.changedPaths.map(\.rawValue) == ["/tmp/project/file.txt"])
            #expect(payload.watchId == "watch_123")
        } else {
            Issue.record("Expected fs/changed payload")
        }
        #expect(fsChanged.threadID == nil)

        let mcpStatus = CodexNotification(
            method: "mcpServer/startupStatus/updated",
            params: .object([
                "name": .string("linear"),
                "status": .string("ready"),
            ])
        )
        if case .mcpServerStatusUpdated(let payload) = mcpStatus.payload {
            #expect(payload.name == "linear")
            #expect(payload.status == .ready)
        } else {
            Issue.record("Expected mcpServer/startupStatus/updated payload")
        }

        let transcriptDelta = CodexNotification(
            method: "thread/realtime/transcript/delta",
            params: .object([
                "delta": .string("Partial "),
                "role": .string("assistant"),
                "threadId": .string("thread_realtime"),
            ])
        )
        if case .threadRealtimeTranscriptDelta(let payload) = transcriptDelta.payload {
            #expect(payload.role == "assistant")
            #expect(payload.delta == "Partial ")
            #expect(payload.threadId == "thread_realtime")
        } else {
            Issue.record("Expected thread/realtime/transcript/delta payload")
        }
        #expect(transcriptDelta.threadID == "thread_realtime")

        let transcriptDone = CodexNotification(
            method: "thread/realtime/transcript/done",
            params: .object([
                "role": .string("assistant"),
                "text": .string("Partial transcript"),
                "threadId": .string("thread_realtime"),
            ])
        )
        if case .threadRealtimeTranscriptDone(let payload) = transcriptDone.payload {
            #expect(payload.role == "assistant")
            #expect(payload.text == "Partial transcript")
            #expect(payload.threadId == "thread_realtime")
        } else {
            Issue.record("Expected thread/realtime/transcript/done payload")
        }

        let realtimeSdp = CodexNotification(
            method: "thread/realtime/sdp",
            params: .object([
                "sdp": .string("v=0"),
                "threadId": .string("thread_realtime"),
            ])
        )
        if case .threadRealtimeSdp(let payload) = realtimeSdp.payload {
            #expect(payload.sdp == "v=0")
            #expect(payload.threadId == "thread_realtime")
        } else {
            Issue.record("Expected thread/realtime/sdp payload")
        }
    }

    @Test
    func latestPlanTypesRoundTrip() throws {
        let prolite = try decodeJSONValue(
            PlanType.self,
            from: .string("prolite")
        )
        #expect(prolite == .prolite)
        #expect(prolite.rawJSON == .string("prolite"))

        let selfServe = try decodeJSONValue(
            PlanType.self,
            from: .string("self_serve_business_usage_based")
        )
        #expect(selfServe == .selfServeBusinessUsageBased)
        #expect(selfServe.rawJSON == .string("self_serve_business_usage_based"))

        let enterpriseUsageBased = try decodeJSONValue(
            PlanType.self,
            from: .string("enterprise_cbp_usage_based")
        )
        #expect(enterpriseUsageBased == .enterpriseCbpUsageBased)
        #expect(enterpriseUsageBased.rawJSON == .string("enterprise_cbp_usage_based"))
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
            sandbox: .workspaceWrite,
            sessionStartSource: .startup
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
        #expect(threadStartParams["sessionStartSource"] == .string("startup"))
        await codex.close()
    }

    @Test
    func threadListSerializesSortDirection() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadListResponses: [appServerThreadListResponse(threads: [makeThread(id: "thread_sorted")])]
        ))

        let client = CodexRPCClient(config: stub.makeConfig())
        _ = try await client.initialize()

        let response = try await client.threadList(options: .init(
            searchTerm: "needle",
            sortDirection: .asc,
            sortKey: .updatedAt
        ))
        #expect(response.data.map(\.id) == ["thread_sorted"])

        let params = try #require(
            try stub.appServerMessages(forInvocation: 0)
                .first { $0.stringValue(forKey: "method") == "thread/list" }?
                .objectValue(forKey: "params")
        )
        #expect(params["searchTerm"] == .string("needle"))
        #expect(params["sortDirection"] == .string("asc"))
        #expect(params["sortKey"] == .string("updated_at"))
        await client.close()
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
