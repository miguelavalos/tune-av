import XCTest
@testable import TuneAVMac

final class TuneAVMacSmokeTests: XCTestCase {
    func testStationSamplesAreAvailable() {
        XCTAssertFalse(Station.samples.isEmpty)
    }

    func testMacRadioLibraryModesUseTheExpectedStationLists() {
        let saved = station(id: "saved", name: "Saved FM")
        let recent = station(id: "recent", name: "Recent FM")
        let tuned = station(id: "tuned", name: "Tuned FM")
        let music = station(id: "music", name: "Music FM")

        XCTAssertEqual(
            MacLibraryView.baseStations(
                for: .saved,
                favoriteStations: [saved],
                recentStations: [recent],
                tunedStations: [tuned],
                musicStations: [music]
            ).map(\.id),
            [saved.id]
        )
        XCTAssertEqual(
            MacLibraryView.baseStations(
                for: .recent,
                favoriteStations: [saved],
                recentStations: [recent],
                tunedStations: [tuned],
                musicStations: [music]
            ).map(\.id),
            [recent.id]
        )
        XCTAssertEqual(
            MacLibraryView.baseStations(
                for: .tuned,
                favoriteStations: [saved],
                recentStations: [recent],
                tunedStations: [tuned],
                musicStations: [music]
            ).map(\.id),
            [tuned.id]
        )
        XCTAssertEqual(
            MacLibraryView.baseStations(
                for: .music,
                favoriteStations: [saved],
                recentStations: [recent],
                tunedStations: [tuned],
                musicStations: [music]
            ).map(\.id),
            [music.id]
        )
    }

    func testMacRadioLibraryTunedStationsDeduplicateFavoritesAndRecentsWithFeedback() {
        let savedAndRecent = station(id: "same", name: "Same FM")
        let recentOnly = station(id: "recent-only", name: "Recent Only FM")
        let noFeedback = station(id: "plain", name: "Plain FM")

        let tuned = MacLibraryView.tunedStations(
            favoriteStations: [savedAndRecent, noFeedback],
            recentStations: [savedAndRecent, recentOnly],
            stationFeedback: [
                savedAndRecent.id: .liked,
                recentOnly.id: .notForMe
            ]
        )

        XCTAssertEqual(tuned.map(\.id), [savedAndRecent.id, recentOnly.id])
    }

    func testMacRadioLibraryMusicStationsComeFromDiscoveredTrackStations() {
        let favorite = station(id: "favorite", name: "Favorite FM")
        let recent = station(id: "recent", name: "Recent FM")
        let unknown = station(id: "unknown", name: "Unknown FM")
        let discoveries = [
            MacDiscoveredTrack(title: "Automatic", artist: "Less Than Jake", station: recent),
            MacDiscoveredTrack(title: "Lights Out", artist: "Royal Blood", station: favorite),
            MacDiscoveredTrack(title: "Lost", artist: "No Match", station: unknown),
            MacDiscoveredTrack(title: "Automatic", artist: "Less Than Jake", station: recent)
        ]

        XCTAssertEqual(
            MacLibraryView.musicStations(
                discoveredTracks: discoveries,
                favoriteStations: [favorite],
                recentStations: [recent]
            ).map(\.id),
            [recent.id, favorite.id]
        )
    }

    func testMacMusicHistoryUsesVisibleDiscoveriesInsteadOfTopDiscoveries() {
        let station = Station.samples[0]
        let historyOnly = MacDiscoveredTrack(
            title: "Automatic",
            artist: "Less Than Jake",
            station: station,
            playedAt: fixedDate("2026-07-03T10:55:00Z")
        )
        let saved = MacDiscoveredTrack(
            title: "Lights Out",
            artist: "Royal Blood",
            station: station,
            playedAt: fixedDate("2026-07-03T10:56:00Z"),
            markedInterestedAt: fixedDate("2026-07-03T10:56:30Z")
        )
        let tuned = MacDiscoveredTrack(
            title: "Faust",
            artist: "ITCHY",
            station: station,
            playedAt: fixedDate("2026-07-03T10:57:00Z")
        )

        XCTAssertEqual(
            MacMusicView.baseDiscoveries(
                for: .history,
                savedDiscoveries: [saved],
                visibleDiscoveries: [historyOnly, saved],
                topDiscoveries: [tuned]
            ),
            [historyOnly, saved]
        )
    }

    func testMacMusicTopUsesTunedDiscoveriesOnly() {
        let station = Station.samples[0]
        let historyOnly = MacDiscoveredTrack(
            title: "Automatic",
            artist: "Less Than Jake",
            station: station,
            playedAt: fixedDate("2026-07-03T10:55:00Z")
        )
        let tuned = MacDiscoveredTrack(
            title: "Faust",
            artist: "ITCHY",
            station: station,
            playedAt: fixedDate("2026-07-03T10:57:00Z")
        )

        XCTAssertEqual(
            MacMusicView.baseDiscoveries(
                for: .top,
                savedDiscoveries: [],
                visibleDiscoveries: [historyOnly],
                topDiscoveries: [tuned]
            ),
            [tuned]
        )
    }

    private func fixedDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
    }

    private func station(id: String, name: String) -> Station {
        Station(
            id: id,
            name: name,
            country: "Spain",
            language: "Spanish",
            tags: "music",
            streamURL: "https://example.com/\(id)"
        )
    }
}
