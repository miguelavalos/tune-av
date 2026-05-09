import XCTest
@testable import TuneAV

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testStationSnapshotsPreserveBackendEnrichmentForRecentsAndFavorites() {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let station = enrichedStation()

        store.recordPlayback(of: station, recentLimit: 10)
        store.toggleFavorite(for: station)

        XCTAssertEqual(store.recentStations().first?.editorial?.summary, "Editorial summary")
        XCTAssertEqual(store.recentStations().first?.editorial?.discoveryProfile?.musicDiscoveryScore, 42)
        XCTAssertEqual(store.favoriteStations().first?.editorial?.summary, "Editorial summary")
        XCTAssertEqual(store.favoriteStations().first?.artwork?.status, "generated")
    }

    func testRememberStationSnapshotsUpdatesExistingBasicLibraryStations() {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let basicStation = Station(
            id: "test-station",
            name: "Test Radio",
            country: "Spain",
            language: "Spanish",
            tags: "news",
            streamURL: "https://example.com/stream.mp3"
        )
        let enrichedStation = enrichedStation()

        store.recordPlayback(of: basicStation, recentLimit: 10)
        store.toggleFavorite(for: basicStation)
        XCTAssertNil(store.recentStations().first?.editorial)

        store.rememberStationSnapshots([enrichedStation])

        XCTAssertEqual(store.recentStations().first?.editorial?.summary, "Editorial summary")
        XCTAssertEqual(store.favoriteStations().first?.editorial?.discoveryProfile?.attentionMode, "active")
    }

    func testToggleDiscoveredTrackSavedSavesAndUnsavesCurrentTrack() {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let station = Station(
            id: "test-station",
            name: "Test Radio",
            country: "Spain",
            language: "Spanish",
            tags: "rock",
            streamURL: "https://example.com/stream.mp3"
        )

        let didSave = store.toggleDiscoveredTrackSaved(
            title: "Sweet Song",
            artist: "The Tests",
            station: station,
            artworkURL: nil,
            savedLimit: 10,
            discoveryLimit: 25
        )

        XCTAssertTrue(didSave)
        XCTAssertTrue(store.isSavedDiscoveredTrack(title: "Sweet Song", artist: "The Tests", station: station))
        XCTAssertEqual(store.savedDiscoveriesCount, 1)

        let didUnsave = store.toggleDiscoveredTrackSaved(
            title: "Sweet Song",
            artist: "The Tests",
            station: station,
            artworkURL: nil,
            savedLimit: 10,
            discoveryLimit: 25
        )

        XCTAssertTrue(didUnsave)
        XCTAssertFalse(store.isSavedDiscoveredTrack(title: "Sweet Song", artist: "The Tests", station: station))
        XCTAssertEqual(store.savedDiscoveriesCount, 0)
    }

    func testMusicLibraryHidesLegacyStationMetadataDiscoveries() {
        let station = Station(
            id: "radio-bob-classic-rock",
            name: "RADIO BOB! Classic Rock",
            country: "Germany",
            language: "German",
            tags: "classic rock",
            streamURL: "https://example.com/radio-bob.mp3"
        )
        let stationMetadata = DiscoveredTrack(
            title: "Classic Rock",
            artist: "RADIO BOB",
            station: station,
            artworkURL: nil,
            markedInterestedAt: .now
        )
        let realSong = DiscoveredTrack(
            title: "Welcome To The Jungle",
            artist: "Guns N' Roses",
            station: station,
            artworkURL: nil,
            markedInterestedAt: .now
        )

        let visible = AppShellMusicLibrary.visibleDiscoveries([stationMetadata, realSong])

        XCTAssertEqual(visible.map(\.title), ["Welcome To The Jungle"])
        XCTAssertEqual(AppShellMusicLibrary.savedDiscoveries([stationMetadata, realSong]).map(\.title), ["Welcome To The Jungle"])
    }

    private func enrichedStation() -> Station {
        Station(
            id: "test-station",
            name: "Test Radio",
            country: "Spain",
            language: "Spanish",
            tags: "news",
            streamURL: "https://example.com/stream.mp3",
            canonicalStationId: "canonical-test-station",
            category: "news",
            visibility: "public",
            qualityScore: 90,
            enrichmentStatus: "enriched",
            artwork: StationArtwork(status: "generated", url: "https://example.com/artwork.png", version: "v1"),
            editorial: StationEditorial(
                summary: "Editorial summary",
                primaryFormat: "newsTalk",
                secondaryFormats: ["sports"],
                musicIntensity: "low",
                speechIntensity: "high",
                languages: ["Spanish"],
                audience: ["Spain"],
                programming: ["news"],
                sourceUrls: ["https://example.com/source"],
                discoveryProfile: StationDiscoveryProfile(
                    musicDiscoveryScore: 42,
                    musicLevel: "low",
                    speechLevel: "high",
                    newsLevel: "high",
                    sportsLevel: "medium",
                    adLoad: "unknown",
                    metadataQuality: "fair",
                    attentionMode: "active",
                    bestFor: ["news"],
                    notIdealFor: ["music"],
                    genres: [],
                    moods: ["informative"],
                    reasons: ["Speech-led station."]
                ),
                confidence: "medium",
                reviewStatus: "generated",
                updatedAt: "2026-05-09T00:00:00Z"
            )
        )
    }
}
