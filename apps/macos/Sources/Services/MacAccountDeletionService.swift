import Foundation

struct MacAccountSummary: Decodable, Equatable {
    let id: String?
    let emailAddress: String?
    let displayName: String?
    let linkedApps: [MacLinkedAccountApp]
    let access: [MacAppAccess]
    let billing: MacAccountBillingSummary?
    let currentDeletionJob: MacAccountDeletionJob?
    let deleteAccountEligibility: MacAccountDeletionEligibility?

    enum CodingKeys: String, CodingKey {
        case id
        case emailAddress
        case email
        case displayName
        case name
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
        linkedApps: [MacLinkedAccountApp] = [],
        access: [MacAppAccess] = [],
        billing: MacAccountBillingSummary? = nil,
        currentDeletionJob: MacAccountDeletionJob? = nil,
        deleteAccountEligibility: MacAccountDeletionEligibility? = nil
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
        id = try container.decodeIfPresent(String.self, forKey: .id)
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress)
            ?? container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        linkedApps = try container.decodeIfPresent([MacLinkedAccountApp].self, forKey: .linkedApps) ?? []
        access = try container.decodeIfPresent([MacAppAccess].self, forKey: .access)
            ?? container.decodeIfPresent([MacAppAccess].self, forKey: .apps)
            ?? []
        billing = try container.decodeIfPresent(MacAccountBillingSummary.self, forKey: .billing)
        currentDeletionJob = try container.decodeIfPresent(MacAccountDeletionJob.self, forKey: .currentDeletionJob)
        deleteAccountEligibility = try container.decodeIfPresent(MacAccountDeletionEligibility.self, forKey: .deleteAccountEligibility)
    }
}

struct MacLinkedAccountApp: Decodable, Equatable, Identifiable {
    let appId: String
    let label: String?

    var id: String { appId }
}

struct MacAccountBillingSummary: Decodable, Equatable {
    let subscriptions: [MacAccountBillingSubscription]

    enum CodingKeys: String, CodingKey {
        case subscriptions
    }

    init(subscriptions: [MacAccountBillingSubscription] = []) {
        self.subscriptions = subscriptions
    }

    init(from decoder: Decoder) throws {
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var decodedSubscriptions: [MacAccountBillingSubscription] = []
            while !unkeyedContainer.isAtEnd {
                decodedSubscriptions.append(try unkeyedContainer.decode(MacAccountBillingSubscription.self))
            }
            subscriptions = decodedSubscriptions
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = try container.decodeIfPresent([MacAccountBillingSubscription].self, forKey: .subscriptions) ?? []
    }
}

struct MacAccountBillingSubscription: Decodable, Equatable, Identifiable {
    let id: String
    let appId: String?
    let provider: String?
    let status: String
    let managementUrl: URL?
}

struct MacAccountDeletionEligibility: Decodable, Equatable {
    let status: Status
    let blockers: [MacAccountDeletionBlocker]
    let currentJob: MacAccountDeletionJob?

    enum Status: String, Decodable {
        case eligible
        case blocked
        case inProgress
        case completed
        case unavailable
    }
}

struct MacAccountDeletionBlocker: Decodable, Equatable, Identifiable {
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
        case activeProAccess
        case activeBillingSubscription
        case identityProvider
        case deletionInProgress
        case eligibilityUnavailable
    }
}

struct MacAccountDeletionJob: Decodable, Equatable, Identifiable {
    let id: String
    let status: String
    let detail: String?
}

struct MacDeleteAccountRequestResponse: Decodable, Equatable {
    let status: String?
    let job: MacAccountDeletionJob?
    let deletionJob: MacAccountDeletionJob?
    let deleteAccountEligibility: MacAccountDeletionEligibility?

    enum CodingKeys: String, CodingKey {
        case status
        case job
        case deletionJob
        case deleteAccountEligibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        let canonicalJob = try container.decodeIfPresent(MacAccountDeletionJob.self, forKey: .deletionJob)
        deletionJob = canonicalJob
        job = try container.decodeIfPresent(MacAccountDeletionJob.self, forKey: .job) ?? canonicalJob
        deleteAccountEligibility = try container.decodeIfPresent(MacAccountDeletionEligibility.self, forKey: .deleteAccountEligibility)
    }
}

struct MacDeleteAccountFinalizeResponse: Decodable, Equatable {
    let status: String?
    let job: MacAccountDeletionJob?
    let deletionJob: MacAccountDeletionJob?
    let deleteAccountEligibility: MacAccountDeletionEligibility?

