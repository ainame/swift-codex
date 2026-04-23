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
            return "Cannot stream turn \(requestedTurnID) while \(activeTurnID) is still active"
        case .turnFailed(let message):
            return message
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
