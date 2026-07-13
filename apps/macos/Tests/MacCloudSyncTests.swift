import XCTest
@testable import TuneAVMac

final class MacCloudSyncTests: XCTestCase {
    func testAccountRefreshPreservesConfirmedAccessForSameInternalUser() {
        XCTAssertFalse(
            MacAccountAccessRefreshPolicy.shouldResolveLocalAccessAfterActiveRestore(
                previousUserID: "user-1",
                restoredUserID: "user-1"
            )
        )
    }

    func testAccountRefreshDropsPreviousAccessBeforeResolvingDifferentInternalUser() {
        XCTAssertTrue(
            MacAccountAccessRefreshPolicy.shouldResolveLocalAccessAfterActiveRestore(
                previousUserID: "user-1",
                restoredUserID: "user-2"
            )
        )
        XCTAssertTrue(
            MacAccountAccessRefreshPolicy.shouldResolveLocalAccessAfterActiveRestore(
                previousUserID: nil,
                restoredUserID: "user-1"
            )
        )
    }

    func testTemporarilyUnavailableRefreshPreservesCurrentAccountAccess() {
        XCTAssertFalse(
            MacAccountAccessRefreshPolicy.shouldResolveLocalAccessAfterUnavailableRestore(
                hasCurrentUser: true
            )
        )
        XCTAssertTrue(
            MacAccountAccessRefreshPolicy.shouldResolveLocalAccessAfterUnavailableRestore(
                hasCurrentUser: false
            )
        )
    }

    func testMacCloudSyncDecodesMinimalFavoriteDeletionTombstone() throws {
        let data = Data(
            """
            {
              "station": {
                "id": "legacy-station",
                "name": "Legacy Station"
              },
              "createdAt": "2026-06-30T09:00:00Z",
              "deletedAt": "2026-07-10T10:00:00Z"
            }
            """.utf8
        )

        let record = try JSONDecoder().decode(FavoriteStationRecord.self, from: data)

        XCTAssertEqual(record.station.id, "legacy-station")
        XCTAssertEqual(record.station.name, "Legacy Station")
        XCTAssertEqual(record.station.country, "")
        XCTAssertEqual(record.station.language, "")
        XCTAssertEqual(record.station.tags, "")
        XCTAssertEqual(record.station.streamURL, "")
        XCTAssertEqual(record.deletedAt, "2026-07-10T10:00:00Z")
    }

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

    func testConcurrentCloudSyncRequestsCoalesceIntoOneBoundedFollowUp() {
        var gate = MacCloudSyncExecutionGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
        XCTAssertTrue(gate.hasPendingFollowUp)
        XCTAssertTrue(gate.consumePendingFollowUp())
        XCTAssertFalse(gate.consumePendingFollowUp())

        // A request that arrives during the bounded follow-up is not allowed to
        // start a third overlapping pass. Finishing clears it so a later user
        // action can start a fresh synchronization normally.
        XCTAssertFalse(gate.begin())
        gate.finish()
        XCTAssertFalse(gate.isRunning)
        XCTAssertFalse(gate.hasPendingFollowUp)
        XCTAssertTrue(gate.begin())
    }

    func testSignOutCancelsPendingSync() {
        let trigger = MacCloudSyncTrigger()

        XCTAssertEqual(trigger.signOutStarted(), .cancel)
    }

    func testRealtimeProjectionWaitsOnlyForMatchingInitialBootstrap() {
        var gate = MacProRealtimeBootstrapGate()
        gate.begin(ownerUserID: "user-1")

        XCTAssertTrue(gate.shouldAwaitBootstrap(for: "user-1"))
        XCTAssertFalse(gate.shouldAwaitBootstrap(for: "user-2"))

        gate.complete(ownerUserID: "user-2")
        XCTAssertTrue(gate.shouldAwaitBootstrap(for: "user-1"))

        gate.complete(ownerUserID: "user-1", succeeded: true)
        XCTAssertFalse(gate.shouldAwaitBootstrap(for: "user-1"))
        XCTAssertTrue(gate.hasCompletedSuccessfulBootstrap(for: "user-1"))

        gate.finishInitialProjection(ownerUserID: "user-2")
        XCTAssertTrue(gate.hasCompletedSuccessfulBootstrap(for: "user-1"))

        gate.finishInitialProjection(ownerUserID: "user-1")
        XCTAssertFalse(gate.hasCompletedSuccessfulBootstrap(for: "user-1"))

        gate.begin(ownerUserID: "user-1")
        gate.complete(ownerUserID: "user-1", succeeded: false)
        XCTAssertNil(gate.ownerUserID)
    }

