import Testing
@testable import Codex

private let commandMethod = "item/commandExecution/requestApproval"
private let fileChangeMethod = "item/fileChange/requestApproval"

private func richCommandParams(itemID: String) -> JSONObject {
    [
        "threadId": "thread", "turnId": "turn", "itemId": .string(itemID), "startedAtMs": 1_790_000_000_123,
        "approvalId": "approval", "command": "git push", "cwd": "/tmp/repo", "reason": "needs network",
        "environmentId": "env-1", "kind": "writeStdin",
        "commandActions": [
            ["type": "read", "command": "cat a", "name": "a", "path": "/tmp/a"],
            ["type": "futureAction", "command": "x", "future": true],
        ],
        "networkApprovalContext": ["host": "example.com", "protocol": "https"],
        "proposedExecpolicyAmendment": ["git", "push"],
        "proposedNetworkPolicyAmendments": [["action": "allow", "host": "example.com"]],
        "additionalPermissions": ["network": ["enabled": true], "fileSystem": ["write": ["/tmp/repo"]]],
        "availableDecisions": [
            "accept", "acceptForSession", "cancel",
            ["acceptWithExecpolicyAmendment": ["execpolicy_amendment": ["git", "push"]]],
        ],
        "future": ["nested": true],
    ]
}

private func richFileChangeParams(itemID: String) -> JSONObject {
    [
        "threadId": "thread", "turnId": "turn", "itemId": .string(itemID), "startedAtMs": 1_790_000_000_456,
        "reason": "write access", "grantRoot": "/tmp/repo", "future": ["nested": true],
    ]
}

private let commandDecisions: [(itemID: String, decision: CommandExecutionApprovalDecision, wire: JSONValue)] = [
    ("accept", .accept, "accept"),
    ("session", .acceptForSession, "acceptForSession"),
    ("decline", .decline, "decline"),
    ("cancel", .cancel, "cancel"),
    ("execpolicy", .acceptWithExecpolicyAmendment(execpolicyAmendment: ["git", "push"]),
     ["acceptWithExecpolicyAmendment": ["execpolicy_amendment": ["git", "push"]]]),
    ("network", .applyNetworkPolicyAmendment(networkPolicyAmendment: NetworkPolicyAmendment(action: .deny, host: "example.com")),
     ["applyNetworkPolicyAmendment": ["network_policy_amendment": ["action": "deny", "host": "example.com"]]]),
]

private let fileChangeDecisions: [(itemID: String, decision: FileChangeApprovalDecision, wire: JSONValue)] = [
    ("accept", .accept, "accept"),
    ("session", .acceptForSession, "acceptForSession"),
    ("decline", .decline, "decline"),
    ("cancel", .cancel, "cancel"),
]

private actor ApprovalRecorder {
    var commandParams: [CommandExecutionRequestApprovalParams] = []
    var fileChangeParams: [FileChangeRequestApprovalParams] = []
    var legacyCommands: [CommandApprovalRequest] = []
    var legacyFileChanges: [FileChangeApprovalRequest] = []
    var generic: [ServerRequest] = []

    func record(_ params: CommandExecutionRequestApprovalParams) { commandParams.append(params) }
    func record(_ params: FileChangeRequestApprovalParams) { fileChangeParams.append(params) }
    func record(_ request: CommandApprovalRequest) { legacyCommands.append(request) }
    func record(_ request: FileChangeApprovalRequest) { legacyFileChanges.append(request) }
    func record(_ request: ServerRequest) { generic.append(request) }
}

private struct ApprovalHandlerFailure: Error, CustomStringConvertible {
    var description: String { "secret-must-not-appear-in-rpc-error" }
}

/// Runs one turn whose script sends `requests`, and returns the replies by ID.
private func runApprovals(
    _ requests: [(id: JSONValue, method: String, params: JSONValue)],
    configure: (inout CodexConfig) -> Void
) async throws -> [JSONValue: JSONObject] {
    let stub = try CodexStub()
    defer { stub.cleanup() }
    try stub.configureAppServerInvocation(0, scenario: AppServerScenario(
        threadStartResponses: [appServerThreadStartResponse(id: "thread")],
        turnStartResponses: [appServerTurnStartResponse(id: "turn")],
        turnStartSequences: [requests.map { .request(id: $0.id, method: $0.method, params: $0.params) } + [
            .notification(method: "turn/completed", params: appServerTurnCompleted(threadID: "thread", turnID: "turn")),
        ]]
    ))
    var config = stub.makeConfig()
    configure(&config)
    let codex = try await Codex(config: config)
    let thread = try await codex.startThread()
    _ = try await thread.run("approve")
    // The transport is still usable after every reply, including failures.
    _ = try await codex.models()
    await codex.close()
    let replies = try stub.appServerResponses(forInvocation: 0)
    #expect(replies.count == requests.count)
    return Dictionary(uniqueKeysWithValues: replies.map { ($0["id"] ?? .null, $0) })
}

