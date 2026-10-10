public struct TurnOptions: Sendable, Hashable, Codable {
    public var approvalPolicy: AskForApproval?
    public var approvalsReviewer: ApprovalsReviewer?
    /// Experimental access program for this turn; omit to use server defaults.
    public var cyberAccessProgram: CyberAccessProgram?
    public var cwd: String?
    public var effort: ReasoningEffort?
    public var model: String?
    public var outputSchema: JSONObject?
    /// The turn that caused this work; omit for work started directly by the user.
    public var parentTurnID: String?
    public var personality: Personality?
    /// The first turn in the chain of work, when known.
    public var rootTurnID: String?
    public var sandbox: Sandbox?
    public var sandboxPolicy: SandboxPolicy?
    public var serviceTier: ServiceTier?
    public var summary: ReasoningSummary?

    public init(
        approvalPolicy: AskForApproval? = nil,
        approvalsReviewer: ApprovalsReviewer? = nil,
        cyberAccessProgram: CyberAccessProgram? = nil,
        cwd: String? = nil,
        effort: ReasoningEffort? = nil,
        model: String? = nil,
        outputSchema: JSONObject? = nil,
        parentTurnID: String? = nil,
        personality: Personality? = nil,
        rootTurnID: String? = nil,
        sandbox: Sandbox? = nil,
        sandboxPolicy: SandboxPolicy? = nil,
        serviceTier: ServiceTier? = nil,
        summary: ReasoningSummary? = nil
    ) {
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.cyberAccessProgram = cyberAccessProgram
        self.cwd = cwd
        self.effort = effort
        self.model = model
        self.outputSchema = outputSchema
        self.parentTurnID = parentTurnID
        self.personality = personality
        self.rootTurnID = rootTurnID
        self.sandbox = sandbox
        self.sandboxPolicy = sandboxPolicy
        self.serviceTier = serviceTier
        self.summary = summary
    }
}
