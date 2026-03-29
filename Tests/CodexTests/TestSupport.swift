import struct Foundation.Data
import class Foundation.FileManager
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.URL
import struct Foundation.UUID
@testable import Codex

struct CodexStub {
    let rootURL: URL
    let executableURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-codex-tests-\(UUID().uuidString)", isDirectory: true)
        executableURL = rootURL.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let script = """
        #!/bin/sh
        set -eu
        state_dir="${CODEX_TEST_STATE_DIR:?}"
        count_file="$state_dir/count"
        if [ -f "$count_file" ]; then
          idx=$(/bin/cat "$count_file")
        else
          idx=0
        fi
        next=$((idx + 1))
        printf '%s' "$next" > "$count_file"

        printf '%s\\n' "$@" > "$state_dir/$idx.args"
        printf '%s' "$PWD" > "$state_dir/$idx.pwd"

        {
          printf 'OPENAI_BASE_URL=%s\\n' "${OPENAI_BASE_URL-}"
          printf 'CODEX_API_KEY=%s\\n' "${CODEX_API_KEY-}"
          printf 'CODEX_INTERNAL_ORIGINATOR_OVERRIDE=%s\\n' "${CODEX_INTERNAL_ORIGINATOR_OVERRIDE-}"
          printf 'CUSTOM_ENV=%s\\n' "${CUSTOM_ENV-}"
          printf 'CODEX_ENV_SHOULD_NOT_LEAK=%s\\n' "${CODEX_ENV_SHOULD_NOT_LEAK-}"
          printf 'PATH=%s\\n' "${PATH-}"
        } > "$state_dir/$idx.env"

        if [ "${1-}" != "app-server" ]; then
          printf 'unexpected invocation: %s\\n' "$*" >&2
          exit 64
        fi

        app_server_script="$state_dir/$idx.appserver.py"
        /bin/cat > "$app_server_script" <<'PY'
        import json
        import os
        import sys

        state_dir = sys.argv[1]
        invocation = sys.argv[2]
        scenario_path = os.path.join(state_dir, f"{invocation}.appserver.json")
        if os.path.exists(scenario_path):
            with open(scenario_path, "r", encoding="utf-8") as handle:
                scenario = json.load(handle)
        else:
            scenario = {}

        initialize_result = scenario.get("initializeResult", {
            "serverInfo": {"name": "codex", "version": "test"},
            "userAgent": "codex/test",
        })
        initialize_close_stderr = scenario.get("initializeCloseStderr", [])
        thread_start_responses = scenario.get("threadStartResponses", [])
        thread_resume_responses = scenario.get("threadResumeResponses", [])
        thread_list_responses = scenario.get("threadListResponses", [])
        thread_read_responses = scenario.get("threadReadResponses", [])
        thread_fork_responses = scenario.get("threadForkResponses", [])
        thread_archive_responses = scenario.get("threadArchiveResponses", [])
        thread_unarchive_responses = scenario.get("threadUnarchiveResponses", [])
        thread_set_name_responses = scenario.get("threadSetNameResponses", [])
        thread_compact_responses = scenario.get("threadCompactResponses", [])
        turn_start_responses = scenario.get("turnStartResponses", [])
        turn_start_sequences = scenario.get("turnStartSequences", [])
        turn_steer_responses = scenario.get("turnSteerResponses", [])
        turn_interrupt_responses = scenario.get("turnInterruptResponses", [])
        model_list_responses = scenario.get("modelListResponses", [])
        plugin_list_responses = scenario.get("pluginListResponses", [])

        thread_start_index = 0
        thread_resume_index = 0
        thread_list_index = 0
        thread_read_index = 0
        thread_fork_index = 0
        thread_archive_index = 0
        thread_unarchive_index = 0
        thread_set_name_index = 0
        thread_compact_index = 0
        turn_start_index = 0
        turn_steer_index = 0
        turn_interrupt_index = 0
        model_list_index = 0
        plugin_list_index = 0

        def append_jsonl(suffix, payload):
            path = os.path.join(state_dir, f"{invocation}.{suffix}.jsonl")
            with open(path, "a", encoding="utf-8") as handle:
                handle.write(json.dumps(payload))
                handle.write("\\n")

        def write_message(payload):
            append_jsonl("appserver.out", payload)
            sys.stdout.write(json.dumps(payload))
            sys.stdout.write("\\n")
            sys.stdout.flush()

        def response_at(entries, index, default):
            if index < len(entries):
                return entries[index]
            return default

        for raw_line in sys.stdin:
            if not raw_line:
                break
            message = json.loads(raw_line)
            append_jsonl("appserver.in", message)

            method = message.get("method")
            request_id = message.get("id")

            if method == "initialize":
                if initialize_close_stderr:
                    for entry in initialize_close_stderr:
                        sys.stderr.write(entry)
                        sys.stderr.write("\\n")
                    sys.stderr.flush()
                    sys.exit(0)
                write_message({"id": request_id, "result": initialize_result})
                continue

            if method == "initialized":
                continue

            if method == "thread/start":
                response = response_at(thread_start_responses, thread_start_index, {})
                thread_start_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/resume":
                response = response_at(thread_resume_responses, thread_resume_index, {})
                thread_resume_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/list":
                response = response_at(thread_list_responses, thread_list_index, {"data": []})
                thread_list_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/read":
                response = response_at(thread_read_responses, thread_read_index, {})
                thread_read_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/fork":
                response = response_at(thread_fork_responses, thread_fork_index, {})
                thread_fork_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/archive":
                response = response_at(thread_archive_responses, thread_archive_index, {})
                thread_archive_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/unarchive":
                response = response_at(thread_unarchive_responses, thread_unarchive_index, {})
                thread_unarchive_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/name/set":
                response = response_at(thread_set_name_responses, thread_set_name_index, {})
                thread_set_name_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/compact/start":
                response = response_at(thread_compact_responses, thread_compact_index, {})
                thread_compact_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "turn/start":
                response = response_at(turn_start_responses, turn_start_index, {})
                sequence = response_at(turn_start_sequences, turn_start_index, [])
                turn_start_index += 1
                write_message({"id": request_id, "result": response})
                for step in sequence:
                    if step["kind"] == "notification":
                        write_message({"method": step["method"], "params": step["params"]})
                        continue

                    write_message({
                        "id": step["requestId"],
                        "method": step["method"],
                        "params": step["params"],
                    })
                    response_line = sys.stdin.readline()
                    if not response_line:
                        sys.exit(0)
                    append_jsonl("appserver.responses", json.loads(response_line))
                continue

            if method == "turn/steer":
                response = response_at(turn_steer_responses, turn_steer_index, {})
                turn_steer_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "turn/interrupt":
                response = response_at(turn_interrupt_responses, turn_interrupt_index, {})
                turn_interrupt_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "model/list":
                response = response_at(model_list_responses, model_list_index, {"data": []})
                model_list_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "plugin/list":
                response = response_at(plugin_list_responses, plugin_list_index, {"marketplaces": []})
                plugin_list_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if request_id is not None:
                write_message({
                    "id": request_id,
                    "error": {
                        "code": -32601,
                        "message": f"Unsupported method: {method}",
                    }
                })
        PY
        /usr/bin/env python3 "$app_server_script" "$state_dir" "$idx"
        """

        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path())
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeConfig(
        launchArgsOverride: [String]? = nil,
        baseURL: String? = "https://example.test",
        apiKey: String? = "test-key",
        config: JSONObject? = nil,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        serverRequestHandler: CodexConfig.ServerRequestHandler? = nil
    ) -> CodexConfig {
        var env = environment ?? [:]
        env["CODEX_TEST_STATE_DIR"] = rootURL.path()
        return CodexConfig(
            codexPathOverride: executableURL.path(),
            launchArgsOverride: launchArgsOverride,
            baseURL: baseURL,
            apiKey: apiKey,
            config: config,
            workingDirectory: workingDirectory,
            environment: env,
            serverRequestHandler: serverRequestHandler
        )
    }

    func makePathLookupConfig(environment: [String: String], workingDirectory: String? = nil) -> CodexConfig {
        var env = environment
        env["CODEX_TEST_STATE_DIR"] = rootURL.path()
        return CodexConfig(
            baseURL: "https://example.test",
            apiKey: "test-key",
            workingDirectory: workingDirectory,
            environment: env
        )
    }

    func arguments(forInvocation index: Int) throws -> [String] {
        let text = try String(contentsOf: rootURL.appendingPathComponent("\(index).args"), encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }

    func environment(forInvocation index: Int) throws -> [String: String] {
        let text = try String(contentsOf: rootURL.appendingPathComponent("\(index).env"), encoding: .utf8)
        return Dictionary(uniqueKeysWithValues: text.split(separator: "\n").map { line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0], parts.count > 1 ? parts[1] : "")
        })
    }

    func workingDirectory(forInvocation index: Int) throws -> String {
        try String(contentsOf: rootURL.appendingPathComponent("\(index).pwd"), encoding: .utf8)
    }

    func configureAppServerInvocation(_ index: Int, scenario: AppServerScenario) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(scenario)
        try data.write(to: rootURL.appendingPathComponent("\(index).appserver.json"))
    }

    func appServerMessages(forInvocation index: Int) throws -> [JSONObject] {
        try decodeJSONLines(at: rootURL.appendingPathComponent("\(index).appserver.in.jsonl"))
    }

    func appServerResponses(forInvocation index: Int) throws -> [JSONObject] {
        try decodeJSONLines(at: rootURL.appendingPathComponent("\(index).appserver.responses.jsonl"))
    }

    func appServerOutboundMessages(forInvocation index: Int) throws -> [JSONObject] {
        try decodeJSONLines(at: rootURL.appendingPathComponent("\(index).appserver.out.jsonl"))
    }
}

