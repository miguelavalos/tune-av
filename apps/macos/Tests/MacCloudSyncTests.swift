import XCTest
@testable import TuneAVMac

final class MacCloudSyncTests: XCTestCase {
    func testStartupSchedulesOneInitialSyncForSignedInUsers() {
        var trigger = MacCloudSyncTrigger()

        XCTAssertEqual(
            trigger.startupCompleted(accountAvailable: true, hasUser: true, hasProAccess: true),
            .schedule(MacCloudSyncTrigger.startupDelay)
        )
        XCTAssertEqual(
            trigger.startupCompleted(accountAvailable: true, hasUser: true, hasProAccess: true),
            .none
        )
    }

    func testStartupDoesNotSyncWithoutSignedInUser() {
        var trigger = MacCloudSyncTrigger()

        XCTAssertEqual(
            trigger.startupCompleted(accountAvailable: true, hasUser: false, hasProAccess: false),
            .none
        )
    }

    func testStartupDoesNotSyncForSignedInFreeUsers() {
        var trigger = MacCloudSyncTrigger()

        XCTAssertEqual(
            trigger.startupCompleted(accountAvailable: true, hasUser: true, hasProAccess: false),
            .none
        )
    }

    func testSignInSchedulesInitialSync() {
        let trigger = MacCloudSyncTrigger()

        XCTAssertEqual(
            trigger.signInCompleted(accountAvailable: true, hasUser: true, hasProAccess: true),
            .schedule(MacCloudSyncTrigger.startupDelay)
        )
    }

    func testLocalChangesDoNotAutomaticallyScheduleCloudSync() {
        let trigger = MacCloudSyncTrigger()

        XCTAssertEqual(
            trigger.localLibraryChanged(accountAvailable: true, hasUser: true, hasProAccess: true),
            .none
        )
        XCTAssertEqual(
            trigger.localLibraryChanged(accountAvailable: true, hasUser: false, hasProAccess: false),
            .none
        )
        XCTAssertEqual(
            trigger.localLibraryChanged(accountAvailable: true, hasUser: true, hasProAccess: false),
            .none
        )
    }

    func testApplyingCloudSnapshotDoesNotScheduleAnotherSync() {
        var trigger = MacCloudSyncTrigger()

        trigger.setApplyingCloudSnapshot(true)

        XCTAssertEqual(
            trigger.localLibraryChanged(accountAvailable: true, hasUser: true, hasProAccess: true),
            .none
        )
    }

    func testSignOutCancelsPendingSync() {
        let trigger = MacCloudSyncTrigger()

        XCTAssertEqual(trigger.signOutStarted(), .cancel)
    }

    func testMacDiagnosticsDoesNotCaptureExpectedConfigurationErrors() {
        XCTAssertFalse(TuneAVMacDiagnostics.shouldCapture(TuneAVAppDataClientError.missingToken))
        XCTAssertFalse(TuneAVMacDiagnostics.shouldCapture(TuneAVAppDataClientError.missingBaseURL))
        XCTAssertFalse(TuneAVMacDiagnostics.shouldCapture(TuneAVAccessClientError.missingToken))
        XCTAssertFalse(TuneAVMacDiagnostics.shouldCapture(TuneAVAccessClientError.missingBaseURL))
        XCTAssertTrue(TuneAVMacDiagnostics.shouldCapture(TuneAVAppDataClientError.requestFailed(statusCode: 500)))
        XCTAssertTrue(TuneAVMacDiagnostics.shouldCapture(TuneAVAccessClientError.requestFailed(statusCode: 500)))
        XCTAssertTrue(TuneAVMacDiagnostics.shouldCapture(TuneAVAccessClientError.avTunesysAccessMissing))
        XCTAssertTrue(TuneAVMacDiagnostics.shouldCapture(URLError(.timedOut)))
    }

