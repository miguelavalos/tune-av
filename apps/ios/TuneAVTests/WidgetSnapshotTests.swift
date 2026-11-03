import XCTest
@testable import TuneAV

final class WidgetSnapshotTests: XCTestCase {
    private let strings = TuneAVWidgetStrings(
        myRadio: "My radio",
        live: "Live",
        loading: "Loading",
        paused: "Paused",
        play: "Play",
        pause: "Pause",
        playStationFormat: "Play %@",
        openPlayer: "Opens the player",
        emptyTitle: "Pick a radio",
        emptyMessage: "Open Tune AV and play a station."
    )

    private func station(_ id: String, name: String? = nil, artwork: String? = nil) -> Station {
        Station(
            id: id,
            name: name ?? "Station \(id)",
            country: "Spain",
            language: "Spanish",
            tags: "pop",
            streamURL: "https://example.com/\(id).mp3",
            artwork: artwork.map { StationArtwork(status: "ready", url: $0, version: nil) }
        )
    }

    private func input(
        current: Station? = nil,
        status: TuneAVPlaybackState = .idle,
        title: String? = nil,
        artist: String? = nil,
        lastPlayed: Station? = nil,
        favorites: [Station] = [],
        opensAppToPlay: Bool = false,
        artworkFileNames: [URL: String] = [:]
    ) -> TuneAVWidgetSnapshotInput {
        TuneAVWidgetSnapshotInput(
            currentStation: current,
            status: status,
            trackTitle: title,
            trackArtist: artist,
            lastPlayedStation: lastPlayed,
            favorites: favorites,
            opensAppToPlay: opensAppToPlay,
            artworkFileNames: artworkFileNames
        )
    }

    private func snapshot(_ input: TuneAVWidgetSnapshotInput) -> TuneAVWidgetSnapshot {
        TuneAVWidgetSnapshotMapper.snapshot(for: input, strings: strings)
    }

    // MARK: Encoding

    func testSnapshotRoundTripsThroughJSONAndStaysSmall() throws {
        let favorites = (1...6).map { station("fav-\($0)", name: String(repeating: "Long name ", count: 30)) }
        let value = snapshot(input(
            current: station("now"),
            status: .playing,
            title: String(repeating: "Roundabout ", count: 40),
            artist: "Yes",
            favorites: favorites
        ))

        let data = try TuneAVWidgetSnapshotStore.encode(value)
        XCTAssertEqual(TuneAVWidgetSnapshotStore.decode(data), value)
        XCTAssertLessThan(data.count, 4 * 1024)
        XCTAssertEqual(try TuneAVWidgetSnapshotStore.encode(value), data, "Encoding must be stable so equal snapshots never rewrite")
    }

    func testDecodeRejectsOtherVersionsAndGarbage() throws {
        var value = snapshot(input(current: station("now"), status: .playing))
        value.version = TuneAVWidgetSnapshot.currentVersion + 1
        XCTAssertNil(TuneAVWidgetSnapshotStore.decode(try TuneAVWidgetSnapshotStore.encode(value)))
        XCTAssertNil(TuneAVWidgetSnapshotStore.decode(Data("not json".utf8)))
        XCTAssertNil(TuneAVWidgetSnapshotStore.decode(Data(count: TuneAVWidgetSnapshotStore.maximumFileSize + 1)))
    }

    func testStoreWritesAndReadsSnapshotInDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let value = snapshot(input(lastPlayed: station("last"), favorites: [station("fav")]))

        try TuneAVWidgetSnapshotStore.write(try TuneAVWidgetSnapshotStore.encode(value), to: directory)

