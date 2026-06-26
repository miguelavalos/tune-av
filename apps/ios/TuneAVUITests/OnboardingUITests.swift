import XCTest

@MainActor
final class OnboardingUITests: TuneAVUITestCase {
    func testSkippingLoginOpensHome() {
        let app = launchApp(
            disableOnboarding: false,
            extraEnvironment: [
                "TUNEAV_UI_TESTS_FORCE_GUEST": "1",
                "TUNEAV_UI_TESTS_SHOW_ONBOARDING": "1"
            ]
        )

        let skipButton = app.buttons["OMITIR POR AHORA"].firstMatch
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["home.section.recentsFavorites"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["OMITIR POR AHORA"].exists)
    }
}
