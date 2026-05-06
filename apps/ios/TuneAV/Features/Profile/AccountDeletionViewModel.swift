import Foundation

@MainActor
final class AccountDeletionViewModel: ObservableObject {
    @Published private(set) var summary: AccountSummary?
    @Published private(set) var resolvedEligibility: AccountDeletionEligibility?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didCompleteDeletion = false
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
        resolvedEligibility?.status == .eligible && confirmationText == "DELETE"
    }

    var canFinalizeDeletion: Bool {
        let status = resolvedEligibility?.currentJob?.status ?? summary?.currentDeletionJob?.status
        return ["awaitingIdentityDeletion", "readyToFinalize"].contains(status)
    }

    var blockers: [AccountDeletionBlocker] {
        resolvedEligibility?.blockers ?? []
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
            resolvedEligibility = .unavailable()
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
            if response.deleteAccountEligibility?.status == .completed || response.job?.status == "completed" {
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

    private func apply(summary: AccountSummary) {
        self.summary = summary
        resolvedEligibility = summary.deleteAccountEligibility ?? Self.conservativeEligibility(from: summary)
    }

    private func completeLocalSignOut() async throws {
        try await signOut()
        didCompleteDeletion = true
    }

    static func conservativeEligibility(from summary: AccountSummary) -> AccountDeletionEligibility {
        var blockers: [AccountDeletionBlocker] = []

        for linkedApp in summary.linkedApps where linkedApp.appId != "tuneav" {
            blockers.append(
                AccountDeletionBlocker(
                    type: .linkedApp,
                    appId: linkedApp.appId,
                    label: linkedApp.label ?? appLabel(for: linkedApp.appId),
                    detail: L10n.string("accountDeletion.blocker.linkedApp.detail"),
                    managementUrl: nil
                )
            )
        }

        for appAccess in summary.access where appAccess.planTier == .pro || appAccess.accessMode == .signedInPro {
            blockers.append(
                AccountDeletionBlocker(
                    type: .activeProAccess,
                    appId: appAccess.appId,
                    label: appLabel(for: appAccess.appId),
                    detail: L10n.string("accountDeletion.blocker.pro.detail"),
                    managementUrl: nil
                )
            )
        }

        for subscription in summary.billing?.subscriptions ?? [] where activeBillingStatuses.contains(subscription.status) {
            blockers.append(
                AccountDeletionBlocker(
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
                AccountDeletionBlocker(
                    type: .deletionInProgress,
                    appId: nil,
                    label: L10n.string("accountDeletion.blocker.job.title"),
                    detail: currentDeletionJob.detail,
                    managementUrl: nil
                )
            )
        }

        if blockers.isEmpty {
            blockers.append(
                AccountDeletionBlocker(
                    type: .eligibilityUnavailable,
                    appId: nil,
                    label: L10n.string("accountDeletion.unavailable.title"),
                    detail: L10n.string("accountDeletion.unavailable.detail"),
                    managementUrl: nil
                )
            )
        }

        return AccountDeletionEligibility(status: .unavailable, blockers: blockers, currentJob: summary.currentDeletionJob)
    }

    private static let activeBillingStatuses = Set(["active", "trialing", "pastDue", "past_due"])

    private static func appLabel(for appId: String) -> String {
        switch appId {
        case "tuneav":
            "Tune AV"
        case "seriesav":
            "Series AV"
        case "avphotos":
            "Photo AV"
        case "avapps":
            "Apps AV"
        default:
            appId
        }
    }
}

private extension AccountDeletionEligibility {
    static func unavailable() -> AccountDeletionEligibility {
        AccountDeletionEligibility(
            status: .unavailable,
            blockers: [
                AccountDeletionBlocker(
                    type: .eligibilityUnavailable,
                    appId: nil,
                    label: L10n.string("accountDeletion.unavailable.title"),
                    detail: L10n.string("accountDeletion.unavailable.detail"),
                    managementUrl: nil
                )
            ],
            currentJob: nil
        )
    }
}
