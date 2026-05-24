import Foundation

struct UpgradePrompt: Identifiable, Equatable {
    let id = UUID()
    let feature: LimitedFeature
    let title: String
    let message: String

    static func forLimitState(_ state: FeatureLimitState) -> UpgradePrompt {
        let content = TuneAVUpgradePromptContent.forLimitState(state)
        return UpgradePrompt(
            feature: content.feature,
            title: content.title,
            message: content.message
        )
    }
}
