import Foundation
import Subprocess

public enum CodexError: Error, Sendable {
    case executableNotFound(String)
    case invalidOutputSchema
    case invalidConfig(String)
    case invalidResponseLine(String)
    case processFailed(detail: String)
    case turnFailed(String)
}

extension CodexError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "Unable to locate \(name). Install Codex and make sure it is on PATH, or pass codexPathOverride."
        case .invalidOutputSchema:
            return "outputSchema must be a plain JSON object."
        case .invalidConfig(let detail):
            return detail
        case .invalidResponseLine(let line):
            return "Failed to parse item: \(line)"
        case .processFailed(let detail):
            return detail
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
        case .unhandledException(let code):
            detail = "signal \(code)"
        @unknown default:
            detail = "\(status)"
        }
        return .processFailed(detail: "Codex Exec exited with \(detail): \(stderr)")
    }
}