struct AppServerScenario: Encodable {
    var initializeResult: JSONObject
    var initializeCloseStderr: [String]
    var threadStartResponses: [JSONObject]
    var threadResumeResponses: [JSONObject]
    var threadListResponses: [JSONObject]
    var threadReadResponses: [JSONObject]
    var threadForkResponses: [JSONObject]
    var threadArchiveResponses: [JSONObject]
    var threadUnarchiveResponses: [JSONObject]
    var threadSetNameResponses: [JSONObject]
    var threadCompactResponses: [JSONObject]
    var turnStartResponses: [JSONObject]
    var turnStartSequences: [[AppServerScriptStep]]
    var turnSteerResponses: [JSONObject]
    var turnInterruptResponses: [JSONObject]
    var modelListResponses: [JSONObject]
    var pluginListResponses: [JSONObject]

    init(
        initializeResult: JSONObject = appServerInitializeResult(),
        initializeCloseStderr: [String] = [],
        threadStartResponses: [JSONObject] = [],
        threadResumeResponses: [JSONObject] = [],
        threadListResponses: [JSONObject] = [],
        threadReadResponses: [JSONObject] = [],
        threadForkResponses: [JSONObject] = [],
        threadArchiveResponses: [JSONObject] = [],
        threadUnarchiveResponses: [JSONObject] = [],
        threadSetNameResponses: [JSONObject] = [],
        threadCompactResponses: [JSONObject] = [],
        turnStartResponses: [JSONObject] = [],
        turnStartSequences: [[AppServerScriptStep]] = [],
        turnSteerResponses: [JSONObject] = [],
        turnInterruptResponses: [JSONObject] = [],
        modelListResponses: [JSONObject] = [],
        pluginListResponses: [JSONObject] = []
    ) {
        self.initializeResult = initializeResult
        self.initializeCloseStderr = initializeCloseStderr
        self.threadStartResponses = threadStartResponses
        self.threadResumeResponses = threadResumeResponses
        self.threadListResponses = threadListResponses
        self.threadReadResponses = threadReadResponses
        self.threadForkResponses = threadForkResponses
        self.threadArchiveResponses = threadArchiveResponses
        self.threadUnarchiveResponses = threadUnarchiveResponses
        self.threadSetNameResponses = threadSetNameResponses
        self.threadCompactResponses = threadCompactResponses
        self.turnStartResponses = turnStartResponses
        self.turnStartSequences = turnStartSequences
        self.turnSteerResponses = turnSteerResponses
        self.turnInterruptResponses = turnInterruptResponses
        self.modelListResponses = modelListResponses
        self.pluginListResponses = pluginListResponses
    }
}

