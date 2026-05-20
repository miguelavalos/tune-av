import XCTest
@testable import TuneAV

final class AviStationDetailBuilderTests: XCTestCase {
    func testDetailUsesEnrichedStationAndQueue() {
        let station = makeStation(id: "base")
        let queueStation = makeStation(id: "queue")
        let builder = AviStationDetailBuilder(
            enrichStation: { station in
                Station(
                    id: station.id,
                    name: "Enriched \(station.name)",
                    country: station.country,
                    language: station.language,
                    tags: station.tags,
                    streamURL: station.streamURL
                )
            },
            enrichStations: { stations in
                stations.map { station in
                    Station(
                        id: station.id,
                        name: "Queue \(station.name)",
                        country: station.country,
                        language: station.language,
                        tags: station.tags,
                        streamURL: station.streamURL
                    )
                }
            }
        )

        let detail = builder.detail(
            station: station,
            queueSource: .homeDiscovery,
            queue: [queueStation]
        )

        XCTAssertEqual(detail.id, "base")
        XCTAssertEqual(detail.station.name, "Enriched Station base")
        XCTAssertEqual(detail.queueSource, .homeDiscovery)
        XCTAssertEqual(detail.queueStations.map(\.name), ["Queue Station queue"])
    }

    func testPlaybackQueueFallsBackWhenCurrentQueueIsEmpty() {
        let fallback = makeStation(id: "fallback")
        let builder = AviStationDetailBuilder(enrichStation: { $0 }, enrichStations: { $0 })

        XCTAssertEqual(
            builder.playbackQueue(stations: [], fallbackStation: fallback).map(\.id),
            ["fallback"]
        )
    }

    func testPlaybackQueueKeepsCurrentQueueWhenAvailable() {
        let fallback = makeStation(id: "fallback")
        let current = makeStation(id: "current")
        let next = makeStation(id: "next")
        let builder = AviStationDetailBuilder(enrichStation: { $0 }, enrichStations: { $0 })

        XCTAssertEqual(
            builder.playbackQueue(stations: [current, next], fallbackStation: fallback).map(\.id),
            ["current", "next"]
        )
    }

    func testActiveSignalSyncOnlyRunsInsideAvi() {
        let builder = AviStationDetailBuilder(enrichStation: { $0 }, enrichStations: { $0 })

        XCTAssertFalse(builder.shouldSyncActiveSignal(
            selectedTab: .home,
            isFullPlayer: true,
            previousStationID: "old",
            selectedDetailStationID: "old"
        ))
    }

    func testActiveSignalSyncRunsForAviFullPlayer() {
        let builder = AviStationDetailBuilder(enrichStation: { $0 }, enrichStations: { $0 })

        XCTAssertTrue(builder.shouldSyncActiveSignal(
            selectedTab: .avi,
            isFullPlayer: true,
            previousStationID: nil,
            selectedDetailStationID: nil
        ))
    }

    func testActiveSignalSyncRunsWhenVisibleDetailMatchesPreviousStation() {
        let builder = AviStationDetailBuilder(enrichStation: { $0 }, enrichStations: { $0 })

        XCTAssertTrue(builder.shouldSyncActiveSignal(
            selectedTab: .avi,
            isFullPlayer: false,
            previousStationID: "old",
            selectedDetailStationID: "old"
        ))
        XCTAssertFalse(builder.shouldSyncActiveSignal(
            selectedTab: .avi,
            isFullPlayer: false,
            previousStationID: "old",
            selectedDetailStationID: "other"
        ))
    }

    func testSelectionReturnsResolvedStationAndEnrichedQueueDetail() {
        let station = makeStation(id: "base")
        let queueStation = makeStation(id: "queue")
        let builder = AviStationDetailBuilder(
            enrichStation: { station in
                Station(
                    id: station.id,
                    name: "Enriched \(station.name)",
                    country: station.country,
                    language: station.language,
                    tags: station.tags,
                    streamURL: station.streamURL
                )
            },
            enrichStations: { stations in
                stations.map { station in
                    Station(
                        id: station.id,
                        name: "Queue \(station.name)",
                        country: station.country,
                        language: station.language,
                        tags: station.tags,
                        streamURL: station.streamURL
                    )
                }
            }
        )

        let selection = builder.selection(
            station: station,
            queueSource: .homeDiscovery,
            queue: { resolvedStation in [resolvedStation, queueStation] }
        )

        XCTAssertEqual(selection.resolvedStation.name, "Enriched Station base")
        XCTAssertEqual(selection.detail.station.name, "Enriched Station base")
        XCTAssertEqual(selection.detail.queueSource, .homeDiscovery)
        XCTAssertEqual(selection.detail.queueStations.map(\.name), ["Queue Enriched Station base", "Queue Station queue"])
    }

    func testOpenDetailSelectionTargetsAviWithoutFullPlayer() {
        let station = makeStation(id: "base")
        let builder = AviStationDetailBuilder(enrichStation: { $0 }, enrichStations: { $0 })

        let selection = builder.openDetailSelection(
            station: station,
            queueSource: .singleStation,
            queue: { [$0] },
            presentation: "detail"
        )

        XCTAssertEqual(selection.resolvedStation.id, "base")
        XCTAssertEqual(selection.detail.station.id, "base")
        XCTAssertEqual(selection.presentation, "detail")
        XCTAssertFalse(selection.isFullPlayer)
        XCTAssertEqual(selection.selectedTab, .avi)
    }

    func testOpenFullPlayerSelectionTargetsAviFullPlayer() {
        let station = makeStation(id: "base")
        let queueStation = makeStation(id: "queue")
        let builder = AviStationDetailBuilder(enrichStation: { $0 }, enrichStations: { $0 })

        let selection = builder.openFullPlayerSelection(
            station: station,
            queueSource: .homeDiscovery,
            queue: { [queueStation, $0] },
            presentation: "player"
        )

        XCTAssertEqual(selection.detail.queueSource, .homeDiscovery)
        XCTAssertEqual(selection.detail.queueStations.map { $0.id }, ["queue", "base"])
        XCTAssertEqual(selection.presentation, "player")
        XCTAssertTrue(selection.isFullPlayer)
        XCTAssertEqual(selection.selectedTab, AppShellTab.avi)
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
