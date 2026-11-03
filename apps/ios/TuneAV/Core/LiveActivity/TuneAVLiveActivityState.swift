import Foundation

struct TuneAVLiveActivityInput: Equatable {
    var station: Station?
    var status: TuneAVPlaybackState
    var trackTitle: String?
    var trackArtist: String?
    var isSaved: Bool
    var heartTarget: TuneAVNowPlayingContentState.HeartTarget
    var artworkFileName: String?
}

struct TuneAVLiveActivityStrings: Equatable {
    var live: String
    var loading: String
    var paused: String
    var play: String
    var pause: String
    var saveSong: String
    var unsaveSong: String
    var saveStation: String
    var unsaveStation: String

    @MainActor
    static var localized: TuneAVLiveActivityStrings {
        TuneAVLiveActivityStrings(
            live: L10n.string("shell.status.live"),
            loading: L10n.string("audio.status.loading"),
            paused: L10n.string("audio.status.paused"),
            play: L10n.string("player.control.play"),
            pause: L10n.string("player.control.pause"),
            saveSong: L10n.string("player.discovery.save"),
            unsaveSong: L10n.string("player.discovery.unsaveShort"),
            saveStation: L10n.string("player.station.save"),
            unsaveStation: L10n.string("player.station.unsave")
        )
    }
}

enum TuneAVLiveActivityStateMapper {
    enum PlaybackCommand: Equatable {
        case pause
        case toggle
    }

    static let maximumTextLength = 160

    static func playbackCommand(status: TuneAVPlaybackState, hasStation: Bool) -> PlaybackCommand? {
        guard hasStation else { return nil }
        switch status {
        case .playing, .loading:
            return .pause
        case .paused, .failed, .idle:
            return .toggle
        }
    }

    static func capped(_ value: String?) -> String? {
        guard let value else { return nil }
        guard value.count > maximumTextLength else { return value }
        return String(value.prefix(maximumTextLength)).trimmingCharacters(in: .whitespaces)
    }

    static func playback(for status: TuneAVPlaybackState) -> TuneAVNowPlayingContentState.Playback? {
        switch status {
        case .idle:
            return nil
        case .loading:
            return .loading
        case .playing:
            return .playing
        case .paused, .failed:
            return .paused
        }
    }

    static func isPlaybackStarting(_ status: TuneAVPlaybackState) -> Bool {
        switch status {
        case .loading, .playing:
            return true
        case .idle, .paused, .failed:
            return false
        }
    }

    static func contentState(
        for input: TuneAVLiveActivityInput,
        strings: TuneAVLiveActivityStrings
    ) -> TuneAVNowPlayingContentState? {
        guard let station = input.station,
              let playback = playback(for: input.status) else { return nil }

        let stationName = capped(TuneAVDisplayMetadata.normalized(station.name) ?? station.name) ?? station.name
        let title = capped(TuneAVDisplayMetadata.plausibleTitle(input.trackTitle, stationName: station.name))
        let artist = title == nil ? nil : capped(TuneAVDisplayMetadata.plausibleArtist(input.trackArtist, stationName: station.name))

        let statusText: String
        switch playback {
        case .playing:
            statusText = strings.live
        case .loading:
            statusText = strings.loading
        case .paused:
            statusText = strings.paused
        }

        let heartActionLabel: String
        switch input.heartTarget {
        case .song:
            heartActionLabel = input.isSaved ? strings.unsaveSong : strings.saveSong
        case .station:
            heartActionLabel = input.isSaved ? strings.unsaveStation : strings.saveStation
        }

        return TuneAVNowPlayingContentState(
            stationName: stationName,
            songTitle: title,
            songArtist: artist,
            playback: playback,
            heartTarget: input.heartTarget,
            isSaved: input.isSaved,
            artworkFileName: input.artworkFileName,
            statusText: statusText,
            playbackActionLabel: playback == .paused ? strings.play : strings.pause,
            heartActionLabel: heartActionLabel
        )
    }
}

struct TuneAVLiveActivityUpdateThrottle {
    var minimumInterval: TimeInterval
    private(set) var lastUpdateAt: Date?

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    func delay(now: Date) -> TimeInterval {
        guard let lastUpdateAt else { return 0 }
        return max(0, minimumInterval - now.timeIntervalSince(lastUpdateAt))
    }

    mutating func recordUpdate(at date: Date) {
        lastUpdateAt = date
    }

    mutating func reset() {
        lastUpdateAt = nil
    }
}