        XCTAssertEqual(TuneAVWidgetSnapshotStore.read(from: directory), value)
    }

    // MARK: Mapping

    func testMyRadioPrefersCurrentThenLastPlayedThenFirstFavorite() {
        let current = station("current")
        let last = station("last")
        let favorite = station("favorite")

        XCTAssertEqual(snapshot(input(current: current, status: .paused, lastPlayed: last, favorites: [favorite])).myRadio?.id, "current")
        XCTAssertEqual(snapshot(input(lastPlayed: last, favorites: [favorite])).myRadio?.id, "last")
        XCTAssertEqual(snapshot(input(favorites: [favorite])).myRadio?.id, "favorite")
    }

    func testPlayingCurrentStationCarriesSongAndLabels() {
        let value = snapshot(input(current: station("now", name: "Radio Paradise"), status: .playing, title: "Roundabout", artist: "Yes"))

        XCTAssertEqual(value.playback, .playing)
        XCTAssertTrue(value.isPlaybackActive)
        XCTAssertEqual(value.songTitle, "Roundabout")
        XCTAssertEqual(value.songArtist, "Yes")
        XCTAssertEqual(value.statusText, "Live")
        XCTAssertEqual(value.playbackActionLabel, "Pause")
        XCTAssertEqual(value.myRadio?.name, "Radio Paradise")
    }

    func testPlaybackStatesMapForCurrentStation() {
        let now = station("now")
        XCTAssertEqual(snapshot(input(current: now, status: .loading)).playback, .loading)
        XCTAssertEqual(snapshot(input(current: now, status: .paused)).playback, .paused)
        XCTAssertEqual(snapshot(input(current: now, status: .failed("error"))).playback, .paused)
        XCTAssertEqual(snapshot(input(current: now, status: .idle)).playback, .stopped)
        XCTAssertEqual(snapshot(input(current: now, status: .paused)).playbackActionLabel, "Play Station now")
    }

    func testLastPlayedStationIsStoppedWithoutSong() {
        let value = snapshot(input(status: .playing, title: "Roundabout", artist: "Yes", lastPlayed: station("last")))

        XCTAssertEqual(value.playback, .stopped)
        XCTAssertNil(value.songTitle)
        XCTAssertNil(value.songArtist)
        XCTAssertEqual(value.statusText, "My radio")
    }

    func testStationNameAsTitleIsNotShownAsSong() {
        let value = snapshot(input(current: station("now", name: "Radio Paradise"), status: .playing, title: "Radio Paradise"))
        XCTAssertNil(value.songTitle)
    }

    func testFavoritesExcludeMyRadioDropDuplicatesAndCapAtFour() {
        let favorites = [station("a"), station("b"), station("a"), station("c"), station("d"), station("e"), station("f")]
        let value = snapshot(input(current: station("b"), status: .playing, favorites: favorites))

        XCTAssertEqual(value.favorites.map(\.id), ["a", "c", "d", "e"])
    }

    func testFavoritesWithMyRadioNameAreNotRepeated() {
        let value = snapshot(input(
            current: station("demo-groove", name: "SomaFM Groove Salad"),
            status: .playing,
            favorites: [station("groove", name: "somafm groove salad"), station("bbc", name: "BBC Radio 1"), station("bbc-2", name: "BBC Radio 1")]
        ))
        XCTAssertEqual(value.favorites.map(\.id), ["bbc"])
    }

    func testFirstFavoriteAsMyRadioIsNotRepeatedInShortcuts() {
        let value = snapshot(input(favorites: [station("a"), station("b")]))
        XCTAssertEqual(value.myRadio?.id, "a")
        XCTAssertEqual(value.favorites.map(\.id), ["b"])
    }

    func testEmptyLibraryMapsToEmptySnapshot() {
        let value = snapshot(input())
        XCTAssertTrue(value.isEmpty)
        XCTAssertNil(value.myRadio)
        XCTAssertEqual(value.playback, .stopped)
    }

    func testArtworkFileNamesAreOnlyUsedWhenReady() throws {
        let readyURL = try XCTUnwrap(URL(string: "https://example.com/ready.png"))
        let current = station("now", artwork: readyURL.absoluteString)
        let favorite = station("fav", artwork: "https://example.com/pending.png")
        let value = snapshot(input(
            current: current,
            status: .playing,
            favorites: [favorite],
            artworkFileNames: [readyURL: "artwork-abc.jpg"]
        ))

        XCTAssertEqual(value.myRadio?.artworkFileName, "artwork-abc.jpg")
        XCTAssertNil(value.favorites.first?.artworkFileName)
    }

    func testArtworkSourcesCoverMyRadioAndShortcutsWithoutDuplicates() {
        let shared = "https://example.com/shared.png"
        let sources = TuneAVWidgetSnapshotMapper.artworkSources(for: input(
            current: station("now", artwork: shared),
            status: .playing,
            favorites: [station("a", artwork: shared), station("b", artwork: "https://example.com/b.png"), station("c")]
        ))

        XCTAssertEqual(sources.map(\.absoluteString), [shared, "https://example.com/b.png"])
    }

    func testOpensAppToPlayFollowsInput() {
        XCTAssertTrue(snapshot(input(lastPlayed: station("last"), opensAppToPlay: true)).opensAppToPlay)
        XCTAssertFalse(snapshot(input(lastPlayed: station("last"))).opensAppToPlay)
    }

    func testStoppedClearsPlaybackAndSong() {
        let playing = snapshot(input(current: station("now"), status: .playing, title: "Roundabout", artist: "Yes"))
        let stopped = TuneAVWidgetSnapshotMapper.stopped(playing)

        XCTAssertEqual(stopped.playback, .stopped)
        XCTAssertNil(stopped.songTitle)
        XCTAssertNil(stopped.songArtist)
        XCTAssertEqual(stopped.myRadio, playing.myRadio)
    }

    func testPlayStationLabelUsesFormat() {
        XCTAssertEqual(strings.playStation("Los 40"), "Play Los 40")
        var german = strings
        german.playStationFormat = "%@ abspielen"
        XCTAssertEqual(german.playStation("Los 40"), "Los 40 abspielen")
    }

    // MARK: Playback commands

    func testPlaybackPlannerCommands() {
        typealias Planner = TuneAVWidgetPlaybackPlanner
        XCTAssertEqual(Planner.command(stationID: "a", isFavoriteShortcut: false, currentStationID: nil, status: .idle), .play)
        XCTAssertEqual(Planner.command(stationID: "a", isFavoriteShortcut: false, currentStationID: "b", status: .playing), .play)
        XCTAssertEqual(Planner.command(stationID: "a", isFavoriteShortcut: false, currentStationID: "a", status: .playing), .pause)
        XCTAssertEqual(Planner.command(stationID: "a", isFavoriteShortcut: false, currentStationID: "a", status: .loading), .pause)
        XCTAssertEqual(Planner.command(stationID: "a", isFavoriteShortcut: false, currentStationID: "a", status: .paused), .resume)
        XCTAssertEqual(Planner.command(stationID: "a", isFavoriteShortcut: false, currentStationID: "a", status: .failed("error")), .resume)
        XCTAssertEqual(Planner.command(stationID: "a", isFavoriteShortcut: true, currentStationID: "a", status: .playing), .none)
        XCTAssertEqual(Planner.command(stationID: "a", isFavoriteShortcut: true, currentStationID: "a", status: .paused), .resume)
        XCTAssertEqual(Planner.queueSource(isFavoriteShortcut: true), .libraryFavorites)
        XCTAssertEqual(Planner.queueSource(isFavoriteShortcut: false), .singleStation)
    }

    func testPlaybackPlannerIgnoresStalePauseTaps() {
        typealias Planner = TuneAVWidgetPlaybackPlanner
        XCTAssertEqual(
            Planner.command(stationID: "a", isFavoriteShortcut: false, expectsActivePlayback: true, currentStationID: nil, status: .idle),
            .none
        )
        XCTAssertEqual(
            Planner.command(stationID: "a", isFavoriteShortcut: false, expectsActivePlayback: true, currentStationID: "a", status: .paused),
            .none
        )
        XCTAssertEqual(
            Planner.command(stationID: "a", isFavoriteShortcut: false, expectsActivePlayback: true, currentStationID: "a", status: .playing),
            .pause
        )
    }

    // MARK: Reload throttling

    func testReloadKindsSkipCompactWidgetsForSongAndFavoriteChanges() {
        let base = snapshot(input(current: station("now"), status: .playing, title: "Roundabout", artist: "Yes", favorites: [station("a")]))
        var songChanged = base
        songChanged.songTitle = "Heart of the Sunrise"
        var favoritesChanged = base
        favoritesChanged.favorites = []
        var playbackChanged = base
        playbackChanged.playback = .paused

        XCTAssertEqual(TuneAVWidgetReloadPlanner.kinds(previous: nil, next: base), Set(TuneAVWidgetKind.all))
        XCTAssertEqual(TuneAVWidgetReloadPlanner.kinds(previous: base, next: base), [])
        XCTAssertEqual(TuneAVWidgetReloadPlanner.kinds(previous: base, next: songChanged), [TuneAVWidgetKind.nowPlayingFavorites])
        XCTAssertEqual(TuneAVWidgetReloadPlanner.kinds(previous: base, next: favoritesChanged), [TuneAVWidgetKind.nowPlayingFavorites])
        XCTAssertEqual(TuneAVWidgetReloadPlanner.kinds(previous: base, next: playbackChanged), Set(TuneAVWidgetKind.all))
    }

    func testReloadPlannerSkipsUnchangedAndThrottlesChanges() {
        let first = snapshot(input(current: station("now"), status: .playing))
        var second = first
        second.songTitle = "Roundabout"
        var throttle = TuneAVLiveActivityUpdateThrottle(minimumInterval: TuneAVWidgetReloadPlanner.minimumInterval)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(TuneAVWidgetReloadPlanner.decision(previous: nil, next: first, throttle: throttle, now: start), .now)
        throttle.recordUpdate(at: start)
        XCTAssertEqual(TuneAVWidgetReloadPlanner.decision(previous: first, next: first, throttle: throttle, now: start), .none)
        XCTAssertEqual(
            TuneAVWidgetReloadPlanner.decision(previous: first, next: second, throttle: throttle, now: start.addingTimeInterval(0.5)),
            .after(1.5)
        )
        XCTAssertEqual(
            TuneAVWidgetReloadPlanner.decision(previous: first, next: second, throttle: throttle, now: start.addingTimeInterval(2)),
            .now
        )
    }

    // MARK: Deep links

    func testDeepLinksRoundTrip() throws {
        let links: [TuneAVWidgetDeepLink] = [
            .home,
            .player(stationID: nil),
            .player(stationID: "los-40"),
            .play(stationID: "los-40", isFavoriteShortcut: true),
            .play(stationID: "id with spaces&x=1", isFavoriteShortcut: false),
        ]
        for link in links {
            let url = try XCTUnwrap(link.url(scheme: "com.avalsys.tuneav.dev"))
            XCTAssertEqual(TuneAVWidgetDeepLink(url: url, scheme: "com.avalsys.tuneav.dev"), link, url.absoluteString)
        }
    }

    func testDeepLinksRejectOtherSchemesHostsAndPaths() throws {
        let scheme = "com.avalsys.tuneav.dev"
        XCTAssertNil(TuneAVWidgetDeepLink(url: try XCTUnwrap(URL(string: "other://widget/player")), scheme: scheme))
        XCTAssertNil(TuneAVWidgetDeepLink(url: try XCTUnwrap(URL(string: "\(scheme)://oauth/callback")), scheme: scheme))
        XCTAssertNil(TuneAVWidgetDeepLink(url: try XCTUnwrap(URL(string: "\(scheme)://widget/unknown")), scheme: scheme))
        XCTAssertNil(TuneAVWidgetDeepLink(url: try XCTUnwrap(URL(string: "\(scheme)://widget/play")), scheme: scheme))
    }

    func testWidgetArtworkURLRejectsUnsafeFileNames() {
        XCTAssertNil(TuneAVSharedContainer.widgetArtworkURL(fileName: "../snapshot.json"))
        XCTAssertNil(TuneAVSharedContainer.widgetArtworkURL(fileName: "snapshot.json"))
    }
}
