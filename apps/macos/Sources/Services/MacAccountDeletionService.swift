import Foundation

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
struct MacUITestAccountDeletionAPI: MacAccountDeletionAPI {
    private let scenario: String

    static func fromEnvironment() -> MacUITestAccountDeletionAPI? {
        guard let scenario = TuneAVUITestEnvironment.current.accountDeletionScenario else {
            return nil
        }
        return MacUITestAccountDeletionAPI(scenario: scenario)
    }

    func fetchAccountSummary() async throws -> MacAccountSummary {
        TuneAVUITestAccountDeletionScenarios.summary(for: scenario)
    }

    func requestAccountDeletion() async throws -> MacDeleteAccountRequestResponse {
        TuneAVUITestAccountDeletionScenarios.completedRequestResponse()
    }

    func finalizeAccountDeletion() async throws -> MacDeleteAccountFinalizeResponse {
        TuneAVUITestAccountDeletionScenarios.completedFinalizeResponse()
    }

    func unlinkCurrentApp() async throws -> MacUnlinkAppResponse {
        TuneAVUITestAccountDeletionScenarios.unlinkResponse()
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
        TuneAVAccountDeletionPolicy.canRequestDeletion(eligibility: resolvedEligibility, confirmationText: confirmationText)
    }

    var canFinalizeDeletion: Bool {
        TuneAVAccountDeletionPolicy.canFinalizeDeletion(eligibility: resolvedEligibility, summary: summary)
    }

    var blockers: [MacAccountDeletionBlocker] {
        resolvedEligibility?.blockers ?? []
    }

    var canUnlinkCurrentApp: Bool {
        guard let summary, !isSubmitting else { return false }
        return TuneAVAccountDeletionPolicy.canUnlinkCurrentApp(from: summary)
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
            resolvedEligibility = TuneAVAccountDeletionPolicy.unavailableEligibility(copy: Self.deletionCopy)
        }
    }

    func requestDeletion() async {
        guard canRequestDeletion, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let response = try await api.requestAccountDeletion()
            if TuneAVAccountDeletionPolicy.didCompleteDeletion(eligibility: response.deleteAccountEligibility, job: response.job) {
                _ = await signOut()
                didCompleteDeletion = true
                return
            }
            let refreshed = try await api.fetchAccountSummary()
            apply(summary: refreshed)
            if resolvedEligibility?.status == .completed {
                _ = await signOut()
                didCompleteDeletion = true
            }
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
            if TuneAVAccountDeletionPolicy.didCompleteDeletion(eligibility: response.deleteAccountEligibility, job: response.job) {
                _ = await signOut()
                didCompleteDeletion = true
                return
            }
            let refreshed = try await api.fetchAccountSummary()
            apply(summary: refreshed)
            if resolvedEligibility?.status == .completed {
                _ = await signOut()
                didCompleteDeletion = true
            }
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
        resolvedEligibility = TuneAVAccountDeletionPolicy.resolvedEligibility(from: summary, copy: Self.deletionCopy)
    }

    static func conservativeEligibility(from summary: MacAccountSummary) -> MacAccountDeletionEligibility {
        TuneAVAccountDeletionPolicy.conservativeEligibility(from: summary, copy: deletionCopy)
    }

    private static var deletionCopy: TuneAVAccountDeletionPolicy.Copy {
        TuneAVAccountDeletionPolicy.Copy(
            linkedAppTitle: L10n.string("accountDeletion.blocker.linkedApp.title"),
            linkedAppDetail: L10n.string("accountDeletion.blocker.linkedApp.detail"),
            proTitle: L10n.string("accountDeletion.blocker.pro.title"),
            proDetail: L10n.string("accountDeletion.blocker.pro.detail"),
            subscriptionTitle: L10n.string("accountDeletion.blocker.subscription.title"),
            subscriptionDetail: L10n.string("accountDeletion.blocker.subscription.detail"),
            jobTitle: L10n.string("accountDeletion.blocker.job.title"),
            unavailableTitle: L10n.string("accountDeletion.unavailable.title"),
            unavailableDetail: L10n.string("accountDeletion.unavailable.detail")
        )
    }
}
