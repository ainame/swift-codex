public struct TurnOptions: Sendable, Hashable, Codable {
    public var approvalPolicy: AskForApproval?
    public var approvalsReviewer: ApprovalsReviewer?
    public var cwd: String?
    public var effort: ReasoningEffort?
    public var model: String?
    public var outputSchema: JSONObject?
    public var personality: Personality?
    public var sandboxPolicy: SandboxPolicy?
    public var serviceTier: ServiceTier?
    public var summary: ReasoningSummary?

    public init(
        approvalPolicy: AskForApproval? = nil,
        approvalsReviewer: ApprovalsReviewer? = nil,
        cwd: String? = nil,
        effort: ReasoningEffort? = nil,
        model: String? = nil,
        outputSchema: JSONObject? = nil,
        personality: Personality? = nil,
        sandboxPolicy: SandboxPolicy? = nil,
        serviceTier: ServiceTier? = nil,
        summary: ReasoningSummary? = nil
    ) {
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.cwd = cwd
        self.effort = effort
        self.model = model
        self.outputSchema = outputSchema
        self.personality = personality
        self.sandboxPolicy = sandboxPolicy
        self.serviceTier = serviceTier
        self.summary = summary
    }
}
