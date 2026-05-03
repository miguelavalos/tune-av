import XCTest

@MainActor
final class DiscoveriesUITests: AvtunesysUITestCase {
    func testLibraryShowsAndFiltersDiscoveries() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "AVTUNESYS_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["music.mode.songs"].exists)
        XCTAssertTrue(app.buttons["music.mode.history"].exists)
        XCTAssertTrue(app.buttons["music.mode.artists"].exists)
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
                "AVTUNESYS_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)
        showDiscoveryHistory(in: app)

        let discoveryID = "m83-midnight-city-groove-salad"
        let saveButton = app.buttons["discoveryTrack.save.\(discoveryID)"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        app.buttons["music.mode.songs"].tap()
        XCTAssertTrue(app.staticTexts["Midnight City"].waitForExistence(timeout: 5))

        let unsaveButton = app.buttons["discoveryTrack.save.\(discoveryID)"].firstMatch
        XCTAssertTrue(unsaveButton.waitForExistence(timeout: 5))
        unsaveButton.tap()

        XCTAssertFalse(app.staticTexts["Midnight City"].exists)
    }

    func testCanMarkDiscoveryNotInterestedFromHistory() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "AVTUNESYS_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)
        showDiscoveryHistory(in: app)

        let discoveryID = "m83-midnight-city-groove-salad"
        XCTAssertTrue(app.staticTexts["Midnight City"].waitForExistence(timeout: 5))

        let menuButton = app.buttons["discoveryTrack.menu.\(discoveryID)"].firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()

        let hideButton = app.buttons["No me interesa"].firstMatch
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
                "AVTUNESYS_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)
        showDiscoveryHistory(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Midnight City"].exists)

        let discovery = app.otherElements.matching(identifier: "discoveryTrack.m83-midnight-city-groove-salad").firstMatch
        XCTAssertTrue(discovery.exists)
        discovery.buttons["Más"].tap()
        app.buttons["Eliminar descubrimiento"].tap()

        XCTAssertFalse(app.staticTexts["Midnight City"].exists)
    }

    func testCanClearAllDiscoveriesAfterConfirmation() {
        let app = launchApp(
            preferredTab: "music",
            extraEnvironment: [
                "AVTUNESYS_UI_TESTS_LOCAL_DISCOVERY": "1",
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
                "AVTUNESYS_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        openDiscover(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))

        discoveriesSection.buttons["discoveries.share"].tap()

        let shareSheet = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5))
    }

    func testArtworkFlipsToTrackOptionsAndSavesDiscovery() {
        let title = "Reckoner UI \(UUID().uuidString.prefix(8))"
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "AVTUNESYS_DEMO_MODE": "1",
                "AVTUNESYS_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "AVTUNESYS_UI_TEST_TRACK_ARTIST": "Radiohead",
                "AVTUNESYS_UI_TEST_TRACK_TITLE": title,
            ]
        )

        let artwork = waitForPlayerArtwork(in: app)
        artwork.tap()

        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Radiohead"].exists)
        XCTAssertTrue(app.buttons["player.artwork.options.share"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.radioInfo"].exists)

        let saveButton = app.buttons["player.artwork.options.discovery"].firstMatch
        saveButton.tap()

        app.buttons["player.artwork.options.discovery"].firstMatch.tap()

        app.buttons["player.artwork.options.discovery"].firstMatch.tap()

        closePlayer(in: app)
        app.buttons["tab.music"].tap()
        openDiscover(in: app)

        let discoveriesSection = app.otherElements["music.section.discoveries"]
        XCTAssertTrue(discoveriesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[title].exists)
        XCTAssertTrue(app.staticTexts["Radiohead"].exists)
    }

    func testArtworkOptionsHandleLongMetadataAndNonActionTitleTapFlipsBack() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "AVTUNESYS_DEMO_MODE": "1",
                "AVTUNESYS_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "AVTUNESYS_UI_TEST_TRACK_ARTIST": "Queens of the Stone Age",
                "AVTUNESYS_UI_TEST_TRACK_TITLE": "You Think I Ain't Worth A Dollar, But I Feel Like A Millionaire",
            ]
        )

        let artwork = waitForPlayerArtwork(in: app)
        artwork.tap()

        let longTitle = app.staticTexts["You Think I Ain't Worth A Dollar, But I Feel Like A Millionaire"].firstMatch
        XCTAssertTrue(longTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Queens of the Stone Age"].exists)
        XCTAssertTrue(app.buttons["player.artwork.options.discovery"].exists)
        XCTAssertTrue(app.buttons["player.artwork.options.artist"].exists)
        XCTAssertTrue(app.buttons["player.artwork.options.artistYouTube"].exists)

        app.buttons["player.artwork.options.songInfo"].tap()

        XCTAssertTrue(waitForPlayerArtwork(in: app).waitForExistence(timeout: 5))
    }

    func testArtworkShowsRadioOptionsWhenTrackArtistIsMissing() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "AVTUNESYS_DEMO_MODE": "1",
                "AVTUNESYS_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "AVTUNESYS_UI_TEST_TRACK_TITLE": "Untitled Broadcast",
            ]
        )

        let artwork = waitForPlayerArtwork(in: app)
        artwork.tap()

        XCTAssertTrue(app.buttons["player.artwork.options.playPause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["player.artwork.options.favorite"].exists)
        XCTAssertTrue(app.buttons["player.artwork.options.radioInfo"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.discovery"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.artist"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.lyrics"].exists)
    }

    func testArtworkShowsRadioModeWhenMetadataLooksLikeBroadcast() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "AVTUNESYS_DEMO_MODE": "1",
                "AVTUNESYS_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "AVTUNESYS_UI_TEST_TRACK_ARTIST": "Live Stream",
                "AVTUNESYS_UI_TEST_TRACK_TITLE": "On Air",
            ]
        )

        let artwork = waitForPlayerArtwork(in: app)
        artwork.tap()

        XCTAssertTrue(app.buttons["player.artwork.options.radioInfo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["player.artwork.options.playPause"].exists)
        XCTAssertTrue(app.buttons["player.artwork.options.favorite"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.discovery"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.share"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.lyrics"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.youtube"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.artist"].exists)
        XCTAssertFalse(app.buttons["player.artwork.options.artistYouTube"].exists)
    }

    func testDetectedTrackAppearsWithoutBeingMarkedInteresting() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "AVTUNESYS_DEMO_MODE": "1",
                "AVTUNESYS_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "AVTUNESYS_UI_TEST_TRACK_ARTIST": "Portishead",
                "AVTUNESYS_UI_TEST_TRACK_TITLE": "Roads",
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

    private func waitForPlayerArtwork(in app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement {
        let button = app.buttons["player.artwork.front"].firstMatch
        if button.waitForExistence(timeout: timeout) {
            return button
        }

        let otherElement = app.otherElements["player.artwork.front"].firstMatch
        XCTAssertTrue(otherElement.waitForExistence(timeout: timeout))
        return otherElement
    }

    private func showDiscoveryHistory(in app: XCUIApplication) {
        let historyButton = app.buttons["music.mode.history"].firstMatch
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()
    }
}
