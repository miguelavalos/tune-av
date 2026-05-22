import Foundation

struct TuneAVCachedNowPlayingState: Equatable {
    let title: String?
    let artist: String?
    let albumTitle: String?
    let artworkURL: URL?
    let artistURL: URL?
    let cachedAt: Date
}

enum TuneAVPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return L10n.string("audio.status.ready")
        case .loading:
            return L10n.string("audio.status.loading")
        case .playing:
            return L10n.string("audio.status.playing")
        case .paused:
            return L10n.string("audio.status.paused")
        case .failed(let message):
            return message
        }
    }
}

enum TuneAVAudioPlaybackPolicy {
    static let loadingTimeoutSeconds: Duration = .seconds(12)
    static let nowPlayingFallbackInitialDelay: Duration = .seconds(4)
    static let nowPlayingFallbackPollingInterval: Duration = .seconds(25)
    static let cachedNowPlayingMaximumAge: TimeInterval = 30 * 60

    static func isCachedNowPlayingFresh(_ state: TuneAVCachedNowPlayingState, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(state.cachedAt)
        return age >= 0 && age <= cachedNowPlayingMaximumAge
    }

    static func fallbackNowPlayingShouldReplaceStreamTrack(
        currentTitle: String?,
        currentArtist: String?,
        fallbackTitle: String,
        fallbackArtist: String?
    ) -> Bool {
        guard let normalizedCurrentTitle = TuneAVTrackMetadataParser.sanitizeTitle(currentTitle, artist: currentArtist) else {
            return true
        }

        let normalizedCurrentArtist = TuneAVTrackMetadataParser.sanitizeArtist(currentArtist)
        let normalizedFallbackArtist = TuneAVTrackMetadataParser.sanitizeArtist(fallbackArtist)

        if let normalizedCurrentArtist,
           let normalizedFallbackArtist,
           normalizedFallbackArtist.localizedCaseInsensitiveCompare(normalizedCurrentArtist) != .orderedSame {
            return false
        }

        let currentComparable = comparableTrackTitle(normalizedCurrentTitle)
        let fallbackComparable = comparableTrackTitle(fallbackTitle)

        guard fallbackComparable.count > currentComparable.count else { return false }
        return fallbackComparable.hasPrefix(currentComparable)
    }

    static func shouldRetryAfterNetworkRestored(
        isNetworkSatisfied: Bool,
        hadPreviousNetworkStatus: Bool,
        wasPreviouslyUnsatisfied: Bool,
        userRequestedPlayback: Bool,
        hasCurrentStation: Bool,
        isRecoverablePlaybackState: Bool
    ) -> Bool {
        isNetworkSatisfied &&
            hadPreviousNetworkStatus &&
            wasPreviouslyUnsatisfied &&
            userRequestedPlayback &&
            hasCurrentStation &&
            isRecoverablePlaybackState
    }

    private static func comparableTrackTitle(_ title: String) -> String {
        title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: L10n.locale)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum ErrorKey {
        static let invalidURL = "audio.error.invalidURL"
        static let sessionUnavailable = "audio.error.sessionUnavailable"
        static let streamInterrupted = "audio.error.streamInterrupted"
        static let streamLoadFailed = "audio.error.streamLoadFailed"
        static let streamTimeout = "audio.error.streamTimeout"
        static let activateAudio = "audio.error.activateAudio"
    }
}
