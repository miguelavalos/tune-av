import Foundation

struct MeAccessResponse: Decodable {
    let apps: [AppAccess]
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
        id = try container.decodeIfPresent(String.self, forKey: .id)
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress)
            ?? container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        linkedApps = try container.decodeIfPresent([LinkedAccountApp].self, forKey: .linkedApps) ?? []
        access = try container.decodeIfPresent([AppAccess].self, forKey: .access)
            ?? container.decodeIfPresent([AppAccess].self, forKey: .apps)
            ?? []
        billing = try container.decodeIfPresent(AccountBillingSummary.self, forKey: .billing)
        currentDeletionJob = try container.decodeIfPresent(AccountDeletionJob.self, forKey: .currentDeletionJob)
        deleteAccountEligibility = try container.decodeIfPresent(AccountDeletionEligibility.self, forKey: .deleteAccountEligibility)
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
    let provider: String?
    let status: String
    let managementUrl: URL?
}

struct AccountDeletionEligibility: Decodable, Equatable {
    let status: Status
    let blockers: [AccountDeletionBlocker]
    let currentJob: AccountDeletionJob?

    enum Status: String, Decodable {
        case eligible
        case blocked
        case inProgress
        case completed
        case unavailable
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

struct AppAccess: Decodable {
    let appId: String
    let accessMode: AccessMode
    let planTier: PlanTier
    let capabilities: AccessCapabilities
    let limits: AccessLimits
}

extension AppAccess: Equatable {}

@MainActor
protocol AccountDeletionAPI {
    func fetchAccountSummary() async throws -> AccountSummary
    func requestAccountDeletion() async throws -> DeleteAccountRequestResponse
    func finalizeAccountDeletion() async throws -> DeleteAccountFinalizeResponse
    func unlinkCurrentApp() async throws -> UnlinkAppResponse
}

enum AVAccountAPIClientError: LocalizedError {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "Missing Apps AV account token."
        case .missingBaseURL:
            "Missing Apps AV API base URL."
        case .requestFailed(let statusCode):
            "Apps AV API request failed with status \(statusCode)."
        }
    }
}

@MainActor
final class AVAccountAPIClient {
    private let getToken: () async throws -> String?
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(
        getToken: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.getToken = getToken
        self.urlSession = urlSession
        self.decoder = decoder
    }

    func isConfigured() -> Bool {
        AppConfig.avAccountAPIBaseURL != nil
    }

    func fetchMeAccess() async throws -> MeAccessResponse {
        try await request(path: "/v1/me/access")
    }

    func fetchAccountSummary() async throws -> AccountSummary {
        try await request(path: "/v1/me")
    }

    func requestAccountDeletion() async throws -> DeleteAccountRequestResponse {
        try await request(path: "/v1/me/delete-account-request", method: "POST")
    }

    func finalizeAccountDeletion() async throws -> DeleteAccountFinalizeResponse {
        try await request(path: "/v1/me/delete-account-finalize", method: "POST")
    }

    func unlinkCurrentApp() async throws -> UnlinkAppResponse {
        try await request(path: "/v1/apps/tuneav/link", method: "DELETE")
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        guard let token = try await getToken(), !token.isEmpty else {
            throw AVAccountAPIClientError.missingToken
        }

        guard let baseURL = AppConfig.avAccountAPIBaseURL else {
            throw AVAccountAPIClientError.missingBaseURL
        }

        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appending(path: sanitizedPath)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("tuneav", forHTTPHeaderField: "x-appsav-app-id")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AVAccountAPIClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }
}

extension AVAccountAPIClient: AccountDeletionAPI {}
