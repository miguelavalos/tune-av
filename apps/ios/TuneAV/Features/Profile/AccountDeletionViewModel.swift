import Foundation

@MainActor
final class AccountDeletionViewModel: ObservableObject {
    @Published private(set) var summary: AccountSummary?
    @Published private(set) var resolvedEligibility: AccountDeletionEligibility?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didCompleteDeletion = false
    @Published private(set) var didUnlinkCurrentApp = false
    @Published private(set) var unlinkMessage: String?
    @Published var confirmationText = ""

    private let api: AccountDeletionAPI
    private let signOut: () async throws -> Void

    init(
        api: AccountDeletionAPI,
        signOut: @escaping () async throws -> Void
    ) {
        self.api = api
        self.signOut = signOut
    }

    var canRequestDeletion: Bool {
        TuneAVAccountDeletionPolicy.canRequestDeletion(eligibility: resolvedEligibility, confirmationText: confirmationText)
    }

    var canFinalizeDeletion: Bool {
        TuneAVAccountDeletionPolicy.canFinalizeDeletion(eligibility: resolvedEligibility, summary: summary)
    }

    var blockers: [AccountDeletionBlocker] {
        resolvedEligibility?.blockers ?? []
    }

    var warnings: [AccountDeletionBlocker] {
        resolvedEligibility?.warnings ?? []
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
                try await completeLocalSignOut()
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
                try await completeLocalSignOut()
                return
            }
            let refreshed = try await api.fetchAccountSummary()
            apply(summary: refreshed)
            if resolvedEligibility?.status == .completed {
                try await completeLocalSignOut()
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
                try await completeLocalSignOut()
                return
            }
            let refreshed = try await api.fetchAccountSummary()
            apply(summary: refreshed)
            if resolvedEligibility?.status == .completed {
                try await completeLocalSignOut()
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
            unlinkMessage = response.message ?? L10n.string("accountDeletion.unlinked.detail")
            try await signOut()
            didUnlinkCurrentApp = true
        } catch {
            errorMessage = L10n.string("accountDeletion.error.unlink")
        }
    }

    private func apply(summary: AccountSummary) {
        self.summary = summary
        resolvedEligibility = TuneAVAccountDeletionPolicy.resolvedEligibility(from: summary, copy: Self.deletionCopy)
    }

    private func completeLocalSignOut() async throws {
        try await signOut()
        didCompleteDeletion = true
    }

    static func conservativeEligibility(from summary: AccountSummary) -> AccountDeletionEligibility {
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
