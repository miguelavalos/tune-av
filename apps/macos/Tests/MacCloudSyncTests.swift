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

    func testLocalChangesDebounceCloudSyncOnlyWhenSignedIn() {
        let trigger = MacCloudSyncTrigger()

        XCTAssertEqual(
            trigger.localLibraryChanged(accountAvailable: true, hasUser: true, hasProAccess: true),
            .schedule(MacCloudSyncTrigger.localChangeDelay)
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
                    updatedAt: "2026-05-23T11:01:00Z"
                )
            ]
        )
    }

    private func fixedDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
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
        playedAt: String,
        markedInterestedAt: String? = nil,
        hiddenAt: String? = nil,
        deletedAt: String? = nil,
        updatedAt: String? = nil
    ) -> DiscoveredTrackRecord {
        DiscoveredTrackRecord(
            discoveryID: id,
            title: "Song \(id)",
            artist: "Artist \(id)",
            stationID: "station-\(id)",
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