    func testMacRealtimeProjectionStateResetsOnlyForDifferentOwner() {
        XCTAssertFalse(
            MacProRealtimeProjectionStatePolicy.shouldReset(
                previousOwnerUserID: "user-1",
                nextOwnerUserID: "user-1"
            )
        )
        XCTAssertTrue(
            MacProRealtimeProjectionStatePolicy.shouldReset(
                previousOwnerUserID: "user-1",
                nextOwnerUserID: "user-2"
            )
        )
        XCTAssertTrue(
            MacProRealtimeProjectionStatePolicy.shouldReset(
                previousOwnerUserID: nil,
                nextOwnerUserID: "user-1"
            )
        )
    }

    func testMacRealtimeBaselineSkipsHistoricalReadButKeepsLaterInvalidation() {
        var cursor = TuneAVProRealtimeProjectionCursor()
        cursor.establishBaseline(TuneAVProLibraryProjection(
            ownerUserId: "user-1",
            projectionVersion: 4,
            libraryGeneration: 4,
            feedbackGeneration: 7,
            sourceUpdatedAt: nil,
            updatedAt: 1
        ))

        XCTAssertEqual(
            cursor.consume(TuneAVProLibraryProjection(
                ownerUserId: "user-1",
                projectionVersion: 4,
                libraryGeneration: 4,
                feedbackGeneration: 7,
                sourceUpdatedAt: nil,
                updatedAt: 1
            )),
            .none
        )
        XCTAssertEqual(
            cursor.consume(TuneAVProLibraryProjection(
                ownerUserId: "user-1",
                projectionVersion: 4,
                libraryGeneration: 5,
                feedbackGeneration: 7,
                sourceUpdatedAt: nil,
                updatedAt: 2
            )),
            TuneAVProRealtimeRefreshPlan(refreshLibrary: true)
        )
    }

    func testMacRealtimeSingleGenerationUsesExactLibraryResource() {
        var cursor = TuneAVProRealtimeProjectionCursor()
        cursor.establishBaseline(TuneAVProLibraryProjection(
            ownerUserId: "user-1",
            projectionVersion: 4,
            libraryGeneration: 8,
            feedbackGeneration: 3,
            resource: "favorites",
            sourceUpdatedAt: 1,
            updatedAt: 1
        ))

        let refreshPlan = cursor.consume(TuneAVProLibraryProjection(
            ownerUserId: "user-1",
            projectionVersion: 4,
            libraryGeneration: 9,
            feedbackGeneration: 3,
            resource: "favorites",
            sourceUpdatedAt: 2,
            updatedAt: 2
        ))
        let executionPlan = MacProRealtimeRefreshExecutionPlan(refreshPlan)

        XCTAssertEqual(refreshPlan.libraryResource, "favorites")
        XCTAssertEqual(executionPlan.libraryResource, .favorites)
        XCTAssertFalse(executionPlan.requiresFullLibraryRefresh)
    }

    func testMacOwnMutationReceiptSuppressesOnlyMatchingRealtimeRead() {
        var cursor = TuneAVProRealtimeProjectionCursor()
        cursor.establishBaseline(TuneAVProLibraryProjection(
            ownerUserId: "user-1",
            projectionVersion: 4,
            libraryGeneration: 8,
            feedbackGeneration: 3,
            resource: "favorites",
            sourceUpdatedAt: 1,
            updatedAt: 1
        ))
        let mutationUpdatedAt = TuneAVDateCoding.date(from: "2026-07-13T15:05:09.614Z")
        let receipt = TuneAVLibraryMutationReceipt(
            resource: .favorites,
            sourceUpdatedAt: mutationUpdatedAt,
            revision: 12,
            etag: "\"revision-12\""
        )
        var coverage: [String: Date] = [:]
        TuneAVLibraryMutationCoverage.record(receipt, in: &coverage)

        let ownPlan = cursor.consume(
            TuneAVProLibraryProjection(
                ownerUserId: "user-1",
                projectionVersion: 4,
                libraryGeneration: 9,
                feedbackGeneration: 3,
                resource: "favorites",
                sourceUpdatedAt: mutationUpdatedAt.timeIntervalSince1970 * 1_000,
                updatedAt: 2
            ),
            coverage: TuneAVProRealtimeCoverage(
                librarySourceUpdatedAtByResource: coverage
            )
        )
        XCTAssertEqual(ownPlan, .none)

        let remotePlan = cursor.consume(
            TuneAVProLibraryProjection(
                ownerUserId: "user-1",
                projectionVersion: 4,
                libraryGeneration: 10,
                feedbackGeneration: 3,
                resource: "favorites",
                sourceUpdatedAt: mutationUpdatedAt.addingTimeInterval(1).timeIntervalSince1970 * 1_000,
                updatedAt: 3
            ),
            coverage: TuneAVProRealtimeCoverage(
                librarySourceUpdatedAtByResource: coverage
            )
        )
        let executionPlan = MacProRealtimeRefreshExecutionPlan(remotePlan)
        XCTAssertEqual(executionPlan.libraryResource, .favorites)
    }

