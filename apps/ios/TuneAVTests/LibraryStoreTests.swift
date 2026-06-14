import XCTest
@testable import TuneAV

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testListeningSessionBufferKeepsMostRecentSessionsWithinLimit() {
        let sessions = (0..<5).map { index in
            listeningSessionDraft(stationID: "station-\(index)")
        }

        let trimmed = LibraryStoreListeningSessionBuffer.trimmed(sessions, maxCount: 3)

        XCTAssertEqual(trimmed.map(\.stationID), ["station-2", "station-3", "station-4"])
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
        XCTAssertEqual(deduplicated.last?.stationID, "station-new")
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
        XCTAssertEqual(bounded.first?.stationID, "station-2-new")
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
            maxCount: 2,
            maxAge: 100,
            now: Date(timeIntervalSince1970: 40)
        )

        let restored = LibraryStoreListeningSessionPersistence.load(
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2,
            maxAge: 100,
            now: Date(timeIntervalSince1970: 40)
        )

        XCTAssertEqual(restored.map(\.id), ["session-2", "session-3"])
        XCTAssertEqual(restored.first?.stationID, "station-2-new")
    }

    func testListeningSessionPersistenceStoresCompactStationIdentityOnly() throws {
        let storageKey = "test.pendingListeningSessions.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: storageKey))
        defer { userDefaults.removePersistentDomain(forName: storageKey) }

        LibraryStoreListeningSessionPersistence.save(
            [listeningSessionDraft(id: "session-1", stationID: "station-1")],
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2,
            maxAge: 100,
            now: Date(timeIntervalSince1970: 40)
        )

        let data = try XCTUnwrap(userDefaults.data(forKey: storageKey))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"stationID\""))
        XCTAssertTrue(json.contains("\"stationName\""))
        XCTAssertFalse(json.contains("\"station\""))
        XCTAssertFalse(json.contains("streamURL"))
    }

    func testListeningSessionPersistenceMigratesLegacyStationDrafts() throws {
        struct LegacyDraft: Encodable {
            let id: String
            let station: Station
            let startedAt: Date
            let endedAt: Date
            let durationSeconds: Int
            let source: String
            let endedReason: String
            let trackDetectedCount: Int
        }

        let storageKey = "test.pendingListeningSessions.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: storageKey))
        defer { userDefaults.removePersistentDomain(forName: storageKey) }

        let legacyDraft = LegacyDraft(
            id: "legacy-session",
            station: Station(
                id: "legacy-station",
                name: "Legacy Station",
                country: "Spain",
                language: "Spanish",
                tags: "pop",
                streamURL: "https://example.com/legacy.mp3"
            ),
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 30),
            durationSeconds: 20,
            source: "home",
            endedReason: "paused",
            trackDetectedCount: 1
        )
        userDefaults.set(try JSONEncoder().encode([legacyDraft]), forKey: storageKey)

        let restored = LibraryStoreListeningSessionPersistence.load(
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2,
            maxAge: 100,
            now: Date(timeIntervalSince1970: 40)
        )

        XCTAssertEqual(restored.first?.stationID, "legacy-station")
        XCTAssertEqual(restored.first?.stationName, "Legacy Station")
    }

    func testListeningSessionPersistenceDropsExpiredSessions() throws {
        let storageKey = "test.pendingListeningSessions.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: storageKey))
        defer { userDefaults.removePersistentDomain(forName: storageKey) }

        let now = Date(timeIntervalSince1970: 1_000)
        let sessions = [
            listeningSessionDraft(
                id: "expired",
                stationID: "station-expired",
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 120)
            ),
            listeningSessionDraft(
                id: "retained",
                stationID: "station-retained",
                startedAt: Date(timeIntervalSince1970: 960),
                endedAt: Date(timeIntervalSince1970: 980)
            )
        ]

        LibraryStoreListeningSessionPersistence.save(
            sessions,
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 5,
            maxAge: 100,
            now: now
        )

        let restored = LibraryStoreListeningSessionPersistence.load(
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 5,
            maxAge: 100,
            now: now
        )

        XCTAssertEqual(restored.map(\.id), ["retained"])
    }

    func testListeningSessionPersistenceClearsStorageWhenEmpty() throws {
        let storageKey = "test.pendingListeningSessions.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: storageKey))
        defer { userDefaults.removePersistentDomain(forName: storageKey) }

        LibraryStoreListeningSessionPersistence.save(
            [listeningSessionDraft(id: "session-1", stationID: "station-1")],
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2,
            maxAge: 100,
            now: Date(timeIntervalSince1970: 40)
        )
        XCTAssertNotNil(userDefaults.data(forKey: storageKey))

        LibraryStoreListeningSessionPersistence.save(
            [],
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2,
            maxAge: 100,
            now: Date(timeIntervalSince1970: 40)
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

    func testLocalFeedbackRetentionLimitsByAccessMode() {
        XCTAssertEqual(TuneAVLocalFeedbackRetention.forMode(.guest).stationFeedbackLimit, 50)
        XCTAssertEqual(TuneAVLocalFeedbackRetention.forMode(.guest).trackFeedbackLimit, 50)
        XCTAssertEqual(TuneAVLocalFeedbackRetention.forMode(.signedInFree).stationFeedbackLimit, 100)
        XCTAssertEqual(TuneAVLocalFeedbackRetention.forMode(.signedInFree).trackFeedbackLimit, 100)
        XCTAssertEqual(TuneAVLocalFeedbackRetention.forMode(.signedInPro).stationFeedbackLimit, 300)
        XCTAssertEqual(TuneAVLocalFeedbackRetention.forMode(.signedInPro).trackFeedbackLimit, 300)
        XCTAssertEqual(TuneAVLocalFeedbackRetention.maximumLocalRetention, TuneAVLocalFeedbackRetention.forMode(.signedInPro))
    }

    func testLibraryStoreInitialLoadKeepsProFeedbackBeforeAccessModeResolves() {
        let stationFeedbackStorageKey = "tuneav.stationFeedback.v1"
        let trackFeedbackStorageKey = "tuneav.trackFeedback.v1"
        let userDefaults = UserDefaults.standard
        let previousStationData = userDefaults.data(forKey: stationFeedbackStorageKey)
        let previousTrackData = userDefaults.data(forKey: trackFeedbackStorageKey)
        defer {
            if let previousStationData {
                userDefaults.set(previousStationData, forKey: stationFeedbackStorageKey)
            } else {
                userDefaults.removeObject(forKey: stationFeedbackStorageKey)
            }
            if let previousTrackData {
                userDefaults.set(previousTrackData, forKey: trackFeedbackStorageKey)
            } else {
                userDefaults.removeObject(forKey: trackFeedbackStorageKey)
            }
        }

        let records = Dictionary(
            uniqueKeysWithValues: (0..<75).map { index in
                (
                    "station-\(index)",
                    TuneAVLocalFeedbackRecord(
                        feedback: .liked,
                        updatedAt: TuneAVDateCoding.string(from: Date(timeIntervalSince1970: TimeInterval(index)))
                    )
                )
            }
        )
        let data = try! JSONEncoder().encode(records)
        userDefaults.set(data, forKey: stationFeedbackStorageKey)
        userDefaults.removeObject(forKey: trackFeedbackStorageKey)

        let store = LibraryStore(container: PersistenceController(inMemory: true).container)

        XCTAssertEqual(store.stationFeedback.count, 75)
    }

    func testLocalFeedbackStoreKeepsMostRecentRecordsWithinLimit() {
        let records = [
            "old": TuneAVLocalFeedbackRecord(feedback: .liked, updatedAt: TuneAVDateCoding.string(from: Date(timeIntervalSince1970: 10))),
            "middle": TuneAVLocalFeedbackRecord(feedback: .notForMe, updatedAt: TuneAVDateCoding.string(from: Date(timeIntervalSince1970: 20))),
            "new": TuneAVLocalFeedbackRecord(feedback: .disliked, updatedAt: TuneAVDateCoding.string(from: Date(timeIntervalSince1970: 30)))
        ]

        let bounded = TuneAVLocalFeedbackStore.bounded(records, maxCount: 2)

        XCTAssertNil(bounded["old"])
        XCTAssertEqual(bounded["middle"]?.feedback, .notForMe)
        XCTAssertEqual(bounded["new"]?.feedback, .disliked)
    }

    func testLocalFeedbackStoreMigratesLegacyFeedbackWithTimestamp() {
        let updatedAt = Date(timeIntervalSince1970: 42)

        let records = TuneAVLocalFeedbackStore.records(
            fromLegacy: [
                "station": .liked,
                "track": .disliked
            ],
            updatedAt: updatedAt
        )

        XCTAssertEqual(records["station"]?.feedback, .liked)
        XCTAssertEqual(records["track"]?.feedback, .disliked)
        XCTAssertEqual(records["station"]?.updatedAt, TuneAVDateCoding.string(from: updatedAt))
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

    func testRememberStationSnapshotsKeepsNewestMetadataSnapshot() {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let newerStation = enrichedStation(metadataUpdatedAt: "2026-05-20T10:00:00Z", artworkVersion: "new")
        let olderStation = enrichedStation(metadataUpdatedAt: "2026-05-19T10:00:00Z", artworkVersion: "old")
        let newestStation = enrichedStation(metadataUpdatedAt: "2026-05-21T10:00:00Z", artworkVersion: "newest")

        store.recordPlayback(of: newerStation, recentLimit: 10)
        store.toggleFavorite(for: newerStation)

        store.rememberStationSnapshots([olderStation])

        XCTAssertEqual(store.recentStations().first?.artwork?.version, "new")
        XCTAssertEqual(store.favoriteStations().first?.metadataUpdatedAt, "2026-05-20T10:00:00Z")

        store.rememberStationSnapshots([newestStation])

        XCTAssertEqual(store.recentStations().first?.artwork?.version, "newest")
        XCTAssertEqual(store.favoriteStations().first?.metadataUpdatedAt, "2026-05-21T10:00:00Z")
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

    func testToggleDiscoveredTrackSavedPersistsCurrentTrackArtwork() throws {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let station = Station(
            id: "test-station",
            name: "Test Radio",
            country: "Spain",
            language: "Spanish",
            tags: "rock",
            streamURL: "https://example.com/stream.mp3"
        )
        let artworkURL = try XCTUnwrap(URL(string: "https://example.com/artwork.jpg"))

        let didSave = store.toggleDiscoveredTrackSaved(
            title: "Sweet Song",
            artist: "The Tests",
            station: station,
            artworkURL: artworkURL,
            savedLimit: 10,
            discoveryLimit: 25
        )

        XCTAssertTrue(didSave)
        XCTAssertEqual(store.discoveries.first?.resolvedArtworkURL, artworkURL)
    }

    func testRemoteTrackFeedbackUsesCanonicalTrackKey() async throws {
        LibraryStoreTestURLProtocol.requestHandler = { request in
            let response: String
            switch request.url?.path {
            case "/v1/tune/feedback":
                response = """
                {
                  "generatedAt": "2026-06-14T16:30:00Z",
                  "stationFeedback": [],
                  "trackFeedback": [
                    {
                      "trackKey": "teardrop::massive attack",
                      "title": "Teardrop",
                      "artist": "Massive Attack",
                      "stationID": "test-station",
                      "feedback": "not_for_me",
                      "updatedAt": "2026-06-14T16:29:00Z"
                    }
                  ]
                }
                """
            case "/v1/tune/me/summary":
                response = """
                {
                  "usage": {},
                  "limits": {},
                  "subscription": { "tier": "free", "status": "inactive", "isPro": false }
                }
                """
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                response = "{}"
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(response.utf8)
            )
        }
        defer { LibraryStoreTestURLProtocol.requestHandler = nil }

        let client = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession()
        )
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let station = Station(
            id: "test-station",
            name: "Test Radio",
            country: "Spain",
            language: "Spanish",
            tags: "trip hop",
            streamURL: "https://example.com/stream.mp3"
        )
        XCTAssertTrue(store.toggleDiscoveredTrackSaved(
            title: "Teardrop",
            artist: "Massive Attack",
            station: station,
            artworkURL: nil,
            savedLimit: 10,
            discoveryLimit: 25
        ))

        store.setBackendService(TuneAVAppDataService(apiClient: client), userID: "user-1")
        await store.refreshCloudFeedbackIfNeeded(force: true)

        let discovery = try XCTUnwrap(store.discoveries.first)
        XCTAssertEqual(store.feedback(for: discovery), .notForMe)
    }

    func testCloudLibraryRefreshAppliesRemoteSavedDiscoveries() async throws {
        LibraryStoreTestURLProtocol.requestHandler = { request in
            let resource = request.url?.path.split(separator: "/").last.map(String.init) ?? "unknown"
            let entries: String
            switch request.url?.path {
            case "/v1/apps/tuneav/data/favorites":
                entries = "[]"
            case "/v1/apps/tuneav/data/savedDiscoveries":
                entries = """
                [
                  {
                    "discoveryID": "bad-manners-lorraine-radio-dance-o-matic",
                    "trackKey": "lorraine::bad manners",
                    "title": "Lorraine",
                    "artist": "Bad Manners",
                    "stationID": "radio-dance-o-matic",
                    "stationName": "Radio Dance O Matic",
                    "artworkURL": null,
                    "stationArtworkURL": null,
                    "playedAt": "2026-06-14T18:50:00Z",
                    "markedInterestedAt": "2026-06-14T18:51:00Z",
                    "hiddenAt": null,
                    "deletedAt": null,
                    "updatedAt": "2026-06-14T18:51:00Z"
                  },
                  {
                    "discoveryID": "the-interrupters-take-back-the-power-radio-dance-o-matic",
                    "trackKey": "take back the power::the interrupters",
                    "title": "Take Back The Power",
                    "artist": "The Interrupters",
                    "stationID": "radio-dance-o-matic",
                    "stationName": "Radio Dance O Matic",
                    "artworkURL": null,
                    "stationArtworkURL": null,
                    "playedAt": "2026-06-14T18:52:00Z",
                    "markedInterestedAt": "2026-06-14T18:53:00Z",
                    "hiddenAt": null,
                    "deletedAt": null,
                    "updatedAt": "2026-06-14T18:53:00Z"
                  },
                  {
                    "discoveryID": "teddy-swims-lose-control-cadena-100",
                    "trackKey": "lose control::teddy swims",
                    "title": "Lose Control",
                    "artist": "Teddy Swims",
                    "stationID": "cadena-100",
                    "stationName": "Cadena 100",
                    "artworkURL": null,
                    "stationArtworkURL": null,
                    "playedAt": "2026-06-14T18:54:00Z",
                    "markedInterestedAt": "2026-06-14T18:55:00Z",
                    "hiddenAt": null,
                    "deletedAt": null,
                    "updatedAt": "2026-06-14T18:55:00Z"
                  }
                ]
                """
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                entries = "[]"
            }
            let response = """
            {
              "data": {
                "appId": "tuneav",
                "resource": "\(resource)",
                "deviceId": "test-device",
                "sentAt": "2026-06-14T18:56:00Z",
                "entries": \(entries)
              },
              "updatedAt": "2026-06-14T18:56:00Z",
              "revision": 42,
              "etag": "\\"revision-42\\""
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json", "ETag": "\"revision-42\""]
                )!,
                Data(response.utf8)
            )
        }
        defer { LibraryStoreTestURLProtocol.requestHandler = nil }

        let client = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession()
        )
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)

        store.setAppDataService(TuneAVAppDataService(apiClient: client))
        await store.refreshCloudLibraryIfNeeded(force: true)

        let savedDiscoveries = AppShellMusicLibrary.savedDiscoveries(store.discoveries)
        XCTAssertEqual(store.savedDiscoveriesCount, 3)
        XCTAssertEqual(Set(savedDiscoveries.map(\.title)), ["Lorraine", "Take Back The Power", "Lose Control"])
        XCTAssertEqual(Set(savedDiscoveries.map { TuneAVDiscoveredTrackSupport.trackKey(title: $0.title, artist: $0.artist, locale: L10n.locale) }), [
            "lorraine::bad manners",
            "take back the power::the interrupters",
            "lose control::teddy swims"
        ])
    }

    func testCloudPushIncludesMarkedInterestedAtWhenSavingExistingHistoryDiscovery() async throws {
        let recorder = LibraryStoreAppDataRequestRecorder()
        LibraryStoreTestURLProtocol.requestHandler = { request in
            try recorder.response(for: request)
        }
        defer { LibraryStoreTestURLProtocol.requestHandler = nil }

        let client = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession()
        )
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let station = Station(
            id: "st_rb_960c37c6_0601_11e8_ae97_52543be04c81",
            name: "Cadena 100",
            country: "Spain",
            language: "Spanish",
            tags: "pop",
            streamURL: "https://example.com/cadena100.mp3"
        )

        store.setAppDataService(TuneAVAppDataService(apiClient: client))
        store.recordDiscoveredTrack(
            title: "Lose control",
            artist: "Teddy Swims",
            station: station,
            artworkURL: nil,
            discoveryLimit: 100
        )

        XCTAssertTrue(store.toggleDiscoveredTrackSaved(
            title: "Lose control",
            artist: "Teddy Swims",
            station: station,
            artworkURL: nil,
            savedLimit: 10,
            discoveryLimit: 100
        ))

        try await Task.sleep(for: .milliseconds(2_800))

        let pushedDiscoveries = try XCTUnwrap(recorder.lastPutEntries(for: "/v1/apps/tuneav/data/savedDiscoveries"))
        let pushedDiscovery = try XCTUnwrap(pushedDiscoveries.first { entry in
            entry["discoveryID"] as? String == "teddy-swims-lose-control-st-rb-960c37c6-0601-11e8-ae97-52543be04c81"
        })
        XCTAssertNotNil(pushedDiscovery["markedInterestedAt"])
        XCTAssertEqual(pushedDiscovery["title"] as? String, "Lose control")
        XCTAssertEqual(pushedDiscovery["artist"] as? String, "Teddy Swims")
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

    private func enrichedStation(metadataUpdatedAt: String? = nil, artworkVersion: String = "v1") -> Station {
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
            metadataUpdatedAt: metadataUpdatedAt,
            artwork: StationArtwork(status: "generated", url: "https://example.com/artwork.png", version: artworkVersion),
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
        endedReason: String = "paused",
        startedAt: Date = Date(timeIntervalSince1970: 10),
        endedAt: Date = Date(timeIntervalSince1970: 30)
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
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(startedAt).rounded())),
            source: "home",
            endedReason: endedReason,
            trackDetectedCount: 1
        )
    }
}

private func libraryStoreTestURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LibraryStoreTestURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class LibraryStoreAppDataRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var putEntriesByPath: [String: [[String: Any]]] = [:]

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if method == "PUT", let body = request.httpBody ?? request.httpBodyStreamData() {
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let entries = payload?["entries"] as? [[String: Any]] ?? []
            lock.lock()
            putEntriesByPath[path] = entries
            lock.unlock()
        }

        let resource = path.split(separator: "/").last.map(String.init) ?? "unknown"
        let response = """
        {
          "data": {
            "appId": "tuneav",
            "resource": "\(resource)",
            "deviceId": "test-device",
            "sentAt": "2026-06-07T17:52:00Z",
            "entries": []
          },
          "updatedAt": "2026-06-07T17:52:00Z",
          "revision": 1,
          "etag": "\\"revision-1\\""
        }
        """

        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "ETag": "\"revision-1\""]
            )!,
            Data(response.utf8)
        )
    }

    func lastPutEntries(for path: String) -> [[String: Any]]? {
        lock.lock()
        defer { lock.unlock() }
        return putEntriesByPath[path]
    }
}

private final class LibraryStoreTestURLProtocol: URLProtocol {
    nonisolated(unsafe)
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func httpBodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
