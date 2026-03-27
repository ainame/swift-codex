import Codex
import Foundation

@main
struct BasicExample {
    static func main() async {
        let config = CodexConfig(
            commandApprovalHandler: { request in
                print("Approve command: \(request.command ?? "<unknown>")")
                return .approve
            },
            fileChangeApprovalHandler: { request in
                print("Approve file changes under: \(request.grantRoot ?? "<unknown>")")
                return .approve
            }
        )

        let client = CodexRPCClient(config: config)

        do {
            let initialize = try await client.initialize()
            print("Connected to \(initialize.serverInfo?.name ?? "codex") \(initialize.serverInfo?.version ?? "")")

            let started = try await client.threadStart(options: .init(
                model: "gpt-5-codex",
                sandbox: .workspaceWrite
            ))
            print("Started thread: \(started.thread.id)")

            let listed = try await client.threadList()
            print("Visible threads: \(listed.data.count)")

            let read = try await client.threadRead(threadID: started.thread.id)
            print("Read thread preview: \(read.thread.preview)")

            let turn = try await client.turnStart(
                threadID: started.thread.id,
                input: [.text("Summarize the repository status and stream progress.")],
                options: .init(summary: .concise)
            )
            print("Streaming turn: \(turn.turn.id)")

            while true {
                let notification = try await client.nextNotification()
                print(describe(notification))

                if case .turnCompleted(let payload) = notification.payload, payload.turn.id == turn.turn.id {
                    break
                }
            }

            let materialized = try await client.threadRead(threadID: started.thread.id, includeTurns: true)
            print("Materialized turn count: \(materialized.thread.turns.count)")
        } catch {
            fputs("Example failed: \(error)\n", stderr)
            Foundation.exit(1)
        }

        await client.close()
    }

    private static func describe(_ notification: CodexNotification) -> String {
        switch notification.payload {
        case .itemCompleted(let payload):
            return "item.completed turn=\(payload.turnId)"
        case .itemStarted(let payload):
            return "item.started turn=\(payload.turnId)"
        case .threadStarted(let payload):
            return "thread.started id=\(payload.thread.id)"
        case .turnStarted(let payload):
            return "turn.started id=\(payload.turn.id)"
        case .turnCompleted(let payload):
            return "turn.completed id=\(payload.turn.id) status=\(payload.turn.status.rawValue)"
        case .threadTokenUsageUpdated(let payload):
            return "usage.updated input=\(payload.tokenUsage.total.inputTokens) output=\(payload.tokenUsage.total.outputTokens)"
        case .unknown(let method, _):
            return "unknown notification \(method)"
        default:
            return notification.method
        }
    }
}
