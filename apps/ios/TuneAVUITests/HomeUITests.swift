import XCTest

@MainActor
final class HomeUITests: TuneAVUITestCase {
    func testTogglingFavoriteKeepsHomeInteractive() {
        let app = launchApp()

        let recentsFavoritesSection = app.otherElements["home.section.recentsFavorites"]
        let favoriteButton = recentsFavoritesSection.descendants(matching: .button)["stationRow.favorite.bbc-radio-1"].firstMatch
        let stationRow = recentsFavoritesSection.descendants(matching: .other)["stationRow.bbc-radio-1"].firstMatch

        XCTAssertTrue(recentsFavoritesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(favoriteButton.exists)
        XCTAssertTrue(stationRow.exists)

        favoriteButton.tap()

        XCTAssertTrue(app.buttons["tab.search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.music"].exists)
    }
}