    func testMacMutationCoverageKeepsNewestReceiptAndIgnoresMissingTimestamp() {
        let latest = TuneAVDateCoding.date(from: "2026-07-13T15:05:09.614Z")
        var coverage = ["savedDiscoveries": latest]

        TuneAVLibraryMutationCoverage.record(
            TuneAVLibraryMutationReceipt(
                resource: .savedDiscoveries,
                sourceUpdatedAt: latest.addingTimeInterval(-1),
                revision: 4,
                etag: nil
            ),
            in: &coverage
        )
        TuneAVLibraryMutationCoverage.record(
            TuneAVLibraryMutationReceipt(
                resource: .savedDiscoveries,
                sourceUpdatedAt: nil,
                revision: 5,
                etag: nil
            ),
            in: &coverage
        )

        XCTAssertEqual(coverage["savedDiscoveries"], latest)
    }

    func testMacRealtimeGenerationGapKeepsConservativeFullRefresh() {
        var cursor = TuneAVProRealtimeProjectionCursor()
        cursor.establishBaseline(TuneAVProLibraryProjection(
            ownerUserId: "user-1",
            projectionVersion: 4,
            libraryGeneration: 8,
            feedbackGeneration: 3,
            resource: "favorites",
            sourceUpdatedAt: 1,
            updatedAt: 1
        ))

        let refreshPlan = cursor.consume(TuneAVProLibraryProjection(
            ownerUserId: "user-1",
            projectionVersion: 4,
            libraryGeneration: 10,
            feedbackGeneration: 3,
            resource: "favorites",
            sourceUpdatedAt: 3,
            updatedAt: 3
        ))
        let executionPlan = MacProRealtimeRefreshExecutionPlan(refreshPlan)

        XCTAssertNil(refreshPlan.libraryResource)
        XCTAssertNil(executionPlan.libraryResource)
        XCTAssertTrue(executionPlan.requiresFullLibraryRefresh)
    }

    func testMacRealtimeUnknownResourceKeepsConservativeFullRefresh() {
        let executionPlan = MacProRealtimeRefreshExecutionPlan(
            TuneAVProRealtimeRefreshPlan(
                refreshLibrary: true,
                libraryResource: "futureResource"
            )
        )

        XCTAssertNil(executionPlan.libraryResource)
        XCTAssertTrue(executionPlan.requiresFullLibraryRefresh)
    }

    func testScopedFavoritesPullReadsOnlyFavorites() async throws {
        let recorder = MacScopedLibraryRequestRecorder()
        let client = TuneAVAppDataSyncClient(
            deviceId: "test-mac",
            platform: "macos",
            request: { path, method, _, _ in
                try await recorder.request(path: path, method: method)
            }
        )
        let localSnapshot = TuneAVLibrarySnapshot(
            favorites: [favoriteRecord(id: "local-favorite")],
            savedDiscoveries: [
                discoveryRecord(
                    id: "local-song",
                    playedAt: "2026-07-13T12:00:00Z",
                    markedInterestedAt: "2026-07-13T12:01:00Z"
                )
            ]
        )

        let document = try await client.pullLibraryResource(.favorites, mergingInto: localSnapshot)
        let calls = await recorder.calls

        XCTAssertEqual(calls, ["GET /v1/apps/tuneav/data/favorites"])
        XCTAssertEqual(document.resource, .favorites)
        XCTAssertEqual(document.snapshot.favorites.map(\.station.id), ["remote-favorite"])
        XCTAssertEqual(document.snapshot.savedDiscoveries, localSnapshot.savedDiscoveries)
    }

