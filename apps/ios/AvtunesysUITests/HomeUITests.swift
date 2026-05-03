import XCTest

@MainActor
final class HomeUITests: AvtunesysUITestCase {
    func testTogglingFavoriteDoesNotRecomposeHomeSections() {
        let app = launchApp()

        let recentsSection = app.otherElements["home.section.recents"]
        let favoritesSection = app.otherElements["home.section.favorites"]
        let discoverySection = app.otherElements["home.section.discovery"]
        let favoriteButton = recentsSection.descendants(matching: .button)["stationRow.favorite.bbc-radio-1"].firstMatch
        let stationRow = recentsSection.descendants(matching: .other)["stationRow.bbc-radio-1"].firstMatch

        XCTAssertTrue(recentsSection.waitForExistence(timeout: 5))
        XCTAssertTrue(favoritesSection.exists)
        XCTAssertTrue(discoverySection.exists)
        XCTAssertTrue(favoriteButton.exists)
        XCTAssertTrue(stationRow.exists)

        favoriteButton.tap()

        XCTAssertTrue(recentsSection.exists)
        XCTAssertTrue(favoritesSection.exists)
        XCTAssertTrue(discoverySection.exists)
        XCTAssertTrue(stationRow.exists)
    }
}
