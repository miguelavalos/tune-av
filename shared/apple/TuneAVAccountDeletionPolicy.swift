import Foundation

struct TuneAVAccountDeletionPolicy {
    struct Copy {
        let linkedAppTitle: String
        let linkedAppDetail: String
        let proTitle: String
        let proDetail: String
        let subscriptionTitle: String
        let subscriptionDetail: String
        let jobTitle: String
        let unavailableTitle: String
        let unavailableDetail: String
    }

    static func canRequestDeletion(eligibility: AccountDeletionEligibility?, confirmationText: String) -> Bool {
        eligibility?.status == .eligible && confirmationText == "DELETE"
    }

    static func canFinalizeDeletion(eligibility: AccountDeletionEligibility?, summary: AccountSummary?) -> Bool {
        let status = eligibility?.currentJob?.status ?? summary?.currentDeletionJob?.status
        return ["awaitingIdentityDeletion", "readyToFinalize"].contains(status)
    }

    static func didCompleteDeletion(eligibility: AccountDeletionEligibility?, job: AccountDeletionJob?) -> Bool {
        eligibility?.status == .completed || job?.status == "completed"
    }

    static func canUnlinkCurrentApp(from summary: AccountSummary, currentAppId: String = "tuneav", suiteAppId: String = "avapps") -> Bool {
        let linkedApps = summary.linkedApps.filter { $0.appId != suiteAppId }
        let isCurrentAppLinked = linkedApps.contains { $0.appId == currentAppId }
        let hasOtherLinkedApps = linkedApps.contains { $0.appId != currentAppId }
        let currentAppAccess = summary.access.first { $0.appId == currentAppId }
        let currentAppIsPro = currentAppAccess?.planTier == .pro || currentAppAccess?.accessMode == .signedInPro

        return isCurrentAppLinked && hasOtherLinkedApps && !currentAppIsPro
    }

    static func resolvedEligibility(
        from summary: AccountSummary,
        copy: Copy,
        currentAppId: String = "tuneav",
        suiteAppId: String = "avapps"
    ) -> AccountDeletionEligibility {
        summary.deleteAccountEligibility
            ?? conservativeEligibility(
                from: summary,
                copy: copy,
                currentAppId: currentAppId,
                suiteAppId: suiteAppId
            )
    }

    static func conservativeEligibility(
        from summary: AccountSummary,
        copy: Copy,
        currentAppId: String = "tuneav",
        suiteAppId: String = "avapps"
    ) -> AccountDeletionEligibility {
        var blockers: [AccountDeletionBlocker] = []

        for linkedApp in summary.linkedApps where linkedApp.appId != currentAppId && linkedApp.appId != suiteAppId {
            blockers.append(
                AccountDeletionBlocker(
                    type: .linkedApp,
                    appId: linkedApp.appId,
                    label: copy.linkedAppTitle,
                    detail: copy.linkedAppDetail,
                    managementUrl: nil
                )
            )
        }

        for appAccess in summary.access where appAccess.planTier == .pro || appAccess.accessMode == .signedInPro {
            blockers.append(
                AccountDeletionBlocker(
                    type: .activeProAccess,
                    appId: appAccess.appId,
                    label: copy.proTitle,
                    detail: copy.proDetail,
                    managementUrl: nil
                )
            )
        }

        for subscription in summary.billing?.subscriptions ?? [] where activeBillingStatuses.contains(subscription.status) {
            blockers.append(
                AccountDeletionBlocker(
                    type: .activeBillingSubscription,
                    appId: subscription.appId,
                    label: subscription.provider ?? copy.subscriptionTitle,
                    detail: copy.subscriptionDetail,
                    managementUrl: subscription.managementUrl
                )
            )
        }

        if let currentDeletionJob = summary.currentDeletionJob,
           !inactiveDeletionJobStatuses.contains(currentDeletionJob.status) {
            blockers.append(
                AccountDeletionBlocker(
                    type: .deletionInProgress,
                    appId: nil,
                    label: copy.jobTitle,
                    detail: currentDeletionJob.detail,
                    managementUrl: nil
                )
            )
        }

        if blockers.isEmpty {
            blockers.append(unavailableBlocker(copy: copy))
        }

        return AccountDeletionEligibility(status: .unavailable, blockers: blockers, currentJob: summary.currentDeletionJob)
    }

    static func unavailableEligibility(copy: Copy) -> AccountDeletionEligibility {
        AccountDeletionEligibility(status: .unavailable, blockers: [unavailableBlocker(copy: copy)], currentJob: nil)
    }

    private static func unavailableBlocker(copy: Copy) -> AccountDeletionBlocker {
        AccountDeletionBlocker(
            type: .eligibilityUnavailable,
            appId: nil,
            label: copy.unavailableTitle,
            detail: copy.unavailableDetail,
            managementUrl: nil
        )
    }

    private static let activeBillingStatuses = Set(["active", "trialing", "pastDue", "past_due"])
    private static let inactiveDeletionJobStatuses = Set(["completed", "cancelled", "failed"])
}