    func testScopedSavedDiscoveriesPullReadsOnlySavedDiscoveries() async throws {
        let recorder = MacScopedLibraryRequestRecorder()
        let client = TuneAVAppDataSyncClient(
            deviceId: "test-mac",
            platform: "macos",
            request: { path, method, _, _ in
                try await recorder.request(path: path, method: method)
            }
        )
        let localSnapshot = TuneAVLibrarySnapshot(
            favorites: [favoriteRecord(id: "local-favorite")],
            savedDiscoveries: []
        )

        let document = try await client.pullLibraryResource(.savedDiscoveries, mergingInto: localSnapshot)
        let calls = await recorder.calls

        XCTAssertEqual(calls, ["GET /v1/apps/tuneav/data/savedDiscoveries"])
        XCTAssertEqual(document.resource, .savedDiscoveries)
        XCTAssertEqual(document.snapshot.favorites, localSnapshot.favorites)
        XCTAssertEqual(document.snapshot.savedDiscoveries.map(\.discoveryID), ["remote-song"])
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
        XCTAssertFalse(TuneAVMacDiagnostics.shouldCapture(TuneAVPromoCodeClientError.server(
            code: "promo_code_unavailable",
            message: "This promo code is not available.",
            statusCode: 404
        )))
        XCTAssertTrue(TuneAVMacDiagnostics.shouldCapture(TuneAVPromoCodeClientError.server(
            code: "promo_backend_unavailable",
            message: "Promo service unavailable.",
            statusCode: 503
        )))
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

    func testMacSyncMergeUsesBackendCanonicalNewestFirstFavoriteOrder() {
        let older = favoriteRecord(id: "older", createdAt: "2026-05-23T09:00:00Z")
        let newer = favoriteRecord(id: "newer", createdAt: "2026-05-23T10:00:00Z")

        let merged = TuneAVLibrarySnapshotMerger.merged(
            local: librarySnapshot(
                favorites: [older, newer],
                updatedAt: "2026-05-23T10:00:00Z"
            ),
            remote: librarySnapshot(
                favorites: [newer, older],
                updatedAt: "2026-05-23T10:00:00Z"
            )
        )

        XCTAssertEqual(merged.favorites.map(\.station.id), ["newer", "older"])
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

    func testMacSyncPlannerPullsWithoutPushingAfterApplyingCloudWithoutALocalMutation() {
        let remoteSnapshot = librarySnapshot(
            favorites: [favoriteRecord(id: "remote-favorite")],
            updatedAt: "2026-05-23T10:00:00Z"
        )
        let remote = TuneAVLibraryDocument(
            snapshot: remoteSnapshot,
            updatedAt: fixedDate("2026-05-23T10:00:00Z"),
            revision: 2,
            etag: nil
        )

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: remoteSnapshot,
                localUpdatedAt: fixedDate("2026-05-23T09:00:00Z"),
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

    func testMacSyncPreservesLegacyMissingTrackKeyWithoutCollapsingBackendIdentity() throws {
        let legacyData = Data(
            """
            {
              "discoveryID": "legacy",
              "title": "Straße",
              "artist": "Artist",
              "stationID": "station-legacy",
              "stationName": "Legacy Station",
              "playedAt": "2026-06-14T17:41:00Z",
              "markedInterestedAt": "2026-06-14T17:42:00Z",
              "updatedAt": "2026-06-14T17:42:00Z"
            }
            """.utf8
        )
        let legacy = try JSONDecoder().decode(DiscoveredTrackRecord.self, from: legacyData)
        let explicit = DiscoveredTrackRecord(
            discoveryID: "explicit",
            trackKey: "strasse::artist",
            title: "Strasse",
            artist: "Artist",
            stationID: "station-explicit",
            stationName: "Explicit Station",
            artworkURL: nil,
            stationArtworkURL: nil,
            playedAt: "2026-06-14T17:41:00Z",
            markedInterestedAt: "2026-06-14T17:42:00Z",
            updatedAt: "2026-06-14T17:42:00Z"
        )

        let canonical = TuneAVLibrarySnapshotMerger.canonicalized(
            TuneAVLibrarySnapshot(favorites: [], savedDiscoveries: [legacy, explicit])
        )
        let model = try XCTUnwrap(MacDiscoveredTrack(record: legacy))

        XCTAssertNil(legacy.trackKey)
        XCTAssertNil(model.record.trackKey)
        XCTAssertEqual(canonical.savedDiscoveries.count, 2)
        XCTAssertEqual(canonical.savedDiscoveries.map(\.discoveryID), ["explicit", "legacy"])
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

    func testMacLibraryStoragePersistsPendingLibraryOperationsIncludingDeletion() {
        let suiteName = "MacCloudSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TuneAVMacLibraryStorage(defaults: defaults)
        let favoriteDeletion = pendingLibraryOperation(
            resource: .favorites,
            action: .delete,
            userID: "user-a",
            identityKey: "stream:https://example.com/station-a.mp3",
            favoriteRecord: favoriteRecord(
                id: "station-a",
                createdAt: nil,
                deletedAt: "2026-05-23T11:00:00Z"
            )
        )
        let discoveryUpsert = pendingLibraryOperation(
            resource: .savedDiscoveries,
            action: .upsert,
            userID: "user-a",
            identityKey: "track:song::artist",
            discoveryRecord: discoveryRecord(
                id: "track-a",
                title: "Song",
                artist: "Artist",
                playedAt: "2026-05-23T11:00:00Z",
                markedInterestedAt: "2026-05-23T11:00:00Z"
            )
        )
        let operations = [
            favoriteDeletion.storageKey: favoriteDeletion,
            discoveryUpsert.storageKey: discoveryUpsert
        ]

        storage.savePendingLibraryOperations(operations)
        let relaunchedStorage = TuneAVMacLibraryStorage(defaults: defaults)

        XCTAssertEqual(relaunchedStorage.loadPendingLibraryOperations(), operations)

        relaunchedStorage.savePendingLibraryOperations([:])

        XCTAssertTrue(relaunchedStorage.loadPendingLibraryOperations().isEmpty)
    }

    func testPendingLibraryOutboxKeepsLatestIntentAndIsolatesUsersAndResources() {
        let firstSave = pendingLibraryOperation(
            resource: .favorites,
            action: .upsert,
            userID: "user-a",
            identityKey: "shared-identity",
            favoriteRecord: favoriteRecord(id: "station-a")
        )
        let deletion = pendingLibraryOperation(
            resource: .favorites,
            action: .delete,
            userID: "user-a",
            identityKey: "shared-identity",
            favoriteRecord: favoriteRecord(
                id: "station-a",
                createdAt: nil,
                deletedAt: "2026-05-23T11:01:00Z"
            )
        )
        let latestSave = pendingLibraryOperation(
            resource: .favorites,
            action: .upsert,
            userID: "user-a",
            identityKey: "shared-identity",
            favoriteRecord: favoriteRecord(id: "station-a", createdAt: "2026-05-23T11:02:00Z")
        )
        let otherUser = pendingLibraryOperation(
            resource: .favorites,
            action: .delete,
            userID: "user-b",
            identityKey: "shared-identity",
            favoriteRecord: favoriteRecord(
                id: "station-a",
                createdAt: nil,
                deletedAt: "2026-05-23T11:03:00Z"
            )
        )
        let otherResource = pendingLibraryOperation(
            resource: .savedDiscoveries,
            action: .upsert,
            userID: "user-a",
            identityKey: "shared-identity",
            discoveryRecord: discoveryRecord(
                id: "track-a",
                playedAt: "2026-05-23T11:04:00Z",
                markedInterestedAt: "2026-05-23T11:04:00Z"
            )
        )

        var operations = TuneAVMacPendingLibraryOutbox.upserting(firstSave, into: [:])
        operations = TuneAVMacPendingLibraryOutbox.upserting(deletion, into: operations)
        operations = TuneAVMacPendingLibraryOutbox.upserting(latestSave, into: operations)
        operations = TuneAVMacPendingLibraryOutbox.upserting(otherUser, into: operations)
        operations = TuneAVMacPendingLibraryOutbox.upserting(otherResource, into: operations)

        XCTAssertEqual(operations.count, 3)
        XCTAssertEqual(operations[latestSave.storageKey], latestSave)
        XCTAssertEqual(operations[otherUser.storageKey], otherUser)
        XCTAssertEqual(operations[otherResource.storageKey], otherResource)
    }

    func testMacLibraryStoragePersistsPendingFeedbackIncludingDeletion() {
        let suiteName = "MacCloudSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = TuneAVMacLibraryStorage(defaults: defaults)
        let upload = pendingFeedbackUpload(
            kind: .station,
            userID: "user-a",
            identityKey: "station-a",
            feedback: nil,
            stationID: "station-a"
        )

        storage.savePendingFeedbackUploads([upload.storageKey: upload])

        XCTAssertEqual(storage.loadPendingFeedbackUploads(), [upload.storageKey: upload])

        storage.savePendingFeedbackUploads([:])

        XCTAssertTrue(storage.loadPendingFeedbackUploads().isEmpty)
    }

    func testFeedbackClearPayloadsEncodeExplicitNull() throws {
        let stationData = try JSONEncoder().encode(
            TuneAVMacFeedbackRequest(deviceId: "tuneav-mac", feedback: nil)
        )
        let trackData = try JSONEncoder().encode(
            TuneAVMacTrackFeedbackRequest(
                deviceId: "tuneav-mac",
                title: "Teardrop",
                artist: "Massive Attack",
                stationId: "BBC Radio 1",
                feedback: nil
            )
        )
        let stationBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: stationData) as? [String: Any]
        )
        let trackBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: trackData) as? [String: Any]
        )

        XCTAssertEqual(stationBody["deviceId"] as? String, "tuneav-mac")
        XCTAssertTrue(stationBody.keys.contains("feedback"))
        XCTAssertTrue(stationBody["feedback"] is NSNull)
        XCTAssertEqual(trackBody["deviceId"] as? String, "tuneav-mac")
        XCTAssertEqual(trackBody["title"] as? String, "Teardrop")
        XCTAssertEqual(trackBody["artist"] as? String, "Massive Attack")
        XCTAssertEqual(trackBody["stationId"] as? String, "BBC Radio 1")
        XCTAssertTrue(trackBody.keys.contains("feedback"))
        XCTAssertTrue(trackBody["feedback"] is NSNull)
    }

