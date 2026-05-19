import XCTest

@MainActor
final class HomeRefreshUITests: TuneAVUITestCase {
    func testPullToRefreshPreservesFavoriteToggleState() {
        let app = launchApp(
            preferredTab: "home",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        let recentsFavoritesSection = app.otherElements["home.section.recentsFavorites"]
        let recentsFavoriteButton = recentsFavoritesSection.descendants(matching: .button)["stationRow.favorite.groove-salad"].firstMatch
        let stationRow = recentsFavoritesSection.descendants(matching: .other)["stationRow.groove-salad"].firstMatch

        XCTAssertTrue(recentsFavoritesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(recentsFavoriteButton.waitForExistence(timeout: 5))
        XCTAssertTrue(stationRow.exists)

        let initialFavoriteLabel = recentsFavoriteButton.label
        XCTAssertFalse(initialFavoriteLabel.isEmpty)

        tapWhenHittable(of: recentsFavoriteButton, scrollView: app.scrollViews.firstMatch)

        XCTAssertTrue(
            recentsFavoriteButton.waitForLabelChangeOrNonExistence(from: initialFavoriteLabel, timeout: 5)
        )

        let scrollView = app.scrollViews.firstMatch
        triggerRefresh(in: scrollView)

        XCTAssertTrue(recentsFavoriteButton.waitForStableToggledState(from: initialFavoriteLabel, timeout: 5))
    }

    private func triggerRefresh(
        in scrollView: XCUIElement,
        startY: CGFloat = 0.18,
        endY: CGFloat = 0.82
    ) {
        let pullStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let pullEnd = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        pullStart.press(forDuration: 0.05, thenDragTo: pullEnd)
    }
}

private extension XCUIElement {
    func waitForLabelChangeOrNonExistence(from previousLabel: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard exists else {
                return true
            }
            if label != previousLabel {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !exists || label != previousLabel
    }

    func waitForStableToggledState(from previousLabel: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard exists else {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                continue
            }
            if label != previousLabel {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !exists
    }
}
