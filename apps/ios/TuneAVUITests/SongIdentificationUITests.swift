import XCTest

/// "What's playing?" in the full player with the scripted identifier the app uses under UI tests
/// (`TUNEAV_UI_TEST_SONG_IDENTIFICATION`): no network to the station, no ShazamKit call.
@MainActor
final class SongIdentificationUITests: TuneAVUITestCase {
    func testIdentifiedSongRendersLikeADetectedTrackAndSaves() {
        let app = launchIdentificationScenario("match")
        let identify = openFullPlayerAndFindIdentifyButton(in: app)

        tapWhenHittable(of: identify, scrollView: app.scrollViews.firstMatch, timeout: 8)

        let listening = app.descendants(matching: .any)["avi.fullPlayer.identifyListening"].firstMatch
        XCTAssertTrue(listening.waitForExistence(timeout: 3), "the listening state shows while the stream is captured")

        let matchedTitle = app.staticTexts["Midnight City"].firstMatch
        XCTAssertTrue(matchedTitle.waitForExistence(timeout: 10), "the recognised song renders as the current track")
        XCTAssertTrue(app.staticTexts["M83"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["avi.fullPlayer.identifyMatched"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["avi.fullPlayer.identifySong"].firstMatch.exists, "with a song on screen the action moves to the Avi panel")

        let heart = app.descendants(matching: .any)["avi.fullPlayer.heart"].firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 5))
        XCTAssertEqual(heart.label, "Guardar", "the heart now saves the song, not the radio")
        tapWhenHittable(of: heart, scrollView: app.scrollViews.firstMatch, timeout: 5)

        let saved = NSPredicate(format: "label == %@", "Quitar de Mis canciones")
        expectation(for: saved, evaluatedWith: heart)
        waitForExpectations(timeout: 5)
    }

    func testNoMatchShowsAvisMessageAndKeepsTheAction() {
        let app = launchIdentificationScenario("noMatch")
        let identify = openFullPlayerAndFindIdentifyButton(in: app)

        tapWhenHittable(of: identify, scrollView: app.scrollViews.firstMatch, timeout: 8)

        let result = app.descendants(matching: .any)["avi.fullPlayer.identifyResult"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains("No lo reconozco"), result.label)
        XCTAssertTrue(app.descendants(matching: .any)["avi.fullPlayer.identifySong"].firstMatch.waitForExistence(timeout: 3), "a no match keeps the action for a retry")
    }

    func testUnsupportedStationShowsAvisMessageWithoutTheAction() {
        let app = launchIdentificationScenario("unsupported")
        let identify = openFullPlayerAndFindIdentifyButton(in: app)

        tapWhenHittable(of: identify, scrollView: app.scrollViews.firstMatch, timeout: 8)

        let result = app.descendants(matching: .any)["avi.fullPlayer.identifyResult"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains("No disponible en esta emisora"), result.label)
        XCTAssertFalse(app.descendants(matching: .any)["avi.fullPlayer.identifySong"].firstMatch.exists)
    }

    func testAviActionsPanelOffersTheIdentification() {
        let app = launchIdentificationScenario("match")
        _ = openFullPlayerAndFindIdentifyButton(in: app)

        let toggle = app.descendants(matching: .any)["avi.actions.toggle"].firstMatch
        tapWhenHittable(of: toggle, scrollView: app.scrollViews.firstMatch, timeout: 8)

        let panelAction = app.descendants(matching: .any)["avi.actions.identifySong"].firstMatch
        XCTAssertTrue(panelAction.waitForExistence(timeout: 5))
        panelAction.tap()

        XCTAssertTrue(app.staticTexts["Midnight City"].firstMatch.waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

    private func launchIdentificationScenario(_ scenario: String) -> XCUIApplication {
        launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_UI_TEST_SONG_IDENTIFICATION": scenario,
                // One identification is one Avi lookup; the simulator's UserDefaults may already hold
                // today's Guest budget from earlier runs, so lift it for these scenarios.
                "TUNEAV_UI_TEST_AVI_ACTION_LIMIT": "100",
            ]
        )
    }

    private func openFullPlayerAndFindIdentifyButton(in app: XCUIApplication) -> XCUIElement {
        let header = app.descendants(matching: .any)["avi.focused.header"].firstMatch
        if !header.waitForExistence(timeout: 2) {
            let miniPlayer = app.descendants(matching: .any)["miniPlayer.container"].firstMatch
            XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
            miniPlayer.tap()
        }
        XCTAssertTrue(header.waitForExistence(timeout: 5))

        let identify = app.descendants(matching: .any)["avi.fullPlayer.identifySong"].firstMatch
        XCTAssertTrue(identify.waitForExistence(timeout: 8), "the station sends no title, so the player offers to identify the song")
        return identify
    }
}