    func testPendingFeedbackOutboxKeepsLatestWritePerUserAndIdentity() {
        let first = pendingFeedbackUpload(
            kind: .station,
            userID: "user-a",
            identityKey: "station-a",
            feedback: .liked,
            stationID: "station-a"
        )
        let latest = pendingFeedbackUpload(
            kind: .station,
            userID: "user-a",
            identityKey: "station-a",
            feedback: .disliked,
            stationID: "station-a"
        )
        let otherUser = pendingFeedbackUpload(
            kind: .station,
            userID: "user-b",
            identityKey: "station-a",
            feedback: .notForMe,
            stationID: "station-a"
        )

        var uploads = TuneAVMacPendingFeedbackOutbox.upserting(first, into: [:])
        uploads = TuneAVMacPendingFeedbackOutbox.upserting(latest, into: uploads)
        uploads = TuneAVMacPendingFeedbackOutbox.upserting(otherUser, into: uploads)

        XCTAssertEqual(uploads.count, 2)
        XCTAssertEqual(uploads[latest.storageKey], latest)
        XCTAssertEqual(uploads[otherUser.storageKey], otherUser)
    }

    func testPendingFeedbackRetryPolicyUsesBoundedExponentialBackoffAndJitter() {
        XCTAssertEqual(
            TuneAVMacSyncRetryPolicy.delay(
                retryCount: 0,
                baseDelay: 5,
                maxDelay: 120,
                jitterFraction: 0.2,
                randomFraction: { 0 }
            ),
            4
        )
        XCTAssertEqual(
            TuneAVMacSyncRetryPolicy.delay(
                retryCount: 1,
                baseDelay: 5,
                maxDelay: 120,
                jitterFraction: 0.2,
                randomFraction: { 0.5 }
            ),
            10
        )
        XCTAssertEqual(
            TuneAVMacSyncRetryPolicy.delay(
                retryCount: 10,
                baseDelay: 5,
                maxDelay: 120,
                jitterFraction: 0.2,
                randomFraction: { 1 }
            ),
            120
        )
    }

