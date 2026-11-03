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

        XCTAssertTrue(shellButton("explore", in: app).exists)
        XCTAssertTrue(shellButton("library", in: app).exists)
    }

    func testShellShowsThreeDestinationsAndAvi() {
        let app = launchApp()

        XCTAssertTrue(shellButton("home", in: app).exists)
        XCTAssertTrue(shellButton("explore", in: app).exists)
        XCTAssertTrue(shellButton("library", in: app).exists)
        XCTAssertTrue(shellButton("avi", in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["tab.music"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tab.search"].exists)

        tapShellButton("explore", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["search.aviHeader"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Explorar"].firstMatch.exists)
    }

    func testLibrarySwitchesBetweenRadiosAndSongs() {
        let app = launchApp()

        tapShellButton("library", in: app)
        let radiosSegment = librarySegment("radios", in: app)
        let songsSegment = librarySegment("songs", in: app)
        XCTAssertTrue(radiosSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(radiosSegment.isSelected)
        XCTAssertTrue(app.otherElements["library.section.favorites"].waitForExistence(timeout: 5))

        songsSegment.tap()
        XCTAssertTrue(songsSegment.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["music.aviHeader"].firstMatch.waitForExistence(timeout: 5))

        tapShellButton("home", in: app)
        tapShellButton("library", in: app)
        XCTAssertTrue(songsSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(songsSegment.isSelected)
    }

    func testOpenTabMusicLandsOnLibrarySongs() {
        let app = launchApp(preferredTab: "music")

        let songsSegment = librarySegment("songs", in: app)
        XCTAssertTrue(songsSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(songsSegment.isSelected)
        XCTAssertFalse(librarySegment("radios", in: app).isSelected)
    }
}
