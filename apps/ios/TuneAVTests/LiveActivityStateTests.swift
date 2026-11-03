import XCTest
@testable import TuneAV

final class LiveActivityStateTests: XCTestCase {
    private let strings = TuneAVLiveActivityStrings(
        live: "Live",
        loading: "Loading",
        paused: "Paused",
        play: "Play",
        pause: "Pause",
        saveSong: "Save song",
        unsaveSong: "Remove song",
        saveStation: "Save radio",
        unsaveStation: "Remove radio"
    )

    private var station: Station { Station.samples[0] }

    private func input(
        status: TuneAVPlaybackState = .playing,
        title: String? = "Roundabout",
        artist: String? = "Yes",
        isSaved: Bool = false,
        heartTarget: TuneAVNowPlayingContentState.HeartTarget = .song,
        artworkFileName: String? = nil,
        station: Station? = Station.samples[0]
    ) -> TuneAVLiveActivityInput {
        TuneAVLiveActivityInput(
            station: station,
            status: status,
            trackTitle: title,
            trackArtist: artist,
            isSaved: isSaved,
            heartTarget: heartTarget,
            artworkFileName: artworkFileName
        )
    }

    func testPlayingSongMapsTitleArtistStationAndLabels() throws {
        let state = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(for: input(), strings: strings))

