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

    func testMacSyncMergeKeepsLocalAndRemoteLibraryItems() {
        let local = librarySnapshot(
            favorites: [favoriteRecord(id: "local-favorite")],
            recents: [recentRecord(id: "local-recent", lastPlayedAt: "2026-05-23T09:00:00Z")],
            updatedAt: "2026-05-23T09:00:00Z"
        )
        let remote = librarySnapshot(
            favorites: [favoriteRecord(id: "remote-favorite")],
            recents: [recentRecord(id: "remote-recent", lastPlayedAt: "2026-05-23T10:00:00Z")],
            updatedAt: "2026-05-23T10:00:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(Set(merged.favorites.map(\.station.id)), ["local-favorite", "remote-favorite"])
        XCTAssertEqual(merged.recents.map(\.station.id), ["remote-recent", "local-recent"])
    }

    func testMacSyncMergeKeepsSettingsDeviceLocal() {
        let local = librarySnapshot(
            favorites: [favoriteRecord(id: "local-favorite")],
            settings: AppSettingsRecord(
                preferredCountry: "ES",
                preferredLanguage: "ca",
                preferredTag: "rock",
                lastPlayedStationID: "local-station",
                sleepTimerMinutes: 30,
                keepScreenAwake: true,
                warnBeforeCellularPlayback: true,
                openLastStationOnLaunch: true,
                autoSkipUnstableStreams: true,
                updatedAt: "2026-05-23T09:00:00Z"
            ),
            updatedAt: "2026-05-23T09:00:00Z"
        )
        let remote = librarySnapshot(
            favorites: [favoriteRecord(id: "remote-favorite")],
            settings: AppSettingsRecord(
                preferredCountry: "US",
                preferredLanguage: "en",
                preferredTag: "news",
                lastPlayedStationID: "remote-station",
                sleepTimerMinutes: nil,
                updatedAt: "2026-05-23T10:00:00Z"
            ),
            updatedAt: "2026-05-23T10:00:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.settings, local.settings)
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

    func testMacSyncMergeKeepsDiscoveryUnsaveWhenUpdatedAtIsNewest() {
        let local = librarySnapshot(
            discoveries: [
                discoveryRecord(
                    id: "track",
                    playedAt: "2026-05-23T10:00:00Z",
                    updatedAt: "2026-05-23T11:00:00Z"
                )
            ],
            updatedAt: "2026-05-23T11:00:00Z"
        )
        let remote = librarySnapshot(
            discoveries: [
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

        XCTAssertEqual(merged.discoveries.count, 1)
        XCTAssertNil(merged.discoveries.first?.markedInterestedAt)
        XCTAssertEqual(merged.discoveries.first?.updatedAt, "2026-05-23T11:00:00Z")
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

    private func fixedDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    private func librarySnapshot(
        favorites: [FavoriteStationRecord] = [],
        recents: [RecentStationRecord] = [],
        discoveries: [DiscoveredTrackRecord] = [],
        settings: AppSettingsRecord? = nil,
        updatedAt: String
    ) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: favorites,
            recents: recents,
            discoveries: discoveries,
            settings: settings ?? AppSettingsRecord(
                preferredCountry: "",
                preferredLanguage: "",
                preferredTag: "",
                lastPlayedStationID: nil,
                sleepTimerMinutes: nil,
                updatedAt: updatedAt
            )
        )
    }

    private func favoriteRecord(
        id: String,
        createdAt: String? = "2026-05-23T09:00:00Z"
    ) -> FavoriteStationRecord {
        FavoriteStationRecord(
            station: stationRecord(id: id),
            createdAt: createdAt
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
