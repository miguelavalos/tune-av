import XCTest

@MainActor
final class PlayerQueueUITests: TuneAVUITestCase {
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

        miniPlayer.tap()

        let currentStationTitle = app.staticTexts["BBC Radio 1"].firstMatch
        XCTAssertTrue(currentStationTitle.waitForExistence(timeout: 5))

        let nextButton = app.buttons["avi.footerPlayer.next"]
        XCTAssertTrue(nextButton.exists)
        nextButton.tap()

        let nextStationTitle = app.staticTexts["SomaFM Groove Salad"].firstMatch
        let switched = NSPredicate(format: "exists == true")
        expectation(for: switched, evaluatedWith: nextStationTitle)
        waitForExpectations(timeout: 5)
    }

}
