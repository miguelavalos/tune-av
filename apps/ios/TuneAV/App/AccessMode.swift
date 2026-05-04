import Foundation

struct FeatureLimitState: Equatable {
    let feature: LimitedFeature
    let currentUsage: Int
    let limit: Int?

    var isLimited: Bool {
        limit != nil
    }

    var isAllowed: Bool {
        guard let limit else { return true }
        return currentUsage < limit
    }

    var remaining: Int? {
        guard let limit else { return nil }
        return max(limit - currentUsage, 0)
    }
}

struct UpgradePrompt: Identifiable, Equatable {
    let id = UUID()
    let feature: LimitedFeature
    let title: String
    let message: String

    static func forLimitState(_ state: FeatureLimitState) -> UpgradePrompt {
        UpgradePrompt(
            feature: state.feature,
            title: title(for: state.feature),
            message: message(for: state)
        )
    }

    private static func title(for feature: LimitedFeature) -> String {
        switch feature {
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

    private static func message(for state: FeatureLimitState) -> String {
        guard let limit = state.limit else {
            return L10n.string("limits.upgrade.default.message")
        }

        switch state.feature {
        case .favoriteStations:
            return L10n.string("limits.upgrade.favoriteStations.message", limit)
        case .savedTracks:
            return L10n.string("limits.upgrade.savedTracks.message", limit)
        case .discoveredTracks:
            return L10n.string("limits.upgrade.discoveredTracks.message", limit)
        case .lyricsSearch:
            return L10n.string("limits.upgrade.lyrics.message", limit)
        case .webSearch:
            return L10n.string("limits.upgrade.web.message", limit)
        case .youtubeSearch:
            return L10n.string("limits.upgrade.youtube.message", limit)
        case .appleMusicSearch:
            return L10n.string("limits.upgrade.appleMusic.message", limit)
        case .spotifySearch:
            return L10n.string("limits.upgrade.spotify.message", limit)
        case .discoveryShare:
            return L10n.string("limits.upgrade.discoveryShare.message", limit)
        }
    }
}

struct ResolvedAccess: Equatable {
    let planTier: PlanTier
    let accessMode: AccessMode
    let capabilities: AccessCapabilities
    let limits: AccessLimits

    static let guest = ResolvedAccess(
        planTier: .free,
        accessMode: .guest,
        capabilities: .forMode(.guest),
        limits: .forMode(.guest)
    )
}

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
        let words = displayName.split(separator: " ").prefix(2)
        let letters = words.map { String($0.prefix(1)).uppercased() }.joined()
        return letters.isEmpty ? "AV" : letters
    }
}
