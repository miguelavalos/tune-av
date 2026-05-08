import Foundation

@MainActor
struct UITestAccountDeletionAPI: AccountDeletionAPI {
    private let scenario: String

    static func fromEnvironment() -> UITestAccountDeletionAPI? {
        guard let scenario = TuneAVUITestEnvironment.current.accountDeletionScenario else {
            return nil
        }
        return UITestAccountDeletionAPI(scenario: scenario)
    }

    func fetchAccountSummary() async throws -> AccountSummary {
        TuneAVUITestAccountDeletionScenarios.summary(for: scenario)
    }

    func requestAccountDeletion() async throws -> DeleteAccountRequestResponse {
        TuneAVUITestAccountDeletionScenarios.completedRequestResponse()
    }

    func finalizeAccountDeletion() async throws -> DeleteAccountFinalizeResponse {
        TuneAVUITestAccountDeletionScenarios.completedFinalizeResponse()
    }

    func unlinkCurrentApp() async throws -> UnlinkAppResponse {
        TuneAVUITestAccountDeletionScenarios.unlinkResponse()
    }
}
