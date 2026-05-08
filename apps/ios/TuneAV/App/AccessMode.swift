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

typealias ResolvedAccess = TuneAVResolvedAccess

struct AccountSession: Equatable {
    let user: AccountUser
    let planTier: PlanTier
    let accessMode: AccessMode
    let capabilities: AccessCapabilities
}

struct AccountUser: Equatable {
    let id: String
    let displayName: String
    let emailAddress: String?

    var initials: String {
        TuneAVInitials.make(from: displayName)
    }
}
