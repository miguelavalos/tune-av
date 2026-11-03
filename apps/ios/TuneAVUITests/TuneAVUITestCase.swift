import XCTest

@MainActor
class TuneAVUITestCase: XCTestCase {
    @discardableResult
    func launchApp(
        preferredTab: String? = nil,
        disableOnboarding: Bool = true,
        extraEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TUNEAV_UI_TESTS"] = "1"
        app.launchEnvironment["TUNEAV_DISABLE_SPLASH"] = "1"
        if disableOnboarding {
            app.launchEnvironment["TUNEAV_DISABLE_ONBOARDING"] = "1"
        }
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

    func shellButton(
        _ id: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let button = shellElement(id, in: app)
        XCTAssertTrue(button.exists || button.waitForExistence(timeout: timeout), file: file, line: line)
        return button
    }

    func shellElement(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let identifiers = ["shell.tab.\(id)", "tab.\(id)", "tune.sidebar.\(id)"]
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", identifiers))
            .firstMatch
    }

    func librarySegment(
        _ id: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons["library.segment.\(id)"].firstMatch
    }

    func openLibrarySegment(
        _ id: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tapShellButton("library", in: app, timeout: timeout, file: file, line: line)
        let segment = librarySegment(id, in: app)
        XCTAssertTrue(segment.waitForExistence(timeout: timeout), file: file, line: line)
        segment.tap()
        XCTAssertTrue(segment.isSelected, file: file, line: line)
    }

    func tapShellButton(
        _ id: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = shellButton(id, in: app, timeout: timeout, file: file, line: line)
        XCTAssertTrue(button.isHittable, file: file, line: line)
        button.tap()
    }

    func firstExistingElement(
        _ elements: [XCUIElement],
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = elements.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertTrue(elements.contains(where: { $0.exists }), file: file, line: line)
        return elements[0]
    }
}