    func testMacSyncMergeKeepsLocalAndRemoteLibraryItems() {
        let local = librarySnapshot(
            favorites: [favoriteRecord(id: "local-favorite")],
            savedDiscoveries: [discoveryRecord(id: "local-track", playedAt: "2026-05-23T09:00:00Z", markedInterestedAt: "2026-05-23T09:01:00Z")],
            updatedAt: "2026-05-23T09:00:00Z"
        )
        let remote = librarySnapshot(
            favorites: [favoriteRecord(id: "remote-favorite")],
            savedDiscoveries: [discoveryRecord(id: "remote-track", playedAt: "2026-05-23T10:00:00Z", markedInterestedAt: "2026-05-23T10:01:00Z")],
            updatedAt: "2026-05-23T10:00:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(Set(merged.favorites.map(\.station.id)), ["local-favorite", "remote-favorite"])
        XCTAssertEqual(Set(merged.savedDiscoveries.map(\.discoveryID)), ["local-track", "remote-track"])
    }

    func testMacSyncPlannerPushesLocalWhenRemoteIsEmpty() {
        let local = librarySnapshot(
            favorites: [favoriteRecord(id: "local-favorite")],
            updatedAt: "2026-05-23T09:00:00Z"
        )
        let remote = TuneAVLibraryDocument(
            snapshot: nil,
            updatedAt: fixedDate("2026-05-23T08:00:00Z"),
            revision: 1,
            etag: nil
        )

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: local,
                localUpdatedAt: fixedDate("2026-05-23T09:00:00Z"),
                remoteDocument: remote
            ),
            .pushLocal
        )
    }

    func testMacSyncPlannerPullsRemoteAfterLocalDeviceReset() {
        let local = librarySnapshot(updatedAt: "2026-05-23T12:00:00Z")
        let remoteSnapshot = librarySnapshot(
            favorites: [favoriteRecord(id: "remote-favorite")],
            updatedAt: "2026-05-23T10:00:00Z"
        )
        let remote = TuneAVLibraryDocument(
            snapshot: remoteSnapshot,
            updatedAt: fixedDate("2026-05-23T10:00:00Z"),
            revision: 1,
            etag: nil
        )

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: local,
                localUpdatedAt: fixedDate("2026-05-23T12:00:00Z"),
                remoteDocument: remote
            ),
            .pullRemote(remoteSnapshot)
        )
    }

    func testMacSyncPlannerPushesExplicitLocalDeletionTombstone() {
        let local = librarySnapshot(
            favorites: [
                favoriteRecord(
                    id: "remote-favorite",
                    createdAt: nil,
                    deletedAt: "2026-05-23T12:00:00Z"
                )
            ],
            updatedAt: "2026-05-23T12:00:00Z"
        )
        let remoteSnapshot = librarySnapshot(
            favorites: [favoriteRecord(id: "remote-favorite")],
            updatedAt: "2026-05-23T10:00:00Z"
        )
        let remote = TuneAVLibraryDocument(
            snapshot: remoteSnapshot,
            updatedAt: fixedDate("2026-05-23T10:00:00Z"),
            revision: 1,
            etag: nil
        )

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: local,
                localUpdatedAt: fixedDate("2026-05-23T12:00:00Z"),
                remoteDocument: remote
            ),
            .pushLocal
        )
    }

    func testMacSyncMergeKeepsFavoriteDeletionTombstoneNewest() {
        let local = librarySnapshot(
            favorites: [
                FavoriteStationRecord(
                    station: stationRecord(id: "favorite"),
                    deletedAt: "2026-05-23T11:00:00Z"
                )
            ],
            updatedAt: "2026-05-23T11:00:00Z"
        )
        let remote = librarySnapshot(
            favorites: [favoriteRecord(id: "favorite", createdAt: "2026-05-23T10:00:00Z")],
            updatedAt: "2026-05-23T10:00:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.favorites.count, 1)
        XCTAssertEqual(merged.favorites.first?.station.id, "favorite")
        XCTAssertEqual(merged.favorites.first?.deletedAt, "2026-05-23T11:00:00Z")
    }

    func testMacSyncMergeKeepsSavedDiscoveryUnsaveWhenUpdatedAtIsNewest() {
        let local = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "track",
                    playedAt: "2026-05-23T10:00:00Z",
                    updatedAt: "2026-05-23T11:00:00Z"
                )
            ],
            updatedAt: "2026-05-23T11:00:00Z"
        )
        let remote = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "track",
                    playedAt: "2026-05-23T10:00:00Z",
                    markedInterestedAt: "2026-05-23T10:30:00Z",
                    updatedAt: "2026-05-23T10:30:00Z"
                )
            ],
            updatedAt: "2026-05-23T10:30:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.savedDiscoveries.count, 1)
        XCTAssertNil(merged.savedDiscoveries.first?.markedInterestedAt)
        XCTAssertEqual(merged.savedDiscoveries.first?.updatedAt, "2026-05-23T11:00:00Z")
    }

    func testMacSyncMergeUsesCanonicalTrackKeyForSavedDiscoveries() {
        let local = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "massive-attack-teardrop-station-a",
                    title: "Teardrop",
                    artist: "Massive Attack",
                    stationID: "station-a",
                    playedAt: "2026-05-23T10:00:00Z",
                    markedInterestedAt: "2026-05-23T10:01:00Z",
                    updatedAt: "2026-05-23T10:01:00Z"
                )
            ],
            updatedAt: "2026-05-23T10:01:00Z"
        )
        let remote = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "massive-attack-teardrop-station-b",
                    title: "Teardrop",
                    artist: "Massive Attack",
                    stationID: "station-b",
                    playedAt: "2026-05-23T10:05:00Z",
                    markedInterestedAt: "2026-05-23T10:06:00Z",
                    updatedAt: "2026-05-23T10:06:00Z"
                )
            ],
            updatedAt: "2026-05-23T10:06:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.savedDiscoveries.count, 1)
        XCTAssertEqual(merged.savedDiscoveries.first?.discoveryID, "massive-attack-teardrop-station-b")
        XCTAssertEqual(merged.savedDiscoveries.first?.trackKey, "teardrop::massive attack")
    }

    func testMacLibraryStoragePersistsTombstones() {
        let suiteName = "MacCloudSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TuneAVMacLibraryStorage(defaults: defaults)
        let tombstone = TuneAVLibraryTombstone(
            resource: "favorites",
            identityKey: "id:favorite",
            payloadJSON: "{}",
            deletedAt: fixedDate("2026-05-23T11:00:00Z")
        )

        storage.saveTombstones([tombstone])

        XCTAssertEqual(storage.loadTombstones(), [tombstone])
    }

    func testMacLibraryStoragePersistsFavoriteRecordsWithPerItemCreatedAt() {
        let suiteName = "MacCloudSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TuneAVMacLibraryStorage(defaults: defaults)
        let favorite = favoriteRecord(id: "favorite", createdAt: "2026-05-23T10:00:00Z")

        storage.saveFavoriteRecords([favorite])

        XCTAssertEqual(storage.loadFavoriteRecords(), [favorite])
        XCTAssertEqual(storage.loadStations(forKey: TuneAVMacLibraryStorage.favoritesKey).map(\.id), ["favorite"])
    }

    @MainActor
    func testMacClearFavoritesDefaultsToLocalOnly() {
        withIsolatedStandardLibraryStorage { storage in
            storage.saveFavoriteRecords([favoriteRecord(id: "favorite")])
            storage.saveTombstones([])

            let model = TuneAVMacModel(
                subscriptionPurchasing: MacUITestTuneAVSubscriptionPurchasing(),
                subscriptionReconciliationRetryDelaysNanoseconds: [],
                sleepNanoseconds: { _ in }
            )

            XCTAssertEqual(model.favoriteStations.map(\.id), ["favorite"])

            model.clearFavorites()

            XCTAssertTrue(model.favoriteStations.isEmpty)
            XCTAssertTrue(storage.loadFavoriteRecords().isEmpty)
            XCTAssertTrue(storage.loadTombstones().isEmpty)
        }
    }

    @MainActor
    func testMacClearDiscoveredTracksDefaultsToLocalOnly() {
        withIsolatedStandardLibraryStorage { storage in
            let discovery = MacDiscoveredTrack(
                title: "Song",
                artist: "Artist",
                station: Station.samples[0],
                playedAt: fixedDate("2026-05-23T10:00:00Z"),
                markedInterestedAt: fixedDate("2026-05-23T10:01:00Z"),
                updatedAt: fixedDate("2026-05-23T10:01:00Z")
            )
            storage.saveDiscoveries([discovery])
            storage.saveTombstones([])

            let model = TuneAVMacModel(
                subscriptionPurchasing: MacUITestTuneAVSubscriptionPurchasing(),
                subscriptionReconciliationRetryDelaysNanoseconds: [],
                sleepNanoseconds: { _ in }
            )

            XCTAssertEqual(model.savedDiscoveredTracks.map(\.discoveryID), [discovery.discoveryID])

            model.clearDiscoveredTracks()

            XCTAssertTrue(model.discoveredTracks.isEmpty)
            XCTAssertTrue(storage.loadDiscoveries().isEmpty)
            XCTAssertTrue(storage.loadTombstones().isEmpty)
        }
    }

    func testMacLibraryStoragePersistsTrackFeedbackRecords() {
        let suiteName = "MacCloudSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TuneAVMacLibraryStorage(defaults: defaults)
        let feedback = [
            "song::artist": TuneAVLocalFeedbackRecord(
                feedback: .liked,
                updatedAt: "2026-05-23T11:00:00Z"
            )
        ]

        storage.saveTrackFeedbackRecords(feedback)

        XCTAssertEqual(storage.loadTrackFeedbackRecords(), feedback)
    }

    func testRealtimeFeedbackProjectionMapsStationAndTrackFeedback() {
        let stationFeedback = TuneAVRealtimeFeedbackProjection.stationFeedback(
            from: [
                TuneAVStationFeedbackRecord(
                    stationID: "station",
                    feedback: .notForMe,
                    updatedAt: "2026-05-23T11:00:00Z"
                )
            ]
        )
        let trackFeedback = TuneAVRealtimeFeedbackProjection.trackFeedbackRecords(
            from: [
                TuneAVTrackFeedbackRecord(
                    trackKey: "song::artist",
                    title: "Song",
                    artist: "Artist",
                    stationID: "station",
                    feedback: .liked,
                    updatedAt: "2026-05-23T11:01:00Z"
                )
            ]
        )

        XCTAssertEqual(stationFeedback, ["station": .notForMe])
        XCTAssertEqual(
            trackFeedback,
            [
                "song::artist": TuneAVLocalFeedbackRecord(
                    feedback: .liked,
                    updatedAt: "2026-05-23T11:01:00Z",
                    title: "Song",
                    artist: "Artist",
                    stationID: "station"
                )
            ]
        )
    }

    func testRealtimeFeedbackProjectionCanonicalizesEncodedTrackFeedbackKeys() {
        let trackFeedback = TuneAVRealtimeFeedbackProjection.trackFeedbackRecords(
            from: [
                TuneAVTrackFeedbackRecord(
                    trackKey: "take%20back%20the%20power%3A%3Athe%20interrupters",
                    title: "Take Back the Power",
                    artist: "The Interrupters",
                    stationID: "station",
                    feedback: .liked,
                    updatedAt: "2026-06-14T19:01:00Z"
                )
            ]
        )

        XCTAssertEqual(
            trackFeedback,
            [
                "take back the power::the interrupters": TuneAVLocalFeedbackRecord(
                    feedback: .liked,
                    updatedAt: "2026-06-14T19:01:00Z",
                    title: "Take Back the Power",
                    artist: "The Interrupters",
                    stationID: "station"
                )
            ]
        )
    }

    func testMacLibraryStorageMigratesEncodedTrackFeedbackKeys() {
        let suiteName = "MacCloudSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TuneAVMacLibraryStorage(defaults: defaults)
        let encodedFeedback = [
            "welcome%20to%20the%20dcc%3A%3Anothing%20but%20thieves": TuneAVLocalFeedbackRecord(
                feedback: .liked,
                updatedAt: "2026-06-14T19:02:00Z"
            )
        ]
        defaults.set(try! JSONEncoder().encode(encodedFeedback), forKey: TuneAVMacLibraryStorage.trackFeedbackKey)

        let expected = [
            "welcome to the dcc::nothing but thieves": TuneAVLocalFeedbackRecord(
                feedback: .liked,
                updatedAt: "2026-06-14T19:02:00Z"
            )
        ]

        XCTAssertEqual(storage.loadTrackFeedbackRecords(), expected)
        XCTAssertEqual(storage.loadTrackFeedbackRecords(), expected)
    }

    private func fixedDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    private func withIsolatedStandardLibraryStorage(_ body: (TuneAVMacLibraryStorage) -> Void) {
        let defaults = UserDefaults.standard
        let keys = [
            TuneAVMacLibraryStorage.favoritesKey,
            TuneAVMacLibraryStorage.favoriteRecordsKey,
            TuneAVMacLibraryStorage.recentsKey,
            TuneAVMacLibraryStorage.discoveriesKey,
            TuneAVMacLibraryStorage.stationFeedbackKey,
            TuneAVMacLibraryStorage.trackFeedbackKey,
            TuneAVMacLibraryStorage.tombstonesKey,
            TuneAVMacLibraryStorage.localLibraryUpdatedAtKey,
            TuneAVMacLibraryStorage.localLibraryMutationAtKey,
            "tuneav.mac.account.lastKnownUser"
        ]
        let originalValues = Dictionary(
            uniqueKeysWithValues: keys.compactMap { key -> (String, Any)? in
                guard let value = defaults.object(forKey: key) else { return nil }
                return (key, value)
            }
        )

        keys.forEach { defaults.removeObject(forKey: $0) }
        defer {
            keys.forEach { defaults.removeObject(forKey: $0) }
            for (key, value) in originalValues {
                defaults.set(value, forKey: key)
            }
        }

        body(TuneAVMacLibraryStorage(defaults: defaults))
    }

    private func librarySnapshot(
        favorites: [FavoriteStationRecord] = [],
        savedDiscoveries: [DiscoveredTrackRecord] = [],
        updatedAt: String
    ) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: favorites,
            savedDiscoveries: savedDiscoveries
        )
    }

    private func favoriteRecord(
        id: String,
        createdAt: String? = "2026-05-23T09:00:00Z",
        deletedAt: String? = nil
    ) -> FavoriteStationRecord {
        FavoriteStationRecord(
            station: stationRecord(id: id),
            createdAt: createdAt,
            deletedAt: deletedAt
        )
    }

    private func recentRecord(
        id: String,
        lastPlayedAt: String
    ) -> RecentStationRecord {
        RecentStationRecord(
            station: stationRecord(id: id),
            lastPlayedAt: lastPlayedAt
        )
    }

    private func discoveryRecord(
        id: String,
        title: String? = nil,
        artist: String? = nil,
        stationID: String? = nil,
        playedAt: String,
        markedInterestedAt: String? = nil,
        hiddenAt: String? = nil,
        deletedAt: String? = nil,
        updatedAt: String? = nil
    ) -> DiscoveredTrackRecord {
        let recordTitle = title ?? "Song \(id)"
        let recordArtist = artist ?? "Artist \(id)"
        return DiscoveredTrackRecord(
            discoveryID: id,
            trackKey: TuneAVDiscoveredTrackSupport.trackKey(title: recordTitle, artist: recordArtist),
            title: recordTitle,
            artist: recordArtist,
            stationID: stationID ?? "station-\(id)",
            stationName: "Station \(id)",
            artworkURL: nil,
            stationArtworkURL: nil,
            playedAt: playedAt,
            markedInterestedAt: markedInterestedAt,
            hiddenAt: hiddenAt,
            deletedAt: deletedAt,
            updatedAt: updatedAt
        )
    }

    private func stationRecord(id: String) -> StationRecord {
        StationRecord(
            id: id,
            name: "Station \(id)",
            country: "Spain",
            countryCode: "ES",
            state: nil,
            language: "Spanish",
            languageCodes: "es",
            tags: "radio",
            streamURL: "https://example.com/\(id).mp3",
            faviconURL: nil,
            bitrate: 128,
            codec: "MP3",
            homepageURL: nil,
            votes: nil,
            clickCount: nil,
            clickTrend: nil,
            isHLS: false,
            hasExtendedInfo: false,
            hasSSLError: false,
            lastCheckOKAt: nil,
            geoLatitude: nil,
            geoLongitude: nil
        )
    }
}