    func testMacListeningSessionLifecycleTracksDistinctSongsAndStationChanges() {
        let startedAt = fixedDate("2026-05-23T10:00:00Z")
        var session: TuneAVMacActiveListeningSession?

        XCTAssertNil(TuneAVMacListeningSessionCoordinator.begin(
            session: &session,
            station: Station.samples[0],
            source: "home",
            userID: "user-a",
            now: startedAt
        ))
        TuneAVMacListeningSessionCoordinator.rememberTrack(session: &session, title: "Song", artist: "Artist")
        TuneAVMacListeningSessionCoordinator.rememberTrack(session: &session, title: "song", artist: "artist")
        TuneAVMacListeningSessionCoordinator.rememberTrack(session: &session, title: "Another Song", artist: "Artist")

        let endedSession = TuneAVMacListeningSessionCoordinator.begin(
            session: &session,
            station: Station.samples[1],
            source: "search",
            userID: "user-a",
            now: startedAt.addingTimeInterval(12)
        )
        let draft = endedSession.flatMap {
            TuneAVMacListeningSessionDraft(
                id: "session-a",
                session: $0,
                endedAt: startedAt.addingTimeInterval(12),
                endedReason: .stationChanged
            )
        }

        XCTAssertEqual(draft?.stationID, Station.samples[0].id)
        XCTAssertEqual(draft?.durationSeconds, 12)
        XCTAssertEqual(draft?.trackDetectedCount, 2)
        XCTAssertEqual(draft?.source, "home")
        XCTAssertEqual(draft?.endedReason, .stationChanged)
        XCTAssertEqual(session?.station.id, Station.samples[1].id)
    }

    func testMacListeningSessionDropsPlaybackShorterThanTenSeconds() {
        let startedAt = fixedDate("2026-05-23T10:00:00Z")
        let session = TuneAVMacActiveListeningSession(
            station: Station.samples[0],
            startedAt: startedAt,
            source: "player",
            userID: "user-a",
            trackKeys: []
        )

        XCTAssertNil(TuneAVMacListeningSessionDraft(
            session: session,
            endedAt: startedAt.addingTimeInterval(9),
            endedReason: .paused
        ))
        XCTAssertNotNil(TuneAVMacListeningSessionDraft(
            session: session,
            endedAt: startedAt.addingTimeInterval(10),
            endedReason: .paused
        ))
    }

