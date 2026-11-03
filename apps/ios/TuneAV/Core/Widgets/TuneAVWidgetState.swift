import Foundation

struct TuneAVWidgetSnapshotInput {
    var currentStation: Station?
    var status: TuneAVPlaybackState
    var trackTitle: String?
    var trackArtist: String?
    var lastPlayedStation: Station?
    var favorites: [Station]
    var opensAppToPlay: Bool
    var artworkFileNames: [URL: String]
}

extension TuneAVWidgetStrings {
    @MainActor
    static var localized: TuneAVWidgetStrings {
        TuneAVWidgetStrings(
            myRadio: L10n.string("widget.myRadio.title"),
            live: L10n.string("shell.status.live"),
            loading: L10n.string("widget.status.loading"),
            paused: L10n.string("audio.status.paused"),
            play: L10n.string("player.control.play"),
            pause: L10n.string("player.control.pause"),
            playStationFormat: L10n.string("widget.action.playStation"),
            openPlayer: L10n.string("widget.action.openPlayer"),
            emptyTitle: L10n.string("widget.empty.title"),
            emptyMessage: L10n.string("widget.empty.message")
        )
    }
}

enum TuneAVWidgetSnapshotMapper {
    static func myRadio(currentStation: Station?, lastPlayedStation: Station?, favorites: [Station]) -> Station? {
        currentStation ?? lastPlayedStation ?? favorites.first
    }

    static func playback(for status: TuneAVPlaybackState, isCurrent: Bool) -> TuneAVWidgetSnapshot.Playback {
        guard isCurrent else { return .stopped }
        switch status {
        case .playing:
            return .playing
        case .loading:
            return .loading
        case .paused, .failed:
            return .paused
        case .idle:
            return .stopped
        }
    }

    static func shortcutFavorites(_ favorites: [Station], excluding excludedStation: Station?) -> [Station] {
        var seenIDs = Set<String>()
        var seenNames = Set<String>()
        if let excludedStation {
            seenIDs.insert(excludedStation.id)
            seenNames.insert(nameKey(for: excludedStation))
        }
        var result: [Station] = []
        for station in favorites {
            guard seenIDs.insert(station.id).inserted, seenNames.insert(nameKey(for: station)).inserted else { continue }
            result.append(station)
            if result.count == TuneAVWidgetSnapshot.maximumFavorites { break }
        }
        return result
    }

    private static func nameKey(for station: Station) -> String {
        (TuneAVDisplayMetadata.normalized(station.name) ?? station.name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func artworkSources(for input: TuneAVWidgetSnapshotInput) -> [URL] {
        let radio = myRadio(
            currentStation: input.currentStation,
            lastPlayedStation: input.lastPlayedStation,
            favorites: input.favorites
        )
        let stations = [radio].compactMap { $0 } + shortcutFavorites(input.favorites, excluding: radio)
        var seen = Set<URL>()
        return stations.compactMap(\.displayArtworkURL).filter { seen.insert($0).inserted }
    }

    static func snapshot(for input: TuneAVWidgetSnapshotInput, strings: TuneAVWidgetStrings) -> TuneAVWidgetSnapshot {
        let radio = myRadio(
            currentStation: input.currentStation,
            lastPlayedStation: input.lastPlayedStation,
            favorites: input.favorites
        )
        let isCurrent = radio != nil && radio?.id == input.currentStation?.id
        let playback = playback(for: input.status, isCurrent: isCurrent)

        var songTitle: String?
        var songArtist: String?
        if let radio, isCurrent, playback != .stopped {
            songTitle = TuneAVLiveActivityStateMapper.capped(
                TuneAVDisplayMetadata.plausibleTitle(input.trackTitle, stationName: radio.name)
            )
            if songTitle != nil {
                songArtist = TuneAVLiveActivityStateMapper.capped(
                    TuneAVDisplayMetadata.plausibleArtist(input.trackArtist, stationName: radio.name)
                )
            }
        }

        return TuneAVWidgetSnapshot(
            version: TuneAVWidgetSnapshot.currentVersion,
            myRadio: radio.map { widgetStation(for: $0, artworkFileNames: input.artworkFileNames) },
            playback: playback,
            songTitle: songTitle,
            songArtist: songArtist,
            favorites: shortcutFavorites(input.favorites, excluding: radio)
                .map { widgetStation(for: $0, artworkFileNames: input.artworkFileNames) },
            opensAppToPlay: input.opensAppToPlay,
            strings: strings
        )
    }

    static func stopped(_ snapshot: TuneAVWidgetSnapshot) -> TuneAVWidgetSnapshot {
        var stopped = snapshot
        stopped.playback = .stopped
        stopped.songTitle = nil
        stopped.songArtist = nil
        return stopped
    }

    private static func widgetStation(for station: Station, artworkFileNames: [URL: String]) -> TuneAVWidgetStation {
        let name = TuneAVLiveActivityStateMapper.capped(TuneAVDisplayMetadata.normalized(station.name) ?? station.name) ?? station.name
        return TuneAVWidgetStation(
            id: station.id,
            name: name,
            artworkFileName: station.displayArtworkURL.flatMap { artworkFileNames[$0] }
        )
    }
}

enum TuneAVWidgetPlaybackPlanner {
    enum Command: Equatable {
        case play
        case pause
        case resume
        case none
    }

    static func command(
        stationID: String,
        isFavoriteShortcut: Bool,
        expectsActivePlayback: Bool = false,
        currentStationID: String?,
        status: TuneAVPlaybackState
    ) -> Command {
        let isActive = currentStationID == stationID && (status == .playing || status == .loading)
        if expectsActivePlayback, !isActive {
            return .none
        }
        guard currentStationID == stationID else { return .play }
        switch status {
        case .playing, .loading:
            return isFavoriteShortcut ? .none : .pause
        case .paused, .failed, .idle:
            return .resume
        }
    }

    static func queueSource(isFavoriteShortcut: Bool) -> TuneAVPlaybackQueueSource {
        isFavoriteShortcut ? .libraryFavorites : .singleStation
    }
}

enum TuneAVWidgetReloadPlanner {
    enum Decision: Equatable {
        case none
        case now
        case after(TimeInterval)
    }

    static let minimumInterval: TimeInterval = 2

    static func kinds(previous: TuneAVWidgetSnapshot?, next: TuneAVWidgetSnapshot) -> Set<String> {
        guard let previous else { return Set(TuneAVWidgetKind.all) }
        guard previous != next else { return [] }
        guard compactContent(of: previous) == compactContent(of: next) else { return Set(TuneAVWidgetKind.all) }
        return [TuneAVWidgetKind.nowPlayingFavorites]
    }

    private static func compactContent(of snapshot: TuneAVWidgetSnapshot) -> TuneAVWidgetSnapshot {
        var compact = snapshot
        compact.songTitle = nil
        compact.songArtist = nil
        compact.favorites = []
        return compact
    }

    static func decision(
        previous: TuneAVWidgetSnapshot?,
        next: TuneAVWidgetSnapshot,
        throttle: TuneAVLiveActivityUpdateThrottle,
        now: Date
    ) -> Decision {
        guard previous != next else { return .none }
        let delay = throttle.delay(now: now)
        return delay > 0 ? .after(delay) : .now
    }
}
