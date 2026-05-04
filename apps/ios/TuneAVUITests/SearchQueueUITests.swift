import XCTest

@MainActor
final class SearchQueueUITests: TuneAVUITestCase {
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

        miniPlayer.tap()

        let headerTitle = app.staticTexts["player.headerTitle"]
        XCTAssertTrue(headerTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(headerTitle.label, "BBC Radio 1")

        let nextButton = app.buttons["player.transport.next"]
        XCTAssertTrue(nextButton.exists)
        nextButton.tap()

        let switched = NSPredicate(format: "label == %@", "Los 40")
        expectation(for: switched, evaluatedWith: headerTitle)
        waitForExpectations(timeout: 5)
    }
}
