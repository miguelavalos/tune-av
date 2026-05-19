import XCTest

@MainActor
final class HomeRefreshUITests: TuneAVUITestCase {
    func testPullToRefreshRecomposesFavoriteSection() {
        let app = launchApp(
            extraEnvironment: [
                "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1",
            ]
        )

        let recentsFavoritesSection = app.otherElements["home.section.recentsFavorites"]
        let recentsFavoriteButton = recentsFavoritesSection.descendants(matching: .button)["stationRow.favorite.groove-salad"].firstMatch
        let favoritesRow = recentsFavoritesSection.descendants(matching: .other)["stationRow.groove-salad"].firstMatch

        XCTAssertTrue(recentsFavoritesSection.waitForExistence(timeout: 5))
        XCTAssertTrue(recentsFavoriteButton.exists)
        XCTAssertTrue(favoritesRow.exists)

        tapWhenHittable(of: recentsFavoriteButton, scrollView: app.scrollViews.firstMatch)

        XCTAssertTrue(favoritesRow.waitForNonExistence(timeout: 5))

        let scrollView = app.scrollViews.firstMatch
        triggerRefresh(in: scrollView)

        if favoritesRow.exists {
            triggerRefresh(in: scrollView, startY: 0.12, endY: 0.9)
        }

        XCTAssertTrue(favoritesRow.waitForNonExistence(timeout: 5))
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
