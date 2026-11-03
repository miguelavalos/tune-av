import AppIntents
import XCTest
@testable import TuneAV

@MainActor
final class SiriControlsTests: XCTestCase {
    private struct ForegroundRequested: Error, Equatable {
        let link: TuneAVWidgetDeepLink
    }

    private var actions: [TuneAVWidgetAction] = []

    private func station(_ id: String, name: String) -> Station {
        Station(
            id: id,
            name: name,
            country: "Spain",
            language: "Spanish",
            tags: "pop",
            streamURL: "https://example.com/\(id).mp3",
            artwork: nil
        )
    }

    private func routed(
        to outcome: TuneAVWidgetActionOutcome?,
        _ body: () async throws -> Void
    ) async rethrows {
        let savedHandler = TuneAVWidgetActionRouter.handler
        defer { TuneAVWidgetActionRouter.handler = savedHandler }
        actions = []
        if let outcome {
            TuneAVWidgetActionRouter.handler = { [weak self] action in
                self?.actions.append(action)
                return outcome
            }
        } else {
            TuneAVWidgetActionRouter.handler = nil
        }
        try await body()
    }

    // MARK: Start and pause plans

    func testStartPlanWithoutStationHasNothingToPlay() {
        XCTAssertEqual(
            TuneAVPlaybackRequestPlanner.startPlan(
                stationID: nil,
                isFavoriteShortcut: false,
                currentStationID: "a",
                status: .playing,
                opensAppToPlay: false
            ),
            .noStation
        )
    }

    func testStartPlanNeverPausesOrRestartsTheStationThatPlays() {
        for status in [TuneAVPlaybackState.playing, .loading] {
            for opensApp in [false, true] {
                XCTAssertEqual(
                    TuneAVPlaybackRequestPlanner.startPlan(
                        stationID: "a",
                        isFavoriteShortcut: false,
                        currentStationID: "a",
                        status: status,
                        opensAppToPlay: opensApp
                    ),
                    .alreadyPlaying
                )
            }
        }
    }

    func testStartPlanResumesOrPlaysWithoutTheCellularWarning() {
        typealias Planner = TuneAVPlaybackRequestPlanner
        for status in [TuneAVPlaybackState.paused, .failed("error"), .idle] {
            XCTAssertEqual(
                Planner.startPlan(stationID: "a", isFavoriteShortcut: false, currentStationID: "a", status: status, opensAppToPlay: false),
                .resume
            )
        }
        XCTAssertEqual(
            Planner.startPlan(stationID: "a", isFavoriteShortcut: true, currentStationID: "b", status: .playing, opensAppToPlay: false),
            .play(stationID: "a", isFavoriteShortcut: true)
        )
        XCTAssertEqual(
            Planner.startPlan(stationID: "a", isFavoriteShortcut: false, currentStationID: nil, status: .idle, opensAppToPlay: false),
            .play(stationID: "a", isFavoriteShortcut: false)
        )
    }

    func testStartPlanOpensTheAppWhenTheCellularWarningIsOn() {
        typealias Planner = TuneAVPlaybackRequestPlanner
        XCTAssertEqual(
            Planner.startPlan(stationID: "a", isFavoriteShortcut: false, currentStationID: nil, status: .idle, opensAppToPlay: true),
            .openApp(.play(stationID: "a", isFavoriteShortcut: false))
        )
        XCTAssertEqual(
            Planner.startPlan(stationID: "a", isFavoriteShortcut: true, currentStationID: "a", status: .paused, opensAppToPlay: true),
            .openApp(.play(stationID: "a", isFavoriteShortcut: true))
        )
    }

    func testPausePlanOnlyPausesActivePlayback() {
        XCTAssertEqual(TuneAVPlaybackRequestPlanner.pausePlan(status: .playing), .pause)
        XCTAssertEqual(TuneAVPlaybackRequestPlanner.pausePlan(status: .loading), .pause)
        XCTAssertEqual(TuneAVPlaybackRequestPlanner.pausePlan(status: .paused), .nothingToPause)
        XCTAssertEqual(TuneAVPlaybackRequestPlanner.pausePlan(status: .idle), .nothingToPause)
        XCTAssertEqual(TuneAVPlaybackRequestPlanner.pausePlan(status: .failed("error")), .nothingToPause)
    }

    // MARK: Station catalog and entity query

    func testCatalogListsFavoritesBeforeRecentsWithoutDuplicates() {
        let stations = TuneAVSiriStationCatalog.stations(
            favorites: [station("1", name: "Radio Clásica"), station("2", name: "Jazz FM")],
            recents: [
                station("2", name: "Jazz FM"),
                station("3", name: "radio clasica"),
                station("4", name: "Rock 80"),
                station("5", name: "   "),
            ]
        )
        XCTAssertEqual(stations.map(\.id), ["1", "2", "4"])
    }

    func testCatalogCapsTheNumberOfStations() {
        let favorites = (1...50).map { station("\($0)", name: "Station \($0)") }
        XCTAssertEqual(TuneAVSiriStationCatalog.stations(favorites: favorites, recents: []).count, TuneAVSiriStationCatalog.maximumStations)
        XCTAssertEqual(TuneAVSiriStationCatalog.stations(favorites: favorites, recents: [], limit: 3).map(\.id), ["1", "2", "3"])
    }

