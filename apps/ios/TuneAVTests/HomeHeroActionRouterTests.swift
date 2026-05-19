import XCTest
@testable import TuneAV

final class HomeHeroActionRouterTests: XCTestCase {
    func testPlayTogglesCurrentStation() {
        let station = makeStation(id: "hero")
        var didToggle = false
        var didPlay = false
        let router = makeRouter(
            isCurrentStation: { $0.id == station.id },
            togglePlayback: { didToggle = true },
            playStation: { _, _, _ in didPlay = true }
        )

        router.play(station, featuredState: makeFeaturedState(station: station))

        XCTAssertTrue(didToggle)
        XCTAssertFalse(didPlay)
    }

    func testPlayRoutesFeaturedQueueForNonCurrentStation() {
        let station = makeStation(id: "hero")
        let queued = makeStation(id: "queued")
        var routedSource: AudioPlayerService.PlaybackQueue.Source?
        var routedQueueIDs: [String] = []
        let router = makeRouter(
            isCurrentStation: { _ in false },
            playStation: { _, source, queue in
                routedSource = source
                routedQueueIDs = queue.map(\.id)
            }
        )

        router.play(
            station,
            featuredState: makeFeaturedState(
                station: station,
                queueSource: .homeFavorites,
                queueStations: [station, queued]
            )
        )

        XCTAssertEqual(routedSource, .homeFavorites)
        XCTAssertEqual(routedQueueIDs, ["hero", "queued"])
    }

    func testShowDetailsRoutesFeaturedQueue() {
        let station = makeStation(id: "hero")
        let queued = makeStation(id: "queued")
        var routedSource: AudioPlayerService.PlaybackQueue.Source?
        var routedQueueIDs: [String] = []
        let router = makeRouter(
            showStationDetails: { _, source, queue in
                routedSource = source
                routedQueueIDs = queue.map(\.id)
            }
        )

        router.showDetails(
            station,
            featuredState: makeFeaturedState(
                station: station,
                queueSource: .homeRecents,
                queueStations: [queued, station]
            )
        )

        XCTAssertEqual(routedSource, .homeRecents)
        XCTAssertEqual(routedQueueIDs, ["queued", "hero"])
    }

    func testSetFeedbackTogglesSelectedFeedback() {
        let station = makeStation(id: "hero")
        var routedFeedback: TuneAVStationFeedback?
        let router = makeRouter(
            currentFeedback: { _ in .liked },
            setStationFeedback: { _, feedback in routedFeedback = feedback }
        )

        router.setFeedback(.liked, for: station)
        XCTAssertNil(routedFeedback)

        router.setFeedback(.disliked, for: station)
        XCTAssertEqual(routedFeedback, .disliked)
    }

    private func makeRouter(
        isCurrentStation: @escaping (Station) -> Bool = { _ in false },
        togglePlayback: @escaping () -> Void = {},
        playStation: @escaping (Station, AudioPlayerService.PlaybackQueue.Source, [Station]) -> Void = { _, _, _ in },
        showStationDetails: @escaping (Station, AudioPlayerService.PlaybackQueue.Source, [Station]) -> Void = { _, _, _ in },
        currentFeedback: @escaping (Station) -> TuneAVStationFeedback? = { _ in nil },
        setStationFeedback: @escaping (Station, TuneAVStationFeedback?) -> Void = { _, _ in }
    ) -> HomeHeroActionRouter {
        HomeHeroActionRouter(
            isCurrentStation: isCurrentStation,
            togglePlayback: togglePlayback,
            playStation: playStation,
            showStationDetails: showStationDetails,
            currentFeedback: currentFeedback,
            setStationFeedback: setStationFeedback
        )
    }

    private func makeFeaturedState(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .homeDiscovery,
        queueStations: [Station]? = nil
    ) -> HomeFeaturedStationState {
        HomeFeaturedStationState(
            station: station,
            source: .popular,
            queueSource: queueSource,
            queueStations: queueStations ?? [station]
        )
    }

    private func makeStation(id: String) -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            country: "Spain",
            language: "Spanish",
            tags: "music",
            streamURL: "https://example.com/\(id)"
        )
    }
}
