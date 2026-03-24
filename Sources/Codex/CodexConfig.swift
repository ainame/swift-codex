import Foundation

public typealias CodexConfig = AppServerConfig

enum CodexConfigSerializer {
    static func serialize(_ object: JSONObject) throws -> [String] {
        var overrides: [String] = []
        try flatten(value: .object(object), prefix: "", into: &overrides)
        return overrides
    }

    private static func flatten(value: JSONValue, prefix: String, into overrides: inout [String]) throws {
        guard case .object(let object) = value else {
            guard !prefix.isEmpty else {
                throw CodexError.invalidConfig("Codex config overrides must be a plain object")
            }
            overrides.append("\(prefix)=\(try toTomlValue(value, path: prefix))")
            return
        }

        if prefix.isEmpty && object.isEmpty {
            return
        }

        if !prefix.isEmpty && object.isEmpty {
            overrides.append("\(prefix)={}")
            return
        }

        for key in object.keys.sorted() {
            guard !key.isEmpty else {
                throw CodexError.invalidConfig("Codex config override keys must be non-empty strings")
            }
            guard let child = object[key] else {
                continue
            }
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if case .object = child {
                try flatten(value: child, prefix: path, into: &overrides)
            } else {
                overrides.append("\(path)=\(try toTomlValue(child, path: path))")
            }
        }
    }

    private static func toTomlValue(_ value: JSONValue, path: String) throws -> String {
        switch value {
        case .string(let string):
            return try renderJSONString(string)
        case .number(let number):
            guard number.isFinite else {
                throw CodexError.invalidConfig("Codex config override at \(path) must be a finite number")
            }
            if number.rounded(.towardZero) == number {
                return String(Int64(number))
            }
            return String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .array(let array):
            let rendered = try array.enumerated().map { index, element in
                try toTomlValue(element, path: "\(path)[\(index)]")
            }
            return "[\(rendered.joined(separator: ", "))]"
        case .object(let object):
            let parts = try object.keys.sorted().compactMap { key -> String? in
                guard let child = object[key] else {
                    return nil
                }
                return "\(formatTomlKey(key)) = \(try toTomlValue(child, path: "\(path).\(key)"))"
            }
            return "{\(parts.joined(separator: ", "))}"
        case .null:
            throw CodexError.invalidConfig("Codex config override at \(path) cannot be null")
        }
    }

    private static func formatTomlKey(_ key: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_-]+$"#)
        let range = NSRange(location: 0, length: key.utf16.count)
        if regex.firstMatch(in: key, range: range) != nil {
            return key
        }
        return (try? renderJSONString(key)) ?? "\"\(key)\""
    }

    private static func renderJSONString(_ string: String) throws -> String {
        let encoded = try JSONEncoder().encode(string)
        guard let rendered = String(data: encoded, encoding: .utf8) else {
            throw CodexError.invalidConfig("Failed to encode string config value")
        }
        return rendered
    }
}