    func testMacListeningSessionStorageSurvivesRelaunchAndClear() {
        let suiteName = "MacCloudSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = TuneAVMacLibraryStorage(defaults: defaults)
        let session = listeningSessionDraft(id: "session-a", userID: "user-a")

        storage.savePendingListeningSessions([session])
        let relaunchedStorage = TuneAVMacLibraryStorage(defaults: defaults)

        XCTAssertEqual(relaunchedStorage.loadPendingListeningSessions(), [session])
        relaunchedStorage.savePendingListeningSessions([])
        XCTAssertTrue(relaunchedStorage.loadPendingListeningSessions().isEmpty)
    }

    func testMacListeningSessionStorageNormalizesLegacyEndedReasons() throws {
        struct LegacyDraft: Encodable {
            let id: String
            let stationID: String
            let stationName: String
            let startedAt: Date
            let endedAt: Date
            let durationSeconds: Int
            let source: String
            let endedReason: String
            let trackDetectedCount: Int
            let userID: String
        }

        let suiteName = "MacCloudSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = TuneAVMacLibraryStorage.pendingListeningSessionsKey
        let endedAt = fixedDate("2026-05-23T11:00:00Z")
        let legacy = LegacyDraft(
            id: "legacy-session",
            stationID: "station-a",
            stationName: "Station A",
            startedAt: endedAt.addingTimeInterval(-30),
            endedAt: endedAt,
            durationSeconds: 30,
            source: "home",
            endedReason: "access_changed",
            trackDetectedCount: 1,
            userID: "user-a"
        )
        defaults.set(try JSONEncoder().encode([legacy]), forKey: key)
        let storage = TuneAVMacLibraryStorage(defaults: defaults)

        let restored = storage.loadPendingListeningSessions()

        XCTAssertEqual(restored.first?.endedReason, .appClosed)
        storage.savePendingListeningSessions(restored)
        let migratedJSON = String(decoding: try XCTUnwrap(defaults.data(forKey: key)), as: UTF8.self)
        XCTAssertTrue(migratedJSON.contains("\"endedReason\":\"app_closed\""))
        XCTAssertFalse(migratedJSON.contains("access_changed"))
    }

    func testMacListeningSessionOutboxBoundsAgeDeduplicatesAndIsolatesUsers() {
        let now = fixedDate("2026-05-23T12:00:00Z")
        var sessions = (0..<55).map { index in
            listeningSessionDraft(
                id: "session-\(index)",
                userID: "user-a",
                endedAt: now.addingTimeInterval(TimeInterval(index - 55))
            )
        }
        sessions.append(listeningSessionDraft(id: "other-user", userID: "user-b", endedAt: now))
        sessions.append(listeningSessionDraft(
            id: "expired",
            userID: "user-a",
            endedAt: now.addingTimeInterval(-(60 * 60 * 24 * 8))
        ))
        sessions.append(listeningSessionDraft(id: "session-54", userID: "user-a", endedAt: now))

        let bounded = TuneAVMacListeningSessionOutbox.bounded(
            sessions,
            maxCount: 50,
            maxAge: 60 * 60 * 24 * 7,
            now: now
        )
        let userABatch = TuneAVMacListeningSessionOutbox.sessions(in: bounded, forUserID: "user-a", limit: 5)

        XCTAssertEqual(bounded.count, 51)
        XCTAssertEqual(bounded.filter { $0.userID == "user-a" }.count, 50)
        XCTAssertEqual(bounded.filter { $0.userID == "user-b" }.count, 1)
        XCTAssertEqual(bounded.filter { $0.id == "session-54" }.count, 1)
        XCTAssertFalse(bounded.contains { $0.id == "expired" })
        XCTAssertEqual(userABatch.count, 5)
        XCTAssertTrue(userABatch.allSatisfy { $0.userID == "user-a" })
    }

    func testMacListeningAnalyticsUploadsOnlyForConfiguredProUsers() {
        XCTAssertTrue(TuneAVMacListeningAnalyticsEligibility.canUpload(
            isEnabled: true,
            accessMode: .signedInPro,
            userID: "user-a",
            accountServiceAvailable: true,
            apiConfigured: true
        ))
        XCTAssertFalse(TuneAVMacListeningAnalyticsEligibility.canUpload(
            isEnabled: true,
            accessMode: .signedInFree,
            userID: "user-a",
            accountServiceAvailable: true,
            apiConfigured: true
        ))
        XCTAssertFalse(TuneAVMacListeningAnalyticsEligibility.canUpload(
            isEnabled: false,
            accessMode: .signedInPro,
            userID: "user-a",
            accountServiceAvailable: true,
            apiConfigured: true
        ))
        XCTAssertFalse(TuneAVMacListeningAnalyticsEligibility.canUpload(
            isEnabled: true,
            accessMode: .signedInPro,
            userID: nil,
            accountServiceAvailable: true,
            apiConfigured: true
        ))
    }