enum AppServerScriptStep: Encodable {
    case notification(method: String, params: JSONObject)
    case request(id: String, method: String, params: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case kind
        case requestID = "requestId"
        case method
        case params
    }

    private enum Kind: String, Encodable {
        case notification
        case request
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notification(let method, let params):
            try container.encode(Kind.notification, forKey: .kind)
            try container.encode(method, forKey: .method)
            try container.encode(params, forKey: .params)
        case .request(let id, let method, let params):
            try container.encode(Kind.request, forKey: .kind)
            try container.encode(id, forKey: .requestID)
            try container.encode(method, forKey: .method)
            try container.encode(params, forKey: .params)
        }
    }
}

func appServerInitializeResult(
    userAgent: String? = "codex/test",
    serverName: String? = "codex",
    serverVersion: String? = "test"
) -> JSONObject {
    jsonObject(
        InitializeResponse(
            serverInfo: serverName == nil && serverVersion == nil ? nil : ServerInfo(name: serverName, version: serverVersion),
            userAgent: userAgent,
            platformFamily: "macOS",
            platformOs: "Darwin"
        )
    )
}

func appServerThreadStartResponse(id: String) -> JSONObject {
    jsonObject(
        ThreadStartResponse(
            approvalPolicy: .never,
            approvalsReviewer: .user,
            cwd: "/tmp/project",
            model: "gpt-5",
            modelProvider: "openai",
            sandbox: .workspaceWrite(
                WorkspaceWriteSandboxPolicy(
                    networkAccess: true,
                    type: .workspaceWrite
                )
            ),
            thread: makeThread(id: id)
        )
    )
}

