import XCTest
@testable import TuneAV

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testPendingLibraryOutboxKeepsLatestOperationPerUserResourceAndIdentity() {
        let firstSave = pendingFavoriteOperation(
            action: .upsert,
            userID: "user-1",
            stationID: "station-1",
            updatedAt: "2026-07-10T10:00:00Z"
        )
        let deletion = pendingFavoriteOperation(
            action: .delete,
            userID: "user-1",
            stationID: "station-1",
            updatedAt: "2026-07-10T10:01:00Z"
        )
        let latestSave = pendingFavoriteOperation(
            action: .upsert,
            userID: "user-1",
            stationID: "station-1",
            updatedAt: "2026-07-10T10:02:00Z"
        )
        let otherUser = pendingFavoriteOperation(
            action: .delete,
            userID: "user-2",
            stationID: "station-1",
            updatedAt: "2026-07-10T10:03:00Z"
        )
        let otherResource = pendingDiscoveryOperation(
            action: .upsert,
            userID: "user-1",
            discoveryID: "station-1",
            updatedAt: "2026-07-10T10:04:00Z"
        )

        var operations = TuneAVPendingLibraryOutbox.upserting(firstSave, into: [:])
        operations = TuneAVPendingLibraryOutbox.upserting(deletion, into: operations)
        operations = TuneAVPendingLibraryOutbox.upserting(latestSave, into: operations)
        operations = TuneAVPendingLibraryOutbox.upserting(otherUser, into: operations)
        operations = TuneAVPendingLibraryOutbox.upserting(otherResource, into: operations)

        XCTAssertEqual(operations.count, 3)
        XCTAssertEqual(operations[latestSave.storageKey], latestSave)
        XCTAssertEqual(operations[otherUser.storageKey], otherUser)
        XCTAssertEqual(operations[otherResource.storageKey], otherResource)
    }

    func testPendingLibraryOperationPersistenceRestoresAndClearsOperations() throws {
        let storageKey = "test.pendingLibraryOperations.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: storageKey))
        defer { userDefaults.removePersistentDomain(forName: storageKey) }
        let operation = pendingFavoriteOperation(
            action: .delete,
            userID: "user-1",
            stationID: "station-1"
        )

        LibraryStorePendingLibraryOperationPersistence.save(
            [operation.storageKey: operation],
            storageKey: storageKey,
            userDefaults: userDefaults
        )

        XCTAssertEqual(
            LibraryStorePendingLibraryOperationPersistence.load(
                storageKey: storageKey,
                userDefaults: userDefaults
            ),
            [operation.storageKey: operation]
        )

        LibraryStorePendingLibraryOperationPersistence.save(
            [:],
            storageKey: storageKey,
            userDefaults: userDefaults
        )
        XCTAssertNil(userDefaults.data(forKey: storageKey))
    }

    func testPendingLibraryOperationSurvivesFailureAndRelaunchWithoutCrossingAccounts() async throws {
        let suiteName = "test.pendingLibraryOperations.relaunch.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            LibraryStoreTestURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let currentUserOperation = pendingFavoriteOperation(
            action: .upsert,
            userID: "user-1",
            stationID: "station-user-1"
        )
        let otherUserOperation = pendingFavoriteOperation(
            action: .upsert,
            userID: "user-2",
            stationID: "station-user-2"
        )
        LibraryStorePendingLibraryOperationPersistence.save(
            [
                currentUserOperation.storageKey: currentUserOperation,
                otherUserOperation.storageKey: otherUserOperation,
            ],
            storageKey: LibraryStore.pendingLibraryOperationsStorageKey,
            userDefaults: userDefaults
        )

        LibraryStoreTestURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data()
            )
        }
        let failingClient = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession(),
            retryPolicy: .disabled
        )
        let firstStore = LibraryStore(
            container: PersistenceController(inMemory: true).container,
            userDefaults: userDefaults
        )
        let failingService = TuneAVAppDataService(apiClient: failingClient)
        firstStore.setBackendService(failingService, userID: "user-1")
        firstStore.setAppDataService(failingService)

        try await Task.sleep(for: .milliseconds(1_300))

        XCTAssertEqual(
            LibraryStorePendingLibraryOperationPersistence.load(
                storageKey: LibraryStore.pendingLibraryOperationsStorageKey,
                userDefaults: userDefaults
            ).count,
            2
        )
        firstStore.setAppDataService(nil)
        firstStore.setBackendService(nil)

        let recorder = LibraryStoreAppDataRequestRecorder()
        LibraryStoreTestURLProtocol.requestHandler = { request in
            try recorder.response(for: request)
        }
        let succeedingClient = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession(),
            retryPolicy: .disabled
        )
        let relaunchedStore = LibraryStore(
            container: PersistenceController(inMemory: true).container,
            userDefaults: userDefaults
        )
        let succeedingService = TuneAVAppDataService(apiClient: succeedingClient)
        relaunchedStore.setBackendService(succeedingService, userID: "user-1")
        relaunchedStore.setAppDataService(succeedingService)

        try await Task.sleep(for: .milliseconds(1_300))

        let remainingOperations = LibraryStorePendingLibraryOperationPersistence.load(
            storageKey: LibraryStore.pendingLibraryOperationsStorageKey,
            userDefaults: userDefaults
        )
        XCTAssertEqual(remainingOperations, [otherUserOperation.storageKey: otherUserOperation])
        let payload = try XCTUnwrap(
            recorder.lastPutPayload(for: "/v1/apps/tuneav/library/favorites/upsert")
        )
        let stationPayload = try XCTUnwrap(payload["station"] as? [String: Any])
        XCTAssertEqual(stationPayload["id"] as? String, "station-user-1")
    }

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
            endedReason: .streamError
        )
        let newer = listeningSessionDraft(
            id: "stable-session",
            stationID: "station-new",
            endedReason: .paused
        )

        let deduplicated = LibraryStoreListeningSessionBuffer.deduplicated([
            listeningSessionDraft(id: "first-session", stationID: "station-first"),
            older,
            newer
        ])

        XCTAssertEqual(deduplicated.map(\.id), ["first-session", "stable-session"])
        XCTAssertEqual(deduplicated.last?.stationID, "station-new")
        XCTAssertEqual(deduplicated.last?.endedReason, .paused)
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
            endedReason: "background",
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
        XCTAssertEqual(restored.first?.endedReason, .appBackgrounded)

        LibraryStoreListeningSessionPersistence.save(
            restored,
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 2,
            maxAge: 100,
            now: Date(timeIntervalSince1970: 40)
        )
        let migratedJSON = String(decoding: try XCTUnwrap(userDefaults.data(forKey: storageKey)), as: UTF8.self)
        XCTAssertTrue(migratedJSON.contains("\"endedReason\":\"app_backgrounded\""))
        XCTAssertFalse(migratedJSON.contains("\"endedReason\":\"background\""))
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

    func testPermanentListeningSessionRejectionIsDiscardedAndNotRetriedAfterRelaunch() async throws {
        let suiteName = "test.pendingListeningSessions.terminal.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            LibraryStoreTestURLProtocol.requestHandler = nil
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let storageKey = LibraryStore.pendingListeningSessionsStorageKey
        let endedAt = Date()
        LibraryStoreListeningSessionPersistence.save(
            [listeningSessionDraft(
                id: "terminal-session",
                stationID: "station-a",
                startedAt: endedAt.addingTimeInterval(-30),
                endedAt: endedAt,
                userID: "user-1"
            )],
            storageKey: storageKey,
            userDefaults: userDefaults,
            maxCount: 50,
            maxAge: 7 * 24 * 60 * 60,
            now: endedAt
        )

        let requestCounter = LibraryStoreAppDataRequestRecorder()
        LibraryStoreTestURLProtocol.requestHandler = { request in
            _ = try requestCounter.response(for: request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"error":"invalid_request"}"#.utf8)
            )
        }
        let client = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            tuneBaseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession(),
            retryPolicy: .disabled
        )
        let service = TuneAVAppDataService(apiClient: client)
        let firstStore = LibraryStore(
            container: PersistenceController(inMemory: true).container,
            userDefaults: userDefaults
        )
        firstStore.setBackendService(service, userID: "user-1")
        firstStore.flushPendingListeningSessions()

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(
            requestCounter.requestCount(method: "POST", path: "/v1/tune/analytics/listening-sessions"),
            1
        )
        XCTAssertNil(userDefaults.data(forKey: storageKey))

        let relaunchedStore = LibraryStore(
            container: PersistenceController(inMemory: true).container,
            userDefaults: userDefaults
        )
        relaunchedStore.setBackendService(service, userID: "user-1")
        relaunchedStore.flushPendingListeningSessions()

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(
            requestCounter.requestCount(method: "POST", path: "/v1/tune/analytics/listening-sessions"),
            1
        )
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
            tuneBaseURLProvider: { URL(string: "https://api.test") },
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

        store.configureLocalFeedbackRetention(for: .signedInPro)
        store.setBackendService(TuneAVAppDataService(apiClient: client), userID: "user-1")
        await store.refreshCloudFeedbackIfNeeded(force: true)

        let discovery = try XCTUnwrap(store.discoveries.first)
        XCTAssertEqual(store.feedback(for: discovery), .notForMe)
    }

    func testBootstrapRealtimeProjectionDoesNotRepeatCoveredCloudReads() async throws {
        let recorder = LibraryStoreAppDataRequestRecorder()
        LibraryStoreTestURLProtocol.requestHandler = { request in
            try recorder.response(for: request)
        }
        defer { LibraryStoreTestURLProtocol.requestHandler = nil }

        let client = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            tuneBaseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession()
        )
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let service = TuneAVAppDataService(apiClient: client)
        store.configureLocalFeedbackRetention(for: .signedInPro)
        store.setBackendService(service, userID: "user-1")
        store.setAppDataService(service)

        await store.refreshCloudLibraryIfNeeded(force: true)
        await store.refreshCloudFeedbackIfNeeded(force: true, refreshSummary: false)
        await store.refreshUserSummary(force: true)
        await store.handleProRealtimeInvalidation(
            TuneAVProLibraryProjection(
                ownerUserId: "user-1",
                projectionVersion: 4,
                libraryGeneration: 5,
                feedbackGeneration: 3,
                resource: "favorites",
                sourceUpdatedAt: nil,
                updatedAt: 1
            )
        )

        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/favorites"), 1)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/savedDiscoveries"), 1)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/tune/feedback"), 1)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/tune/me/summary"), 1)
    }

    func testRealtimeFavoritesInvalidationReadsOnlyFavorites() async {
        let recorder = LibraryStoreAppDataRequestRecorder()
        let store = makeRealtimeLibraryStore(recorder: recorder)
        defer { LibraryStoreTestURLProtocol.requestHandler = nil }

        await bootstrapRealtimeLibrary(store)
        await store.handleProRealtimeInvalidation(realtimeLibraryProjection(
            libraryGeneration: 6,
            resource: "favorites",
            updatedAt: 2
        ))

        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/favorites"), 2)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/savedDiscoveries"), 1)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/tune/feedback"), 1)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/tune/me/summary"), 0)
    }

    func testRealtimeSavedDiscoveriesInvalidationReadsOnlySavedDiscoveries() async {
        let recorder = LibraryStoreAppDataRequestRecorder()
        let store = makeRealtimeLibraryStore(recorder: recorder)
        defer { LibraryStoreTestURLProtocol.requestHandler = nil }

        await bootstrapRealtimeLibrary(store)
        await store.handleProRealtimeInvalidation(realtimeLibraryProjection(
            libraryGeneration: 6,
            resource: "savedDiscoveries",
            updatedAt: 2
        ))

        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/favorites"), 1)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/savedDiscoveries"), 2)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/tune/feedback"), 1)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/tune/me/summary"), 0)
    }

    func testRealtimeUnknownLibraryResourceUsesConservativeFullRefresh() async {
        let recorder = LibraryStoreAppDataRequestRecorder()
        let store = makeRealtimeLibraryStore(recorder: recorder)
        defer { LibraryStoreTestURLProtocol.requestHandler = nil }

        await bootstrapRealtimeLibrary(store)
        await store.handleProRealtimeInvalidation(realtimeLibraryProjection(
            libraryGeneration: 6,
            resource: "futureResource",
            updatedAt: 2
        ))

        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/favorites"), 2)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/savedDiscoveries"), 2)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/apps/tuneav/data/futureResource"), 0)
        XCTAssertEqual(recorder.requestCount(method: "GET", path: "/v1/tune/feedback"), 1)
    }

    func testRemoteTrackFeedbackCreatesTunedDiscoveryWithoutLocalHistory() async throws {
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
                      "trackKey": "welcome to the dcc::nothing but thieves",
                      "title": "Welcome to the DCC",
                      "artist": "Nothing But Thieves",
                      "stationID": "test-station",
                      "feedback": "liked",
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
                  "subscription": { "tier": "pro", "status": "active", "isPro": true }
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
            tuneBaseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession()
        )
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        store.configureLocalFeedbackRetention(for: .signedInPro)
        store.setBackendService(TuneAVAppDataService(apiClient: client), userID: "user-1")

        await store.refreshCloudFeedbackIfNeeded(force: true)

        XCTAssertTrue(store.discoveries.isEmpty)
        XCTAssertEqual(store.tunedDiscoveries.map(\.title), ["Welcome to the DCC"])
        XCTAssertEqual(store.feedback(for: try XCTUnwrap(store.tunedDiscoveries.first)), .liked)
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

    func testSavedDiscoveryItemOperationIncludesMarkedInterestedAtWithoutSnapshotPush() async throws {
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

        let service = TuneAVAppDataService(apiClient: client)
        store.setBackendService(service, userID: "user-1")
        store.setAppDataService(service)
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

        let operationPayload = try XCTUnwrap(recorder.lastPutPayload(for: "/v1/apps/tuneav/library/savedDiscoveries/upsert"))
        XCTAssertEqual(operationPayload["title"] as? String, "Lose control")
        XCTAssertEqual(operationPayload["artist"] as? String, "Teddy Swims")
        XCTAssertNotNil(operationPayload["markedInterestedAt"])
        XCTAssertEqual(
            recorder.putRequestCount(for: "/v1/apps/tuneav/library/savedDiscoveries/upsert"),
            1
        )
        XCTAssertTrue(recorder.putPaths().filter { $0.contains("/v1/apps/tuneav/data/") }.isEmpty)
    }

    func testToggleFavoriteSendsOnlyPerItemCloudOperation() async throws {
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
            id: "st_radio_bob_rock",
            name: "RADIO BOB! Rock",
            country: "Germany",
            language: "German",
            tags: "rock",
            streamURL: "https://example.com/radio-bob-rock.mp3"
        )

        let service = TuneAVAppDataService(apiClient: client)
        store.setBackendService(service, userID: "user-1")
        store.setAppDataService(service)
        store.toggleFavorite(for: station)

        try await Task.sleep(for: .milliseconds(2_400))

        let operationPayload = try XCTUnwrap(recorder.lastPutPayload(for: "/v1/apps/tuneav/library/favorites/upsert"))
        let stationPayload = try XCTUnwrap(operationPayload["station"] as? [String: Any])
        XCTAssertEqual(stationPayload["id"] as? String, "st_radio_bob_rock")
        XCTAssertEqual(stationPayload["name"] as? String, "RADIO BOB! Rock")
        XCTAssertNotNil(operationPayload["createdAt"])
        XCTAssertEqual(recorder.putPaths(), ["/v1/apps/tuneav/library/favorites/upsert"])
        XCTAssertEqual(
            recorder.putRequestCount(for: "/v1/apps/tuneav/library/favorites/upsert"),
            1
        )
    }

    func testClearFavoritesDefaultsToLocalOnlyWithoutCloudPush() async throws {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let station = Station(
            id: "st_local_only",
            name: "Local Only Radio",
            country: "Spain",
            language: "Spanish",
            tags: "rock",
            streamURL: "https://example.com/local-only.mp3"
        )
        store.toggleFavorite(for: station)

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
        store.setAppDataService(TuneAVAppDataService(apiClient: client))

        store.clearFavorites()
        try await Task.sleep(for: .milliseconds(2_400))

        XCTAssertEqual(recorder.putPaths(), [])
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

    private func pendingFavoriteOperation(
        action: TuneAVPendingLibraryOperation.Action,
        userID: String,
        stationID: String,
        updatedAt: String = "2026-07-10T10:00:00Z"
    ) -> TuneAVPendingLibraryOperation {
        let record = FavoriteStationRecord(
            station: Station(
                id: stationID,
                name: "Station \(stationID)",
                country: "Spain",
                language: "Spanish",
                tags: "pop",
                streamURL: "https://example.com/\(stationID).mp3"
            ).appDataRecord,
            createdAt: updatedAt,
            deletedAt: action == .delete ? updatedAt : nil
        )
        return TuneAVPendingLibraryOperation(
            resource: .favorites,
            action: action,
            userID: userID,
            identityKey: TuneAVLibrarySnapshotMerger.stationIdentityKey(record.station),
            favoriteRecord: record,
            discoveryRecord: nil,
            updatedAt: updatedAt
        )
    }

    private func pendingDiscoveryOperation(
        action: TuneAVPendingLibraryOperation.Action,
        userID: String,
        discoveryID: String,
        updatedAt: String = "2026-07-10T10:00:00Z"
    ) -> TuneAVPendingLibraryOperation {
        let record = DiscoveredTrackRecord(
            discoveryID: discoveryID,
            trackKey: "song::artist",
            title: "Song",
            artist: "Artist",
            stationID: "station-1",
            stationName: "Station 1",
            artworkURL: nil,
            stationArtworkURL: nil,
            playedAt: updatedAt,
            markedInterestedAt: action == .upsert ? updatedAt : nil,
            deletedAt: action == .delete ? updatedAt : nil,
            updatedAt: updatedAt
        )
        return TuneAVPendingLibraryOperation(
            resource: .savedDiscoveries,
            action: action,
            userID: userID,
            identityKey: TuneAVLibrarySnapshotMerger.discoveryIdentityKey(record),
            favoriteRecord: nil,
            discoveryRecord: record,
            updatedAt: updatedAt
        )
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

    private func makeRealtimeLibraryStore(
        recorder: LibraryStoreAppDataRequestRecorder
    ) -> LibraryStore {
        LibraryStoreTestURLProtocol.requestHandler = { request in
            try recorder.response(for: request)
        }
        let client = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            tuneBaseURLProvider: { URL(string: "https://api.test") },
            urlSession: libraryStoreTestURLSession()
        )
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        let service = TuneAVAppDataService(apiClient: client)
        store.configureLocalFeedbackRetention(for: .signedInPro)
        store.setBackendService(service, userID: "user-1")
        store.setAppDataService(service)
        return store
    }

    private func bootstrapRealtimeLibrary(_ store: LibraryStore) async {
        await store.refreshCloudLibraryIfNeeded(force: true)
        await store.refreshCloudFeedbackIfNeeded(force: true, refreshSummary: false)
        await store.handleProRealtimeInvalidation(realtimeLibraryProjection(
            libraryGeneration: 5,
            resource: "favorites",
            updatedAt: 1
        ))
    }

    private func realtimeLibraryProjection(
        libraryGeneration: Int,
        resource: String,
        updatedAt: Double
    ) -> TuneAVProLibraryProjection {
        TuneAVProLibraryProjection(
            ownerUserId: "user-1",
            projectionVersion: 4,
            libraryGeneration: libraryGeneration,
            feedbackGeneration: 3,
            resource: resource,
            sourceUpdatedAt: nil,
            updatedAt: updatedAt
        )
    }

    private func listeningSessionDraft(
        id: String = UUID().uuidString,
        stationID: String,
        endedReason: TuneAVListeningEndedReason = .paused,
        startedAt: Date = Date(timeIntervalSince1970: 10),
        endedAt: Date = Date(timeIntervalSince1970: 30),
        userID: String? = nil
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
            trackDetectedCount: 1,
            userID: userID
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
    private var putPayloadsByPath: [String: [String: Any]] = [:]
    private var putRequestCountsByPath: [String: Int] = [:]
    private var requestCountsByMethodAndPath: [String: Int] = [:]

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        lock.lock()
        requestCountsByMethodAndPath["\(method) \(path)", default: 0] += 1
        lock.unlock()

        if method == "PUT", let body = request.httpBody ?? request.httpBodyStreamData() {
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let entries = payload?["entries"] as? [[String: Any]] ?? []
            lock.lock()
            putPayloadsByPath[path] = payload
            putEntriesByPath[path] = entries
            putRequestCountsByPath[path, default: 0] += 1
            lock.unlock()
        }

        let response: String
        switch path {
        case "/v1/tune/feedback":
            response = """
            {
              "generatedAt": "2026-06-07T17:53:00Z",
              "stationFeedback": [],
              "trackFeedback": []
            }
            """
        case "/v1/tune/me/summary":
            response = """
            {
              "usage": {},
              "limits": {},
              "subscription": { "tier": "pro", "status": "active", "isPro": true }
            }
            """
        default:
            let resource = path.split(separator: "/").last.map(String.init) ?? "unknown"
            response = """
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
        }

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

    func lastPutPayload(for path: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return putPayloadsByPath[path]
    }

    func putPaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return putPayloadsByPath.keys.sorted()
    }

    func putRequestCount(for path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return putRequestCountsByPath[path, default: 0]
    }

    func requestCount(method: String, path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCountsByMethodAndPath["\(method) \(path)", default: 0]
    }
}

private final class LibraryStoreTestURLProtocol: URLProtocol {
    private static let requestHandlerLock = NSLock()

    nonisolated(unsafe)
    private static var storedRequestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    nonisolated(unsafe)
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            requestHandlerLock.lock()
            defer { requestHandlerLock.unlock() }
            return storedRequestHandler
        }
        set {
            requestHandlerLock.lock()
            storedRequestHandler = newValue
            requestHandlerLock.unlock()
        }
    }

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
