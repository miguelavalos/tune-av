import Foundation

enum AccessMode: String, CaseIterable, Codable, Identifiable {
    case guest
    case signedInFree
    case signedInPro

    var id: String { rawValue }
}

enum PlanTier: String, Codable {
    case free
    case pro
}

enum LimitedFeature: String, CaseIterable, Codable {
    case favoriteStations
    case savedTracks
    case discoveredTracks
    case lyricsSearch
    case webSearch
    case youtubeSearch
    case appleMusicSearch
    case spotifySearch
    case discoveryShare
}

struct TuneAVAccessLimitValues: Equatable {
    let favoriteStations: Int?
    let recentStations: Int?
    let discoveredTracks: Int?
    let savedTracks: Int?
    let lyricsSearchesPerDay: Int?
    let webSearchesPerDay: Int?
    let youtubeSearchesPerDay: Int?
    let appleMusicSearchesPerDay: Int?
    let spotifySearchesPerDay: Int?
    let discoverySharesPerDay: Int?
}

struct TuneAVAccessCapabilityValues: Equatable {
    let isSignedIn: Bool
    let canUseBackend: Bool
    let canAccessPremiumFeatures: Bool
    let canUseCloudSync: Bool
    let canManagePlan: Bool
}

struct AccessLimits: Codable, Equatable {
    let favoriteStations: Int?
    let recentStations: Int?
    let discoveredTracks: Int?
    let savedTracks: Int?
    let lyricsSearchesPerDay: Int?
    let webSearchesPerDay: Int?
    let youtubeSearchesPerDay: Int?
    let appleMusicSearchesPerDay: Int?
    let spotifySearchesPerDay: Int?
    let discoverySharesPerDay: Int?

    enum CodingKeys: String, CodingKey {
        case favoriteStations
        case recentStations
        case discoveredTracks
        case savedTracks
        case lyricsSearchesPerDay
        case webSearchesPerDay
        case youtubeSearchesPerDay
        case appleMusicSearchesPerDay
        case spotifySearchesPerDay
        case discoverySharesPerDay
    }

    init(
        favoriteStations: Int?,
        recentStations: Int?,
        discoveredTracks: Int?,
        savedTracks: Int?,
        lyricsSearchesPerDay: Int?,
        webSearchesPerDay: Int?,
        youtubeSearchesPerDay: Int?,
        appleMusicSearchesPerDay: Int?,
        spotifySearchesPerDay: Int?,
        discoverySharesPerDay: Int?
    ) {
        self.favoriteStations = favoriteStations
        self.recentStations = recentStations
        self.discoveredTracks = discoveredTracks
        self.savedTracks = savedTracks
        self.lyricsSearchesPerDay = lyricsSearchesPerDay
        self.webSearchesPerDay = webSearchesPerDay
        self.youtubeSearchesPerDay = youtubeSearchesPerDay
        self.appleMusicSearchesPerDay = appleMusicSearchesPerDay
        self.spotifySearchesPerDay = spotifySearchesPerDay
        self.discoverySharesPerDay = discoverySharesPerDay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.favoriteStations = try container.decodeIfPresent(Int.self, forKey: .favoriteStations)
        self.recentStations = try container.decodeIfPresent(Int.self, forKey: .recentStations)
        self.discoveredTracks = try container.decodeIfPresent(Int.self, forKey: .discoveredTracks)
        self.savedTracks = try container.decodeIfPresent(Int.self, forKey: .savedTracks)
        self.lyricsSearchesPerDay = try container.decodeIfPresent(Int.self, forKey: .lyricsSearchesPerDay)
        self.webSearchesPerDay = try container.decodeIfPresent(Int.self, forKey: .webSearchesPerDay)
        self.youtubeSearchesPerDay = try container.decodeIfPresent(Int.self, forKey: .youtubeSearchesPerDay)
        self.appleMusicSearchesPerDay = try container.decodeIfPresent(Int.self, forKey: .appleMusicSearchesPerDay)
        self.spotifySearchesPerDay = try container.decodeIfPresent(Int.self, forKey: .spotifySearchesPerDay)
        self.discoverySharesPerDay = try container.decodeIfPresent(Int.self, forKey: .discoverySharesPerDay)
    }

    func limit(for feature: LimitedFeature) -> Int? {
        switch feature {
        case .favoriteStations:
            favoriteStations
        case .savedTracks:
            savedTracks
        case .discoveredTracks:
            discoveredTracks
        case .lyricsSearch:
            lyricsSearchesPerDay
        case .webSearch:
            webSearchesPerDay
        case .youtubeSearch:
            youtubeSearchesPerDay
        case .appleMusicSearch:
            appleMusicSearchesPerDay
        case .spotifySearch:
            spotifySearchesPerDay
        case .discoveryShare:
            discoverySharesPerDay
        }
    }

