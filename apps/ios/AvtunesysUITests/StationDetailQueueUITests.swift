import XCTest

@MainActor
final class StationDetailQueueUITests: AvtunesysUITestCase {
    func testPlayingFromSearchStationSheetKeepsSearchQueue() {
        let app = launchApp(
            preferredTab: "search",
            extraEnvironment: [
                "AVTUNESYS_UI_TESTS_LOCAL_SEARCH": "1",
            ]
        )

        let stationRow = app.otherElements["stationRow.bbc-radio-1"].firstMatch
        XCTAssertTrue(stationRow.waitForExistence(timeout: 5))
        stationRow.tap()

        let sheetPlayButton = app.buttons["stationDetail.play"].firstMatch
        XCTAssertTrue(sheetPlayButton.waitForExistence(timeout: 5))
        sheetPlayButton.tap()

        let miniPlayer = app.buttons["miniPlayer.container"].firstMatch
        let miniPlayerNext = app.buttons["miniPlayer.next"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
        XCTAssertTrue(miniPlayerNext.exists)
    }
}
