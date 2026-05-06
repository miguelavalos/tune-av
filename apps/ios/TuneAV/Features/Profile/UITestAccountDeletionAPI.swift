import Foundation

@MainActor
struct UITestAccountDeletionAPI: AccountDeletionAPI {
    private let scenario: String
    private var didRequestDeletion = false

    static func fromEnvironment() -> UITestAccountDeletionAPI? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TUNEAV_UI_TESTS"] == "1",
              let scenario = environment["TUNEAV_UI_TEST_ACCOUNT_DELETION"] else {
            return nil
        }
        return UITestAccountDeletionAPI(scenario: scenario)
    }

    func fetchAccountSummary() async throws -> AccountSummary {
        switch scenario {
        case "blocked_series":
            AccountSummary(
                id: "ui-test-user",
                emailAddress: "ui-test@example.test",
                displayName: "UI Test User",
                linkedApps: [
                    LinkedAccountApp(appId: "tuneav", label: "Tune AV"),
                    LinkedAccountApp(appId: "seriesav", label: "Series AV")
                ],
                deleteAccountEligibility: AccountDeletionEligibility(
                    status: .blocked,
                    blockers: [
                        AccountDeletionBlocker(
                            type: .linkedApp,
                            appId: "seriesav",
                            label: "Series AV",
                            detail: L10n.string("accountDeletion.blocker.linkedApp.detail"),
                            managementUrl: nil
                        )
                    ],
                    currentJob: nil
                )
            )
        case "blocked_pro":
            AccountSummary(
                id: "ui-test-user",
                emailAddress: "ui-test@example.test",
                displayName: "UI Test User",
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
                    status: .blocked,
                    blockers: [
                        AccountDeletionBlocker(
                            type: .activeProAccess,
                            appId: "tuneav",
                            label: "Tune AV Pro",
                            detail: L10n.string("accountDeletion.blocker.pro.detail"),
                            managementUrl: nil
                        )
                    ],
                    currentJob: nil
                )
            )
        case "completed":
            AccountSummary(
                id: "ui-test-user",
                emailAddress: "ui-test@example.test",
                displayName: "UI Test User",
                deleteAccountEligibility: AccountDeletionEligibility(status: .completed, blockers: [], currentJob: nil)
            )
        default:
            AccountSummary(
                id: "ui-test-user",
                emailAddress: "ui-test@example.test",
                displayName: "UI Test User",
                linkedApps: [LinkedAccountApp(appId: "tuneav", label: "Tune AV")],
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

    func requestAccountDeletion() async throws -> DeleteAccountRequestResponse {
        DeleteAccountRequestResponse(
            status: "completed",
            job: AccountDeletionJob(id: "ui-test-job", status: "completed", detail: nil),
            deleteAccountEligibility: AccountDeletionEligibility(status: .completed, blockers: [], currentJob: nil)
        )
    }

    func finalizeAccountDeletion() async throws -> DeleteAccountFinalizeResponse {
        DeleteAccountFinalizeResponse(
            status: "completed",
            job: AccountDeletionJob(id: "ui-test-job", status: "completed", detail: nil),
            deleteAccountEligibility: AccountDeletionEligibility(status: .completed, blockers: [], currentJob: nil)
        )
    }
}
