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

        app.terminate()
        app.launch()
        addTeardownBlock {
            app.terminate()
        }
        return app
    }

    func tapWhenHittable(
        of element: XCUIElement,
        scrollView: XCUIElement? = nil,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)

        let deadline = Date().addingTimeInterval(timeout)
        var scrollAttempts = 0
        while !element.isHittable, Date() < deadline {
            if scrollAttempts < 4 {
                scrollView?.swipeUp()
                scrollAttempts += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertTrue(element.isHittable, file: file, line: line)
        element.tap()
    }
}
