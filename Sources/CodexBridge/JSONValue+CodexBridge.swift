import Codex

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        self.objectValue?[key]
    }

    func objectValue(forKey key: String) -> [String: JSONValue]? {
        self[key]?.objectValue
    }

    func stringValue(forKey key: String) -> String? {
        self[key]?.stringValue
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}
