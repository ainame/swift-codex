public struct CodexOptions: Sendable, Hashable {
    public var codexPathOverride: String?
    public var baseURL: String?
    public var apiKey: String?
    public var config: JSONObject?
    public var environment: [String: String]?

    public init(
        codexPathOverride: String? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        config: JSONObject? = nil,
        environment: [String: String]? = nil
    ) {
        self.codexPathOverride = codexPathOverride
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.config = config
        self.environment = environment
    }
}