struct ApprovalTests {
    @Test(arguments: ["inner", "outer", "network", "unknown"])
    func invalidNestedDecisionFailsOnlyItsRequest(site: String) async throws {
        let replies = try await runApprovals([
            ("bad", commandMethod, .object(richCommandParams(itemID: "bad"))),
            ("good", commandMethod, .object(richCommandParams(itemID: "good"))),
        ]) { config in
            config.commandExecutionRequestApprovalHandler = { params in
                if params.itemId == "good" { return .init(decision: .decline) }
                let invalid: JSONObject = ["invalid": .number(.nan)]
                let decision: CommandExecutionApprovalDecision
                switch site {
                case "inner":
                    decision = .acceptWithExecpolicyAmendment(.init(
                        acceptWithExecpolicyAmendment: .init(execpolicyAmendment: ["git"], additionalFields: invalid)
                    ))
                case "outer":
                    decision = .acceptWithExecpolicyAmendment(.init(
                        acceptWithExecpolicyAmendment: .init(execpolicyAmendment: ["git"]), additionalFields: invalid
                    ))
                case "network":
                    decision = .applyNetworkPolicyAmendment(networkPolicyAmendment: .init(action: .allow, host: "example.test", additionalFields: invalid))
                default: decision = .unknown(.number(.nan))
                }
                return .init(decision: decision)
            }
        }
        #expect(replies["bad"]?["error"]?.objectValue?["code"] == -32603)
        #expect(replies["good"]?["result"] == ["decision": "decline"])
    }

    @Test
    func typedCommandHandlerSendsEveryDecisionVariantWithExactWireKeys() async throws {
        let recorder = ApprovalRecorder()
        let requests = commandDecisions.enumerated().map { index, entry in
            // Alternate string and integer request IDs.
            (id: index.isMultiple(of: 2) ? JSONValue.string("cmd-\(entry.itemID)") : .number(Double(100 + index)),
             method: commandMethod, params: JSONValue.object(richCommandParams(itemID: entry.itemID)))
        }
        let replies = try await runApprovals(requests) { config in
            config.commandApprovalHandler = { _ in
                Issue.record("Simplified handler must not run when a typed handler is set")
                return .deny
            }
            config.commandExecutionRequestApprovalHandler = { params in
                await recorder.record(params)
                let decision = try #require(commandDecisions.first { $0.itemID == params.itemId }).decision
                return CommandExecutionRequestApprovalResponse(decision: decision)
            }
        }
        for (request, entry) in zip(requests, commandDecisions) {
            let reply = try #require(replies[request.id])
            #expect(reply["result"] == ["decision": entry.wire])
            #expect(reply["error"] == nil)
        }

        let params = try #require(await recorder.commandParams.first)
        #expect(params.rawJSON == .object(richCommandParams(itemID: params.itemId)), "Typed params must round-trip losslessly")
        #expect(params.startedAtMs == 1_790_000_000_123)
        #expect(params.kind == .writeStdin)
        #expect(params.environmentId == "env-1")
        #expect(params.networkApprovalContext?.host == "example.com")
        #expect(params.networkApprovalContext?.protocolValue == .https)
        #expect(params.proposedExecpolicyAmendment == ["git", "push"])
        #expect(params.proposedNetworkPolicyAmendments?.first?.action == .allow)
        #expect(params.additionalPermissions?.network?.enabled == true)
        #expect(params.availableDecisions?.contains(.acceptForSession) == true)
        #expect(params.additionalFields["future"] == ["nested": true])
        guard case .read(let read)? = params.commandActions?.first, case .unknown(let future)? = params.commandActions?.last else {
            Issue.record("Expected known and future command actions")
            return
        }
        #expect(read.name == "a")
        #expect(future.objectValue?["future"] == true)
    }