    static func forMode(_ accessMode: AccessMode) -> AccessLimits {
        let values = TuneAVAccessPolicy.limits(for: accessMode.rawValue)
        return AccessLimits(
            favoriteStations: values.favoriteStations,
            recentStations: values.recentStations,
            discoveredTracks: values.discoveredTracks,
            savedTracks: values.savedTracks,
            lyricsSearchesPerDay: values.lyricsSearchesPerDay,
            webSearchesPerDay: values.webSearchesPerDay,
            youtubeSearchesPerDay: values.youtubeSearchesPerDay,
            appleMusicSearchesPerDay: values.appleMusicSearchesPerDay,
            spotifySearchesPerDay: values.spotifySearchesPerDay,
            discoverySharesPerDay: values.discoverySharesPerDay
        )
    }
}

struct AccessCapabilities: Codable, Equatable {
    let isSignedIn: Bool
    let canUseBackend: Bool
    let canAccessPremiumFeatures: Bool
    let canUseCloudSync: Bool
    let canManagePlan: Bool

    enum CodingKeys: String, CodingKey {
        case isSignedIn
        case canUseBackend
        case canAccessPremiumFeatures = "canUsePremiumFeatures"
        case canUseCloudSync
        case canManagePlan
    }

    var isLocalOnly: Bool {
        !canUseBackend && !canUseCloudSync
    }

    var usesBackend: Bool {
        canUseBackend || canUseCloudSync
    }

    var canManageAVAccount: Bool {
        isSignedIn
    }

    var canUpgradeToPro: Bool {
        isSignedIn && !canAccessPremiumFeatures
    }

    static func forMode(_ accessMode: AccessMode) -> AccessCapabilities {
        let values = TuneAVAccessPolicy.capabilities(for: accessMode.rawValue)
        return AccessCapabilities(
            isSignedIn: values.isSignedIn,
            canUseBackend: values.canUseBackend,
            canAccessPremiumFeatures: values.canAccessPremiumFeatures,
            canUseCloudSync: values.canUseCloudSync,
            canManagePlan: values.canManagePlan
        )
    }
}

enum TuneAVAccessPolicy {
    static func limits(for accessMode: String) -> TuneAVAccessLimitValues {
        switch accessMode {
        case "guest":
            TuneAVAccessLimitValues(
                favoriteStations: 5,
                recentStations: 10,
                discoveredTracks: 20,
                savedTracks: 5,
                lyricsSearchesPerDay: 3,
                webSearchesPerDay: 3,
                youtubeSearchesPerDay: 3,
                appleMusicSearchesPerDay: 3,
                spotifySearchesPerDay: 3,
                discoverySharesPerDay: 1
            )
        case "signedInFree":
            TuneAVAccessLimitValues(
                favoriteStations: 15,
                recentStations: 25,
                discoveredTracks: 50,
                savedTracks: 20,
                lyricsSearchesPerDay: 10,
                webSearchesPerDay: 10,
                youtubeSearchesPerDay: 10,
                appleMusicSearchesPerDay: 10,
                spotifySearchesPerDay: 10,
                discoverySharesPerDay: 3
            )
        case "signedInPro":
            TuneAVAccessLimitValues(
                favoriteStations: 500,
                recentStations: 200,
                discoveredTracks: 1_000,
                savedTracks: 1_000,
                lyricsSearchesPerDay: nil,
                webSearchesPerDay: nil,
                youtubeSearchesPerDay: nil,
                appleMusicSearchesPerDay: nil,
                spotifySearchesPerDay: nil,
                discoverySharesPerDay: nil
            )
        default:
            limits(for: "guest")
        }
    }

    static func capabilities(for accessMode: String) -> TuneAVAccessCapabilityValues {
        switch accessMode {
        case "guest":
            TuneAVAccessCapabilityValues(
                isSignedIn: false,
                canUseBackend: false,
                canAccessPremiumFeatures: false,
                canUseCloudSync: false,
                canManagePlan: false
            )
        case "signedInFree":
            TuneAVAccessCapabilityValues(
                isSignedIn: true,
                canUseBackend: false,
                canAccessPremiumFeatures: false,
                canUseCloudSync: false,
                canManagePlan: true
            )
        case "signedInPro":
            TuneAVAccessCapabilityValues(
                isSignedIn: true,
                canUseBackend: true,
                canAccessPremiumFeatures: true,
                canUseCloudSync: true,
                canManagePlan: true
            )
        default:
            capabilities(for: "guest")
        }
    }
}
