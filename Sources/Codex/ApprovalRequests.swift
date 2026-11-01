import Foundation
import Logging

public extension CommandExecutionApprovalDecision {
    /// Accepts the command and applies an execpolicy amendment
    /// (`{"acceptWithExecpolicyAmendment": {"execpolicy_amendment": [...]}}`).
    static func acceptWithExecpolicyAmendment(execpolicyAmendment: [String]) -> Self {
        .acceptWithExecpolicyAmendment(AcceptWithExecpolicyAmendmentCommandExecutionApprovalDecision(
            acceptWithExecpolicyAmendment: .init(execpolicyAmendment: execpolicyAmendment)
        ))
    }

    /// Applies a persistent network policy rule
    /// (`{"applyNetworkPolicyAmendment": {"network_policy_amendment": {...}}}`).
    static func applyNetworkPolicyAmendment(networkPolicyAmendment: NetworkPolicyAmendment) -> Self {
        .applyNetworkPolicyAmendment(ApplyNetworkPolicyAmendmentCommandExecutionApprovalDecision(
            applyNetworkPolicyAmendment: .init(networkPolicyAmendment: networkPolicyAmendment)
        ))
    }
}

/// Decodes and dispatches command and file change approval requests.
///
/// Params are validated against the pinned upstream schemas. The only
/// compatibility path is for older servers that omit `startedAtMs`: when the
/// rest of the params is valid, the simplified handlers still run (with
/// `params == nil`), but typed handlers reject the request with -32602.
enum ApprovalRequests {
    static let commandMethod = "item/commandExecution/requestApproval"
    static let fileChangeMethod = "item/fileChange/requestApproval"

    /// Returns `nil` when params are invalid.
    static func commandRequest(from params: JSONValue?) -> CommandApprovalRequest? {
        guard let raw = params, let typed = decodeAllowingLegacyStartTime(CommandExecutionRequestApprovalParams.self, from: raw) else {
            return nil
        }
        return CommandApprovalRequest(
            threadID: typed.value.threadId,
            turnID: typed.value.turnId,
            itemID: typed.value.itemId,
            approvalID: typed.value.approvalId,
            command: typed.value.command,
            workingDirectory: typed.value.cwd?.rawValue,
            reason: typed.value.reason,
            params: typed.isLegacy ? nil : typed.value,
            rawParams: raw
        )
    }

    /// Returns `nil` when params are invalid.
    static func fileChangeRequest(from params: JSONValue?) -> FileChangeApprovalRequest? {
        guard let raw = params, let typed = decodeAllowingLegacyStartTime(FileChangeRequestApprovalParams.self, from: raw) else {
            return nil
        }
        return FileChangeApprovalRequest(
            threadID: typed.value.threadId,
            turnID: typed.value.turnId,
            itemID: typed.value.itemId,
            reason: typed.value.reason,
            grantRoot: typed.value.grantRoot,
            params: typed.isLegacy ? nil : typed.value,
            rawParams: raw
        )
    }

    static func resolveCommand(params: JSONValue?, config: CodexConfig, logger: Logger) async -> ServerRequestResult {
        guard let request = commandRequest(from: params) else {
            return .error(code: -32602, message: "Invalid params for \(commandMethod)")
        }
        var metadata: Logger.Metadata = [
            "thread_id": .string(request.threadID),
            "turn_id": .string(request.turnID),
            "item_id": .string(request.itemID),
        ]
        if let approvalID = request.approvalID {
            metadata["approval_id"] = .string(approvalID)
        }
        if let handler = config.commandExecutionRequestApprovalHandler {
            guard let typed = request.params else {
                return .error(code: -32602, message: "Invalid params for \(commandMethod)")
            }
            let response: CommandExecutionRequestApprovalResponse
            do {
                response = try await handler(typed)
            } catch {
                return .error(code: -32603, message: "Server request handler failed")
            }
            metadata["decision"] = .string(label(response.decision))
            logger.info("Resolved command approval request", metadata: metadata)
            return .commandExecutionApproval(response)
        }
        let decision = await config.commandApprovalHandler(request)
        metadata["decision"] = .string(decision.rawValue)
        logger.info("Resolved command approval request", metadata: metadata)
        return .approval(decision)
    }

    static func resolveFileChange(params: JSONValue?, config: CodexConfig, logger: Logger) async -> ServerRequestResult {
        guard let request = fileChangeRequest(from: params) else {
            return .error(code: -32602, message: "Invalid params for \(fileChangeMethod)")
        }
        var metadata: Logger.Metadata = [
            "thread_id": .string(request.threadID),
            "turn_id": .string(request.turnID),
            "item_id": .string(request.itemID),
        ]
        if let handler = config.fileChangeRequestApprovalHandler {
            guard let typed = request.params else {
                return .error(code: -32602, message: "Invalid params for \(fileChangeMethod)")
            }
            let response: FileChangeRequestApprovalResponse
            do {
                response = try await handler(typed)
            } catch {
                return .error(code: -32603, message: "Server request handler failed")
            }
            metadata["decision"] = .string(label(response.decision.rawJSON))
            logger.info("Resolved file change approval request", metadata: metadata)
            return .fileChangeApproval(response)
        }
        let decision = await config.fileChangeApprovalHandler(request)
        metadata["decision"] = .string(decision.rawValue)
        logger.info("Resolved file change approval request", metadata: metadata)
        return .approval(decision)
    }

    /// Decodes upstream params. If and only if `startedAtMs` is absent, the
    /// remaining params are validated with a placeholder and flagged legacy;
    /// the placeholder value is never exposed.
    private static func decodeAllowingLegacyStartTime<T: Decodable>(_ type: T.Type, from raw: JSONValue) -> (value: T, isLegacy: Bool)? {
        if let value = try? decodeJSONValue(T.self, from: raw) {
            return (value, false)
        }
        guard var object = raw.objectValue, object["startedAtMs"] == nil else {
            return nil
        }
        object["startedAtMs"] = .number(0)
        guard let value = try? decodeJSONValue(T.self, from: .object(object)) else {
            return nil
        }
        return (value, true)
    }

    private static func label(_ decision: CommandExecutionApprovalDecision) -> String {
        switch decision {
        case .acceptWithExecpolicyAmendment: return "acceptWithExecpolicyAmendment"
        case .applyNetworkPolicyAmendment: return "applyNetworkPolicyAmendment"
        default: return label(decision.rawJSON)
        }
    }

    private static func label(_ decision: JSONValue) -> String {
        decision.stringValue ?? "unknown"
    }
}
