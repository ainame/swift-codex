import Foundation
import Subprocess

public enum CodexError: Error, Sendable {
    case executableNotFound(String)
    case invalidConfig(String)
    case invalidResponseLine(String)
    case invalidResponse(String)
    case invalidRequestID
    case missingMetadata
    case processFailed(detail: String)
    case transportClosed
    case transportClosedWithStderrTail(String)
    case parseError(message: String, data: JSONValue?)
    case invalidRequest(message: String, data: JSONValue?)
    case methodNotFound(message: String, data: JSONValue?)
    case invalidParams(message: String, data: JSONValue?)
    case internalRPC(message: String, data: JSONValue?)
    case serverBusy(message: String, data: JSONValue?)
    case retryLimitExceeded(message: String, data: JSONValue?)
    case jsonRPCError(code: Int, message: String, data: JSONValue?)
    case concurrentTurnConsumer(activeTurnID: String, requestedTurnID: String)
    case turnFailed(String)
    /// A turn stream cannot be produced without losing notifications.
    case turnStreamUnavailable(threadID: String, turnID: String, reason: TurnStreamUnavailableReason)
    /// The raw `nextNotification()` backlog exceeded its bound and dropped the
    /// oldest notifications. Reported once; later calls continue with newer ones.
    case notificationBacklogOverflow(droppedCount: Int)
}

public enum TurnStreamUnavailableReason: String, Sendable, Hashable {
    /// The turn's stream already delivered `turn/completed`.
    case alreadyConsumed
    /// The completed turn was never streamed and was evicted from the buffer.
    case evicted
    /// The turn produced more notifications than can be replayed.
    case bufferLimitExceeded
    /// The transport closed before the turn completed.
    case transportClosed
    /// No route is retained for this turn (unobserved or beyond the retired-key window).
    case unknownTurn
}

extension CodexError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "Unable to locate \(name). Install Codex and make sure it is on PATH, or pass codexPathOverride."
        case .invalidConfig(let detail):
            return detail
        case .invalidResponseLine(let line):
            return "Failed to parse item: \(line)"
        case .invalidResponse(let detail):
            return detail
        case .invalidRequestID:
            return "Missing JSON-RPC request identifier"
        case .missingMetadata:
            return "Initialize response is missing required metadata"
        case .processFailed(let detail):
            return detail
        case .transportClosed:
            return "The Codex RPC transport closed unexpectedly"
        case .transportClosedWithStderrTail(let stderrTail):
            return "The Codex RPC transport closed unexpectedly:\n\(stderrTail)"
        case .parseError(let message, _),
             .invalidRequest(let message, _),
             .methodNotFound(let message, _),
             .invalidParams(let message, _),
             .internalRPC(let message, _),
             .serverBusy(let message, _),
             .retryLimitExceeded(let message, _):
            return message
        case .jsonRPCError(_, let message, _):
            return message
        case .concurrentTurnConsumer(let activeTurnID, let requestedTurnID):
            if activeTurnID == requestedTurnID {
                return "Turn \(requestedTurnID) already has an active stream"
            }
            return "Cannot stream turn \(requestedTurnID) while \(activeTurnID) is still active"
        case .turnFailed(let message):
            return message
        case .turnStreamUnavailable(let threadID, let turnID, let reason):
            return "Cannot stream turn \(turnID) on thread \(threadID): \(reason.rawValue)"
        case .notificationBacklogOverflow(let droppedCount):
            return "Dropped \(droppedCount) unread notifications from the raw notification backlog"
        }
    }
}

extension CodexError {
    static func fromTerminationStatus(_ status: TerminationStatus, stderr: String) -> CodexError {
        let detail: String
        switch status {
        case .exited(let code):
            detail = "code \(code)"
        case .signaled(let code):
            detail = "signal \(code)"
        @unknown default:
            detail = "\(status)"
        }
        return .processFailed(detail: "Codex process exited with \(detail): \(stderr)")
    }
}
