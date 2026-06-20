import Testing
@testable import Codex

@Suite(.serialized)
struct AppServerSDKTests {
    @Test
    func codexInitializesAndStreamsTypedNotifications() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_app")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_app")],
            turnStartSequences: [[
                .notification(method: "thread/started", params: appServerThreadStarted(threadID: "thread_app")),
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_app", turnID: "turn_app")),
                .notification(
                    method: "item/completed",
                    params: appServerItemCompleted(
                        threadID: "thread_app",
                        turnID: "turn_app",
                        item: appServerAgentMessageItem(text: "Done")
                    )
                ),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_app", turnID: "turn_app")),
            ]]
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let metadata = await codex.metadata()
        #expect(metadata.serverInfo?.name == "codex")
        #expect(metadata.serverInfo?.version == "test")

        let thread = try await codex.startThread()
        let handle = try await thread.turn("Hello")
        let stream = try await handle.stream()

        var methods: [String] = []
        var threadIDs: [String?] = []
        var turnIDs: [String?] = []
        for try await notification in stream {
            methods.append(notification.method)
            threadIDs.append(notification.threadID)
            turnIDs.append(notification.turnID)
        }

        #expect(methods == ["thread/started", "turn/started", "item/completed", "turn/completed"])
        #expect(threadIDs == ["thread_app", "thread_app", "thread_app", "thread_app"])
        #expect(turnIDs == [nil, "turn_app", "turn_app", "turn_app"])
        await codex.close()
    }

    @Test
    func convenienceInitializersUseDefaultLogger() async throws {
        TestLogging.install()
        let stub = try CodexStub()
        defer { stub.cleanup() }

        let client = CodexRPCClient(config: stub.makeConfig())
        _ = try await client.initialize()
        await client.close()

        let entries = TestLogging.recorder.entries()
        #expect(entries.contains { $0.label == "swift-codex" && $0.message == "Initializing Codex RPC client" })
        #expect(entries.contains { $0.label == "swift-codex" && $0.message == "Initialized Codex RPC client" })
    }

    @Test
    func cleanCloseDoesNotLogErrors() async throws {
        TestLogging.install()
        let stub = try CodexStub()
        defer { stub.cleanup() }

        let client = CodexRPCClient(config: stub.makeConfig())
        _ = try await client.initialize()
        await client.close()

        let entries = TestLogging.recorder.entries()
        #expect(!entries.contains { $0.level == .error })
    }

    @Test
    func explicitLoggerKeepsNotificationLevelsSelective() async throws {
        TestLogging.install()
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_levels")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_levels")],
            turnStartSequences: [[
                .notification(method: "item/started", params: appServerItemStarted(
                    threadID: "thread_levels",
                    turnID: "turn_levels",
                    item: appServerAgentMessageItem(id: "msg_started", text: "Interim", phase: .commentary)
                )),
                .notification(method: "item/completed", params: appServerItemCompleted(
                    threadID: "thread_levels",
                    turnID: "turn_levels",
                    item: appServerAgentMessageItem(text: "Interim", phase: .commentary)
                )),
                .notification(method: "turn/completed", params: appServerTurnCompleted(
                    threadID: "thread_levels",
                    turnID: "turn_levels"
                )),
            ]]
        ))

        let logger = Codex.defaultLogger(label: "custom-codex")
        let codex = try await Codex(config: stub.makeConfig(), logger: logger)
        let thread = try await codex.startThread()
        _ = try await thread.run("Hello")
        await codex.close()

        let entries = TestLogging.recorder.entries()
        #expect(entries.contains {
            $0.label == "custom-codex"
                && $0.level == .debug
                && $0.message == "Received RPC notification"
                && $0.metadata["method"] == "item/started"
                && $0.metadata["item_id"] == "msg_started"
                && $0.metadata["item_type"] == "agentMessage"
        })
        #expect(entries.contains {
            $0.label == "custom-codex"
                && $0.level == .debug
                && $0.message == "Received RPC notification"
                && $0.metadata["method"] == "item/completed"
        })
        #expect(entries.contains {
            $0.label == "custom-codex"
                && $0.level == .debug
                && $0.message == "Received RPC notification"
                && $0.metadata["method"] == "turn/completed"
        })
    }

    @Test
    func runCollectsFinalResponseAndUsage() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_run")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_run")],
            turnStartSequences: [[
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_run", turnID: "turn_run")),
                .notification(
                    method: "item/completed",
                    params: appServerItemCompleted(
                        threadID: "thread_run",
                        turnID: "turn_run",
                        item: appServerAgentMessageItem(text: "Interim", phase: .commentary)
                    )
                ),
                .notification(
                    method: "item/completed",
                    params: appServerItemCompleted(
                        threadID: "thread_run",
                        turnID: "turn_run",
                        item: appServerAgentMessageItem(text: "Final", phase: .finalAnswer)
                    )
                ),
                .notification(
                    method: "thread/tokenUsage/updated",
                    params: appServerThreadTokenUsageUpdated(threadID: "thread_run", turnID: "turn_run")
                ),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_run", turnID: "turn_run")),
            ]]
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let thread = try await codex.startThread()
        let result = try await thread.run("Hello")

        #expect(result.finalResponse == "Final")
        #expect(result.items.count == 2)
        #expect(result.usage?.total.inputTokens == 1)
        #expect(result.usage?.total.outputTokens == 2)
        await codex.close()
    }

    @Test
    func defaultApprovalAcceptsAndUnknownServerRequestsReturnEmptyObject() async throws {
        TestLogging.install()
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_cmd")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_cmd")],
            turnStartSequences: [[
                .request(
                    id: "approval-1",
                    method: "item/commandExecution/requestApproval",
                    params: .object(appServerCommandApprovalParams(
                        threadID: "thread_cmd",
                        turnID: "turn_cmd",
                        itemID: "cmd_1",
                        approvalID: "approval_1",
                        command: "git push",
                        cwd: "/tmp/repo",
                        reason: "requires approval"
                    ))
                ),
                .request(
                    id: "unknown-1",
                    method: "item/tool/requestUserInput",
                    params: .object([
                        "threadId": .string("thread_cmd"),
                        "turnId": .string("turn_cmd"),
                    ])
                ),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_cmd", turnID: "turn_cmd")),
            ]]
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let thread = try await codex.startThread()
        _ = try await thread.run("Approve it")

        let responses = try stub.appServerResponses(forInvocation: 0)
        let approval = try #require(responses.first?.objectValue(forKey: "result"))
        #expect(approval["decision"] == .string("accept"))
        let fallback = try #require(responses.dropFirst().first?.objectValue(forKey: "result"))
        #expect(fallback == [:])

        let entries = TestLogging.recorder.entries()
        #expect(entries.contains {
            $0.level == .info
                && $0.message == "Resolved command approval request"
                && $0.metadata["approval_id"] == "approval_1"
                && $0.metadata["decision"] == "approve"
        })
        #expect(entries.contains {
            $0.level == .warning
                && $0.message == "Returning default empty response for unknown server request"
                && $0.metadata["method"] == "item/tool/requestUserInput"
        })
        #expect(!entries.contains { $0.message.contains("git push") })
        await codex.close()
    }

    @Test
    func lowLevelClientCoversThreadAndModelHelpers() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_start")],
            threadResumeResponses: [appServerThreadResumeResponse(id: "thread_resume")],
            threadListResponses: [appServerThreadListResponse(threads: [makeThread(id: "thread_listed")])],
            threadReadResponses: [appServerThreadReadResponse(thread: makeThread(id: "thread_read", turns: [makeTurn(id: "turn_old")]))],
            threadForkResponses: [appServerThreadForkResponse(id: "thread_fork")],
            threadArchiveResponses: [appServerEmptyResponse()],
            threadUnarchiveResponses: [appServerThreadUnarchiveResponse(id: "thread_unarchived")],
            threadSetNameResponses: [appServerEmptyResponse()],
            threadCompactResponses: [appServerEmptyResponse()],
            modelListResponses: [appServerModelListResponse(models: [makeModel(id: "gpt-5")])],
            accountRateLimitsReadResponses: [appServerAccountRateLimitsReadResponse()],
            accountTokenUsageReadResponses: [appServerAccountTokenUsageReadResponse()],
            skillsExtraRootsSetResponses: [appServerEmptyResponse()]
        ))

        let client = CodexRPCClient(config: stub.makeConfig())
        let initialize = try await client.initialize()
        #expect(initialize.serverInfo?.name == "codex")

        let started = try await client.threadStart(options: .init(model: "gpt-5"))
        #expect(started.thread.id == "thread_start")
        let resumed = try await client.threadResume(threadID: "thread_resume")
        #expect(resumed.thread.id == "thread_resume")
        let listed = try await client.threadList()
        #expect(listed.data.map(\.id) == ["thread_listed"])
        let read = try await client.threadRead(threadID: "thread_read", includeTurns: true)
        #expect(read.thread.turns.map(\.id) == ["turn_old"])
        let forked = try await client.threadFork(threadID: "thread_resume")
        #expect(forked.thread.id == "thread_fork")
        _ = try await client.threadArchive(threadID: "thread_resume")
        let unarchived = try await client.threadUnarchive(threadID: "thread_resume")
        #expect(unarchived.thread.id == "thread_unarchived")
        _ = try await client.threadSetName(threadID: "thread_resume", name: "Renamed")
        _ = try await client.threadCompact(threadID: "thread_resume")
        let models = try await client.modelList()
        #expect(models.data.map(\.id) == ["gpt-5"])
        let rateLimits = try await client.accountRateLimitsRead()
        #expect(rateLimits.rateLimits.individualLimit?.remainingPercent == 42)
        let tokenUsage = try await client.accountTokenUsageRead()
        #expect(tokenUsage.summary.lifetimeTokens == 9000)
        #expect(tokenUsage.dailyUsageBuckets?.first?.tokens == 1200)
        _ = try await client.skillsExtraRootsSet(["/tmp/project/skills", "/tmp/shared/skills"])

        let messages = try stub.appServerMessages(forInvocation: 0)
        let methods = messages.compactMap { $0.stringValue(forKey: "method") }
        #expect(methods == [
            "initialize",
            "initialized",
            "thread/start",
            "thread/resume",
            "thread/list",
            "thread/read",
            "thread/fork",
            "thread/archive",
            "thread/unarchive",
            "thread/name/set",
            "thread/compact/start",
            "model/list",
            "account/rateLimits/read",
            "account/tokenUsage/read",
            "skills/extraRoots/set",
        ])
        let extraRootsParams = try #require(messages.first { $0.stringValue(forKey: "method") == "skills/extraRoots/set" }?.objectValue(forKey: "params"))
        #expect(extraRootsParams["extraRoots"] == .array([
            .string("/tmp/project/skills"),
            .string("/tmp/shared/skills"),
        ]))
        await client.close()
    }

    @Test
    func generatedModelsDecodeRust0137Additions() throws {
        var thread = makeThread(id: "child")
        thread.parentThreadId = "parent"
        #expect(thread.rawJSON.objectValue?["parentThreadId"] == .string("parent"))

        let decodedThread = try decodeJSONValue(Thread.self, from: thread.rawJSON)
        #expect(decodedThread.parentThreadId == "parent")

        let turnsPage = TurnsPage(
            backwardsCursor: "older",
            data: [makeTurn(id: "turn_page")],
            nextCursor: "newer"
        )
        let decodedPage = try decodeJSONValue(TurnsPage.self, from: turnsPage.rawJSON)
        #expect(decodedPage.data.map(\.id) == ["turn_page"])
        #expect(decodedPage.backwardsCursor == "older")
        #expect(decodedPage.nextCursor == "newer")

        let initialTurns = ThreadResumeInitialTurnsPageParams(
            itemsView: .summary,
            limit: 25,
            sortDirection: .asc
        )
        #expect(initialTurns.rawJSON.objectValue?["itemsView"] == .string("summary"))
        #expect(initialTurns.rawJSON.objectValue?["limit"] == .number(25))
        #expect(initialTurns.rawJSON.objectValue?["sortDirection"] == .string("asc"))
    }

    @Test
    func generatedModelsDecodeRust0139Additions() throws {
        let tokenUsage = GetAccountTokenUsageResponse(
            dailyUsageBuckets: [
                AccountTokenUsageDailyBucket(startDate: "2026-06-09", tokens: 321),
            ],
            summary: AccountTokenUsageSummary(lifetimeTokens: 12345)
        )
        let decodedUsage = try decodeJSONValue(GetAccountTokenUsageResponse.self, from: tokenUsage.rawJSON)
        #expect(decodedUsage.dailyUsageBuckets?.first?.startDate == "2026-06-09")
        #expect(decodedUsage.summary.lifetimeTokens == 12345)

        let template = AppTemplateSummary(
            canonicalConnectorId: "connector.slack",
            description: "Slack workspace",
            logoUrl: "https://example.test/light.png",
            logoUrlDark: "https://example.test/dark.png",
            materializedAppIds: ["app.slack"],
            name: "Slack",
            reason: .noActiveWorkspace,
            templateId: "template.slack"
        )
        let decodedTemplate = try decodeJSONValue(AppTemplateSummary.self, from: template.rawJSON)
        #expect(decodedTemplate.materializedAppIds == ["app.slack"])
        #expect(decodedTemplate.reason == .noActiveWorkspace)

    }

    @Test
    func generatedModelsDecodeRust0141Additions() throws {
        let response = ThreadGoalSetResponse(goal: ThreadGoal(
            createdAt: 1,
            objective: "Keep syncing",
            status: .active,
            threadId: "thread_141",
            timeUsedSeconds: 2,
            tokenBudget: 5000,
            tokensUsed: 100,
            updatedAt: 3
        ))
        let decoded = try decodeJSONValue(ThreadGoalSetResponse.self, from: response.rawJSON)
        #expect(decoded.goal.objective == "Keep syncing")
        #expect(decoded.goal.status == .active)
        #expect(decoded.goal.tokenBudget == 5000)
    }

    @Test
    func lowLevelClientSupportsThreadDeleteAndGoals() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        let goal = ThreadGoal(
            createdAt: 1,
            objective: "Ship the sync",
            status: .active,
            threadId: "thread_goal",
            timeUsedSeconds: 0,
            tokenBudget: 4000,
            tokensUsed: 0,
            updatedAt: 1
        )
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadDeleteResponses: [appServerEmptyResponse()],
            threadGoalSetResponses: [jsonObject(ThreadGoalSetResponse(goal: goal))],
            threadGoalGetResponses: [jsonObject(ThreadGoalGetResponse(goal: goal))],
            threadGoalClearResponses: [jsonObject(ThreadGoalClearResponse(cleared: true))]
        ))

        let client = CodexRPCClient(config: stub.makeConfig())
        _ = try await client.initialize()
        let set = try await client.threadGoalSet(
            threadID: "thread_goal",
            objective: "Ship the sync",
            status: .active,
            tokenBudget: 4000
        )
        #expect(set.goal.objective == "Ship the sync")
        #expect(try await client.threadGoalGet(threadID: "thread_goal").goal?.status == .active)
        #expect(try await client.threadGoalClear(threadID: "thread_goal").cleared)
        _ = try await client.threadDelete(threadID: "thread_goal")

        let messages = try stub.appServerMessages(forInvocation: 0)
        let methods = messages.compactMap { $0.stringValue(forKey: "method") }
        #expect(methods == [
            "initialize", "initialized", "thread/goal/set", "thread/goal/get",
            "thread/goal/clear", "thread/delete",
        ])
        let params = try #require(messages.first { $0.stringValue(forKey: "method") == "thread/goal/set" }?.objectValue(forKey: "params"))
        #expect(params["objective"] == .string("Ship the sync"))
        #expect(params["status"] == .string("active"))
        #expect(params["tokenBudget"] == .number(4000))
        await client.close()
    }

    @Test
    func lowLevelClientSupportsPluginList() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            pluginListResponses: [[
                "marketplaces": .array([
                    .object([
                        "name": .string("local"),
                        "path": .string("/tmp/marketplace"),
                        "plugins": .array([]),
                    ]),
                ]),
                "featuredPluginIds": .array([.string("plugin.alpha")]),
                "marketplaceLoadErrors": .array([
                    .object([
                        "marketplacePath": .string("/tmp/broken"),
                        "message": .string("failed to load"),
                    ]),
                ]),
                "remoteSyncError": .string("sync failed"),
            ]]
        ))

        let client = CodexRPCClient(config: stub.makeConfig())
        _ = try await client.initialize()

        let plugins = try await client.pluginList()
        #expect(plugins.marketplaces.map(\.name) == ["local"])
        #expect(plugins.featuredPluginIds == ["plugin.alpha"])
        #expect(plugins.marketplaceLoadErrors?.map(\.message) == ["failed to load"])
        #expect(plugins.additionalFields["remoteSyncError"] == .string("sync failed"))

        let methods = try stub.appServerMessages(forInvocation: 0).compactMap { $0.stringValue(forKey: "method") }
        #expect(methods == ["initialize", "initialized", "plugin/list"])
        await client.close()
    }

    @Test
    func threadStartAcceptsOlderThreadPayloadWithoutEphemeral() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }

        var legacyStart = appServerThreadStartResponse(id: "thread_legacy")
        var legacyThread = try #require(legacyStart.objectValue(forKey: "thread"))
        legacyThread.removeValue(forKey: "ephemeral")
        legacyStart["thread"] = .object(legacyThread)

        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [legacyStart]
        ))

        let client = CodexRPCClient(config: stub.makeConfig())
        let started = try await client.threadStart()

        #expect(started.thread.id == "thread_legacy")
        #expect(started.thread.ephemeral == false)
        await client.close()
    }

    @Test
    func threadStartAcceptsOlderThreadPayloadWithoutStatus() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }

        var legacyStart = appServerThreadStartResponse(id: "thread_legacy_status")
        var legacyThread = try #require(legacyStart.objectValue(forKey: "thread"))
        legacyThread.removeValue(forKey: "status")
        legacyStart["thread"] = .object(legacyThread)

        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [legacyStart]
        ))

        let client = CodexRPCClient(config: stub.makeConfig())
        let started = try await client.threadStart()

        #expect(started.thread.id == "thread_legacy_status")
        if case .idle(let payload) = started.thread.status {
            #expect(payload.type == .idle)
        } else {
            Issue.record("Expected missing thread status to default to idle")
        }
        await client.close()
    }

    @Test
    func turnSteerAndInterruptUseExpectedMethods() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_control")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_control")],
            turnStartSequences: [[]],
            turnSteerResponses: [appServerTurnSteerResponse(turnID: "turn_control")],
            turnInterruptResponses: [appServerEmptyResponse()]
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let thread = try await codex.startThread()
        let handle = try await thread.turn([
            .text("Hello"),
            .image(url: "https://example.test/a.png"),
            .skill(name: "checks", path: "/tmp/checks"),
            .mention(name: "repo", path: "/tmp/repo"),
        ])
        let steer = try await handle.steer(.localImage(path: "/tmp/local.png"))
        #expect(steer.turnId == "turn_control")
        _ = try await handle.interrupt()

        let messages = try stub.appServerMessages(forInvocation: 0)
        let methods = messages.compactMap { $0.stringValue(forKey: "method") }
        #expect(methods == ["initialize", "initialized", "thread/start", "turn/start", "turn/steer", "turn/interrupt"])

        let turnStartInput = try #require(messages.first { $0.stringValue(forKey: "method") == "turn/start" }?.objectValue(forKey: "params")?["input"])
        if case .array(let items) = turnStartInput {
            #expect(items.count == 4)
        } else {
            Issue.record("Expected turn/start input array")
        }

        let steerInput = try #require(messages.first { $0.stringValue(forKey: "method") == "turn/steer" }?.objectValue(forKey: "params")?["input"])
        if case .array(let items) = steerInput {
            #expect(items.count == 1)
            #expect(items.first?.objectValue?["type"] == .string("localImage"))
        } else {
            Issue.record("Expected turn/steer input array")
        }

        await codex.close()
    }

    @Test
    func rejectsConcurrentTurnConsumers() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_concurrent")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_concurrent")],
            turnStartSequences: [[
                .notification(method: "turn/started", params: appServerTurnStarted(threadID: "thread_concurrent", turnID: "turn_concurrent")),
            ]]
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let thread = try await codex.startThread()
        let handle = try await thread.turn("Concurrent")
        let first = try await handle.stream()
        _ = first

        do {
            _ = try await handle.stream()
            Issue.record("Expected concurrent turn consumer rejection")
        } catch let error as CodexError {
            switch error {
            case .concurrentTurnConsumer(let activeTurnID, let requestedTurnID):
                #expect(activeTurnID == "turn_concurrent")
                #expect(requestedTurnID == "turn_concurrent")
            default:
                Issue.record("Expected concurrentTurnConsumer, got \(error)")
            }
        }

        await codex.close()
    }

    @Test
    func initializeClosureIncludesStderrTail() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            initializeCloseStderr: [
                "fatal: initialize failed",
                "hint: app-server exited early",
            ]
        ))

        do {
            _ = try await Codex(config: stub.makeConfig())
            Issue.record("Expected transport closure during initialize")
        } catch let error as CodexError {
            if case .transportClosedWithStderrTail(let stderrTail) = error {
                #expect(stderrTail.contains("fatal: initialize failed"))
                #expect(stderrTail.contains("hint: app-server exited early"))
            } else {
                Issue.record("Expected transportClosedWithStderrTail, got \(error)")
            }
        }
    }

    @Test
    func initializeNormalizesServerMetadataFromUserAgent() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            initializeResult: appServerInitializeResult(
                userAgent: "codex 9.9.9",
                serverName: nil,
                serverVersion: nil
            )
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let metadata = await codex.metadata()
        #expect(metadata.serverInfo?.name == "codex")
        #expect(metadata.serverInfo?.version == "9.9.9")
        await codex.close()
    }

    @Test
    func initializeAcceptsServerInfoWithoutUserAgent() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            initializeResult: appServerInitializeResult(
                userAgent: nil,
                serverName: "codex",
                serverVersion: "10.0.0"
            )
        ))

        let codex = try await Codex(config: stub.makeConfig())
        let metadata = await codex.metadata()
        #expect(metadata.serverInfo?.name == "codex")
        #expect(metadata.serverInfo?.version == "10.0.0")
        #expect(metadata.userAgent == nil)
        await codex.close()
    }

    @Test
    func unknownServerRequestsPreserveNonObjectParamsAndResults() async throws {
        actor RequestRecorder {
            var request: ServerRequest?

            func record(_ request: ServerRequest) {
                self.request = request
            }
        }

        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
            threadStartResponses: [appServerThreadStartResponse(id: "thread_unknown")],
            turnStartResponses: [appServerTurnStartResponse(id: "turn_unknown")],
            turnStartSequences: [[
                .request(
                    id: "unknown-array",
                    method: "host/customRequest",
                    params: .array([.string("first"), .number(2)])
                ),
                .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread_unknown", turnID: "turn_unknown")),
            ]]
        ))

        let recorder = RequestRecorder()
        let config = stub.makeConfig(serverRequestHandler: { request in
            await recorder.record(request)
            return .json(.array([.string("ack"), .bool(true)]))
        })

        let codex = try await Codex(config: config)
        let thread = try await codex.startThread()
        _ = try await thread.run("Hello")

        let request = try #require(await recorder.request)
        switch request {
        case .unknown(let method, let params):
            #expect(method == "host/customRequest")
            #expect(params == .array([.string("first"), .number(2)]))
        default:
            Issue.record("Expected unknown server request")
        }

        let responses = try stub.appServerResponses(forInvocation: 0)
        let result = try #require(responses.first?["result"])
        #expect(result == .array([.string("ack"), .bool(true)]))
        await codex.close()
    }
}
