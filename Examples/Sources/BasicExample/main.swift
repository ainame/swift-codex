import Codex
import Foundation

@main
struct BasicExample {
    static func main() async {
        let codex = Codex()
        let thread = codex.startThread(options: ThreadOptions(skipGitRepoCheck: true))

        do {
            let turn = try await thread.run("Summarize the current repository status in two sentences.")
            print("Buffered response:")
            print(turn.finalResponse)
            print("")

            print("Streaming a follow-up turn:")
            let stream = await thread.runStreamed("List the next three engineering tasks as a todo list.")
            for try await event in stream {
                print(describe(event))
            }
        } catch {
            fputs("Example failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func describe(_ event: ThreadEvent) -> String {
        switch event {
        case .threadStarted(let started):
            return "thread.started id=\(started.threadID)"
        case .turnStarted:
            return "turn.started"
        case .turnCompleted(let completed):
            return "turn.completed output_tokens=\(completed.usage.outputTokens)"
        case .turnFailed(let failed):
            return "turn.failed message=\(failed.error.message)"
        case .itemStarted(let item):
            return "item.started \(describe(item.item))"
        case .itemUpdated(let item):
            return "item.updated \(describe(item.item))"
        case .itemCompleted(let item):
            return "item.completed \(describe(item.item))"
        case .error(let error):
            return "error message=\(error.message)"
        }
    }

    private static func describe(_ item: ThreadItem) -> String {
        switch item {
        case .agentMessage(let message):
            return "agent_message text=\(message.text)"
        case .reasoning(let reasoning):
            return "reasoning text=\(reasoning.text)"
        case .commandExecution(let command):
            return "command_execution status=\(command.status.rawValue)"
        case .fileChange(let change):
            return "file_change status=\(change.status.rawValue)"
        case .mcpToolCall(let call):
            return "mcp_tool_call tool=\(call.tool) status=\(call.status.rawValue)"
        case .webSearch(let search):
            return "web_search query=\(search.query)"
        case .todoList(let todo):
            return "todo_list count=\(todo.items.count)"
        case .error(let error):
            return "error message=\(error.message)"
        }
    }
}
