import Foundation
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

        if [ "${1-}" = "app-server" ]; then
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
            "userAgent": "codex/test"
        })
        initialize_close_stderr = scenario.get("initializeCloseStderr", [])
        thread_start_responses = scenario.get("threadStartResponses", [])
        thread_resume_responses = scenario.get("threadResumeResponses", [])
        turn_start_responses = scenario.get("turnStartResponses", [])
        turn_start_sequences = scenario.get("turnStartSequences", [])
        turn_interrupt_responses = scenario.get("turnInterruptResponses", [])

        thread_start_index = 0
        thread_resume_index = 0
        turn_start_index = 0
        turn_interrupt_index = 0

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

            if method == "thread/start":
                response = thread_start_responses[thread_start_index]
                thread_start_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "thread/resume":
                response = thread_resume_responses[thread_resume_index]
                thread_resume_index += 1
                write_message({"id": request_id, "result": response})
                continue

            if method == "turn/start":
                response = turn_start_responses[turn_start_index]
                sequence = turn_start_sequences[turn_start_index]
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

            if method == "turn/interrupt":
                response = turn_interrupt_responses[turn_interrupt_index]
                turn_interrupt_index += 1
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
          exit 0
        fi

        /bin/cat > "$state_dir/$idx.stdin"

        delay="0"
        if [ -f "$state_dir/$idx.delay" ]; then
          delay=$(/bin/cat "$state_dir/$idx.delay")
        fi

        if [ -f "$state_dir/$idx.output" ]; then
          while IFS= read -r line || [ -n "$line" ]; do
            printf '%s\\n' "$line"
            if [ "$delay" != "0" ]; then
              /bin/sleep "$delay"
            fi
          done < "$state_dir/$idx.output"
        fi

        if [ -f "$state_dir/$idx.stderr" ]; then
          /bin/cat "$state_dir/$idx.stderr" >&2
        fi

        exit_code=0
        if [ -f "$state_dir/$idx.exit" ]; then
          exit_code=$(/bin/cat "$state_dir/$idx.exit")
        fi
        exit "$exit_code"
        """

        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path())
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func configureInvocation(
        _ index: Int,
        outputLines: [String],
        exitCode: Int = 0,
        stderr: String = "",
        delaySeconds: Double = 0
    ) throws {
        let outputURL = rootURL.appendingPathComponent("\(index).output")
        try outputLines.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)
        try String(exitCode).write(
            to: rootURL.appendingPathComponent("\(index).exit"),
            atomically: true,
            encoding: .utf8
        )
        try stderr.write(
            to: rootURL.appendingPathComponent("\(index).stderr"),
            atomically: true,
            encoding: .utf8
        )
        try String(delaySeconds).write(
            to: rootURL.appendingPathComponent("\(index).delay"),
            atomically: true,
            encoding: .utf8
        )
    }

    func explicitOptions(
        baseURL: String? = "https://example.test",
        apiKey: String? = "test-key",
        config: JSONObject? = nil,
        environment: [String: String]? = nil
    ) -> CodexOptions {
        var env = environment ?? [:]
        env["CODEX_TEST_STATE_DIR"] = rootURL.path()
        return CodexOptions(
            codexPathOverride: executableURL.path(),
            baseURL: baseURL,
            apiKey: apiKey,
            config: config,
            environment: env
        )
    }

    func pathLookupOptions(environment: [String: String]) -> CodexOptions {
        var env = environment
        env["CODEX_TEST_STATE_DIR"] = rootURL.path()
        return CodexOptions(
            baseURL: "https://example.test",
            apiKey: "test-key",
            environment: env
        )
    }

    func arguments(forInvocation index: Int) throws -> [String] {
        let text = try String(contentsOf: rootURL.appendingPathComponent("\(index).args"), encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }

    func input(forInvocation index: Int) throws -> String {
        try String(contentsOf: rootURL.appendingPathComponent("\(index).stdin"), encoding: .utf8)
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
    var turnStartResponses: [JSONObject]
    var turnStartSequences: [[AppServerScriptStep]]
    var turnInterruptResponses: [JSONObject]

    init(
        initializeResult: JSONObject = appServerInitializeResult(),
        initializeCloseStderr: [String] = [],
        threadStartResponses: [JSONObject] = [],
        threadResumeResponses: [JSONObject] = [],
        turnStartResponses: [JSONObject] = [],
        turnStartSequences: [[AppServerScriptStep]] = [],
        turnInterruptResponses: [JSONObject] = []
    ) {
        self.initializeResult = initializeResult
        self.initializeCloseStderr = initializeCloseStderr
        self.threadStartResponses = threadStartResponses
        self.threadResumeResponses = threadResumeResponses
        self.turnStartResponses = turnStartResponses
        self.turnStartSequences = turnStartSequences
        self.turnInterruptResponses = turnInterruptResponses
    }
}

enum AppServerScriptStep: Encodable {
    case notification(method: String, params: JSONObject)
    case request(id: String, method: String, params: JSONObject)

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
    userAgent: String = "codex/test",
    serverName: String = "codex",
    serverVersion: String = "test"
) -> JSONObject {
    [
        "userAgent": .string(userAgent),
        "serverInfo": .object([
            "name": .string(serverName),
            "version": .string(serverVersion),
        ]),
    ]
}

func appServerThreadResponse(id: String) -> JSONObject {
    [
        "thread": .object([
            "id": .string(id),
        ]),
    ]
}

func appServerTurnResponse(id: String) -> JSONObject {
    [
        "turn": .object([
            "id": .string(id),
        ]),
    ]
}

func appServerEmptyResponse() -> JSONObject {
    [:]
}

func appServerThreadStarted(threadID: String) -> JSONObject {
    [
        "thread": .object([
            "id": .string(threadID),
        ]),
    ]
}

func appServerTurnStarted(threadID: String, turnID: String) -> JSONObject {
    [
        "threadId": .string(threadID),
        "turn": .object([
            "id": .string(turnID),
        ]),
    ]
}

func appServerTurnCompleted(threadID: String, turnID: String) -> JSONObject {
    [
        "threadId": .string(threadID),
        "turn": .object([
            "id": .string(turnID),
        ]),
    ]
}

func appServerErrorNotification(threadID: String, turnID: String, message: String) -> JSONObject {
    [
        "threadId": .string(threadID),
        "turnId": .string(turnID),
        "error": .object([
            "message": .string(message),
        ]),
    ]
}

func appServerItemNotification(threadID: String, turnID: String, item: JSONObject) -> JSONObject {
    [
        "threadId": .string(threadID),
        "turnId": .string(turnID),
        "item": .object(item),
    ]
}

func appServerAgentMessageItem(id: String = "msg_1", text: String) -> JSONObject {
    [
        "id": .string(id),
        "type": .string("agentMessage"),
        "text": .string(text),
    ]
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

func threadStarted(_ id: String) -> String {
    #"{"type":"thread.started","thread_id":"\#(id)"}"#
}

func turnStarted() -> String {
    #"{"type":"turn.started"}"#
}

func assistantMessage(id: String = "msg_1", text: String) -> String {
    #"{"type":"item.completed","item":{"id":"\#(id)","type":"agent_message","text":"\#(text)"}}"#
}

func reasoningMessage(id: String = "rsn_1", text: String) -> String {
    #"{"type":"item.completed","item":{"id":"\#(id)","type":"reasoning","text":"\#(text)"}}"#
}

func turnCompleted() -> String {
    #"{"type":"turn.completed","usage":{"input_tokens":42,"cached_input_tokens":12,"output_tokens":5}}"#
}

func turnFailed(_ message: String) -> String {
    #"{"type":"turn.failed","error":{"message":"\#(message)"}}"#
}
