public struct ThreadOptions: Sendable, Hashable, Codable {
    public var approvalPolicy: AskForApproval?
    public var approvalsReviewer: ApprovalsReviewer?
    public var baseInstructions: String?
    public var config: JSONObject?
    public var cwd: String?
    public var developerInstructions: String?
    public var ephemeral: Bool?
    public var model: String?
    public var modelProvider: String?
    public var personality: Personality?
    public var sandbox: SandboxMode?
    public var serviceName: String?
    public var serviceTier: ServiceTier?
    public var sessionStartSource: ThreadStartSource?

    public init(
        approvalPolicy: AskForApproval? = nil,
        approvalsReviewer: ApprovalsReviewer? = nil,
        baseInstructions: String? = nil,
        config: JSONObject? = nil,
        cwd: String? = nil,
        developerInstructions: String? = nil,
        ephemeral: Bool? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        personality: Personality? = nil,
        sandbox: SandboxMode? = nil,
        serviceName: String? = nil,
        serviceTier: ServiceTier? = nil,
        sessionStartSource: ThreadStartSource? = nil
    ) {
        self.approvalPolicy = approvalPolicy
        self.approvalsReviewer = approvalsReviewer
        self.baseInstructions = baseInstructions
        self.config = config
        self.cwd = cwd
        self.developerInstructions = developerInstructions
        self.ephemeral = ephemeral
        self.model = model
        self.modelProvider = modelProvider
        self.personality = personality
        self.sandbox = sandbox
        self.serviceName = serviceName
        self.serviceTier = serviceTier
        self.sessionStartSource = sessionStartSource
    }
}

public struct ThreadListOptions: Sendable, Hashable, Codable {
    public var archived: Bool?
    public var cursor: String?
    public var cwd: String?
    public var limit: Int?
    public var modelProviders: [String]?
    public var searchTerm: String?
    public var sortDirection: SortDirection?
    public var sortKey: ThreadSortKey?
    public var sourceKinds: [ThreadSourceKind]?

    public init(
        archived: Bool? = nil,
        cursor: String? = nil,
        cwd: String? = nil,
        limit: Int? = nil,
        modelProviders: [String]? = nil,
        searchTerm: String? = nil,
        sortDirection: SortDirection? = nil,
        sortKey: ThreadSortKey? = nil,
        sourceKinds: [ThreadSourceKind]? = nil
    ) {
        self.archived = archived
        self.cursor = cursor
        self.cwd = cwd
        self.limit = limit
        self.modelProviders = modelProviders
        self.searchTerm = searchTerm
        self.sortDirection = sortDirection
        self.sortKey = sortKey
        self.sourceKinds = sourceKinds
    }
}
