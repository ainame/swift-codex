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
