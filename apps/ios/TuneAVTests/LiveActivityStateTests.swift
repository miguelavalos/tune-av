import ActivityKit
import AVFoundation
import MediaPlayer
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

    func testVeryLongMetadataIsCappedSoThePayloadNeverOverflows() throws {
        let huge = String(repeating: "x", count: 10_000)
        let state = try XCTUnwrap(TuneAVLiveActivityStateMapper.contentState(
            for: input(title: huge, artist: huge),
            strings: strings
        ))

        XCTAssertEqual(state.songTitle?.count, TuneAVLiveActivityStateMapper.maximumTextLength)
        XCTAssertEqual(state.songArtist?.count, TuneAVLiveActivityStateMapper.maximumTextLength)
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 4 * 1024)
    }

    func testPlayPauseFromTheActivityNeverStartsARadioWhenNoStationIsLoaded() {
        XCTAssertNil(TuneAVLiveActivityStateMapper.playbackCommand(status: .idle, hasStation: false))
        XCTAssertNil(TuneAVLiveActivityStateMapper.playbackCommand(status: .paused, hasStation: false))
        XCTAssertEqual(TuneAVLiveActivityStateMapper.playbackCommand(status: .playing, hasStation: true), .pause)
        XCTAssertEqual(TuneAVLiveActivityStateMapper.playbackCommand(status: .loading, hasStation: true), .pause)
        XCTAssertEqual(TuneAVLiveActivityStateMapper.playbackCommand(status: .paused, hasStation: true), .toggle)
        XCTAssertEqual(TuneAVLiveActivityStateMapper.playbackCommand(status: .failed("x"), hasStation: true), .toggle)
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

    // MARK: Live Activity switched off (1.1.0 build 62 showed the song twice on the lock screen)

    func testLiveActivitySwitchIsOffInTheAppAndTheWidgetExtension() {
        XCTAssertFalse(TuneAVLiveActivityController.isEnabled)
        XCTAssertFalse(TuneAVLiveActivityFeature.isEnabled)
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities"))
    }

    @MainActor
    func testStartingPlaybackRequestsNoActivityAndKeepsTheSystemNowPlayingPlayer() async throws {
        let suiteName = "LiveActivityStateTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let audioPlayer = AudioPlayerService()
        let libraryStore = LibraryStore(container: PersistenceController(inMemory: true).container)
        let accessController = AccessController(
            accountService: SignedOutAccountService(),
            accountProfileResolver: NoAccountProfileResolver(),
            entitlementService: GuestEntitlementService(),
            userDefaults: userDefaults
        )
        let controller = TuneAVLiveActivityController()
        controller.attach(audioPlayer: audioPlayer, libraryStore: libraryStore, accessController: accessController)
        defer { audioPlayer.stop() }

        let station = Station(
            id: "live-activity-off",
            name: "Live Activity Off FM",
            country: "Spain",
            language: "Spanish",
            tags: "pop",
            streamURL: "http://127.0.0.1:9/live-activity-off.mp3",
            artwork: nil
        )
        audioPlayer.play(station: station)
        XCTAssertTrue(TuneAVLiveActivityStateMapper.isPlaybackStarting(audioPlayer.status))

        // The system player still gets the station and its remote commands, on an
        // AirPlay-capable long-form playback session.
        let info = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(info[MPMediaItemPropertyAlbumTitle] as? String, station.name)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, true)
        let commands = MPRemoteCommandCenter.shared()
        XCTAssertTrue(commands.playCommand.isEnabled)
        XCTAssertTrue(commands.pauseCommand.isEnabled)
        XCTAssertTrue(commands.togglePlayPauseCommand.isEnabled)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        XCTAssertEqual(AVAudioSession.sharedInstance().routeSharingPolicy, .longFormAudio)

        // Longer than the coalescing delay an enabled controller waits before it requests.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertFalse(controller.isObservingPlayback)
        XCTAssertEqual(controller.activityRequestCount, 0)
        XCTAssertTrue(Activity<TuneAVNowPlayingAttributes>.activities.isEmpty)
    }
}

private struct SignedOutAccountService: AVAccountService {
    var isAvailable: Bool { true }
    var providerSessionUser: AccountUser? { nil }

    func restoreSession() async -> AVAccountSessionRestoreResult { .signedOut }
    func getToken() async throws -> String? { nil }
    func signInWithApple() async throws {}
    func signInWithGoogle() async throws {}
    func signOut() async throws {}
}

@MainActor
private struct NoAccountProfileResolver: AccountProfileResolving {
    func resolveCurrentAccountUser() async throws -> AccountUser {
        throw AccountProfileResolverError.missingInternalUserId
    }
}

@MainActor
private struct GuestEntitlementService: EntitlementService {
    func resolveAccess(for user: AccountUser?) -> ResolvedAccess { .guest }
    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess { .guest }
}
