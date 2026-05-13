import XCTest

@MainActor
final class ZHomeEmptyStateUITests: TuneAVUITestCase {
    func testNewUserHomeShowsAviBriefWithoutRoutineSections() {
        let app = launchApp(
            extraEnvironment: [
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        let aviBrief = app.buttons["home.aviBrief.open"].firstMatch
        let recentsFavoritesSection = app.otherElements["home.section.recentsFavorites"]
        let legacyRecentsSection = app.otherElements["home.section.recents"]
        let legacyFavoritesSection = app.otherElements["home.section.favorites"]

        XCTAssertTrue(aviBrief.waitForExistence(timeout: 5))
        XCTAssertFalse(recentsFavoritesSection.exists)
        XCTAssertFalse(legacyRecentsSection.exists)
        XCTAssertFalse(legacyFavoritesSection.exists)
    }
}
