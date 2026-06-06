import Foundation

enum TuneAVInitials {
    static func make(from value: String, fallback: String = "AV") -> String {
        let tokens = value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .compactMap { token -> String? in
                let folded = token.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                let letters = folded.unicodeScalars.filter { CharacterSet.letters.contains($0) }
                guard let firstLetter = letters.first else { return nil }
                return String(Character(firstLetter)).uppercased()
            }

        let letters = tokens
            .prefix(2)
            .joined()

        return letters.isEmpty ? fallback : letters
    }
}

struct AccountSummary: Decodable, Equatable {
    let id: String?
    let emailAddress: String?
    let displayName: String?
    let linkedApps: [LinkedAccountApp]
    let access: [AppAccess]
    let billing: AccountBillingSummary?
    let currentDeletionJob: AccountDeletionJob?
    let deleteAccountEligibility: AccountDeletionEligibility?

    enum CodingKeys: String, CodingKey {
        case id
        case emailAddress
        case email
        case displayName
        case name
        case user
        case linkedApps
        case apps
        case access
        case billing
        case currentDeletionJob
        case deleteAccountEligibility
    }

    init(
        id: String? = nil,
        emailAddress: String? = nil,
        displayName: String? = nil,
        linkedApps: [LinkedAccountApp] = [],
        access: [AppAccess] = [],
        billing: AccountBillingSummary? = nil,
        currentDeletionJob: AccountDeletionJob? = nil,
        deleteAccountEligibility: AccountDeletionEligibility? = nil
    ) {
        self.id = id
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.linkedApps = linkedApps
        self.access = access
        self.billing = billing
        self.currentDeletionJob = currentDeletionJob
        self.deleteAccountEligibility = deleteAccountEligibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let user = try container.decodeIfPresent(AccountSummaryUser.self, forKey: .user)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? user?.id
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress)
            ?? container.decodeIfPresent(String.self, forKey: .email)
            ?? user?.emailAddress
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? user?.displayName
        linkedApps = try container.decodeIfPresent([LinkedAccountApp].self, forKey: .linkedApps) ?? []
        access = try container.decodeIfPresent([AppAccess].self, forKey: .access)
            ?? container.decodeIfPresent([AppAccess].self, forKey: .apps)
            ?? []
        billing = try container.decodeIfPresent(AccountBillingSummary.self, forKey: .billing)
        currentDeletionJob = try container.decodeIfPresent(AccountDeletionJob.self, forKey: .currentDeletionJob)
        deleteAccountEligibility = try container.decodeIfPresent(AccountDeletionEligibility.self, forKey: .deleteAccountEligibility)
    }
}

private struct AccountSummaryUser: Decodable, Equatable {
    let id: String?
    let emailAddress: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case emailAddress
        case displayName
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress)
            ?? container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct LinkedAccountApp: Decodable, Equatable, Identifiable {
    let appId: String
    let label: String?

    var id: String { appId }
}

struct AccountBillingSummary: Decodable, Equatable {
    let subscriptions: [AccountBillingSubscription]

    enum CodingKeys: String, CodingKey {
        case subscriptions
    }

    init(subscriptions: [AccountBillingSubscription] = []) {
        self.subscriptions = subscriptions
    }

    init(from decoder: Decoder) throws {
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var decodedSubscriptions: [AccountBillingSubscription] = []
            while !unkeyedContainer.isAtEnd {
                decodedSubscriptions.append(try unkeyedContainer.decode(AccountBillingSubscription.self))
            }
            subscriptions = decodedSubscriptions
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try container.decodeIfPresent([AccountBillingSubscription].self, forKey: .subscriptions) ?? []
    }
}

struct AccountBillingSubscription: Decodable, Equatable, Identifiable {
    let id: String
    let appId: String?
    let planId: String?
    let planTier: PlanTier?
    let provider: String?
    let status: String
    let renewsAt: String?
    let expiresAt: String?
    let managementUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case appId
        case planId
        case name
        case planTier
        case provider
        case status
        case renewsAt
        case expiresAt
        case managementUrl
        case manageUrl
    }

    init(
        id: String,
        appId: String? = nil,
        planId: String? = nil,
        planTier: PlanTier? = nil,
        provider: String? = nil,
        status: String,
        renewsAt: String? = nil,
        expiresAt: String? = nil,
        managementUrl: URL? = nil
    ) {
        self.id = id
        self.appId = appId
        self.planId = planId
        self.planTier = planTier
        self.provider = provider
        self.status = status
        self.renewsAt = renewsAt
        self.expiresAt = expiresAt
        self.managementUrl = managementUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decodeIfPresent(String.self, forKey: .appId)
        planId = try container.decodeIfPresent(String.self, forKey: .planId)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        planTier = try container.decodeIfPresent(PlanTier.self, forKey: .planTier)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        status = try container.decode(String.self, forKey: .status)
        renewsAt = try container.decodeIfPresent(String.self, forKey: .renewsAt)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        managementUrl = try container.decodeIfPresent(URL.self, forKey: .managementUrl)
            ?? container.decodeIfPresent(URL.self, forKey: .manageUrl)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? [appId, planId, provider, status].compactMap { $0 }.joined(separator: ":")
    }
}

