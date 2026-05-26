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

        openAccountProfile(in: app)
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

        openAccountProfile(in: app)
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

        openAccountProfile(in: app)
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["UI Test User"].exists)
    }

    func testSignedInFreeCanOpenProPaywallWithRestoreAndLegalLinks() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free",
                "TUNEAV_UI_TEST_SUBSCRIPTION_STUB": "1"
            ]
        )

        openAccountProfile(in: app)
        openProPaywall(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["paywall.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paywall.purchase"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paywall.restore"].exists)

        let termsButton = app.buttons["paywall.terms"].firstMatch
        let privacyButton = app.buttons["paywall.privacy"].firstMatch
        for _ in 0..<5 where !termsButton.exists || !privacyButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(termsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 3))
    }

    func testDeleteAccountEligibleFreeTuneOnlyFlowSignsOutLocally() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "eligible"
            ]
        )

        openAccountProfile(in: app)
        openAccountDeletion(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.status.eligible"].waitForExistence(timeout: 5))

        let confirmation = app.textFields["accountDeletion.confirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.tap()
        confirmation.typeText("DELETE")
        app.buttons["accountDeletion.deleteButton"].tap()

        XCTAssertTrue(app.buttons["profile.account.connect"].waitForExistence(timeout: 5))
    }

    func testDeleteAccountWarnsForLinkedApp() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "blocked_series"
            ]
        )

        openAccountProfile(in: app)
        openAccountDeletion(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.status.eligible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.impact.linkedApps"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.warning.linkedApp"].exists)
        XCTAssertTrue(app.buttons["accountDeletion.deleteButton"].exists)
    }

    func testDeleteAccountWarnsForActivePro() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "pro",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "blocked_pro"
            ]
        )

        openAccountProfile(in: app)
        openAccountDeletion(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.status.eligible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.impact.high"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.warning.activeProAccess"].exists)
        XCTAssertTrue(app.buttons["accountDeletion.deleteButton"].exists)
    }

    func testDeleteAccountWarnsStronglyForActiveCreditsButDoesNotBlock() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "active_credits"
            ]
        )

        openAccountProfile(in: app)
        openAccountDeletion(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.status.eligible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.impact.high"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["accountDeletion.warning.activeAiCredits"].exists)
        XCTAssertTrue(app.buttons["accountDeletion.deleteButton"].exists)
    }

    func testCompletedDeletionSignsOutLocally() {
        let app = launchApp(
            preferredTab: "settings",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_ACCOUNT_MODE": "free",
                "TUNEAV_UI_TEST_ACCOUNT_DELETION": "completed"
            ]
        )

        openAccountProfile(in: app)
        tapAccountDeletionRow(in: app)

        XCTAssertTrue(app.buttons["profile.account.connect"].waitForExistence(timeout: 5))
    }

    private func openAccountProfile(in app: XCUIApplication) {
        let accountButton = app.buttons["header.account"].firstMatch
        XCTAssertTrue(accountButton.waitForExistence(timeout: 5))
        accountButton.tap()
    }

    private func openProPaywall(in app: XCUIApplication) {
        let proButton = app.descendants(matching: .any)["profile.pro.viewOffer"].firstMatch
        let localizedProButton = app.buttons["Ver Pro"].firstMatch
        for _ in 0..<6 where !proButton.exists || !proButton.isHittable {
            if localizedProButton.exists, localizedProButton.isHittable {
                localizedProButton.tap()
                return
            }
            app.swipeUp()
        }
        if proButton.waitForExistence(timeout: 2), proButton.isHittable {
            proButton.tap()
        } else {
            XCTAssertTrue(localizedProButton.waitForExistence(timeout: 5))
            XCTAssertTrue(localizedProButton.isHittable)
            localizedProButton.tap()
        }
    }

    private func openAccountDeletion(in app: XCUIApplication) {
        tapAccountDeletionRow(in: app)
        let sheet = app.descendants(matching: .any)["accountDeletion.sheet"]
        if !sheet.waitForExistence(timeout: 5) {
            tapAccountDeletionRow(in: app)
        }
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    }

    private func tapAccountDeletionRow(in app: XCUIApplication) {
        let deleteRow = app.descendants(matching: .any)["profile.safety.delete"].firstMatch
        for _ in 0..<6 where !deleteRow.exists || !deleteRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteRow.isHittable)
        deleteRow.tap()
    }
}