    func testMatchingIgnoresCaseAndAccentsAndRanksExactThenPrefixThenContains() {
        let stations = [
            station("1", name: "Los 40 Clásicos"),
            station("2", name: "Clásica FM"),
            station("3", name: "Radio Clásica"),
            station("4", name: "Jazz FM"),
            station("5", name: "Clasica"),
        ]
        XCTAssertEqual(TuneAVSiriStationCatalog.matching("CLASICA", in: stations).map(\.id), ["5", "2", "3"])
        XCTAssertEqual(TuneAVSiriStationCatalog.matching("  jazz fm ", in: stations).map(\.id), ["4"])
        XCTAssertEqual(TuneAVSiriStationCatalog.matching("", in: stations).map(\.id), ["1", "2", "3", "4", "5"])
        XCTAssertTrue(TuneAVSiriStationCatalog.matching("Opera", in: stations).isEmpty)
    }

    func testCatalogSignatureChangesWithNamesAndOrder() {
        let first = [station("1", name: "A"), station("2", name: "B")]
        XCTAssertEqual(TuneAVSiriStationCatalog.signature(of: first), TuneAVSiriStationCatalog.signature(of: first))
        XCTAssertNotEqual(
            TuneAVSiriStationCatalog.signature(of: first),
            TuneAVSiriStationCatalog.signature(of: [station("1", name: "A2"), station("2", name: "B")])
        )
        XCTAssertNotEqual(TuneAVSiriStationCatalog.signature(of: first), TuneAVSiriStationCatalog.signature(of: first.reversed()))
    }

    func testStationEntityUsesTheStationIDAndDisplayName() {
        let entity = TuneAVStationEntity(station: station("abc", name: "  Radio   Tune  "))
        XCTAssertEqual(entity.id, "abc")
        XCTAssertEqual(entity.name, TuneAVDisplayMetadata.normalized("  Radio   Tune  "))
        XCTAssertEqual(entity, TuneAVStationEntity(id: "abc", name: entity.name))
    }

    func testEntityQueryReadsTheSharedLibrary() async throws {
        let query = TuneAVStationEntityQuery()
        let expected = TuneAVWidgetController.shared.siriStations().map(\.id)
        let suggested = try await query.suggestedEntities()
        XCTAssertEqual(suggested.map(\.id), expected)
        XCTAssertLessThanOrEqual(suggested.count, TuneAVSiriStationCatalog.maximumStations)

        let missing = try await query.entities(for: ["tuneav-tests-missing-station"])
        XCTAssertTrue(missing.isEmpty)

        if let first = suggested.first {
            let resolved = try await query.entities(for: [first.id])
            XCTAssertEqual(resolved.map(\.id), [first.id])
            let matched = try await query.entities(matching: first.name)
            XCTAssertEqual(matched.first?.id, first.id)
        }
    }

    // MARK: Intent routing

    func testRouterWithoutHandlerHasNothingToPlay() async throws {
        try await routed(to: nil) {
            let outcome = await TuneAVWidgetActionRouter.perform(.startMyRadio)
            XCTAssertEqual(outcome, .noStation)
        }
    }

    func testPlayMyRadioIntentStartsMyRadio() async throws {
        try await routed(to: .playing) {
            _ = try await TuneAVPlayMyRadioIntent().perform()
            XCTAssertEqual(actions, [.startMyRadio])
        }
    }

    func testPlayMyRadioIntentIsQuietWhenAlreadyPlaying() async throws {
        try await routed(to: .alreadyPlaying) {
            _ = try await TuneAVPlayMyRadioIntent().perform()
            XCTAssertEqual(actions, [.startMyRadio])
        }
    }