    @Test
    func typedFileChangeHandlerSendsEveryDecisionVariant() async throws {
        let recorder = ApprovalRecorder()
        let requests = fileChangeDecisions.enumerated().map { index, entry in
            (id: index.isMultiple(of: 2) ? JSONValue.number(Double(200 + index)) : .string("file-\(entry.itemID)"),
             method: fileChangeMethod, params: JSONValue.object(richFileChangeParams(itemID: entry.itemID)))
        }
        let replies = try await runApprovals(requests) { config in
            config.fileChangeRequestApprovalHandler = { params in
                await recorder.record(params)
                let decision = try #require(fileChangeDecisions.first { $0.itemID == params.itemId }).decision
                return FileChangeRequestApprovalResponse(decision: decision)
            }
        }
        for (request, entry) in zip(requests, fileChangeDecisions) {
            #expect(replies[request.id]?["result"] == ["decision": entry.wire])
        }
        let params = try #require(await recorder.fileChangeParams.first)
        #expect(params.rawJSON == .object(richFileChangeParams(itemID: params.itemId)))
        #expect(params.grantRoot == "/tmp/repo")
        #expect(params.startedAtMs == 1_790_000_000_456)
    }

    @Test
    func genericHandlerTakesPrecedenceAndSeesFullMetadata() async throws {
        let recorder = ApprovalRecorder()
        let command = richCommandParams(itemID: "generic")
        let fileChange = richFileChangeParams(itemID: "generic")
        let replies = try await runApprovals([
            ("generic-command", commandMethod, .object(command)),
            (300, fileChangeMethod, .object(fileChange)),
        ]) { config in
            config.commandExecutionRequestApprovalHandler = { _ in
                Issue.record("Generic handler must take precedence")
                return .init(decision: .decline)
            }
            config.fileChangeRequestApprovalHandler = { _ in
                Issue.record("Generic handler must take precedence")
                return .init(decision: .decline)
            }
            config.serverRequestHandler = { request in
                await recorder.record(request)
                switch request {
                case .commandApproval:
                    return .commandExecutionApproval(.init(decision: .acceptForSession, additionalFields: ["future": true]))
                case .fileChangeApproval:
                    return .fileChangeApproval(.init(decision: .cancel))
                default:
                    return .error(code: -32601, message: "unexpected")
                }
            }
        }
        #expect(replies["generic-command"]?["result"] == ["decision": "acceptForSession", "future": true])
        #expect(replies[300]?["result"] == ["decision": "cancel"])

        let generic = await recorder.generic
        guard generic.count == 2,
              case .commandApproval(let commandRequest) = generic[0],
              case .fileChangeApproval(let fileRequest) = generic[1] else {
            Issue.record("Expected command and file change approval requests, got \(generic)")
            return
        }
        #expect(commandRequest.command == "git push")
        #expect(commandRequest.workingDirectory == "/tmp/repo")
        #expect(commandRequest.approvalID == "approval")
        #expect(commandRequest.rawParams == .object(command))
        #expect(commandRequest.params?.kind == .writeStdin)
        #expect(commandRequest.params?.proposedNetworkPolicyAmendments?.first?.host == "example.com")
        #expect(commandRequest.params?.additionalFields["future"] == ["nested": true])
        #expect(fileRequest.grantRoot == "/tmp/repo")
        #expect(fileRequest.rawParams == .object(fileChange))
        #expect(fileRequest.params?.startedAtMs == 1_790_000_000_456)
    }

    @Test
    func simplifiedHandlersReceiveFullMetadataAndKeepTheirWireFormat() async throws {
        let recorder = ApprovalRecorder()
        let replies = try await runApprovals([
            (1, commandMethod, .object(richCommandParams(itemID: "simple"))),
            ("file", fileChangeMethod, .object(richFileChangeParams(itemID: "simple"))),
        ]) { config in
            config.commandApprovalHandler = { request in
                await recorder.record(request)
                return .deny
            }
            config.fileChangeApprovalHandler = { request in
                await recorder.record(request)
                return .approve
            }
        }
        #expect(replies[1]?["result"] == ["decision": "decline"])
        #expect(replies["file"]?["result"] == ["decision": "accept"])
        let command = try #require(await recorder.legacyCommands.first)
        #expect(command.params?.environmentId == "env-1")
        #expect(command.rawParams == .object(richCommandParams(itemID: "simple")))
        let file = try #require(await recorder.legacyFileChanges.first)
        #expect(file.params?.grantRoot == "/tmp/repo")
    }

