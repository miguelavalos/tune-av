import Foundation

struct TuneAVCachedNowPlayingState: Equatable {
    let title: String?
    let artist: String?
    let albumTitle: String?
    let artworkURL: URL?
    let artistURL: URL?
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

    enum ErrorKey {
        static let invalidURL = "audio.error.invalidURL"
        static let sessionUnavailable = "audio.error.sessionUnavailable"
        static let streamInterrupted = "audio.error.streamInterrupted"
        static let streamLoadFailed = "audio.error.streamLoadFailed"
        static let streamTimeout = "audio.error.streamTimeout"
        static let activateAudio = "audio.error.activateAudio"
    }
}
