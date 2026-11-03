import Foundation
import WidgetKit

struct TuneAVWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TuneAVWidgetSnapshot?

    var strings: TuneAVWidgetStrings {
        snapshot?.strings ?? TuneAVWidgetText.fallbackStrings
    }

    var myRadio: TuneAVWidgetStation? {
        snapshot?.myRadio
    }

    var homeURL: URL? {
        TuneAVWidgetDeepLink.home.url()
    }

    var tapURL: URL? {
        guard let snapshot, let radio = snapshot.myRadio else { return homeURL }
        return TuneAVWidgetDeepLink.player(stationID: radio.id).url()
    }

    var compactTapURL: URL? {
        guard let snapshot, let radio = snapshot.myRadio else { return homeURL }
        guard snapshot.opensAppToPlay, !snapshot.isPlaybackActive else { return tapURL }
        return TuneAVWidgetDeepLink.play(stationID: radio.id, isFavoriteShortcut: false).url()
    }
}

struct TuneAVWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TuneAVWidgetEntry {
        TuneAVWidgetEntry(date: .now, snapshot: TuneAVWidgetText.previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (TuneAVWidgetEntry) -> Void) {
        let stored = TuneAVWidgetSnapshotStore.readShared()
        let snapshot = stored ?? (context.isPreview ? TuneAVWidgetText.previewSnapshot : nil)
        completion(TuneAVWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TuneAVWidgetEntry>) -> Void) {
        let entry = TuneAVWidgetEntry(date: .now, snapshot: TuneAVWidgetSnapshotStore.readShared())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

enum TuneAVWidgetText {
    static func string(_ key: String, fallback: String) -> String {
        guard let bundle = containingAppBundle else { return fallback }
        return bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    static var fallbackStrings: TuneAVWidgetStrings {
        TuneAVWidgetStrings(
            myRadio: string("widget.myRadio.title", fallback: "My radio"),
            live: string("shell.status.live", fallback: "Live"),
            loading: string("widget.status.loading", fallback: "Loading"),
            paused: string("audio.status.paused", fallback: "Paused"),
            play: string("player.control.play", fallback: "Play"),
            pause: string("player.control.pause", fallback: "Pause"),
            playStationFormat: string("widget.action.playStation", fallback: "Play %@"),
            openPlayer: string("widget.action.openPlayer", fallback: "Opens the player"),
            emptyTitle: string("widget.empty.title", fallback: "Pick a radio"),
            emptyMessage: string("widget.empty.message", fallback: "Open Tune AV and play a station. It will show up here.")
        )
    }

    static var previewSnapshot: TuneAVWidgetSnapshot {
        let strings = fallbackStrings
        return TuneAVWidgetSnapshot(
            version: TuneAVWidgetSnapshot.currentVersion,
            myRadio: TuneAVWidgetStation(id: "preview", name: "Tune AV", artworkFileName: nil),
            playback: .stopped,
            songTitle: nil,
            songArtist: nil,
            favorites: [],
            opensAppToPlay: false,
            strings: strings
        )
    }

    private static var containingAppBundle: Bundle? {
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app" else { return nil }
        return Bundle(url: appURL)
    }
}