func appServerThreadResumeResponse(id: String) -> JSONObject {
    jsonObject(
        ThreadResumeResponse(
            approvalPolicy: .never,
            approvalsReviewer: .user,
            cwd: "/tmp/project",
            model: "gpt-5",
            modelProvider: "openai",
            sandbox: .workspaceWrite(
                WorkspaceWriteSandboxPolicy(
                    networkAccess: true,
                    type: .workspaceWrite
                )
            ),
            thread: makeThread(id: id)
        )
    )
}

func appServerThreadForkResponse(id: String) -> JSONObject {
    jsonObject(
        ThreadForkResponse(
            approvalPolicy: .never,
            approvalsReviewer: .user,
            cwd: "/tmp/project",
            model: "gpt-5",
            modelProvider: "openai",
            sandbox: .workspaceWrite(
                WorkspaceWriteSandboxPolicy(
                    networkAccess: true,
                    type: .workspaceWrite
                )
            ),
            thread: makeThread(id: id)
        )
    )
}

func appServerThreadUnarchiveResponse(id: String) -> JSONObject {
    jsonObject(ThreadUnarchiveResponse(thread: makeThread(id: id)))
}

func appServerThreadListResponse(threads: [Thread], nextCursor: String? = nil) -> JSONObject {
    jsonObject(ThreadListResponse(data: threads, nextCursor: nextCursor))
}

func appServerThreadReadResponse(thread: Thread) -> JSONObject {
    jsonObject(ThreadReadResponse(thread: thread))
}

func appServerTurnStartResponse(id: String, status: TurnStatus = .inProgress) -> JSONObject {
    jsonObject(TurnStartResponse(turn: makeTurn(id: id, status: status)))
}

func appServerTurnSteerResponse(turnID: String) -> JSONObject {
    jsonObject(TurnSteerResponse(turnId: turnID))
}

func appServerEmptyResponse() -> JSONObject {
    [:]
}

func appServerModelListResponse(models: [Model]) -> JSONObject {
    jsonObject(ModelListResponse(data: models))
}

func appServerThreadStarted(threadID: String) -> JSONObject {
    jsonObject(ThreadStartedNotification(thread: makeThread(id: threadID)))
}

func appServerTurnStarted(threadID: String, turnID: String) -> JSONObject {
    jsonObject(
        TurnStartedNotification(
            threadId: threadID,
            turn: makeTurn(id: turnID, status: .inProgress)
        )
    )
}

func appServerTurnCompleted(
    threadID: String,
    turnID: String,
    status: TurnStatus = .completed,
    items: [ThreadItem] = [],
    error: TurnError? = nil
) -> JSONObject {
    jsonObject(
        TurnCompletedNotification(
            threadId: threadID,
            turn: makeTurn(id: turnID, status: status, items: items, error: error)
        )
    )
}