struct AccountDeletionEligibility: Decodable, Equatable {
    let status: Status
    let blockers: [AccountDeletionBlocker]
    let warnings: [AccountDeletionBlocker]
    let currentJob: AccountDeletionJob?

    enum Status: String, Decodable {
        case eligible
        case blocked
        case inProgress
        case completed
        case unavailable
    }

    init(
        status: Status,
        blockers: [AccountDeletionBlocker],
        warnings: [AccountDeletionBlocker] = [],
        currentJob: AccountDeletionJob?
    ) {
        self.status = status
        self.blockers = blockers
        self.warnings = warnings
        self.currentJob = currentJob
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case blockers
        case warnings
        case currentJob
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Status.self, forKey: .status)
        blockers = try container.decodeIfPresent([AccountDeletionBlocker].self, forKey: .blockers) ?? []
        warnings = try container.decodeIfPresent([AccountDeletionBlocker].self, forKey: .warnings) ?? []
        currentJob = try container.decodeIfPresent(AccountDeletionJob.self, forKey: .currentJob)
    }
}

struct AccountDeletionBlocker: Decodable, Equatable, Identifiable {
    let type: BlockerType
    let appId: String?
    let label: String
    let detail: String?
    let managementUrl: URL?

    var id: String {
        [type.rawValue, appId, label, detail].compactMap { $0 }.joined(separator: "|")
    }

    enum BlockerType: String, Decodable {
        case linkedApp
        case activeAiCredits
        case activeProAccess
        case activeBillingSubscription
        case identityProvider
        case deletionInProgress
        case eligibilityUnavailable
    }
}

struct AccountDeletionJob: Decodable, Equatable, Identifiable {
    let id: String
    let status: String
    let detail: String?
}

struct DeleteAccountRequestResponse: Decodable, Equatable {
    let status: String?
    let job: AccountDeletionJob?
    let deletionJob: AccountDeletionJob?
    let deleteAccountEligibility: AccountDeletionEligibility?

    enum CodingKeys: String, CodingKey {
        case status
        case job
        case deletionJob
        case deleteAccountEligibility
    }

    init(status: String? = nil, job: AccountDeletionJob? = nil, deletionJob: AccountDeletionJob? = nil, deleteAccountEligibility: AccountDeletionEligibility? = nil) {
        self.status = status
        self.deletionJob = deletionJob ?? job
        self.job = job ?? deletionJob
        self.deleteAccountEligibility = deleteAccountEligibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        let canonicalJob = try container.decodeIfPresent(AccountDeletionJob.self, forKey: .deletionJob)
        deletionJob = canonicalJob
        job = try container.decodeIfPresent(AccountDeletionJob.self, forKey: .job) ?? canonicalJob
        deleteAccountEligibility = try container.decodeIfPresent(AccountDeletionEligibility.self, forKey: .deleteAccountEligibility)
    }
}

struct DeleteAccountFinalizeResponse: Decodable, Equatable {
    let status: String?
    let job: AccountDeletionJob?
    let deletionJob: AccountDeletionJob?
    let deleteAccountEligibility: AccountDeletionEligibility?

    enum CodingKeys: String, CodingKey {
        case status
        case job
        case deletionJob
        case deleteAccountEligibility
    }

    init(status: String? = nil, job: AccountDeletionJob? = nil, deletionJob: AccountDeletionJob? = nil, deleteAccountEligibility: AccountDeletionEligibility? = nil) {
        self.status = status
        self.deletionJob = deletionJob ?? job
        self.job = job ?? deletionJob
        self.deleteAccountEligibility = deleteAccountEligibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        let canonicalJob = try container.decodeIfPresent(AccountDeletionJob.self, forKey: .deletionJob)
        deletionJob = canonicalJob
        job = try container.decodeIfPresent(AccountDeletionJob.self, forKey: .job) ?? canonicalJob
        deleteAccountEligibility = try container.decodeIfPresent(AccountDeletionEligibility.self, forKey: .deleteAccountEligibility)
    }
}

struct UnlinkAppResponse: Decodable, Equatable {
    let link: UnlinkAppResult
    let message: String?
}

struct UnlinkAppResult: Decodable, Equatable {
    let appId: String
    let remainingLinkedApps: Int
    let unlinked: Bool
}

typealias MacAccountSummary = AccountSummary
typealias MacLinkedAccountApp = LinkedAccountApp
typealias MacAccountBillingSummary = AccountBillingSummary
typealias MacAccountBillingSubscription = AccountBillingSubscription
typealias MacAccountDeletionEligibility = AccountDeletionEligibility
typealias MacAccountDeletionBlocker = AccountDeletionBlocker
typealias MacAccountDeletionJob = AccountDeletionJob
typealias MacDeleteAccountRequestResponse = DeleteAccountRequestResponse
typealias MacDeleteAccountFinalizeResponse = DeleteAccountFinalizeResponse
typealias MacUnlinkAppResponse = UnlinkAppResponse
typealias MacUnlinkAppResult = UnlinkAppResult
