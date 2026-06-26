import XCTest

@MainActor
final class HomeUITests: TuneAVUITestCase {
    func testTogglingFavoriteKeepsHomeInteractive() {
        let app = launchApp()

        let recentsFavoritesSection = app.otherElements["home.section.recentsFavorites"]
        let favoriteButton = recentsFavoritesSection.descendants(matching: .button)["stationRow.favorite.bbc-radio-1"].firstMatch
        let stationRow = recentsFavoritesSection.descendants(matching: .other)["stationRow.bbc-radio-1"].firstMatch

        XCTAssertTrue(recentsFavoritesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(stationRow.exists)

        tapWhenHittable(of: favoriteButton, scrollView: app.scrollViews.firstMatch)

        XCTAssertTrue(shellButton("search", in: app).exists)
        XCTAssertTrue(shellButton("music", in: app).exists)
    }
}
