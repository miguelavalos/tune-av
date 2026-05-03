import XCTest

@MainActor
final class ZHomeEmptyStateUITests: AvtunesysUITestCase {
    func testNewUserHomeShowsDiscoveryWithoutRoutineSections() {
        let app = launchApp(
            extraEnvironment: [
                "AVTUNESYS_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "AVTUNESYS_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        let recentsSection = app.otherElements["home.section.recents"]
        let favoritesSection = app.otherElements["home.section.favorites"]
        let discoverySection = app.otherElements["home.section.discovery"]

        XCTAssertTrue(discoverySection.waitForExistence(timeout: 5))
        XCTAssertFalse(recentsSection.exists)
        XCTAssertFalse(favoritesSection.exists)
    }
}
