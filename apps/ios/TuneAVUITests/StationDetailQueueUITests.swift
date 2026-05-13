import XCTest

@MainActor
final class StationDetailQueueUITests: TuneAVUITestCase {
    func testPlayingFromSearchRowKeepsSearchQueue() {
        let app = launchApp(
            preferredTab: "search",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_SEARCH": "1",
            ]
        )

        let playButton = app.buttons["stationRow.play.bbc-radio-1"].firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        playButton.tap()

        let miniPlayer = app.buttons["miniPlayer.container"].firstMatch
        let miniPlayerNext = app.buttons["miniPlayer.next"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
        XCTAssertTrue(miniPlayerNext.exists)
    }
}
