import XCTest

@MainActor
class AvtunesysUITestCase: XCTestCase {
    @discardableResult
    func launchApp(
        preferredTab: String? = nil,
        extraEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AVTUNESYS_UI_TESTS"] = "1"
        app.launchEnvironment["AVTUNESYS_DISABLE_SPLASH"] = "1"
        app.launchEnvironment["AVTUNESYS_DISABLE_ONBOARDING"] = "1"

        if let preferredTab {
            app.launchEnvironment["AVTUNESYS_OPEN_TAB"] = preferredTab
        }

        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }

        app.launch()
        return app
    }
}
