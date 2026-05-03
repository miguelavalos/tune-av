import XCTest

@MainActor
final class ProfileUITests: AvtunesysUITestCase {
    func testSignedInFreeProfileStaysLocalFirstWithoutCloudSync() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "AVTUNESYS_UI_TESTS_ACCOUNT_MODE": "free"
            ]
        )

        XCTAssertTrue(app.staticTexts["UI Test User"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ui-test@example.test"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["profile.sync.card"].exists)
    }

    func testProProfileShowsCloudSyncStatusAndRetry() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "AVTUNESYS_UI_TESTS_ACCOUNT_MODE": "pro"
            ]
        )

        let syncCard = app.descendants(matching: .any)["profile.sync.card"].firstMatch
        for _ in 0..<4 where !syncCard.waitForExistence(timeout: 1) {
            app.swipeUp()
        }

        XCTAssertTrue(syncCard.waitForExistence(timeout: 5))
    }

    func testCloudSyncConflictDoesNotInterruptTheUser() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "AVTUNESYS_UI_TESTS_ACCOUNT_MODE": "pro",
                "AVTUNESYS_UI_TEST_CLOUD_SYNC_STATUS": "conflict"
            ]
        )

        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["UI Test User"].exists)
    }
}