    func testPlayMyRadioIntentExplainsWhenThereIsNoRadio() async throws {
        try await routed(to: .noStation) {
            do {
                _ = try await TuneAVPlayMyRadioIntent().perform()
                XCTFail("Expected an error")
            } catch let error as TuneAVSiriIntentError {
                XCTAssertEqual(error, .noRadio)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testPlayRadioIntentStartsTheChosenStation() async throws {
        try await routed(to: .playing) {
            let intent = TuneAVPlayRadioIntent(station: TuneAVStationEntity(id: "abc", name: "Radio"))
            _ = try await intent.perform()
            XCTAssertEqual(actions, [.startStation(id: "abc")])
        }
    }

    func testPlayRadioIntentReportsAStationThatIsGone() async throws {
        try await routed(to: .noStation) {
            do {
                _ = try await TuneAVPlayRadioIntent(station: TuneAVStationEntity(id: "gone", name: "Gone")).perform()
                XCTFail("Expected an error")
            } catch let error as TuneAVSiriIntentError {
                XCTAssertEqual(error, .stationUnavailable)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testStartRoutingContinuesInTheAppWhenTheCellularWarningIsOn() async throws {
        let link = TuneAVWidgetDeepLink.play(stationID: "abc", isFavoriteShortcut: false)
        try await routed(to: .needsApp(link)) {
            do {
                try await TuneAVSiriIntentRouting.start(.startMyRadio, missing: .noRadio) { link in
                    ForegroundRequested(link: link)
                }
                XCTFail("Expected a foreground request")
            } catch let error as ForegroundRequested {
                XCTAssertEqual(error.link, link)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testPlayIntentsAskToContinueInTheAppWhenTheCellularWarningIsOn() async throws {
        try await routed(to: .needsApp(.play(stationID: "abc", isFavoriteShortcut: false))) {
            do {
                _ = try await TuneAVPlayMyRadioIntent().perform()
                XCTFail("Expected a foreground request")
            } catch {
                XCTAssertFalse(error is TuneAVSiriIntentError)
            }
            do {
                _ = try await TuneAVPlayRadioIntent(station: TuneAVStationEntity(id: "abc", name: "Radio")).perform()
                XCTFail("Expected a foreground request")
            } catch {
                XCTAssertFalse(error is TuneAVSiriIntentError)
            }
        }
    }

    func testPauseIntentPausesWithoutErrors() async throws {
        try await routed(to: .nothingToPause) {
            _ = try await TuneAVPausePlaybackIntent().perform()
            XCTAssertEqual(actions, [.pausePlayback])
        }
    }

    func testControlIntentStartsAndPausesMyRadio() async throws {
        try await routed(to: .playing) {
            var intent = TuneAVMyRadioControlIntent()
            intent.value = true
            _ = try await intent.perform()
            intent.value = false
            _ = try await intent.perform()
            XCTAssertEqual(actions, [.startMyRadio, .pausePlayback])
        }
    }

    func testControlIntentOpensTheAppOnlyWhenItCannotPlayInPlace() {
        typealias Control = TuneAVMyRadioControlIntent
        let link = TuneAVWidgetDeepLink.play(stationID: "abc", isFavoriteShortcut: false)
        XCTAssertEqual(Control.appLink(after: .needsApp(link), startingPlayback: true), link)
        XCTAssertEqual(Control.appLink(after: .noStation, startingPlayback: true), .home)
        XCTAssertNil(Control.appLink(after: .noStation, startingPlayback: false))
        for outcome in [TuneAVWidgetActionOutcome.playing, .alreadyPlaying, .paused, .nothingToPause, .done] {
            XCTAssertNil(Control.appLink(after: outcome, startingPlayback: true))
            XCTAssertNil(Control.appLink(after: outcome, startingPlayback: false))
        }
    }

    func testContinueInAppIntentCarriesTheWidgetDeepLink() {
        let link = TuneAVWidgetDeepLink.play(stationID: "abc", isFavoriteShortcut: true)
        XCTAssertEqual(TuneAVContinueInAppIntent(link: link).deepLink, link)
        XCTAssertEqual(TuneAVContinueInAppIntent(link: .home).deepLink, .home)
        var foreign = TuneAVContinueInAppIntent()
        foreign.link = "https://example.com/widget/play?station=abc"
        XCTAssertNil(foreign.deepLink)
    }

    func testControlIntentRunsWhenTheCellularWarningIsOn() async throws {
        try await routed(to: .needsApp(.play(stationID: "abc", isFavoriteShortcut: false))) {
            var intent = TuneAVMyRadioControlIntent()
            intent.value = true
            _ = try await intent.perform()
            XCTAssertEqual(actions, [.startMyRadio])
        }
    }

    func testOnlyMyRadioChangesReloadTheControl() {
        XCTAssertTrue(TuneAVWidgetReloadPlanner.reloadsControls(kinds: TuneAVWidgetKind.all))
        XCTAssertTrue(TuneAVWidgetReloadPlanner.reloadsControls(kinds: [TuneAVWidgetKind.myRadio]))
        XCTAssertFalse(TuneAVWidgetReloadPlanner.reloadsControls(kinds: [TuneAVWidgetKind.nowPlayingFavorites]))
        XCTAssertFalse(TuneAVWidgetReloadPlanner.reloadsControls(kinds: []))
    }

    // MARK: Opening the app

    func testContinueInAppGoesToTheShellOrWaitsForIt() async {
        let controller = TuneAVWidgetController.shared
        var delivered: [TuneAVWidgetDeepLink] = []
        let link = TuneAVWidgetDeepLink.play(stationID: "abc", isFavoriteShortcut: true)

        let token = controller.registerShellPlayback({ _, _, _ in }, deepLink: { delivered.append($0) })
        controller.continueInApp(link)
        XCTAssertEqual(delivered, [link])
        controller.unregisterShellPlayback(token: token)

        controller.continueInApp(.home)
        XCTAssertEqual(delivered, [link])
        let laterToken = controller.registerShellPlayback({ _, _, _ in }, deepLink: { delivered.append($0) })
        for _ in 0..<20 where delivered.count < 2 {
            await Task.yield()
        }
        XCTAssertEqual(delivered, [link, .home])
        controller.unregisterShellPlayback(token: laterToken)
    }

    // MARK: Phrases

    func testProviderOffersPlayPauseAndPlayStationShortcuts() {
        let shortcuts = TuneAVAppShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 3)
    }
}
