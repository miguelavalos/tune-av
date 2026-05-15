import Foundation

struct TuneAVUpgradePromptContent: Equatable {
    let feature: LimitedFeature
    let title: String
    let message: String

    static func forLimitState(_ state: FeatureLimitState) -> TuneAVUpgradePromptContent {
        TuneAVUpgradePromptContent(
            feature: state.feature,
            title: title(for: state.feature),
            message: message(for: state)
        )
    }

    static func featureName(for feature: LimitedFeature) -> String {
        switch feature {
        case .aviAction:
            L10n.string("mac.limits.feature.aviAction")
        case .favoriteStations:
            L10n.string("mac.limits.feature.favoriteStations")
        case .savedTracks:
            L10n.string("mac.limits.feature.savedTracks")
        case .discoveredTracks:
            L10n.string("mac.limits.feature.discoveredTracks")
        case .lyricsSearch:
            L10n.string("mac.limits.feature.lyrics")
        case .webSearch:
            L10n.string("mac.limits.feature.web")
        case .youtubeSearch:
            L10n.string("mac.limits.feature.youtube")
        case .appleMusicSearch:
            L10n.string("mac.limits.feature.appleMusic")
        case .spotifySearch:
            L10n.string("mac.limits.feature.spotify")
        case .discoveryShare:
            L10n.string("mac.limits.feature.discoveryShare")
        }
    }

    static func title(for feature: LimitedFeature) -> String {
        switch feature {
        case .aviAction:
            L10n.string("limits.upgrade.aviAction.title")
        case .favoriteStations:
            L10n.string("limits.upgrade.favoriteStations.title")
        case .savedTracks:
            L10n.string("limits.upgrade.savedTracks.title")
        case .discoveredTracks:
            L10n.string("limits.upgrade.discoveredTracks.title")
        case .lyricsSearch:
            L10n.string("limits.upgrade.lyrics.title")
        case .webSearch:
            L10n.string("limits.upgrade.web.title")
        case .youtubeSearch:
            L10n.string("limits.upgrade.youtube.title")
        case .appleMusicSearch:
            L10n.string("limits.upgrade.appleMusic.title")
        case .spotifySearch:
            L10n.string("limits.upgrade.spotify.title")
        case .discoveryShare:
            L10n.string("limits.upgrade.discoveryShare.title")
        }
    }

    static func message(for state: FeatureLimitState) -> String {
        guard let limit = state.limit else {
            return L10n.string("limits.upgrade.default.message")
        }

        switch state.feature {
        case .aviAction:
            return L10n.string("limits.upgrade.aviAction.message", limit)
        case .favoriteStations:
            return L10n.string("limits.upgrade.favoriteStations.message", limit)
        case .savedTracks:
            return L10n.string("limits.upgrade.savedTracks.message", limit)
        case .discoveredTracks:
            return L10n.string("limits.upgrade.discoveredTracks.message", limit)
        case .lyricsSearch:
            return L10n.string("limits.upgrade.aviAction.message", limit)
        case .webSearch:
            return L10n.string("limits.upgrade.aviAction.message", limit)
        case .youtubeSearch:
            return L10n.string("limits.upgrade.aviAction.message", limit)
        case .appleMusicSearch:
            return L10n.string("limits.upgrade.aviAction.message", limit)
        case .spotifySearch:
            return L10n.string("limits.upgrade.aviAction.message", limit)
        case .discoveryShare:
            return L10n.string("limits.upgrade.aviAction.message", limit)
        }
    }
}

struct TuneAVUpgradePromptContext: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let benefit: String
    let progressText: String?

    static func favorites(current: Int, limit: Int) -> TuneAVUpgradePromptContext {
        let content = TuneAVUpgradePromptContent.forLimitState(
            FeatureLimitState(feature: .favoriteStations, currentUsage: current, limit: limit)
        )
        return TuneAVUpgradePromptContext(
            title: content.title,
            message: content.message,
            benefit: L10n.string("limits.upgrade.default.message"),
            progressText: L10n.string("mac.limits.progress.favorites", current, limit)
        )
    }

    static func savedTracks(current: Int, limit: Int) -> TuneAVUpgradePromptContext {
        let content = TuneAVUpgradePromptContent.forLimitState(
            FeatureLimitState(feature: .savedTracks, currentUsage: current, limit: limit)
        )
        return TuneAVUpgradePromptContext(
            title: content.title,
            message: content.message,
            benefit: L10n.string("limits.upgrade.default.message"),
            progressText: L10n.string("mac.limits.progress.savedTracks", current, limit)
        )
    }

    static func dailyFeature(_ feature: LimitedFeature, current: Int, limit: Int) -> TuneAVUpgradePromptContext {
        let featureName = TuneAVUpgradePromptContent.featureName(for: feature)
        return TuneAVUpgradePromptContext(
            title: L10n.string("mac.limits.daily.title", featureName),
            message: L10n.string("mac.limits.daily.message", current, limit, featureName),
            benefit: L10n.string("limits.upgrade.default.message"),
            progressText: L10n.string("mac.limits.progress.today", current, limit)
        )
    }
}
