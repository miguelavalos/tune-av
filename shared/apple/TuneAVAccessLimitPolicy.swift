import Foundation

enum TuneAVAccessLimitPolicy {
    static func resolvedLimits(
        _ limits: AccessLimits,
        accessMode: AccessMode,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AccessLimits {
        uiTestOverrides(
            dailyActionsUnlimitedForPro(limits, accessMode: accessMode),
            environment: environment
        )
    }

    static func dailyActionsUnlimitedForPro(_ limits: AccessLimits, accessMode: AccessMode) -> AccessLimits {
        guard accessMode == .signedInPro else { return limits }

        return AccessLimits(
            favoriteStations: limits.favoriteStations,
            recentStations: limits.recentStations,
            discoveredTracks: limits.discoveredTracks,
            savedTracks: limits.savedTracks,
            aviActionsPerDay: nil,
            lyricsSearchesPerDay: nil,
            webSearchesPerDay: nil,
            youtubeSearchesPerDay: nil,
            appleMusicSearchesPerDay: nil,
            spotifySearchesPerDay: nil,
            discoverySharesPerDay: nil
        )
    }

    static func uiTestOverrides(
        _ limits: AccessLimits,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AccessLimits {
        guard TuneAVUITestEnvironment(environment: environment).isEnabled else {
            return limits
        }

        return AccessLimits(
            favoriteStations: environment["TUNEAV_UI_TEST_FAVORITE_LIMIT"].flatMap(Int.init) ?? limits.favoriteStations,
            recentStations: limits.recentStations,
            discoveredTracks: limits.discoveredTracks,
            savedTracks: limits.savedTracks,
            aviActionsPerDay: environment["TUNEAV_UI_TEST_AVI_ACTION_LIMIT"].flatMap(Int.init) ?? limits.aviActionsPerDay,
            lyricsSearchesPerDay: environment["TUNEAV_UI_TEST_LYRICS_LIMIT"].flatMap(Int.init) ?? limits.lyricsSearchesPerDay,
            webSearchesPerDay: environment["TUNEAV_UI_TEST_WEB_LIMIT"].flatMap(Int.init) ?? limits.webSearchesPerDay,
            youtubeSearchesPerDay: environment["TUNEAV_UI_TEST_YOUTUBE_LIMIT"].flatMap(Int.init) ?? limits.youtubeSearchesPerDay,
            appleMusicSearchesPerDay: environment["TUNEAV_UI_TEST_APPLE_MUSIC_LIMIT"].flatMap(Int.init) ?? limits.appleMusicSearchesPerDay,
            spotifySearchesPerDay: environment["TUNEAV_UI_TEST_SPOTIFY_LIMIT"].flatMap(Int.init) ?? limits.spotifySearchesPerDay,
            discoverySharesPerDay: environment["TUNEAV_UI_TEST_DISCOVERY_SHARE_LIMIT"].flatMap(Int.init) ?? limits.discoverySharesPerDay
        )
    }
}
