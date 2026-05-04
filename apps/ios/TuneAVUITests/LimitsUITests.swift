import XCTest

@MainActor
final class LimitsUITests: TuneAVUITestCase {
    func testFavoriteLimitShowsUpgradePrompt() {
        let app = launchApp(
            extraEnvironment: [
                "TUNEAV_UI_TESTS_FORCE_GUEST": "1",
                "TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED": "1",
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TEST_FAVORITE_LIMIT": "0"
            ]
        )

        let recentsSection = app.otherElements["home.section.recents"]
        XCTAssertTrue(recentsSection.waitForExistence(timeout: 5))

        let favoriteButton = recentsSection.descendants(matching: .button)["stationRow.favorite.demo-groove-salad"].firstMatch
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 5))
        favoriteButton.tap()

        let upgradeSheet = app.descendants(matching: .any)["limits.upgrade.sheet.favoriteStations"].firstMatch
        XCTAssertTrue(upgradeSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["limits.upgrade.message"].exists)

        let dismissButton = app.descendants(matching: .any)["limits.upgrade.dismiss"].firstMatch
        XCTAssertTrue(dismissButton.exists)
        dismissButton.tap()

        XCTAssertFalse(upgradeSheet.exists)
    }

    func testYouTubeLimitShowsUpgradePromptInNowPlaying() {
        assertNowPlayingUpgradePrompt(
            feature: "youtubeSearch",
            limitEnvironmentKey: "TUNEAV_UI_TEST_YOUTUBE_LIMIT"
        )
    }

    func testLyricsLimitShowsUpgradePromptInNowPlaying() {
        assertNowPlayingUpgradePrompt(
            feature: "lyricsSearch",
            limitEnvironmentKey: "TUNEAV_UI_TEST_LYRICS_LIMIT"
        )
    }

    func testAppleMusicLimitShowsUpgradePromptInNowPlaying() {
        assertNowPlayingUpgradePrompt(
            feature: "appleMusicSearch",
            limitEnvironmentKey: "TUNEAV_UI_TEST_APPLE_MUSIC_LIMIT"
        )
    }

    func testSpotifyLimitShowsUpgradePromptInNowPlaying() {
        assertNowPlayingUpgradePrompt(
            feature: "spotifySearch",
            limitEnvironmentKey: "TUNEAV_UI_TEST_SPOTIFY_LIMIT"
        )
    }

    private func assertNowPlayingUpgradePrompt(
        feature: String,
        limitEnvironmentKey: String
    ) {
        let app = launchApp(
            preferredTab: "player",
            extraEnvironment: [
                "TUNEAV_UI_TESTS_FORCE_GUEST": "1",
                "TUNEAV_DEMO_MODE": "1",
                "TUNEAV_UI_TEST_TRACK_TITLE": "Midnight City",
                "TUNEAV_UI_TEST_TRACK_ARTIST": "M83",
                limitEnvironmentKey: "0",
                "TUNEAV_UI_TEST_UPGRADE_PROMPT_FEATURE": feature
            ]
        )

        let artworkFront = app.descendants(matching: .any)["player.artwork.front"].firstMatch
        XCTAssertTrue(artworkFront.waitForExistence(timeout: 5))

        let upgradeSheet = app.descendants(matching: .any)["limits.upgrade.sheet.\(feature)"].firstMatch
        XCTAssertTrue(upgradeSheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["limits.upgrade.message"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["limits.upgrade.dismiss"].exists)
    }
}
