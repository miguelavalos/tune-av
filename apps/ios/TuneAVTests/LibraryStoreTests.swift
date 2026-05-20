import XCTest
@testable import TuneAV

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testListeningSessionBufferKeepsMostRecentSessionsWithinLimit() {
        let sessions = (0..<5).map { index in
            listeningSessionDraft(stationID: "station-\(index)")
        }

        let trimmed = LibraryStoreListeningSessionBuffer.trimmed(sessions, maxCount: 3)

        XCTAssertEqual(trimmed.map(\.station.id), ["station-2", "station-3", "station-4"])
    }

    func testListeningSessionBufferHandlesZeroLimit() {
        let sessions = [
            listeningSessionDraft(stationID: "station")
        ]

        XCTAssertTrue(LibraryStoreListeningSessionBuffer.trimmed(sessions, maxCount: 0).isEmpty)
    }

    func testListeningSessionBufferDeduplicatesByStableSessionIDKeepingNewestDraft() {
        let older = listeningSessionDraft(
            id: "stable-session",
            stationID: "station-old",
            endedReason: "stream_error"
        )
        let newer = listeningSessionDraft(
            id: "stable-session",
            stationID: "station-new",
            endedReason: "paused"
        )

        let deduplicated = LibraryStoreListeningSessionBuffer.deduplicated([
            listeningSessionDraft(id: "first-session", stationID: "station-first"),
            older,
            newer
        ])

        XCTAssertEqual(deduplicated.map(\.id), ["first-session", "stable-session"])
        XCTAssertEqual(deduplicated.last?.station.id, "station-new")
        XCTAssertEqual(deduplicated.last?.endedReason, "paused")
    }

    func testListeningSessionBufferBoundsAfterDeduplicatingRetries() {
        let sessions = [
            listeningSessionDraft(id: "session-1", stationID: "station-1"),
            listeningSessionDraft(id: "session-2", stationID: "station-2-old"),
            listeningSessionDraft(id: "session-2", stationID: "station-2-new"),
            listeningSessionDraft(id: "session-3", stationID: "station-3")
        ]

        let bounded = LibraryStoreListeningSessionBuffer.bounded(sessions, maxCount: 2)

        XCTAssertEqual(bounded.map(\.id), ["session-2", "session-3"])
        XCTAssertEqual(bounded.first?.station.id, "station-2-new")
    }

    func testListeningSessionPersistenceRestoresBoundedSessions() throws {
        let storageKey = "test.pendingListeningSessions.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: storageKey))
        defer { userDefaults.removePersistentDomain(forName: storageKey) }

        let sessions = [
            listeningSessionDraft(id: "session-1", stationID: "station-1"),
            listeningSessionDraft(id: "session-2", stationID: "station-2-old"),
            listeningSessionDraft(id: "session-2", stationID: "station-2-new"),
            listeningSessionDraft(id: "session-3", stationID: "station-3")
        ]

        LibraryStoreListeningSessionPersistence.save(
            sessions,
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2
        )

        let restored = LibraryStoreListeningSessionPersistence.load(
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2
        )

        XCTAssertEqual(restored.map(\.id), ["session-2", "session-3"])
        XCTAssertEqual(restored.first?.station.id, "station-2-new")
    }

    func testListeningSessionPersistenceClearsStorageWhenEmpty() throws {
        let storageKey = "test.pendingListeningSessions.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: storageKey))
        defer { userDefaults.removePersistentDomain(forName: storageKey) }

        LibraryStoreListeningSessionPersistence.save(
            [listeningSessionDraft(id: "session-1", stationID: "station-1")],
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2
        )
        XCTAssertNotNil(userDefaults.data(forKey: storageKey))

        LibraryStoreListeningSessionPersistence.save(
            [],
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2
        )

        XCTAssertNil(userDefaults.data(forKey: storageKey))
    }

    func testListeningSessionRetryPolicyAppliesExponentialBackoffAndJitter() {
        let firstRetryDelay = LibraryStoreListeningSessionRetryPolicy.delay(
            retryCount: 0,
            baseDelay: 30,
            maxDelay: 300,
            jitterFraction: 0.2,
            randomFraction: { 0 }
        )
        let secondRetryDelay = LibraryStoreListeningSessionRetryPolicy.delay(
            retryCount: 1,
            baseDelay: 30,
            maxDelay: 300,
            jitterFraction: 0.2,
            randomFraction: { 0.5 }
        )
        let cappedRetryDelay = LibraryStoreListeningSessionRetryPolicy.delay(
            retryCount: 10,
            baseDelay: 30,
            maxDelay: 300,
            jitterFraction: 0.2,
            randomFraction: { 1 }
        )

        XCTAssertEqual(firstRetryDelay, 24)
        XCTAssertEqual(secondRetryDelay, 60)
        XCTAssertEqual(cappedRetryDelay, 300)
    }

    func testListeningSessionRetryPolicyBoundsInvalidInputs() {
        XCTAssertEqual(
            LibraryStoreListeningSessionRetryPolicy.delay(
                retryCount: -1,
                baseDelay: 30,
                maxDelay: 300,
                jitterFraction: 2,
                randomFraction: { -1 }
            ),
            0
        )
        XCTAssertEqual(
            LibraryStoreListeningSessionRetryPolicy.delay(
                retryCount: 0,
                baseDelay: 0,
                maxDelay: 300,
                jitterFraction: 0.2
            ),
            0
        )
    }

    func testShellUITestBootstrapSeederSeedsFavoritesRecentsAndLocalDiscoveries() {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let launchContext = TuneAVLaunchContext(environment: [
            "TUNEAV_UI_TESTS": "1",
            "TUNEAV_UI_TESTS_LOCAL_DISCOVERY": "1"
        ])

        ShellUITestBootstrapSeeder.seedLibraryIfNeeded(
            launchContext: launchContext,
            libraryStore: store,
            recentLimit: 10
        )

        XCTAssertEqual(store.favoriteStations().map(\.id), Array(Station.samples.prefix(2)).map(\.id).reversed())
        XCTAssertEqual(store.recentStations().map(\.id), Array(Station.samples.prefix(3)).map(\.id).reversed())
        XCTAssertEqual(store.discoveries.map(\.title).sorted(), ["Midnight City", "Sweet Disposition"])
        XCTAssertEqual(store.discoveries.filter(\.isMarkedInteresting).map(\.title), ["Sweet Disposition"])
    }

    func testShellUITestBootstrapSeederSkipsExistingLibrariesAndNonUITestLaunches() {
        let existingStore = LibraryStore(container: PersistenceController(inMemory: true).container)
        existingStore.toggleFavorite(for: Station.samples[0])

        ShellUITestBootstrapSeeder.seedLibraryIfNeeded(
            launchContext: TuneAVLaunchContext(environment: ["TUNEAV_UI_TESTS": "1"]),
            libraryStore: existingStore,
            recentLimit: 10
        )

        XCTAssertEqual(existingStore.favoriteStations().map(\.id), [Station.samples[0].id])
        XCTAssertTrue(existingStore.recentStations().isEmpty)

        let productionStore = LibraryStore(container: PersistenceController(inMemory: true).container)
        ShellUITestBootstrapSeeder.seedLibraryIfNeeded(
            launchContext: TuneAVLaunchContext(environment: [:]),
            libraryStore: productionStore,
            recentLimit: 10
        )

        XCTAssertTrue(productionStore.favoriteStations().isEmpty)
        XCTAssertTrue(productionStore.recentStations().isEmpty)
    }

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

    private func listeningSessionDraft(
        id: String = UUID().uuidString,
        stationID: String,
        endedReason: String = "paused"
    ) -> TuneAVListeningSessionDraft {
        TuneAVListeningSessionDraft(
            id: id,
            station: Station(
                id: stationID,
                name: "Station \(stationID)",
                country: "Spain",
                language: "Spanish",
                tags: "pop",
                streamURL: "https://example.com/\(stationID)"
            ),
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 30),
            durationSeconds: 20,
            source: "home",
            endedReason: endedReason,
            trackDetectedCount: 1
        )
    }
}
