import XCTest

@MainActor
final class PlayerQueueUITests: TuneAVUITestCase {
    func testTabletPlayerLivesInContentArea() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }

        let app = launchApp(
            preferredTab: "home",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_SEED_FAVORITE": "1"
            ]
        )

        let sidebarHomeButton = app.descendants(matching: .any)["shell.tab.home"].firstMatch
        XCTAssertTrue(sidebarHomeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["shell.tab.explore"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["shell.tab.library"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["tune.sidebar.avi"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["tune.sidebar.music"].firstMatch.exists)

        let miniPlayerPlayPause = app.buttons["miniPlayer.playPause"].firstMatch
        XCTAssertTrue(miniPlayerPlayPause.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(miniPlayerPlayPause.frame.minX, sidebarHomeButton.frame.maxX)

        app.descendants(matching: .any)["tune.sidebar.avi"].firstMatch.tap()

        let expandedFooterPlayPause = app.buttons["avi.footerPlayer.playPause"].firstMatch
        XCTAssertTrue(expandedFooterPlayPause.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(expandedFooterPlayPause.frame.minX, sidebarHomeButton.frame.maxX)
    }

    func testFavoriteQueueAdvancesFromLibraryContext() {
        let app = launchApp(preferredTab: "library")

        let favoritesSection = app.otherElements["library.section.favorites"]
        let playButton = favoritesSection.descendants(matching: .button)["stationRow.play.bbc-radio-1"].firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        playButton.tap()

        let miniPlayer = app.buttons["miniPlayer.container"].firstMatch
        let miniPlayerNext = app.buttons["miniPlayer.next"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
        XCTAssertTrue(miniPlayerNext.exists)
        miniPlayerNext.tap()

        let switched = NSPredicate(format: "label CONTAINS %@", "SomaFM Groove Salad")
        expectation(for: switched, evaluatedWith: miniPlayer)
        waitForExpectations(timeout: 5)
    }

    func testFullPlayerShowsAirPlayRoutePicker() {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_SEED_FAVORITE": "1"
            ]
        )

        let playPause = app.buttons["avi.footerPlayer.playPause"].firstMatch
        if !playPause.waitForExistence(timeout: 2) {
            let miniPlayer = app.descendants(matching: .any)["miniPlayer.container"].firstMatch
            XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
            miniPlayer.tap()
        }
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))

        let airPlay = app.buttons["avi.footerPlayer.airplay"].firstMatch
        XCTAssertTrue(airPlay.waitForExistence(timeout: 5))
        XCTAssertTrue(airPlay.isHittable)
        XCTAssertFalse(airPlay.label.isEmpty)

        let stationTitle = app.descendants(matching: .any)["avi.footerPlayer.primaryTitle"].firstMatch
        XCTAssertTrue(stationTitle.exists)
        XCTAssertFalse(airPlay.frame.intersects(stationTitle.frame))
        XCTAssertLessThan(airPlay.frame.maxY, playPause.frame.minY)

        let container = app.descendants(matching: .any)["avi.footerPlayer.container"].firstMatch
        XCTAssertTrue(container.frame.contains(airPlay.frame))

        for identifier in ["queue", "previous", "next", "sleepTimer"] {
            XCTAssertTrue(app.descendants(matching: .any)["avi.footerPlayer.\(identifier)"].firstMatch.exists, identifier)
        }
    }
}
