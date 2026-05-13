import Foundation

enum TuneAVUITestAccountDeletionScenarios {
    static func summary(for scenario: String) -> AccountSummary {
        switch scenario {
        case "blocked_series":
            AccountSummary(
                id: TuneAVUITestEnvironment.accountUserId,
                emailAddress: TuneAVUITestEnvironment.accountUserEmailAddress,
                displayName: TuneAVUITestEnvironment.accountUserDisplayName,
                linkedApps: [
                    LinkedAccountApp(appId: "tuneav", label: "Apps AV"),
                    LinkedAccountApp(appId: "seriesav", label: "Apps AV")
                ],
                deleteAccountEligibility: AccountDeletionEligibility(
                    status: .eligible,
                    blockers: [],
                    warnings: [
                        AccountDeletionBlocker(
                            type: .linkedApp,
                            appId: "seriesav",
                            label: L10n.string("accountDeletion.blocker.linkedApp.title"),
                            detail: L10n.string("accountDeletion.blocker.linkedApp.detail"),
                            managementUrl: nil
                        )
                    ],
                    currentJob: nil
                )
            )
        case "blocked_pro":
            AccountSummary(
                id: TuneAVUITestEnvironment.accountUserId,
                emailAddress: TuneAVUITestEnvironment.accountUserEmailAddress,
                displayName: TuneAVUITestEnvironment.accountUserDisplayName,
                access: [
                    AppAccess(
                        appId: "tuneav",
                        accessMode: .signedInPro,
                        planTier: .pro,
                        capabilities: .forMode(.signedInPro),
                        limits: .forMode(.signedInPro)
                    )
                ],
                deleteAccountEligibility: AccountDeletionEligibility(
                    status: .eligible,
                    blockers: [],
                    warnings: [
                        AccountDeletionBlocker(
                            type: .activeProAccess,
                            appId: "tuneav",
                            label: L10n.string("accountDeletion.blocker.pro.title"),
                            detail: L10n.string("accountDeletion.blocker.pro.detail"),
                            managementUrl: nil
                        )
                    ],
                    currentJob: nil
                )
            )
        case "completed":
            AccountSummary(
                id: TuneAVUITestEnvironment.accountUserId,
                emailAddress: TuneAVUITestEnvironment.accountUserEmailAddress,
                displayName: TuneAVUITestEnvironment.accountUserDisplayName,
                deleteAccountEligibility: AccountDeletionEligibility(status: .completed, blockers: [], currentJob: nil)
            )
        default:
            AccountSummary(
                id: TuneAVUITestEnvironment.accountUserId,
                emailAddress: TuneAVUITestEnvironment.accountUserEmailAddress,
                displayName: TuneAVUITestEnvironment.accountUserDisplayName,
                linkedApps: [LinkedAccountApp(appId: "tuneav", label: "Apps AV")],
                access: [
                    AppAccess(
                        appId: "tuneav",
                        accessMode: .signedInFree,
                        planTier: .free,
                        capabilities: .forMode(.signedInFree),
                        limits: .forMode(.signedInFree)
                    )
                ],
                deleteAccountEligibility: AccountDeletionEligibility(status: .eligible, blockers: [], currentJob: nil)
            )
        }
    }

    static func completedRequestResponse() -> DeleteAccountRequestResponse {
        DeleteAccountRequestResponse(
            status: "completed",
            job: AccountDeletionJob(id: "ui-test-job", status: "completed", detail: nil),
            deleteAccountEligibility: AccountDeletionEligibility(status: .completed, blockers: [], currentJob: nil)
        )
    }

    static func completedFinalizeResponse() -> DeleteAccountFinalizeResponse {
        DeleteAccountFinalizeResponse(
            status: "completed",
            job: AccountDeletionJob(id: "ui-test-job", status: "completed", detail: nil),
            deleteAccountEligibility: AccountDeletionEligibility(status: .completed, blockers: [], currentJob: nil)
        )
    }

    static func unlinkResponse() -> UnlinkAppResponse {
        UnlinkAppResponse(
            link: UnlinkAppResult(appId: "tuneav", remainingLinkedApps: 1, unlinked: true),
            message: L10n.string("accountDeletion.unlinked.detail")
        )
    }
}
