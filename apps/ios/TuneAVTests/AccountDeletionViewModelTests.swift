import XCTest
@testable import TuneAV

@MainActor
final class AccountDeletionViewModelTests: XCTestCase {
    func testSignedInFreeTuneOnlyEligibleCanRequestDeletionAndSignsOut() async {
        var didSignOut = false
        let api = MockAccountDeletionAPI(
            summary: AccountSummary(
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
            ),
            requestResponse: DeleteAccountRequestResponse(
                status: "completed",
                job: AccountDeletionJob(id: "job-1", status: "completed", detail: nil),
                deleteAccountEligibility: AccountDeletionEligibility(status: .completed, blockers: [], currentJob: nil)
            )
        )
        let viewModel = AccountDeletionViewModel(api: api, signOut: { didSignOut = true })

        await viewModel.load()
        viewModel.confirmationText = "DELETE"
        await viewModel.requestDeletion()

        XCTAssertTrue(viewModel.didCompleteDeletion)
        XCTAssertTrue(didSignOut)
    }

    func testWarnsButAllowsDeletionWithSeriesAVLinkedApp() async {
        let viewModel = AccountDeletionViewModel(
            api: MockAccountDeletionAPI(
                summary: AccountSummary(
                    linkedApps: [
                        LinkedAccountApp(appId: "tuneav", label: "Tune AV"),
                        LinkedAccountApp(appId: "seriesav", label: "Series AV")
                    ]
                )
            ),
            signOut: {}
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.resolvedEligibility?.status, .eligible)
        XCTAssertEqual(viewModel.warnings.first?.type, .linkedApp)
        XCTAssertTrue(viewModel.blockers.isEmpty)
        viewModel.confirmationText = "DELETE"
        XCTAssertTrue(viewModel.canRequestDeletion)
    }

    func testWarnsButAllowsDeletionWithActivePro() async {
        let viewModel = AccountDeletionViewModel(
            api: MockAccountDeletionAPI(
                summary: AccountSummary(
                    access: [
                        AppAccess(
                            appId: "tuneav",
                            accessMode: .signedInPro,
                            planTier: .pro,
                            capabilities: .forMode(.signedInPro),
                            limits: .forMode(.signedInPro)
                        )
                    ]
                )
            ),
            signOut: {}
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.resolvedEligibility?.status, .eligible)
        XCTAssertEqual(viewModel.warnings.first?.type, .activeProAccess)
        XCTAssertTrue(viewModel.blockers.isEmpty)
        viewModel.confirmationText = "DELETE"
        XCTAssertTrue(viewModel.canRequestDeletion)
    }

    func testHighImpactWarningsStillAllowDeletion() async {
        let viewModel = AccountDeletionViewModel(
            api: MockAccountDeletionAPI(
                summary: AccountSummary(
                    deleteAccountEligibility: AccountDeletionEligibility(
                        status: .eligible,
                        blockers: [],
                        warnings: [
                            AccountDeletionBlocker(
                                type: .activeAiCredits,
                                appId: "momentsav",
                                label: "Moments AV credits",
                                detail: "Account deletion permanently removes 12 AI credits. This cannot be undone.",
                                managementUrl: nil
                            )
                        ],
                        currentJob: nil
                    )
                )
            ),
            signOut: {}
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.hasHighImpactDeletionWarnings)
        viewModel.confirmationText = "DELETE"
        XCTAssertTrue(viewModel.canRequestDeletion)
    }

    func testCompletedDeletionSignsOutLocallyOnLoad() async {
        var didSignOut = false
        let viewModel = AccountDeletionViewModel(
            api: MockAccountDeletionAPI(
                summary: AccountSummary(
                    deleteAccountEligibility: AccountDeletionEligibility(status: .completed, blockers: [], currentJob: nil)
                )
            ),
            signOut: { didSignOut = true }
        )

        await viewModel.load()
        await Task.yield()

        XCTAssertTrue(viewModel.didCompleteDeletion)
        XCTAssertTrue(didSignOut)
    }

    func testLoadFailureDoesNotPresentAsBlockedDeletion() async {
        let viewModel = AccountDeletionViewModel(
            api: MockAccountDeletionAPI(summary: AccountSummary(), fetchError: MockAccountDeletionAPI.Error.fetchFailed),
            signOut: {}
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.resolvedEligibility?.status, .unavailable)
        XCTAssertEqual(viewModel.blockers.first?.type, .eligibilityUnavailable)
        XCTAssertFalse(viewModel.canRequestDeletion)
    }

    func testOpenDeletionJobIsInProgressNotUnavailable() {
        let eligibility = AccountDeletionViewModel.conservativeEligibility(
            from: AccountSummary(
                currentDeletionJob: AccountDeletionJob(
                    id: "job-1",
                    status: "awaitingIdentityDeletion",
                    detail: "Final identity deletion is pending."
                )
            )
        )

        XCTAssertEqual(eligibility.status, .inProgress)
        XCTAssertEqual(eligibility.currentJob?.status, "awaitingIdentityDeletion")
    }

    func testAccountSummaryDecodesAccessWithoutCapabilitiesAndLimits() throws {
        let json = """
        {
          "id": "user_1",
          "emailAddress": "review@example.com",
          "linkedApps": [{ "appId": "tuneav", "label": "Tune AV" }],
          "access": [
            {
              "appId": "tuneav",
              "accessMode": "signedInFree",
              "planTier": "free"
            }
          ],
          "deleteAccountEligibility": {
            "status": "eligible",
            "blockers": [],
            "warnings": [],
            "currentJob": null
          }
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(AccountSummary.self, from: json)

        XCTAssertEqual(summary.access.first?.appId, "tuneav")
        XCTAssertEqual(summary.access.first?.capabilities, .forMode(.signedInFree))
        XCTAssertEqual(summary.access.first?.limits, .forMode(.signedInFree))
        XCTAssertEqual(summary.deleteAccountEligibility?.status, .eligible)
    }
}

private struct MockAccountDeletionAPI: AccountDeletionAPI {
    enum Error: Swift.Error {
        case fetchFailed
    }

    let summary: AccountSummary
    var fetchError: Swift.Error? = nil
    var requestResponse = DeleteAccountRequestResponse(status: nil, job: nil, deleteAccountEligibility: nil)
    var finalizeResponse = DeleteAccountFinalizeResponse(status: nil, job: nil, deleteAccountEligibility: nil)
    var unlinkResponse = UnlinkAppResponse(
        link: UnlinkAppResult(appId: "tuneav", remainingLinkedApps: 1, unlinked: true),
        message: nil
    )

    func fetchAccountSummary() async throws -> AccountSummary {
        if let fetchError {
            throw fetchError
        }
        return summary
    }

    func requestAccountDeletion() async throws -> DeleteAccountRequestResponse {
        requestResponse
    }

    func finalizeAccountDeletion() async throws -> DeleteAccountFinalizeResponse {
        finalizeResponse
    }

    func unlinkCurrentApp() async throws -> UnlinkAppResponse {
        unlinkResponse
    }
}
