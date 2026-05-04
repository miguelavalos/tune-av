import XCTest
@testable import TuneAV

@MainActor
final class LibraryStoreTests: XCTestCase {
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
}