    func testMacListeningSessionPayloadUsesMacDeviceAndDoesNotExposeUserID() throws {
        let session = listeningSessionDraft(id: "session-a", userID: "internal-user")
        let data = try JSONEncoder().encode(
            TuneAVMacListeningSessionsRequest(deviceId: "tuneav-mac", sessions: [session.apiInput])
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedSessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])

        XCTAssertEqual(json["deviceId"] as? String, "tuneav-mac")
        XCTAssertEqual(encodedSessions.first?["id"] as? String, "session-a")
        XCTAssertNil(encodedSessions.first?["userID"])
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

    private func pendingFeedbackUpload(
        kind: TuneAVMacPendingFeedbackUpload.Kind,
        userID: String,
        identityKey: String,
        feedback: TuneAVStationFeedback?,
        stationID: String?,
        title: String? = nil,
        artist: String? = nil
    ) -> TuneAVMacPendingFeedbackUpload {
        TuneAVMacPendingFeedbackUpload(
            kind: kind,
            userID: userID,
            identityKey: identityKey,
            feedback: feedback,
            stationID: stationID,
            title: title,
            artist: artist,
            updatedAt: "2026-05-23T11:00:00Z"
        )
    }

    private func listeningSessionDraft(
        id: String,
        userID: String,
        endedAt: Date = ISO8601DateFormatter().date(from: "2026-05-23T11:00:00Z")!
    ) -> TuneAVMacListeningSessionDraft {
        TuneAVMacListeningSessionDraft(
            id: id,
            stationID: "station-a",
            stationName: "Station A",
            startedAt: endedAt.addingTimeInterval(-30),
            endedAt: endedAt,
            durationSeconds: 30,
            source: "home",
            endedReason: .paused,
            trackDetectedCount: 1,
            userID: userID
        )
    }

    private func pendingLibraryOperation(
        resource: TuneAVMacPendingLibraryOperation.Resource,
        action: TuneAVMacPendingLibraryOperation.Action,
        userID: String,
        identityKey: String,
        favoriteRecord: FavoriteStationRecord? = nil,
        discoveryRecord: DiscoveredTrackRecord? = nil
    ) -> TuneAVMacPendingLibraryOperation {
        TuneAVMacPendingLibraryOperation(
            resource: resource,
            action: action,
            userID: userID,
            identityKey: identityKey,
            favoriteRecord: favoriteRecord,
            discoveryRecord: discoveryRecord,
            updatedAt: "2026-05-23T11:00:00Z"
        )
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
            TuneAVMacLibraryStorage.pendingLibraryOperationsKey,
            TuneAVMacLibraryStorage.pendingFeedbackUploadsKey,
            TuneAVMacLibraryStorage.pendingListeningSessionsKey,
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

private actor MacScopedLibraryRequestRecorder {
    private(set) var calls: [String] = []

    func request(path: String, method: String) throws -> Data {
        calls.append("\(method) \(path)")

        switch path {
        case "/v1/apps/tuneav/data/favorites":
            return Data(
                #"{"data":{"appId":"tuneav","resource":"favorites","deviceId":"remote","sentAt":"2026-07-13T12:05:00Z","entries":[{"station":{"id":"remote-favorite","name":"Remote Favorite"},"createdAt":"2026-07-13T12:05:00Z"}]},"updatedAt":"2026-07-13T12:05:00Z","revision":11,"etag":"revision-11"}"#.utf8
            )
        case "/v1/apps/tuneav/data/savedDiscoveries":
            return Data(
                #"{"data":{"appId":"tuneav","resource":"savedDiscoveries","deviceId":"remote","sentAt":"2026-07-13T12:06:00Z","entries":[{"discoveryID":"remote-song","trackKey":"remote song::artist","title":"Remote Song","artist":"Artist","stationID":"station-1","stationName":"Station 1","playedAt":"2026-07-13T12:05:00Z","markedInterestedAt":"2026-07-13T12:06:00Z","updatedAt":"2026-07-13T12:06:00Z"}]},"updatedAt":"2026-07-13T12:06:00Z","revision":12,"etag":"revision-12"}"#.utf8
            )
        default:
            throw TuneAVAppDataClientError.requestFailed(statusCode: 404)
        }
    }
}
