public enum CodexRPCErrorMapper {
    public static func map(code: Int, message: String, data: JSONValue?) -> CodexError {
        switch code {
        case -32700:
            return .parseError(message: message, data: data)
        case -32600:
            return .invalidRequest(message: message, data: data)
        case -32601:
            return .methodNotFound(message: message, data: data)
        case -32602:
            return .invalidParams(message: message, data: data)
        case -32603:
            return .internalRPC(message: message, data: data)
        case -32099 ... -32000:
            if containsRetryLimitText(message) {
                return .retryLimitExceeded(message: message, data: data)
            }
            if isServerOverloaded(data) {
                return .serverBusy(message: message, data: data)
            }
            return .jsonRPCError(code: code, message: message, data: data)
        default:
            return .jsonRPCError(code: code, message: message, data: data)
        }
    }

    static func containsRetryLimitText(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("retry limit") || lowered.contains("too many failed attempts")
    }

    public static func isServerOverloaded(_ data: JSONValue?) -> Bool {
        guard let data else {
            return false
        }
        switch data {
        case .string(let value):
            return value.lowercased() == "server_overloaded" || value.lowercased() == "serveroverloaded"
        case .object(let object):
            let directKeys = ["codex_error_info", "codexErrorInfo", "errorInfo"]
            for key in directKeys {
                if isServerOverloaded(object[key]) {
                    return true
                }
            }
            for value in object.values where isServerOverloaded(value) {
                return true
            }
            return false
        case .array(let values):
            return values.contains(where: isServerOverloaded)
        default:
            return false
        }
    }
}