func appServerThreadTokenUsageUpdated(threadID: String, turnID: String) -> JSONObject {
    jsonObject(
        ThreadTokenUsageUpdatedNotification(
            threadId: threadID,
            tokenUsage: makeThreadTokenUsage(),
            turnId: turnID
        )
    )
}

func appServerItemCompleted(threadID: String, turnID: String, item: ThreadItem) -> JSONObject {
    jsonObject(
        ItemCompletedNotification(
            item: item,
            threadId: threadID,
            turnId: turnID
        )
    )
}

func appServerAgentMessageItem(id: String = "msg_1", text: String, phase: MessagePhase? = nil) -> ThreadItem {
    .agentMessage(
        AgentMessageThreadItem(
            id: id,
            phase: phase,
            text: text,
            type: .agentMessage
        )
    )
}

func appServerCommandApprovalParams(
    threadID: String,
    turnID: String,
    itemID: String,
    approvalID: String? = nil,
    command: String,
    cwd: String,
    reason: String
) -> JSONObject {
    var params: JSONObject = [
        "threadId": .string(threadID),
        "turnId": .string(turnID),
        "itemId": .string(itemID),
        "command": .string(command),
        "cwd": .string(cwd),
        "reason": .string(reason),
    ]
    if let approvalID {
        params["approvalId"] = .string(approvalID)
    }
    return params
}

func appServerFileChangeApprovalParams(
    threadID: String,
    turnID: String,
    itemID: String,
    reason: String,
    grantRoot: String? = nil
) -> JSONObject {
    var params: JSONObject = [
        "threadId": .string(threadID),
        "turnId": .string(turnID),
        "itemId": .string(itemID),
        "reason": .string(reason),
    ]
    if let grantRoot {
        params["grantRoot"] = .string(grantRoot)
    }
    return params
}

func makeThread(
    id: String,
    turns: [Turn] = [],
    source: SessionSource = .appServer,
    status: ThreadStatus = .idle(IdleThreadStatus(type: .idle))
) -> Thread {
    Thread(
        cliVersion: "0.0.0-test",
        createdAt: 1,
        cwd: "/tmp/project",
        ephemeral: false,
        id: id,
        modelProvider: "openai",
        preview: "preview",
        source: source,
        status: status,
        turns: turns,
        updatedAt: 2
    )
}

func makeTurn(
    id: String,
    status: TurnStatus = .completed,
    items: [ThreadItem] = [],
    error: TurnError? = nil
) -> Turn {
    Turn(
        error: error,
        id: id,
        items: items,
        status: status
    )
}

func makeThreadTokenUsage() -> ThreadTokenUsage {
    ThreadTokenUsage(
        last: TokenUsageBreakdown(
            cachedInputTokens: 0,
            inputTokens: 1,
            outputTokens: 2,
            reasoningOutputTokens: 0,
            totalTokens: 3
        ),
        total: TokenUsageBreakdown(
            cachedInputTokens: 0,
            inputTokens: 1,
            outputTokens: 2,
            reasoningOutputTokens: 0,
            totalTokens: 3
        )
    )
}

func makeModel(id: String, hidden: Bool = false) -> Model {
    Model(
        defaultReasoningEffort: .medium,
        description: "Test model",
        displayName: id,
        hidden: hidden,
        id: id,
        isDefault: true,
        model: id,
        supportedReasoningEfforts: [
            ReasoningEffortOption(
                description: "Medium",
                reasoningEffort: .medium
            )
        ]
    )
}

func jsonObject<T: RawJSONRepresentable>(_ value: T) -> JSONObject {
    guard let object = value.rawJSON.objectValue else {
        fatalError("Expected \(T.self) to encode as a JSON object")
    }
    return object
}

private func decodeJSONLines(at url: URL) throws -> [JSONObject] {
    guard FileManager.default.fileExists(atPath: url.path()) else {
        return []
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    return try text
        .split(separator: "\n")
        .map { line in
            try JSONDecoder().decode(JSONObject.self, from: Data(line.utf8))
        }
}
