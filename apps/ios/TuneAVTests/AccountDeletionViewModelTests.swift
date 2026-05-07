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

    func testBlockedBySeriesAVLinkedApp() async {
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

        XCTAssertEqual(viewModel.resolvedEligibility?.status, .unavailable)
        XCTAssertEqual(viewModel.blockers.first?.type, .linkedApp)
        XCTAssertFalse(viewModel.canRequestDeletion)
    }

    func testBlockedByActivePro() async {
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

        XCTAssertEqual(viewModel.resolvedEligibility?.status, .unavailable)
        XCTAssertEqual(viewModel.blockers.first?.type, .activeProAccess)
        XCTAssertFalse(viewModel.canRequestDeletion)
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
}

private struct MockAccountDeletionAPI: AccountDeletionAPI {
    let summary: AccountSummary
    var requestResponse = DeleteAccountRequestResponse(status: nil, job: nil, deleteAccountEligibility: nil)
    var finalizeResponse = DeleteAccountFinalizeResponse(status: nil, job: nil, deleteAccountEligibility: nil)
    var unlinkResponse = UnlinkAppResponse(
        link: UnlinkAppResult(appId: "tuneav", remainingLinkedApps: 1, unlinked: true),
        message: nil
    )

    func fetchAccountSummary() async throws -> AccountSummary {
        summary
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
