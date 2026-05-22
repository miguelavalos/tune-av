import XCTest

@MainActor
final class DiscoveriesUITests: TuneAVUITestCase {
    func testLibraryShowsAndFiltersDiscoveries() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sweet Disposition"].exists)
        XCTAssertFalse(app.staticTexts["Midnight City"].exists)

        showDiscoveryHistory(in: app)

        XCTAssertTrue(app.staticTexts["Midnight City"].exists)
        XCTAssertTrue(app.staticTexts["Sweet Disposition"].exists)
    }

    func testCanSaveAndUnsaveDiscoveryFromHistory() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)
        showDiscoveryHistory(in: app)

        let discoveryID = "m83-midnight-city-groove-salad"
        toggleDiscoverySaved(discoveryID, in: app)

        showSavedSongs(in: app)
        XCTAssertTrue(app.staticTexts["Midnight City"].waitForExistence(timeout: 5))

        toggleDiscoverySaved(discoveryID, in: app)

        XCTAssertFalse(app.staticTexts["Midnight City"].exists)
    }

    func testCanMarkDiscoveryNotInterestedFromHistory() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)
        showDiscoveryHistory(in: app)

        let discoveryID = "m83-midnight-city-groove-salad"
        XCTAssertTrue(app.staticTexts["Midnight City"].waitForExistence(timeout: 5))

        let menuButton = app.buttons["discoveryTrack.menu.\(discoveryID)"].firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()

        let hideButton = app.descendants(matching: .any)["discoveryTrack.hide.\(discoveryID)"].firstMatch
        XCTAssertTrue(hideButton.waitForExistence(timeout: 5))
        hideButton.tap()

        XCTAssertFalse(app.staticTexts["Midnight City"].exists)

        let undoBanner = app.otherElements["discoveries.hiddenUndo"].firstMatch
        XCTAssertTrue(undoBanner.waitForExistence(timeout: 5))
        undoBanner.buttons["discoveries.undoHide"].tap()

        XCTAssertTrue(app.staticTexts["Midnight City"].waitForExistence(timeout: 5))
    }

    func testCanRemoveDiscovery() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)
        showDiscoveryHistory(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Midnight City"].exists)

        let discovery = app.otherElements.matching(identifier: "discoveryTrack.m83-midnight-city-groove-salad").firstMatch
        XCTAssertTrue(discovery.exists)
        discovery.buttons["discoveryTrack.menu.m83-midnight-city-groove-salad"].tap()
        app.descendants(matching: .any)["discoveryTrack.remove.m83-midnight-city-groove-salad"].tap()

        XCTAssertFalse(app.staticTexts["Midnight City"].exists)
    }

    func testCanClearAllDiscoveriesAfterConfirmation() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)
        showDiscoveryHistory(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Midnight City"].exists)
        XCTAssertTrue(app.staticTexts["Sweet Disposition"].exists)

        discoveriesSection.buttons["discoveries.clear"].tap()

        let confirmButton = app.buttons["Borrar descubrimientos"].firstMatch
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.staticTexts["Aún no hay descubrimientos"].waitForExistence(timeout: 5))
    }

    func testCanOpenShareSheetForDiscoveries() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))

        discoveriesSection.buttons["discoveries.share"].tap()

        let shareSheet = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5))
    }

    func testAviShowsTrackActionsForDiscoverableMetadata() {
        let title = "Reckoner UI \(UUID().uuidString.prefix(8))"
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_UI_TEST_TRACK_ARTIST": "Radiohead",
                "TUNEAV_UI_TEST_TRACK_TITLE": title,
            ]
        )

        openAviActions(in: app)

        XCTAssertTrue(app.buttons["avi.actions.lyrics"].exists)
        XCTAssertTrue(app.buttons["avi.actions.saveSong"].exists)
        XCTAssertFalse(app.buttons["avi.actions.radioInfo"].exists)

        let saveButton = app.buttons["avi.actions.saveSong"].firstMatch
        XCTAssertTrue(saveButton.isHittable)
        saveButton.tap()
    }

    func testFullPlayerAviReactsAndSettlesWhenLikingSong() {
        let title = "Avi Reaction UI \(UUID().uuidString.prefix(8))"
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_UI_TEST_TRACK_ARTIST": "Radiohead",
                "TUNEAV_UI_TEST_TRACK_TITLE": title,
            ]
        )

        let aviEmotion = app.descendants(matching: .any)["avi.focused.header"].firstMatch
        if !aviEmotion.waitForExistence(timeout: 2) {
            openFullPlayerFromMiniPlayer(in: app)
        }
        XCTAssertTrue(aviEmotion.waitForExistence(timeout: 5))

        let clearButton = app.descendants(matching: .any)["stationFeedback.clear"].firstMatch
        if clearButton.exists && clearButton.isHittable {
            clearButton.tap()
        }

        let likeButton = app.descendants(matching: .any)["stationFeedback.liked"].firstMatch
        XCTAssertTrue(likeButton.waitForExistence(timeout: 5))
        likeButton.tap()

        let reactionPredicate = NSPredicate(format: "value CONTAINS %@", "reaction:AviV2TuneLiked")
        expectation(for: reactionPredicate, evaluatedWith: aviEmotion)
        waitForExpectations(timeout: 2)

        let settledPredicate = NSPredicate(format: "value CONTAINS %@", "static:AviV2TuneLiked")
        expectation(for: settledPredicate, evaluatedWith: aviEmotion)
        waitForExpectations(timeout: 6)
    }

    func testAviTrackActionsHandleLongMetadataAndCollapse() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_UI_TEST_TRACK_ARTIST": "Queens of the Stone Age",
                "TUNEAV_UI_TEST_TRACK_TITLE": "You Think I Ain't Worth A Dollar, But I Feel Like A Millionaire",
            ]
        )

        openAviActions(in: app)

        XCTAssertTrue(app.buttons["avi.actions.saveSong"].exists)
        XCTAssertTrue(app.buttons["avi.actions.lyrics"].exists)
        XCTAssertFalse(app.buttons["avi.actions.saveRadio"].exists)

        app.descendants(matching: .any)["avi.actions.close"].firstMatch.tap()

        XCTAssertFalse(app.buttons["avi.actions.saveSong"].exists)
    }

    func testArtworkShowsRadioOptionsWhenTrackArtistIsMissing() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_UI_TEST_TRACK_TITLE": "Untitled Broadcast",
            ]
        )

        openAviActions(in: app)

        XCTAssertTrue(app.buttons["avi.actions.radioInfo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["avi.actions.saveRadio"].exists)
        XCTAssertTrue(app.buttons["avi.actions.history"].exists)
        XCTAssertFalse(app.buttons["avi.actions.saveSong"].exists)
        XCTAssertFalse(app.buttons["avi.actions.artist"].exists)
        XCTAssertFalse(app.buttons["avi.actions.lyrics"].exists)
    }

    func testArtworkShowsRadioModeWhenMetadataLooksLikeBroadcast() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_UI_TEST_TRACK_ARTIST": "Live Stream",
                "TUNEAV_UI_TEST_TRACK_TITLE": "On Air",
            ]
        )

        openAviActions(in: app)

        XCTAssertTrue(app.buttons["avi.actions.radioInfo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["avi.actions.saveRadio"].exists)
        XCTAssertTrue(app.buttons["avi.actions.history"].exists)
        XCTAssertFalse(app.buttons["avi.actions.saveSong"].exists)
        XCTAssertFalse(app.buttons["avi.actions.lyrics"].exists)
        XCTAssertFalse(app.buttons["avi.actions.youtube"].exists)
        XCTAssertFalse(app.buttons["avi.actions.artist"].exists)
    }

    func testDetectedTrackAppearsWithoutBeingMarkedInteresting() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_UI_TEST_TRACK_ARTIST": "Portishead",
                "TUNEAV_UI_TEST_TRACK_TITLE": "Roads",
            ]
        )

        XCTAssertTrue(app.staticTexts["Roads"].waitForExistence(timeout: 5))

        closePlayer(in: app)
        app.buttons["tab.music"].tap()
        openDiscover(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Roads"].exists)
        XCTAssertTrue(app.staticTexts["Portishead"].exists)
    }

    private func openDiscover(in app: XCUIApplication) {
        let discoveriesSection = app.otherElements["music.section.discoveries"].firstMatch
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))
    }

    private func closePlayer(in app: XCUIApplication) {
        let closeOptionsButton = app.buttons["player.artwork.options.close"].firstMatch
        if closeOptionsButton.exists && closeOptionsButton.isHittable {
            closeOptionsButton.tap()
        }

        let musicTab = app.buttons["tab.music"].firstMatch
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86))

        for _ in 0..<3 {
            if musicTab.exists && musicTab.isHittable {
                return
            }

            start.press(forDuration: 0.05, thenDragTo: end)
        }

        XCTAssertTrue(musicTab.waitForExistence(timeout: 5))
        XCTAssertTrue(musicTab.isHittable)
    }

    private func openAviActions(in app: XCUIApplication, timeout: TimeInterval = 5) {
        let toggle = app.descendants(matching: .any)["avi.actions.toggle"].firstMatch
        if !toggle.waitForExistence(timeout: 2) {
            openFullPlayerFromMiniPlayer(in: app)
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout))
        toggle.tap()

        XCTAssertTrue(app.descendants(matching: .any)["avi.actions.history"].waitForExistence(timeout: timeout))
    }

    private func openFullPlayerFromMiniPlayer(in app: XCUIApplication, timeout: TimeInterval = 5) {
        let miniPlayer = app.descendants(matching: .any)["miniPlayer.container"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: timeout))
        miniPlayer.tap()
    }

    private func showDiscoveryHistory(in app: XCUIApplication) {
        if app.buttons["music.history.all"].firstMatch.exists {
            return
        }

        openMusicOverview(in: app)

        let historyButton = app.buttons["music.overview.history"].firstMatch
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()
        XCTAssertTrue(app.otherElements["music.section.discoveries"].firstMatch.waitForExistence(timeout: 5))
    }

    private func showSavedSongs(in app: XCUIApplication) {
        openMusicOverview(in: app)

        let songsButton = app.buttons["music.overview.songs"].firstMatch
        XCTAssertTrue(songsButton.waitForExistence(timeout: 5))
        songsButton.tap()
        XCTAssertTrue(app.otherElements["music.section.discoveries"].firstMatch.waitForExistence(timeout: 5))
    }

    private func toggleDiscoverySaved(_ discoveryID: String, in app: XCUIApplication) {
        let menuButton = app.buttons["discoveryTrack.menu.\(discoveryID)"].firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()

        let saveButton = app.descendants(matching: .any)["discoveryTrack.save.\(discoveryID)"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
    }

    private func openMusicOverview(in app: XCUIApplication) {
        if app.buttons["music.overview.songs"].firstMatch.exists {
            return
        }

        let overviewButton = app.buttons["music.overview"].firstMatch
        if overviewButton.waitForExistence(timeout: 2) {
            overviewButton.tap()
        } else {
            let backButton = app.buttons["music.detail.header.back"].firstMatch
            XCTAssertTrue(backButton.waitForExistence(timeout: 5))
            backButton.tap()
        }

        XCTAssertTrue(app.buttons["music.overview.songs"].firstMatch.waitForExistence(timeout: 5))
    }
}