    @Test
    func legacyParamsWithoutStartTimeUseOnlyTheSimplifiedPath() async throws {
        let legacyCommand = appServerCommandApprovalParams(
            threadID: "thread", turnID: "turn", itemID: "legacy", approvalID: "approval",
            command: "ls", cwd: "/tmp", reason: "old server"
        )
        let legacyFile = appServerFileChangeApprovalParams(threadID: "thread", turnID: "turn", itemID: "legacy", reason: "old server")

        // Simplified handlers keep working for older servers, without a timestamp.
        let recorder = ApprovalRecorder()
        let simplified = try await runApprovals([
            ("legacy-command", commandMethod, .object(legacyCommand)),
            (7, fileChangeMethod, .object(legacyFile)),
        ]) { config in
            config.commandApprovalHandler = { request in
                await recorder.record(request)
                return .deny
            }
            config.fileChangeApprovalHandler = { request in
                await recorder.record(request)
                return .approve
            }
        }
        #expect(simplified["legacy-command"]?["result"] == ["decision": "decline"])
        #expect(simplified[7]?["result"] == ["decision": "accept"])
        let command = try #require(await recorder.legacyCommands.first)
        #expect(command.params == nil)
        #expect(command.command == "ls")
        #expect(command.rawParams == .object(legacyCommand))
        let file = try #require(await recorder.legacyFileChanges.first)
        #expect(file.params == nil)
        #expect(file.reason == "old server")

        // Generic handlers see the legacy request with its raw params.
        let genericRecorder = ApprovalRecorder()
        _ = try await runApprovals([("legacy-generic", commandMethod, .object(legacyCommand))]) { config in
            config.serverRequestHandler = { request in
                await genericRecorder.record(request)
                return .approval(.deny)
            }
        }
        guard case .commandApproval(let generic)? = await genericRecorder.generic.first else {
            Issue.record("Expected legacy command approval")
            return
        }
        #expect(generic.params == nil)
        #expect(generic.rawParams == .object(legacyCommand))

        // Typed handlers require the upstream shape and are never bypassed.
        let typed = try await runApprovals([
            ("legacy-typed", commandMethod, .object(legacyCommand)),
            (8, fileChangeMethod, .object(legacyFile)),
        ]) { config in
            config.commandExecutionRequestApprovalHandler = { _ in
                Issue.record("Typed handler must not receive legacy params")
                return .init(decision: .accept)
            }
            config.fileChangeRequestApprovalHandler = { _ in
                Issue.record("Typed handler must not receive legacy params")
                return .init(decision: .accept)
            }
        }
        #expect(typed["legacy-typed"]?["error"]?.objectValue?["code"] == -32602)
        #expect(typed[8]?["error"]?.objectValue?["code"] == -32602)
    }

    @Test
    func malformedParamsThrowingHandlersAndInvalidResultsFailOnlyTheRequest() async throws {
        var malformed = richCommandParams(itemID: "malformed")
        malformed.removeValue(forKey: "itemId")
        var badStartTime = richFileChangeParams(itemID: "bad")
        badStartTime["startedAtMs"] = "yesterday"

        for mode in ["default", "typed"] {
            let replies = try await runApprovals([
                ("malformed-command", commandMethod, .object(malformed)),
                (9, fileChangeMethod, .object(badStartTime)),
                ("null-command", commandMethod, .null),
            ]) { config in
                config.commandApprovalHandler = { _ in
                    Issue.record("Invalid params must not reach a handler")
                    return .approve
                }
                if mode == "typed" {
                    config.commandExecutionRequestApprovalHandler = { _ in
                        Issue.record("Invalid params must not reach a handler")
                        return .init(decision: .accept)
                    }
                }
            }
            for id: JSONValue in ["malformed-command", 9, "null-command"] {
                #expect(replies[id]?["error"]?.objectValue?["code"] == -32602, "\(mode) \(id)")
                #expect(replies[id]?["result"] == nil)
            }
        }

        // Invalid params reach a generic handler unmodified as unknown requests.
        let recorder = ApprovalRecorder()
        _ = try await runApprovals([("malformed-generic", commandMethod, .object(malformed))]) { config in
            config.serverRequestHandler = { request in
                await recorder.record(request)
                return .approval(.deny)
            }
        }
        guard case .unknown(let method, let params)? = await recorder.generic.first else {
            Issue.record("Expected malformed approval as an unknown request")
            return
        }
        #expect(method == commandMethod)
        #expect(params == .object(malformed))

        let failures = try await runApprovals([
            ("throwing", commandMethod, .object(richCommandParams(itemID: "throwing"))),
            (10, fileChangeMethod, .object(richFileChangeParams(itemID: "nan"))),
        ]) { config in
            config.commandExecutionRequestApprovalHandler = { _ in throw ApprovalHandlerFailure() }
            config.fileChangeRequestApprovalHandler = { _ in
                .init(decision: .accept, additionalFields: ["invalid": .number(.nan)])
            }
        }
        for id: JSONValue in ["throwing", 10] {
            let error = try #require(failures[id]?["error"]?.objectValue)
            #expect(error["code"] == -32603)
            #expect(error["message"]?.stringValue?.contains("secret") == false)
        }
    }
}

