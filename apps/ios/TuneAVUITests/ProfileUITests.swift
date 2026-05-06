import XCTest

@MainActor
final class ProfileUITests: TuneAVUITestCase {
    func testSignedInFreeProfileStaysLocalFirstWithoutCloudSync() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free"
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
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "pro"
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
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "pro",
                "TUNEAV_UI_TEST_CLOUD_SYNC_STATUS": "conflict"
            ]
        )

        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["UI Test User"].exists)
    }

    func testDeleteAccountEligibleFreeTuneOnlyFlowSignsOutLocally() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "eligible"
            ]
        )

        openAccountDeletion(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.status.eligible"].waitForExistence(timeout: 5))

        let confirmation = app.textFields["accountDeletion.confirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.tap()
        confirmation.typeText("DELETE")
        app.buttons["accountDeletion.deleteButton"].tap()

        XCTAssertTrue(app.buttons["profile.account.connect"].waitForExistence(timeout: 5))
    }

    func testDeleteAccountBlockedBySeriesAVLinkedApp() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "blocked_series"
            ]
        )

        openAccountDeletion(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.status.blocked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Series AV"].exists)
        XCTAssertFalse(app.buttons["accountDeletion.deleteButton"].exists)
    }

    func testDeleteAccountBlockedByActivePro() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "pro",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "blocked_pro"
            ]
        )

        openAccountDeletion(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.status.blocked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tune AV Pro"].exists)
        XCTAssertFalse(app.buttons["accountDeletion.deleteButton"].exists)
    }

    func testCompletedDeletionSignsOutLocally() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "completed"
            ]
        )

        tapAccountDeletionRow(in: app)

        XCTAssertTrue(app.buttons["profile.account.connect"].waitForExistence(timeout: 5))
    }

    private func openAccountDeletion(in app: XCUIApplication) {
        tapAccountDeletionRow(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.sheet"].waitForExistence(timeout: 5))
    }

    private func tapAccountDeletionRow(in app: XCUIApplication) {
        let deleteRow = app.descendants(matching: .any)["profile.safety.delete"].firstMatch
        for _ in 0..<5 where !deleteRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 5))
        deleteRow.tap()
    }
}
