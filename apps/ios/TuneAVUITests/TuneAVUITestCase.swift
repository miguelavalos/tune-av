import XCTest

@MainActor
class TuneAVUITestCase: XCTestCase {
    @discardableResult
    func launchApp(
        preferredTab: String? = nil,
        extraEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEAV_UI_TESTS"] = "1"
        app.launchEnvironment["TUNEAV_DISABLE_SPLASH"] = "1"
        app.launchEnvironment["TUNEAV_DISABLE_ONBOARDING"] = "1"
        app.launchEnvironment["TUNEAV_APP_LANGUAGE"] = "es"
        app.launchEnvironment["TUNEAV_UI_TEST_DISCOVERY_SHARE_LIMIT"] = "100"

        if let preferredTab {
            app.launchEnvironment["TUNEAV_OPEN_TAB"] = preferredTab
        }

        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }

        app.launch()
        return app
    }
}
