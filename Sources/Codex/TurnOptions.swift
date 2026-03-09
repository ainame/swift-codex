public struct TurnOptions: Sendable, Hashable {
    public var outputSchema: JSONObject?

    public init(outputSchema: JSONObject? = nil) {
        self.outputSchema = outputSchema
    }
}