        XCTAssertEqual(state.stationName, station.name)
        XCTAssertEqual(state.songTitle, "Roundabout")
        XCTAssertEqual(state.songArtist, "Yes")
        XCTAssertEqual(state.playback, .playing)
        XCTAssertTrue(state.isLive)
        XCTAssertEqual(state.primaryText, "Roundabout")
        XCTAssertEqual(state.secondaryText, "Yes")
        XCTAssertEqual(state.statusText, "Live")
        XCTAssertEqual(state.playbackActionLabel, "Pause")
        XCTAssertEqual(state.heartActionLabel, "Save song")
    }

    func testStationWithoutMetadataFallsBackToStationNameAndStatus() throws {
        let state = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(
            for: input(title: nil, artist: nil, heartTarget: .station),
            strings: strings
        ))

        XCTAssertFalse(state.hasSong)
        XCTAssertEqual(state.primaryText, station.name)
        XCTAssertEqual(state.secondaryText, "Live")
        XCTAssertEqual(state.heartActionLabel, "Save radio")
    }

    func testBroadcastMetadataEqualToStationNameIsNotShownAsSong() throws {
        let state = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(
            for: input(title: station.name, artist: nil, heartTarget: .station),
            strings: strings
        ))

        XCTAssertNil(state.songTitle)
        XCTAssertNil(state.songArtist)
    }

    func testPausedAndFailedShowPlayAction() throws {
        let paused = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(for: input(status: .paused), strings: strings))
        XCTAssertEqual(paused.playback, .paused)
        XCTAssertEqual(paused.playbackActionLabel, "Play")
        XCTAssertEqual(paused.statusText, "Paused")
        XCTAssertFalse(paused.isLive)

        let failed = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(for: input(status: .failed("x")), strings: strings))
        XCTAssertEqual(failed.playback, .paused)
        XCTAssertEqual(failed.playbackActionLabel, "Play")
    }

    func testLoadingKeepsPauseActionAndLoadingStatus() throws {
        let state = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(for: input(status: .loading), strings: strings))

        XCTAssertEqual(state.playback, .loading)
        XCTAssertEqual(state.statusText, "Loading")
        XCTAssertEqual(state.playbackActionLabel, "Pause")
    }

    func testIdleOrMissingStationEndsActivity() {
        XCTAssertNil(TuneAVLiveActivityStateMapper.contentState(for: input(status: .idle), strings: strings))
        XCTAssertNil(TuneAVLiveActivityStateMapper.contentState(for: input(station: nil), strings: strings))
    }

    func testOnlyLoadingAndPlayingStartAnActivity() {
        XCTAssertTrue(TuneAVLiveActivityStateMapper.isPlaybackStarting(.loading))
        XCTAssertTrue(TuneAVLiveActivityStateMapper.isPlaybackStarting(.playing))
        XCTAssertFalse(TuneAVLiveActivityStateMapper.isPlaybackStarting(.paused))
        XCTAssertFalse(TuneAVLiveActivityStateMapper.isPlaybackStarting(.idle))
        XCTAssertFalse(TuneAVLiveActivityStateMapper.isPlaybackStarting(.failed("x")))
    }

    func testSavedHeartUsesRemoveLabels() throws {
        let song = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(for: input(isSaved: true), strings: strings))
        XCTAssertTrue(song.isSaved)
        XCTAssertEqual(song.heartActionLabel, "Remove song")

        let radio = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(
            for: input(title: nil, artist: nil, isSaved: true, heartTarget: .station),
            strings: strings
        ))
        XCTAssertEqual(radio.heartActionLabel, "Remove radio")
    }

    func testUnchangedInputProducesEqualStateSoUpdatesAreDeduplicated() {
        let first = TuneAVLiveActivityStateMapper.contentState(for: input(), strings: strings)
        let second = TuneAVLiveActivityStateMapper.contentState(for: input(), strings: strings)
        let changed = TuneAVLiveActivityStateMapper.contentState(for: input(isSaved: true), strings: strings)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, changed)
    }

    @MainActor
    func testHeartTargetNeedsPlausibleTitleAndArtist() {
        XCTAssertEqual(TuneAVHeartAction.target(title: "Roundabout", artist: "Yes", station: station), .song)
        XCTAssertEqual(TuneAVHeartAction.target(title: "Roundabout", artist: nil, station: station), .station)
        XCTAssertEqual(TuneAVHeartAction.target(title: nil, artist: nil, station: station), .station)
    }

    func testContentStatePayloadStaysWellUnderActivityKitLimit() throws {
        let longText = String(repeating: "Long title with words ", count: 20)
        let state = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(
            for: input(
                title: longText,
                artist: longText,
                artworkFileName: TuneAVLiveActivityController.artworkFileName(for: URL(string: "https://example.com/a.jpg")!)
            ),
            strings: strings
        ))

        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4 * 1024)
        XCTAssertEqual(try JSONDecoder().decode(TuneAVNowPlayingContentState.self, from: data), state)
    }

    func testThrottleAllowsFirstUpdateAndSpacesFollowingOnes() {
        var throttle = TuneAVLiveActivityUpdateThrottle(minimumInterval: 1)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(throttle.delay(now: start), 0)

        throttle.recordUpdate(at: start)
        XCTAssertEqual(throttle.delay(now: start.addingTimeInterval(0.25)), 0.75, accuracy: 0.0001)
        XCTAssertEqual(throttle.delay(now: start.addingTimeInterval(1)), 0)
        XCTAssertEqual(throttle.delay(now: start.addingTimeInterval(5)), 0)

        throttle.reset()
        XCTAssertEqual(throttle.delay(now: start.addingTimeInterval(0.1)), 0)
    }

    func testArtworkFileNamesAreStableAndAcceptedBySharedContainer() {
        let url = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/a/100x100bb.jpg")!
        let fileName = TuneAVLiveActivityController.artworkFileName(for: url)

        XCTAssertEqual(fileName, TuneAVLiveActivityController.artworkFileName(for: url))
        XCTAssertNotEqual(fileName, TuneAVLiveActivityController.artworkFileName(for: URL(string: "https://example.com/b.jpg")!))
        XCTAssertTrue(TuneAVSharedContainer.isValidArtworkFileName(fileName))
        XCTAssertFalse(TuneAVSharedContainer.isValidArtworkFileName("../secret.jpg"))
        XCTAssertFalse(TuneAVSharedContainer.isValidArtworkFileName("artwork-../../x.jpg"))
    }
}