    enum CodingKeys: String, CodingKey {
        case status
        case job
        case deletionJob
        case deleteAccountEligibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        let canonicalJob = try container.decodeIfPresent(MacAccountDeletionJob.self, forKey: .deletionJob)
        deletionJob = canonicalJob
        job = try container.decodeIfPresent(MacAccountDeletionJob.self, forKey: .job) ?? canonicalJob
        deleteAccountEligibility = try container.decodeIfPresent(MacAccountDeletionEligibility.self, forKey: .deleteAccountEligibility)
    }
}

struct MacUnlinkAppResponse: Decodable, Equatable {
    let link: MacUnlinkAppResult
    let message: String?
}

struct MacUnlinkAppResult: Decodable, Equatable {
    let appId: String
    let remainingLinkedApps: Int
    let unlinked: Bool
}

@MainActor
protocol MacAccountDeletionAPI {
    func fetchAccountSummary() async throws -> MacAccountSummary
    func requestAccountDeletion() async throws -> MacDeleteAccountRequestResponse
    func finalizeAccountDeletion() async throws -> MacDeleteAccountFinalizeResponse
    func unlinkCurrentApp() async throws -> MacUnlinkAppResponse
}

@MainActor
final class MacAccountAPIClient: MacAccountDeletionAPI {
    private let getToken: () async throws -> String?
    private let baseURL: URL?
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(
        baseURL: URL? = MacAppConfig.avAccountAPIBaseURL,
        getToken: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.getToken = getToken
        self.urlSession = urlSession
        self.decoder = decoder
    }

    func fetchAccountSummary() async throws -> MacAccountSummary {
        try await request(path: "/v1/me")
    }

    func requestAccountDeletion() async throws -> MacDeleteAccountRequestResponse {
        try await request(path: "/v1/me/delete-account-request", method: "POST")
    }

    func finalizeAccountDeletion() async throws -> MacDeleteAccountFinalizeResponse {
        try await request(path: "/v1/me/delete-account-finalize", method: "POST")
    }

    func unlinkCurrentApp() async throws -> MacUnlinkAppResponse {
        try await request(path: "/v1/apps/tuneav/link", method: "DELETE")
    }

    private func request<T: Decodable>(path: String, method: String = "GET") async throws -> T {
        guard let token = try await getToken(), !token.isEmpty else {
            throw MacAccessRefreshError.missingToken
        }
        guard let baseURL, baseURL.isSupportedAVAccountBaseURL else {
            throw MacAccessRefreshError.missingBaseURL
        }

        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appending(path: sanitizedPath)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("tuneav", forHTTPHeaderField: "x-appsav-app-id")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MacAccessRefreshError.requestFailed(statusCode: httpResponse.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}

@MainActor
final class MacAccountDeletionViewModel: ObservableObject {
    @Published private(set) var summary: MacAccountSummary?
    @Published private(set) var resolvedEligibility: MacAccountDeletionEligibility?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didCompleteDeletion = false
    @Published private(set) var didUnlinkCurrentApp = false
    @Published private(set) var unlinkMessage: String?
    @Published var confirmationText = ""

    private let api: MacAccountDeletionAPI
    private let signOut: () async -> Bool

    init(api: MacAccountDeletionAPI, signOut: @escaping () async -> Bool) {
        self.api = api
        self.signOut = signOut
    }

    var canRequestDeletion: Bool {
        resolvedEligibility?.status == .eligible && confirmationText == "DELETE"
    }

    var canFinalizeDeletion: Bool {
        let status = resolvedEligibility?.currentJob?.status ?? summary?.currentDeletionJob?.status
        return ["awaitingIdentityDeletion", "readyToFinalize"].contains(status)
    }

    var blockers: [MacAccountDeletionBlocker] {
        resolvedEligibility?.blockers ?? []
    }

    var canUnlinkCurrentApp: Bool {
        guard let summary, !isSubmitting else { return false }
        return Self.canUnlinkCurrentApp(from: summary)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let summary = try await api.fetchAccountSummary()
            apply(summary: summary)
            if resolvedEligibility?.status == .completed {
                _ = await signOut()
                didCompleteDeletion = true
            }
        } catch {
            errorMessage = L10n.string("accountDeletion.error.load")
            resolvedEligibility = Self.unavailableEligibility()
        }
    }

    func requestDeletion() async {
        guard canRequestDeletion, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let response = try await api.requestAccountDeletion()
            if response.deleteAccountEligibility?.status == .completed || response.job?.status == "completed" {
                _ = await signOut()
                didCompleteDeletion = true
                return
            }
            let refreshed = try await api.fetchAccountSummary()
            apply(summary: refreshed)
        } catch {
            errorMessage = L10n.string("accountDeletion.error.request")
        }
    }

