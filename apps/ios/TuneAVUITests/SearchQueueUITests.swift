import XCTest

@MainActor
final class SearchQueueUITests: TuneAVUITestCase {
    func testSeededSearchQueryOpensResults() {
        let app = launchApp(
            preferredTab: "search",
            extraEnvironment: [
                "TUNEAV_SEARCH_QUERY": "bbc",
                "TUNEAV_UI_TESTS_LOCAL_SEARCH": "1",
            ]
        )

        let resultsSection = app.otherElements["search.section.results"]
        let queryField = app.textFields.firstMatch
        let firstResult = resultsSection.descendants(matching: .staticText)["BBC Radio 1"].firstMatch

        XCTAssertTrue(queryField.waitForExistence(timeout: 5))
        XCTAssertEqual(queryField.value as? String, "bbc")
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5))
    }

    func testSearchResultsAdvanceWithinSearchQueue() {
        let app = launchApp(
            preferredTab: "search",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_SEARCH": "1",
            ]
        )

        let resultsSection = app.otherElements["search.section.results"]
        let playButton = resultsSection.descendants(matching: .button)["stationRow.play.bbc-radio-1"].firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        playButton.tap()

        let miniPlayer = app.buttons["miniPlayer.container"].firstMatch
        let miniPlayerNext = app.buttons["miniPlayer.next"].firstMatch
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
        XCTAssertTrue(miniPlayerNext.exists)
        miniPlayerNext.tap()

        miniPlayer.tap()

        let headerTitle = app.staticTexts["avi.context.header"]
        XCTAssertTrue(headerTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(headerTitle.label.contains("BBC Radio 1"))
    }
}