private func humanCommandParams(itemID: String) -> JSONObject {
    var params = richCommandParams(itemID: itemID)
    params["kind"] = "humanCommand"
    params["availableDecisions"] = ["accept", "decline", "cancel"]
    return params
}

struct HumanCommandApprovalTests {
    @Test(arguments: [false, true])
    func requiredHumanApprovalCapabilityIsOptIn(enabled: Bool) async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        try stub.configureAppServerInvocation(0, scenario: AppServerScenario())
        var config = stub.makeConfig()
        config.requiredHumanApproval = enabled
        let codex = try await Codex(config: config)
        await codex.close()
        let messages = try stub.appServerMessages(forInvocation: 0)
        #expect(messages.first?["method"] == "initialize")
        let expected: JSONValue = enabled
            ? ["experimentalApi": true, "requiredHumanApproval": true]
            : ["experimentalApi": true]
        #expect(messages.first?["params"]?.objectValue?["capabilities"] == expected)
    }

    @Test
    func requiredHumanApprovalRequiresExperimentalAPI() async throws {
        let stub = try CodexStub()
        defer { stub.cleanup() }
        var config = stub.makeConfig()
        config.requiredHumanApproval = true
        config.experimentalAPI = false
        let client = CodexRPCClient(config: config)
        await #expect {
            _ = try await client.initialize()
        } throws: { error in
            guard case CodexError.invalidConfig(let message) = error else { return false }
            return message.contains("experimentalAPI")
        }
    }

    @Test
    func typedHandlerMayOnlySendOneTimeDecisionsForHumanCommand() async throws {
        let requests = commandDecisions.map { entry in
            (id: JSONValue.string("human-\(entry.itemID)"), method: commandMethod,
             params: JSONValue.object(humanCommandParams(itemID: entry.itemID)))
        } + [(id: "plain-session", method: commandMethod, params: .object(richCommandParams(itemID: "session")))]
        let replies = try await runApprovals(requests) { config in
            config.requiredHumanApproval = true
            config.commandExecutionRequestApprovalHandler = { params in
                let decision = try #require(commandDecisions.first { $0.itemID == params.itemId }).decision
                return .init(decision: decision)
            }
        }
        let allowed: Set<String> = ["accept", "decline", "cancel"]
        for entry in commandDecisions {
            let reply = try #require(replies[.string("human-\(entry.itemID)")])
            if allowed.contains(entry.itemID) {
                #expect(reply["result"] == ["decision": entry.wire])
                #expect(reply["error"] == nil)
            } else {
                #expect(reply["result"] == nil, "\(entry.itemID) must not be sent for humanCommand")
                #expect(reply["error"]?.objectValue?["code"] == -32603)
            }
        }
        // Other approval kinds keep every decision.
        #expect(replies["plain-session"]?["result"] == ["decision": "acceptForSession"])
    }

    @Test
    func simplifiedAndGenericHandlersKeepTheirSemanticsForHumanCommand() async throws {
        let simple = try await runApprovals([
            ("approve", commandMethod, .object(humanCommandParams(itemID: "approve"))),
            ("deny", commandMethod, .object(humanCommandParams(itemID: "deny"))),
        ]) { config in
            config.commandApprovalHandler = { $0.itemID == "approve" ? .approve : .deny }
        }
        #expect(simple["approve"]?["result"] == ["decision": "accept"])
        #expect(simple["deny"]?["result"] == ["decision": "decline"])

        let generic = try await runApprovals([
            ("generic", commandMethod, .object(humanCommandParams(itemID: "generic"))),
        ]) { config in
            config.serverRequestHandler = { request in
                guard case .commandApproval(let approval) = request else { return .error(code: -32601, message: "unexpected") }
                #expect(approval.params?.kind == .humanCommand)
                return .commandExecutionApproval(.init(decision: .acceptForSession))
            }
        }
        #expect(generic["generic"]?["result"] == ["decision": "acceptForSession"])
    }
}