    func finalizeDeletion() async {
        guard canFinalizeDeletion, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let response = try await api.finalizeAccountDeletion()
            if response.deleteAccountEligibility?.status == .completed || response.job?.status == "completed" {
                _ = await signOut()
                didCompleteDeletion = true
                return
            }
            let refreshed = try await api.fetchAccountSummary()
            apply(summary: refreshed)
        } catch {
            errorMessage = L10n.string("accountDeletion.error.finalize")
        }
    }

    func unlinkCurrentApp() async {
        guard canUnlinkCurrentApp, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let response = try await api.unlinkCurrentApp()
            unlinkMessage = response.message ?? L10n.string("mac.accountDeletion.unlinked.detail")
            _ = await signOut()
            didUnlinkCurrentApp = true
        } catch {
            errorMessage = L10n.string("accountDeletion.error.unlink")
        }
    }

    private func apply(summary: MacAccountSummary) {
        self.summary = summary
        resolvedEligibility = summary.deleteAccountEligibility ?? Self.conservativeEligibility(from: summary)
    }

    static func conservativeEligibility(from summary: MacAccountSummary) -> MacAccountDeletionEligibility {
        var blockers: [MacAccountDeletionBlocker] = []

        for linkedApp in summary.linkedApps where linkedApp.appId != "tuneav" && linkedApp.appId != "avapps" {
            blockers.append(
                MacAccountDeletionBlocker(
                    type: .linkedApp,
                    appId: linkedApp.appId,
                    label: L10n.string("accountDeletion.blocker.linkedApp.title"),
                    detail: L10n.string("accountDeletion.blocker.linkedApp.detail"),
                    managementUrl: nil
                )
            )
        }

        for appAccess in summary.access where appAccess.planTier == .pro || appAccess.accessMode == .signedInPro {
            blockers.append(
                MacAccountDeletionBlocker(
                    type: .activeProAccess,
                    appId: appAccess.appId,
                    label: L10n.string("accountDeletion.blocker.pro.title"),
                    detail: L10n.string("accountDeletion.blocker.pro.detail"),
                    managementUrl: nil
                )
            )
        }

        for subscription in summary.billing?.subscriptions ?? [] where activeBillingStatuses.contains(subscription.status) {
            blockers.append(
                MacAccountDeletionBlocker(
                    type: .activeBillingSubscription,
                    appId: subscription.appId,
                    label: subscription.provider ?? L10n.string("accountDeletion.blocker.subscription.title"),
                    detail: L10n.string("accountDeletion.blocker.subscription.detail"),
                    managementUrl: subscription.managementUrl
                )
            )
        }

        if let currentDeletionJob = summary.currentDeletionJob,
           !["completed", "cancelled", "failed"].contains(currentDeletionJob.status) {
            blockers.append(
                MacAccountDeletionBlocker(
                    type: .deletionInProgress,
                    appId: nil,
                    label: L10n.string("accountDeletion.blocker.job.title"),
                    detail: currentDeletionJob.detail,
                    managementUrl: nil
                )
            )
        }

        if blockers.isEmpty {
            return unavailableEligibility()
        }

        return MacAccountDeletionEligibility(status: .unavailable, blockers: blockers, currentJob: summary.currentDeletionJob)
    }

    private static func unavailableEligibility() -> MacAccountDeletionEligibility {
        MacAccountDeletionEligibility(
            status: .unavailable,
            blockers: [
                MacAccountDeletionBlocker(
                    type: .eligibilityUnavailable,
                    appId: nil,
                    label: L10n.string("accountDeletion.blocker.eligibility.title"),
                    detail: L10n.string("accountDeletion.blocker.eligibility.detail"),
                    managementUrl: nil
                )
            ],
            currentJob: nil
        )
    }

    private static let activeBillingStatuses = Set(["active", "trialing", "pastDue", "past_due"])

    private static func canUnlinkCurrentApp(from summary: MacAccountSummary) -> Bool {
        let linkedApps = summary.linkedApps.filter { $0.appId != "avapps" }
        let isCurrentAppLinked = linkedApps.contains { $0.appId == "tuneav" }
        let hasOtherLinkedApps = linkedApps.contains { $0.appId != "tuneav" }
        let currentAppAccess = summary.access.first { $0.appId == "tuneav" }
        let currentAppIsPro = currentAppAccess?.planTier == .pro || currentAppAccess?.accessMode == .signedInPro

        return isCurrentAppLinked && hasOtherLinkedApps && !currentAppIsPro
    }
}
