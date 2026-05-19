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
