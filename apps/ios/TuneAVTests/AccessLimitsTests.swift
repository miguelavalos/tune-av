import XCTest
@testable import TuneAV

final class AccessLimitsTests: XCTestCase {
    func testRootStartupSyncPolicySkipsGuestAccountRefreshWhenAccountProviderIsUnavailable() {
        let policy = RootStartupSyncPolicy(accountIsAvailable: false, isSignedIn: false)

        XCTAssertFalse(policy.shouldRefreshAccountState)
        XCTAssertFalse(policy.shouldScheduleLibrarySync)
    }

    func testRootStartupSyncPolicyRefreshesAccountStateWhenProviderIsAvailable() {
        let policy = RootStartupSyncPolicy(accountIsAvailable: true, isSignedIn: false)

        XCTAssertTrue(policy.shouldRefreshAccountState)
        XCTAssertFalse(policy.shouldScheduleLibrarySync)
    }

    func testRootStartupSyncPolicyRefreshesAndSyncsLibraryForSignedInUsers() {
        let policy = RootStartupSyncPolicy(accountIsAvailable: false, isSignedIn: true)

        XCTAssertTrue(policy.shouldRefreshAccountState)
        XCTAssertTrue(policy.shouldScheduleLibrarySync)
    }

    func testRootStartupSyncPolicySkipsRecentAutomaticLibrarySync() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = RootStartupSyncPolicy(
            accountIsAvailable: true,
            isSignedIn: true,
            lastLibrarySyncRequestedAt: now.addingTimeInterval(-60),
            now: now
        )

        XCTAssertTrue(policy.shouldRefreshAccountState)
        XCTAssertFalse(policy.shouldScheduleLibrarySync)
    }

    func testRootStartupSyncPolicyDoesNotRepeatAutomaticLibrarySyncAfterInterval() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = RootStartupSyncPolicy(
            accountIsAvailable: true,
            isSignedIn: true,
            lastLibrarySyncRequestedAt: now.addingTimeInterval(-86_400),
            now: now
        )

        XCTAssertTrue(policy.shouldRefreshAccountState)
        XCTAssertFalse(policy.shouldScheduleLibrarySync)
    }

    func testRootStartupSyncPolicyDoesNotRepeatAccountRefreshAfterForegrounding() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = RootStartupSyncPolicy(
            accountIsAvailable: true,
            isSignedIn: true,
            lastAccountRefreshRequestedAt: now.addingTimeInterval(-86_400),
            now: now
        )

        XCTAssertFalse(policy.shouldRefreshAccountState)
        XCTAssertTrue(policy.shouldScheduleLibrarySync)
    }

    func testAccessPolicyMatchesSharedContract() throws {
        let contract = try loadAccessPolicyContract()
        let expectedModes: [(mode: AccessMode, planTier: String)] = [
            (.guest, "free"),
            (.signedInFree, "free"),
            (.signedInPro, "pro")
        ]

        XCTAssertEqual(contract.appId, "tuneav")
        XCTAssertEqual(contract.schemaVersion, 1)
        XCTAssertEqual(Set(contract.accessModes.keys), Set(expectedModes.map { $0.mode.rawValue }))

        for expectedMode in expectedModes {
            let contractMode = try XCTUnwrap(contract.accessModes[expectedMode.mode.rawValue])
            XCTAssertEqual(contractMode.planTier, expectedMode.planTier)
            XCTAssertEqual(AccessCapabilities.forMode(expectedMode.mode), contractMode.capabilities.tuneavValue)
            XCTAssertEqual(AccessLimits.forMode(expectedMode.mode), contractMode.limits.tuneavValue)
        }
    }

    func testGuestLimitsAllowSmallLocalPreviewOnly() {
        let limits = AccessLimits.forMode(.guest)

        XCTAssertEqual(limits.favoriteStations, 5)
        XCTAssertEqual(limits.recentStations, 15)
        XCTAssertEqual(limits.discoveredTracks, 25)
        XCTAssertEqual(limits.savedTracks, 10)
        XCTAssertEqual(limits.aviActionsPerDay, 5)
        XCTAssertEqual(limits.lyricsSearchesPerDay, 5)
        XCTAssertEqual(limits.webSearchesPerDay, 5)
        XCTAssertEqual(limits.youtubeSearchesPerDay, 5)
        XCTAssertEqual(limits.appleMusicSearchesPerDay, 5)
        XCTAssertEqual(limits.spotifySearchesPerDay, 5)
        XCTAssertEqual(limits.discoverySharesPerDay, 5)
    }

    func testSignedInFreeLimitsAreHigherAndBackendEnabledButCloudSyncLocalOnly() {
        let limits = AccessLimits.forMode(.signedInFree)
        let capabilities = AccessCapabilities.forMode(.signedInFree)

        XCTAssertEqual(limits.favoriteStations, 15)
        XCTAssertEqual(limits.recentStations, 50)
        XCTAssertEqual(limits.discoveredTracks, 100)
        XCTAssertEqual(limits.savedTracks, 50)
        XCTAssertEqual(limits.aviActionsPerDay, 15)
        XCTAssertEqual(limits.lyricsSearchesPerDay, 15)
        XCTAssertEqual(limits.webSearchesPerDay, 15)
        XCTAssertEqual(limits.youtubeSearchesPerDay, 15)
        XCTAssertEqual(limits.appleMusicSearchesPerDay, 15)
        XCTAssertEqual(limits.spotifySearchesPerDay, 15)
        XCTAssertEqual(limits.discoverySharesPerDay, 15)
        XCTAssertTrue(capabilities.isSignedIn)
        XCTAssertTrue(capabilities.isLocalOnly)
        XCTAssertTrue(capabilities.canUseBackend)
        XCTAssertFalse(capabilities.canUseCloudSync)
        XCTAssertFalse(capabilities.canAccessPremiumFeatures)
    }

    func testProKeepsLibraryLargeAndDailyMusicActionsUnlimited() {
        let limits = AccessLimits.forMode(.signedInPro)
        let capabilities = AccessCapabilities.forMode(.signedInPro)

        XCTAssertEqual(limits.favoriteStations, 1_000)
        XCTAssertEqual(limits.recentStations, 1_000)
        XCTAssertEqual(limits.discoveredTracks, 1_000)
        XCTAssertEqual(limits.savedTracks, 1_000)
        XCTAssertNil(limits.aviActionsPerDay)
        XCTAssertNil(limits.lyricsSearchesPerDay)
        XCTAssertNil(limits.webSearchesPerDay)
        XCTAssertNil(limits.youtubeSearchesPerDay)
        XCTAssertNil(limits.appleMusicSearchesPerDay)
        XCTAssertNil(limits.spotifySearchesPerDay)
        XCTAssertNil(limits.discoverySharesPerDay)
        XCTAssertTrue(capabilities.usesBackend)
        XCTAssertTrue(capabilities.canUseCloudSync)
        XCTAssertTrue(capabilities.canAccessPremiumFeatures)
    }

    func testFeatureLimitStateBlocksAtLimitAndReportsRemainingUsage() {
        let allowed = FeatureLimitState(feature: .favoriteStations, currentUsage: 4, limit: 5)
        let blocked = FeatureLimitState(feature: .favoriteStations, currentUsage: 5, limit: 5)
        let unlimited = FeatureLimitState(feature: .lyricsSearch, currentUsage: 10_000, limit: nil)

        XCTAssertTrue(allowed.isLimited)
        XCTAssertTrue(allowed.isAllowed)
        XCTAssertEqual(allowed.remaining, 1)

        XCTAssertTrue(blocked.isLimited)
        XCTAssertFalse(blocked.isAllowed)
        XCTAssertEqual(blocked.remaining, 0)

        XCTAssertFalse(unlimited.isLimited)
        XCTAssertTrue(unlimited.isAllowed)
        XCTAssertNil(unlimited.remaining)
    }

    func testLimitLookupMapsEveryLimitedFeatureToItsConfiguredValue() {
        let limits = AccessLimits.forMode(.guest)

        XCTAssertEqual(limits.limit(for: .favoriteStations), limits.favoriteStations)
        XCTAssertEqual(limits.limit(for: .savedTracks), limits.savedTracks)
        XCTAssertEqual(limits.limit(for: .discoveredTracks), limits.discoveredTracks)
        XCTAssertEqual(limits.limit(for: .aviAction), limits.aviActionsPerDay)
        XCTAssertEqual(limits.limit(for: .lyricsSearch), limits.aviActionsPerDay)
        XCTAssertEqual(limits.limit(for: .webSearch), limits.aviActionsPerDay)
        XCTAssertEqual(limits.limit(for: .youtubeSearch), limits.aviActionsPerDay)
        XCTAssertEqual(limits.limit(for: .appleMusicSearch), limits.aviActionsPerDay)
        XCTAssertEqual(limits.limit(for: .spotifySearch), limits.aviActionsPerDay)
        XCTAssertEqual(limits.limit(for: .discoveryShare), limits.aviActionsPerDay)
    }

    func testLibrarySyncPlannerPushesLocalWhenRemoteIsEmpty() {
        let local = librarySnapshot(favorites: [favoriteRecord()], updatedAt: "2026-04-30T10:00:00Z")
        let remote = libraryDocument(snapshot: nil, updatedAt: fixedDate("2026-04-30T09:00:00Z"))

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: local,
                localUpdatedAt: fixedDate("2026-04-30T10:00:00Z"),
                remoteDocument: remote
            ),
            .pushLocal
        )
    }

    func testLibrarySyncPlannerPullsRemoteAfterLocalDeviceReset() {
        let local = librarySnapshot(updatedAt: "2026-04-30T12:00:00Z")
        let remoteSnapshot = librarySnapshot(
            favorites: [favoriteRecord(id: "remote")],
            updatedAt: "2026-04-30T09:00:00Z"
        )
        let remote = libraryDocument(
            snapshot: remoteSnapshot,
            updatedAt: fixedDate("2026-04-30T09:00:00Z")
        )

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: local,
                localUpdatedAt: fixedDate("2026-04-30T12:00:00Z"),
                remoteDocument: remote
            ),
            .pullRemote(remoteSnapshot)
        )
    }

    func testLibrarySyncPlannerPushesExplicitLocalDeletionTombstone() {
        let local = librarySnapshot(
            favorites: [favoriteRecord(id: "remote", deletedAt: "2026-04-30T12:00:00Z")],
            updatedAt: "2026-04-30T12:00:00Z"
        )
        let remoteSnapshot = librarySnapshot(
            favorites: [favoriteRecord(id: "remote")],
            updatedAt: "2026-04-30T09:00:00Z"
        )
        let remote = libraryDocument(
            snapshot: remoteSnapshot,
            updatedAt: fixedDate("2026-04-30T09:00:00Z")
        )

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: local,
                localUpdatedAt: fixedDate("2026-04-30T12:00:00Z"),
                remoteDocument: remote
            ),
            .pushLocal
        )
    }

    func testLibrarySyncPlannerPullsRemoteWhenRemoteIsNewer() {
        let local = librarySnapshot(favorites: [favoriteRecord()], updatedAt: "2026-04-30T10:00:00Z")
        let remoteSnapshot = librarySnapshot(
            favorites: [favoriteRecord(id: "remote")],
            updatedAt: "2026-04-30T11:00:00Z"
        )
        let remote = libraryDocument(
            snapshot: remoteSnapshot,
            updatedAt: fixedDate("2026-04-30T11:00:00Z")
        )

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: local,
                localUpdatedAt: fixedDate("2026-04-30T10:00:00Z"),
                remoteDocument: remote
            ),
            .pullRemote(remoteSnapshot)
        )
    }

    func testLibrarySyncPlannerLeavesMatchingDocumentsCurrent() {
        let snapshot = librarySnapshot(favorites: [favoriteRecord()], updatedAt: "2026-04-30T10:00:00Z")
        let date = fixedDate("2026-04-30T10:00:00Z")

        XCTAssertEqual(
            TuneAVLibrarySyncPlanner.decision(
                localSnapshot: snapshot,
                localUpdatedAt: date,
                remoteDocument: libraryDocument(snapshot: snapshot, updatedAt: date)
            ),
            .alreadyCurrent
        )
    }

    func testLibrarySnapshotMergerKeepsFavoritesFromBothDevices() {
        let local = librarySnapshot(
            favorites: [
                favoriteRecord(id: "skyrock", createdAt: "2026-04-30T10:00:00Z"),
                favoriteRecord(id: "los-40", createdAt: "2026-04-30T10:01:00Z")
            ],
            updatedAt: "2026-04-30T10:01:00Z"
        )
        let remote = librarySnapshot(
            favorites: [
                favoriteRecord(id: "bbc-radio-1", createdAt: "2026-04-30T09:00:00Z"),
                favoriteRecord(id: "somafm", createdAt: "2026-04-30T09:01:00Z")
            ],
            updatedAt: "2026-04-30T09:01:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(
            Set(merged.favorites.map(\.station.id)),
            ["bbc-radio-1", "somafm", "skyrock", "los-40"]
        )
    }

    func testLibrarySnapshotMergerDeduplicatesStationsWithDifferentIDsButSameStream() {
        let local = librarySnapshot(
            favorites: [
                favoriteRecord(
                    id: "demo-groove-salad",
                    streamURL: "https://ice1.somafm.com/groovesalad-128-mp3",
                    createdAt: "2026-04-30T09:00:00Z"
                )
            ],
            updatedAt: "2026-04-30T09:00:00Z"
        )
        let remote = librarySnapshot(
            favorites: [
                favoriteRecord(
                    id: "groove-salad",
                    streamURL: "https://ice1.somafm.com/groovesalad-128-mp3",
                    createdAt: "2026-04-30T10:00:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:00:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.favorites.count, 1)
        XCTAssertEqual(merged.favorites.first?.station.id, "groove-salad")
    }

    func testLibrarySnapshotMergerKeepsFavoriteDeletionWhenItIsNewestChange() {
        let local = librarySnapshot(
            favorites: [
                favoriteRecord(
                    id: "groove-salad",
                    streamURL: "https://ice1.somafm.com/groovesalad-128-mp3",
                    deletedAt: "2026-04-30T10:30:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:30:00Z"
        )
        let remote = librarySnapshot(
            favorites: [
                favoriteRecord(
                    id: "groove-salad",
                    streamURL: "https://ice1.somafm.com/groovesalad-128-mp3",
                    createdAt: "2026-04-30T10:00:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:00:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.favorites.count, 1)
        XCTAssertEqual(merged.favorites.first?.deletedAt, "2026-04-30T10:30:00Z")
    }

    func testLibrarySnapshotMergerKeepsNewestSavedDiscoveryAction() {
        let local = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    markedInterestedAt: "2026-04-30T10:05:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:05:00Z"
        )
        let remote = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    markedInterestedAt: "2026-04-30T10:10:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:10:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.savedDiscoveries.count, 1)
        XCTAssertEqual(merged.savedDiscoveries.first?.markedInterestedAt, "2026-04-30T10:10:00Z")
    }

    func testLibrarySnapshotMergerKeepsSavedDiscoveryUnsaveWhenUpdatedAtIsNewest() {
        let local = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    updatedAt: "2026-04-30T10:30:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:30:00Z"
        )
        let remote = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    markedInterestedAt: "2026-04-30T10:05:00Z",
                    updatedAt: "2026-04-30T10:05:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:05:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.savedDiscoveries.count, 1)
        XCTAssertNil(merged.savedDiscoveries.first?.markedInterestedAt)
        XCTAssertEqual(merged.savedDiscoveries.first?.updatedAt, "2026-04-30T10:30:00Z")
    }

    func testLibrarySnapshotMergerKeepsSavedDiscoveryDeletionWhenItIsNewestChange() {
        let local = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    deletedAt: "2026-04-30T10:30:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:30:00Z"
        )
        let remote = librarySnapshot(
            savedDiscoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    markedInterestedAt: "2026-04-30T10:05:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:05:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.savedDiscoveries.count, 1)
        XCTAssertEqual(merged.savedDiscoveries.first?.deletedAt, "2026-04-30T10:30:00Z")
        XCTAssertNil(merged.savedDiscoveries.first?.markedInterestedAt)
    }

    @MainActor
    func testDailyFeatureCountersBlockAtGuestLimit() {
        let userDefaults = isolatedUserDefaults()
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
            accountProfileResolver: StubAccountProfileResolver(),
            entitlementService: StubEntitlementService(access: .guest),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        XCTAssertTrue(controller.canUseDailyFeature(.lyricsSearch))
        XCTAssertEqual(controller.dailyLimitState(for: .lyricsSearch).remaining, 5)

        for _ in 0..<5 {
            controller.recordDailyFeatureUse(.lyricsSearch)
        }

        XCTAssertFalse(controller.canUseDailyFeature(.lyricsSearch))
        XCTAssertEqual(controller.dailyLimitState(for: .lyricsSearch).remaining, 0)
    }

    @MainActor
    func testDailyFeatureCountersResetOnNextDay() {
        let userDefaults = isolatedUserDefaults()
        var currentDate = fixedDate("2026-04-30T10:00:00Z")
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
            accountProfileResolver: StubAccountProfileResolver(),
            entitlementService: StubEntitlementService(access: .guest),
            userDefaults: userDefaults,
            now: { currentDate }
        )

        controller.recordDailyFeatureUse(.youtubeSearch)
        XCTAssertEqual(controller.dailyLimitState(for: .youtubeSearch).remaining, 4)

        currentDate = fixedDate("2026-05-01T10:00:00Z")

        XCTAssertTrue(controller.canUseDailyFeature(.youtubeSearch))
        XCTAssertEqual(controller.dailyLimitState(for: .youtubeSearch).remaining, 5)
    }

    @MainActor
    func testDailyMusicActionCountersUseOneAviActionBudget() {
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
            accountProfileResolver: StubAccountProfileResolver(),
            entitlementService: StubEntitlementService(access: .guest),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        let musicActions: [LimitedFeature] = [
            .lyricsSearch,
            .webSearch,
            .youtubeSearch,
            .appleMusicSearch,
            .spotifySearch
        ]

        for feature in musicActions {
            XCTAssertEqual(controller.dailyLimitState(for: feature).remaining, 5)
        }

        for _ in 0..<4 {
            controller.recordDailyFeatureUse(.lyricsSearch)
        }
        controller.recordDailyFeatureUse(.youtubeSearch)

        XCTAssertEqual(controller.dailyLimitState(for: .lyricsSearch).remaining, 0)
        XCTAssertEqual(controller.dailyLimitState(for: .webSearch).remaining, 0)
        XCTAssertEqual(controller.dailyLimitState(for: .youtubeSearch).remaining, 0)
        XCTAssertEqual(controller.dailyLimitState(for: .appleMusicSearch).remaining, 0)
        XCTAssertEqual(controller.dailyLimitState(for: .spotifySearch).remaining, 0)
    }

    @MainActor
    func testDailyFeatureUsageKeysOnlyCountUniqueUses() {
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
            accountProfileResolver: StubAccountProfileResolver(),
            entitlementService: StubEntitlementService(access: .guest),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        let lyricsURL = "https://www.google.com/search?q=artist%20song%20lyrics"
        XCTAssertTrue(controller.canUseDailyFeature(.lyricsSearch, usageKey: lyricsURL))

        controller.recordDailyFeatureUse(.lyricsSearch, usageKey: lyricsURL)
        controller.recordDailyFeatureUse(.lyricsSearch, usageKey: lyricsURL)
        controller.recordDailyFeatureUse(.lyricsSearch, usageKey: "  \(lyricsURL.uppercased())  ")

        XCTAssertEqual(controller.dailyLimitState(for: .lyricsSearch).remaining, 4)

        controller.recordDailyFeatureUse(.lyricsSearch, usageKey: "https://www.google.com/search?q=other%20song%20lyrics")
        XCTAssertEqual(controller.dailyLimitState(for: .lyricsSearch).remaining, 3)
    }

    @MainActor
    func testPreviouslyUsedDailyFeatureKeyRemainsAllowedAfterLimitIsReached() {
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
            accountProfileResolver: StubAccountProfileResolver(),
            entitlementService: StubEntitlementService(access: .guest),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        let usedURL = "https://www.google.com/search?q=artist%20song%20lyrics"
        let usageKeys = [
            usedURL,
            "https://www.google.com/search?q=artist%20song%202%20lyrics",
            "https://www.youtube.com/results?search_query=artist%20song",
            "https://www.google.com/search?q=artist%20song%203%20lyrics",
            "https://www.google.com/search?q=artist%20song%204%20lyrics"
        ]

        for usageKey in usageKeys {
            XCTAssertTrue(controller.canUseDailyFeature(.lyricsSearch, usageKey: usageKey))
            controller.recordDailyFeatureUse(.lyricsSearch, usageKey: usageKey)
        }

        XCTAssertEqual(controller.dailyLimitState(for: .lyricsSearch).remaining, 0)
        XCTAssertTrue(controller.canUseDailyFeature(.lyricsSearch, usageKey: usedURL))
        XCTAssertFalse(controller.canUseDailyFeature(.lyricsSearch, usageKey: "https://www.google.com/search?q=new%20song%20lyrics"))
    }

    @MainActor
    func testUpgradePromptUsesTheBlockedFeatureAndConfiguredLimit() {
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
            accountProfileResolver: StubAccountProfileResolver(),
            entitlementService: StubEntitlementService(access: .guest),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        controller.presentUpgradePrompt(for: .youtubeSearch, currentUsage: 5)

        XCTAssertEqual(controller.upgradePrompt?.feature, .youtubeSearch)
        XCTAssertEqual(controller.upgradePrompt?.title, L10n.string("limits.upgrade.youtube.title"))
        XCTAssertEqual(controller.upgradePrompt?.message, L10n.string("limits.upgrade.aviAction.message", 5))
    }

    @MainActor
    func testProDailyFeaturesRemainAllowedWithoutDailyLimit() async {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: ResolvedAccess(
                platformUserId: nil,
                planTier: .pro,
                accessMode: .signedInPro,
                capabilities: .forMode(.signedInPro),
                limits: .forMode(.signedInPro)
            )),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )
        await controller.syncFromAccountProvider()

        for _ in 0..<25 {
            controller.recordDailyFeatureUse(.appleMusicSearch)
        }

        XCTAssertTrue(controller.canUseDailyFeature(.appleMusicSearch))
        XCTAssertNil(controller.dailyLimitState(for: .appleMusicSearch).remaining)
    }

    @MainActor
    func testSignedInProAccountResolvesBackendPremiumAndCloudSyncCapabilities() async {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()

        XCTAssertTrue(controller.isSignedIn)
        XCTAssertFalse(controller.isLocalOnly)
        XCTAssertEqual(controller.accountUser, user)
        XCTAssertEqual(controller.accountSession?.user, user)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.capabilities, .forMode(.signedInPro))
        XCTAssertTrue(controller.capabilities.canUseBackend)
        XCTAssertTrue(controller.capabilities.canUseCloudSync)
        XCTAssertTrue(controller.capabilities.canAccessPremiumFeatures)
        XCTAssertTrue(controller.capabilities.canManagePlan)
        XCTAssertEqual(controller.limits, .forMode(.signedInPro))
        XCTAssertNil(controller.dailyLimitState(for: .lyricsSearch).remaining)
        XCTAssertNil(controller.dailyLimitState(for: .webSearch).remaining)
        XCTAssertNil(controller.dailyLimitState(for: .youtubeSearch).remaining)
        XCTAssertNil(controller.dailyLimitState(for: .appleMusicSearch).remaining)
        XCTAssertNil(controller.dailyLimitState(for: .spotifySearch).remaining)
        XCTAssertNil(controller.dailyLimitState(for: .discoveryShare).remaining)
    }

    @MainActor
    func testConcurrentAccountRefreshesShareOneProviderAndEntitlementResolution() async {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let accountProfileResolver = CountingAccountProfileResolver(user: user)
        let entitlementService = SuspendingEntitlementService(access: .signedInPro)
        entitlementService.suspendNextRefresh()
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: accountProfileResolver,
            entitlementService: entitlementService,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        let rootRefresh = Task { @MainActor in
            await controller.syncFromAccountProvider()
        }
        await entitlementService.waitUntilRefreshIsSuspended()
        let profileRefresh = Task { @MainActor in
            await controller.syncFromAccountProviderIfNeeded()
        }

        entitlementService.resumeRefresh()
        await rootRefresh.value
        await profileRefresh.value

        XCTAssertEqual(accountProfileResolver.resolveCount, 1)
        XCTAssertEqual(entitlementService.refreshCount, 1)
    }

    @MainActor
    func testRecentAccountRefreshSkipsProfileEntryRefresh() async {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let accountProfileResolver = CountingAccountProfileResolver(user: user)
        let entitlementService = SuspendingEntitlementService(access: .signedInPro)
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: accountProfileResolver,
            entitlementService: entitlementService,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()
        await controller.syncFromAccountProviderIfNeeded()

        XCTAssertEqual(accountProfileResolver.resolveCount, 1)
        XCTAssertEqual(entitlementService.refreshCount, 1)
    }

    @MainActor
    func testAccountRefreshPublishesResolvedSummaryForProfileReuse() async {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let summary = AccountSummary(
            id: user.id,
            emailAddress: user.emailAddress,
            displayName: user.displayName
        )
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user, summary: summary),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()

        XCTAssertEqual(controller.accountSummary, summary)
    }

    @MainActor
    func testExplicitAccountRefreshPromotesStaleSignedInFreeAccountToBackendPro() async {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let entitlementService = SequenceStubEntitlementService(accesses: [
            .signedInFree,
            .signedInPro
        ])
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: entitlementService,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()
        XCTAssertEqual(controller.accessMode, .signedInFree)
        XCTAssertEqual(controller.planTier, .free)

        await controller.syncFromAccountProvider()

        XCTAssertEqual(controller.accountUser, user)
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertTrue(controller.capabilities.canAccessPremiumFeatures)
        XCTAssertEqual(entitlementService.refreshCount, 2)
    }

    @MainActor
    func testSameUserAccountRefreshPreservesProCapabilitiesUntilBackendResolutionCompletes() async {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let entitlementService = SuspendingEntitlementService(access: .signedInPro)
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: entitlementService,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()
        XCTAssertEqual(controller.accessMode, .signedInPro)

        entitlementService.suspendNextRefresh()
        let refreshTask = Task { @MainActor in
            await controller.syncFromAccountProvider()
        }
        await entitlementService.waitUntilRefreshIsSuspended()

        XCTAssertTrue(controller.isRefreshingAccountAccess)
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertTrue(controller.capabilities.canUseCloudSync)

        entitlementService.resumeRefresh()
        await refreshTask.value

        XCTAssertFalse(controller.isRefreshingAccountAccess)
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertTrue(controller.capabilities.canUseCloudSync)
    }

    @MainActor
    func testAccountSwitchDropsPreviousProCapabilitiesUntilBackendResolutionCompletes() async {
        let firstUser = AccountUser(id: "first-user", displayName: "First User", emailAddress: "first@example.com")
        let secondUser = AccountUser(id: "second-user", displayName: "Second User", emailAddress: "second@example.com")
        let accountService = MutableStubAccountService(user: firstUser)
        let accountProfileResolver = MutableStubAccountProfileResolver(user: firstUser)
        let entitlementService = SuspendingEntitlementService(
            access: .signedInFree,
            refreshedAccess: .signedInPro
        )
        let controller = AccessController(
            accountService: accountService,
            accountProfileResolver: accountProfileResolver,
            entitlementService: entitlementService,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()
        XCTAssertEqual(controller.accountUser?.id, firstUser.id)
        XCTAssertEqual(controller.accessMode, .signedInPro)

        accountService.setUser(secondUser)
        accountProfileResolver.user = secondUser
        entitlementService.suspendNextRefresh()
        let refreshTask = Task { @MainActor in
            await controller.syncFromAccountProvider()
        }
        await entitlementService.waitUntilRefreshIsSuspended()

        XCTAssertEqual(controller.accountUser?.id, secondUser.id)
        XCTAssertEqual(controller.accessMode, .signedInFree)
        XCTAssertFalse(controller.capabilities.canUseCloudSync)

        entitlementService.resumeRefresh()
        await refreshTask.value

        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertTrue(controller.capabilities.canUseCloudSync)
    }

    @MainActor
    func testActiveProviderSessionPublishesInternalAccountUserId() async {
        let providerUser = AccountUser(id: "user_clerk_subject", displayName: "Clerk User", emailAddress: "clerk@example.com")
        let internalUser = AccountUser(id: "appsav-internal-user-id", displayName: "Internal User", emailAddress: "internal@example.com")
        let controller = AccessController(
            accountService: StubAccountService(user: providerUser),
            accountProfileResolver: StubAccountProfileResolver(user: internalUser),
            entitlementService: StubEntitlementService(access: .signedInFree),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()

        XCTAssertEqual(controller.accountUser?.id, "appsav-internal-user-id")
        XCTAssertEqual(controller.accountSession?.user.id, "appsav-internal-user-id")
        XCTAssertNotEqual(controller.accountUser?.id, providerUser.id)
        XCTAssertFalse(controller.isAccountSessionTemporarilyUnavailable)
    }

    @MainActor
    func testProviderSessionDoesNotPublishProviderUserIdWhenInternalResolutionFails() async {
        let providerUser = AccountUser(id: "user_clerk_subject", displayName: "Clerk User", emailAddress: "clerk@example.com")
        let controller = AccessController(
            accountService: StubAccountService(user: providerUser),
            accountProfileResolver: StubAccountProfileResolver(error: AccountProfileResolverError.missingInternalUserId),
            entitlementService: StubEntitlementService(access: .signedInFree),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()

        XCTAssertNil(controller.accountUser)
        XCTAssertNil(controller.accountSession)
        XCTAssertEqual(controller.accessMode, .guest)
        XCTAssertTrue(controller.isAccountSessionTemporarilyUnavailable)
    }

    @MainActor
    func testSignedInAccountIsPreservedWhenSessionIsTemporarilyUnavailable() async {
        let userDefaults = isolatedUserDefaults()
        let user = AccountUser(id: "stale-user", displayName: "Stale User", emailAddress: "stale@example.com")
        let signedInController = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )
        await signedInController.syncFromAccountProvider()

        let accountService = MutableStubAccountService(
            user: nil,
            restoreResult: .temporarilyUnavailable(nil)
        )
        let controller = AccessController(
            accountService: accountService,
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()

        XCTAssertTrue(controller.isSignedIn)
        XCTAssertEqual(controller.accountUser, user)
        XCTAssertEqual(controller.accountSession?.user, user)
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertTrue(controller.isAccountSessionTemporarilyUnavailable)
        XCTAssertFalse(accountService.didSignOut)
    }

    @MainActor
    func testLastKnownAccountUserPreservesColdStartDuringTemporarySessionFailure() async {
        let userDefaults = isolatedUserDefaults()
        let user = AccountUser(id: "cached-user", displayName: "Cached User", emailAddress: "cached@example.com")
        let signedInController = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await signedInController.syncFromAccountProvider()

        let restoredController = AccessController(
            accountService: MutableStubAccountService(user: nil, restoreResult: .temporarilyUnavailable(nil)),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await restoredController.syncFromAccountProvider()

        XCTAssertTrue(restoredController.isSignedIn)
        XCTAssertEqual(restoredController.accountUser, user)
        XCTAssertEqual(restoredController.accountSession?.user, user)
        XCTAssertEqual(restoredController.accessMode, .signedInPro)
        XCTAssertTrue(restoredController.isAccountSessionTemporarilyUnavailable)
    }

    @MainActor
    func testSignedInAccountIsPreservedWhenProviderReportsSignedOut() async {
        let userDefaults = isolatedUserDefaults()
        let signedOutUser = AccountUser(id: "signed-out-user", displayName: "Signed Out User", emailAddress: "signedout@example.com")
        let signedInController = AccessController(
            accountService: MutableStubAccountService(user: signedOutUser),
            accountProfileResolver: StubAccountProfileResolver(user: signedOutUser),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await signedInController.syncFromAccountProvider()

        let accountService = MutableStubAccountService(
            user: nil,
            restoreResult: .signedOut
        )
        let controller = AccessController(
            accountService: accountService,
            accountProfileResolver: StubAccountProfileResolver(user: signedOutUser),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()

        XCTAssertTrue(controller.isSignedIn)
        XCTAssertEqual(controller.accountUser, signedOutUser)
        XCTAssertEqual(controller.accountSession?.user, signedOutUser)
        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertEqual(controller.planTier, .pro)
        XCTAssertTrue(controller.isAccountSessionTemporarilyUnavailable)
        XCTAssertFalse(accountService.didSignOut)
    }

    @MainActor
    func testSignOutFromProAccountReturnsToGuestLocalOnlyAccess() async throws {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let accountService = MutableStubAccountService(
            user: user
        )
        let controller = AccessController(
            accountService: accountService,
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()
        XCTAssertEqual(controller.accessMode, .signedInPro)

        try await controller.signOut()

        XCTAssertFalse(controller.isSignedIn)
        XCTAssertTrue(controller.isLocalOnly)
        XCTAssertNil(controller.accountUser)
        XCTAssertNil(controller.accountSession)
        XCTAssertEqual(controller.planTier, .free)
        XCTAssertEqual(controller.accessMode, .guest)
        XCTAssertEqual(controller.capabilities, .forMode(.guest))
        XCTAssertEqual(controller.limits, .forMode(.guest))
    }

    @MainActor
    func testManualSignOutClearsLastKnownAccountUserSnapshot() async throws {
        let userDefaults = isolatedUserDefaults()
        let user = AccountUser(id: "snapshot-user", displayName: "Snapshot User", emailAddress: "snapshot@example.com")
        let accountService = MutableStubAccountService(user: user)
        let controller = AccessController(
            accountService: accountService,
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.syncFromAccountProvider()
        try await controller.signOut()

        let restoredController = AccessController(
            accountService: MutableStubAccountService(user: nil, restoreResult: .temporarilyUnavailable(nil)),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInPro),
            userDefaults: userDefaults,
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        XCTAssertFalse(restoredController.isSignedIn)
        XCTAssertNil(restoredController.accountUser)
        XCTAssertEqual(restoredController.accessMode, .guest)
    }

    @MainActor
    func testGuestCannotStartSubscriptionPurchaseBoundary() async {
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
            accountProfileResolver: StubAccountProfileResolver(),
            entitlementService: StubEntitlementService(access: .guest),
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.loadMonthlySubscriptionOffer()
        await controller.purchaseMonthlyPro()
        await controller.restorePurchases()

        XCTAssertEqual(controller.subscriptionError, .missingAccountUser)
        XCTAssertEqual(subscriptionPurchasing.loadedOfferUserIDs, [])
        XCTAssertEqual(subscriptionPurchasing.purchaseUserIDs, [])
        XCTAssertEqual(subscriptionPurchasing.restoreUserIDs, [])
    }

    @MainActor
    func testPurchaseStopsWaitingWhenBackendEntitlementBudgetIsExhausted() async {
        let user = AccountUser(id: "signed-in-free", displayName: "Free User", emailAddress: "free@example.com")
        let entitlementService = MutableStubEntitlementService(access: .signedInFree)
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: entitlementService,
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") },
            subscriptionReconciliationRetryDelaysNanoseconds: []
        )

        await controller.syncFromAccountProvider()
        await controller.loadMonthlySubscriptionOffer()

        XCTAssertEqual(controller.subscriptionOffer?.localizedPrice, "$4.99")
        XCTAssertEqual(subscriptionPurchasing.loadedOfferUserIDs, [user.id])

        await controller.purchaseMonthlyPro()

        XCTAssertEqual(controller.accessMode, .signedInFree)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
        XCTAssertEqual(controller.subscriptionError, .purchaseReconciliationDelayed)
        XCTAssertEqual(subscriptionPurchasing.purchaseUserIDs, [user.id])

        entitlementService.access = .signedInPro
        await controller.syncFromAccountProvider()

        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
        XCTAssertNil(controller.subscriptionError)
    }

    @MainActor
    func testSubscriptionPurchasingUsesPlatformUserIdAfterAccessRefresh() async {
        let providerUser = AccountUser(id: "clerk-user-id", displayName: "Free User", emailAddress: "free@example.com")
        let user = AccountUser(id: "appsav-internal-user-id", displayName: "Free User", emailAddress: "free@example.com")
        let entitlementService = MutableStubEntitlementService(access: ResolvedAccess(
            platformUserId: "appsav-internal-user-id",
            planTier: .free,
            accessMode: .signedInFree,
            capabilities: .forMode(.signedInFree),
            limits: .forMode(.signedInFree)
        ))
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        let controller = AccessController(
            accountService: StubAccountService(user: providerUser),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: entitlementService,
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") },
            subscriptionReconciliationRetryDelaysNanoseconds: []
        )

        await controller.syncFromAccountProvider()
        await controller.loadMonthlySubscriptionOffer()
        await controller.purchaseMonthlyPro()
        await controller.restorePurchases()

        XCTAssertEqual(controller.platformUserId, "appsav-internal-user-id")
        XCTAssertEqual(subscriptionPurchasing.loadedOfferUserIDs, ["appsav-internal-user-id"])
        XCTAssertEqual(subscriptionPurchasing.purchaseUserIDs, ["appsav-internal-user-id"])
        XCTAssertEqual(subscriptionPurchasing.restoreUserIDs, ["appsav-internal-user-id"])
        XCTAssertFalse(subscriptionPurchasing.loadedOfferUserIDs.contains(providerUser.id))
        XCTAssertFalse(subscriptionPurchasing.purchaseUserIDs.contains(providerUser.id))
        XCTAssertFalse(subscriptionPurchasing.restoreUserIDs.contains(providerUser.id))
    }

    @MainActor
    func testPurchaseRetriesAccessRefreshUntilBackendEntitlementIsVisible() async {
        let user = AccountUser(id: "signed-in-free", displayName: "Free User", emailAddress: "free@example.com")
        let entitlementService = SequenceStubEntitlementService(accesses: [
            .signedInFree,
            .signedInFree,
            .signedInPro
        ])
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        var sleepCalls: [UInt64] = []
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: entitlementService,
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") },
            subscriptionReconciliationRetryDelaysNanoseconds: [1, 2],
            sleepNanoseconds: { delay in
                sleepCalls.append(delay)
            }
        )

        await controller.syncFromAccountProvider()
        await controller.purchaseMonthlyPro()

        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
        XCTAssertEqual(entitlementService.refreshCount, 3)
        XCTAssertEqual(sleepCalls, [1])
    }

    @MainActor
    func testRestoreStopsWaitingWhenBackendEntitlementBudgetIsExhausted() async {
        let user = AccountUser(id: "signed-in-free", displayName: "Free User", emailAddress: "free@example.com")
        let entitlementService = MutableStubEntitlementService(access: .signedInFree)
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: entitlementService,
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") },
            subscriptionReconciliationRetryDelaysNanoseconds: []
        )

        await controller.syncFromAccountProvider()
        await controller.restorePurchases()

        XCTAssertEqual(controller.accessMode, .signedInFree)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
        XCTAssertEqual(controller.subscriptionError, .restoreReconciliationDelayed)
        XCTAssertEqual(subscriptionPurchasing.restoreUserIDs, [user.id])
    }

    @MainActor
    func testInactiveRevenueCatOutcomesDoNotStartBackendReconciliation() async {
        let user = AccountUser(id: "signed-in-free", displayName: "Free User", emailAddress: "free@example.com")
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        subscriptionPurchasing.purchaseError = TuneAVSubscriptionPurchaseError.purchaseNotEntitled
        subscriptionPurchasing.restoreError = TuneAVSubscriptionPurchaseError.restoreNotEntitled
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInFree),
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") },
            subscriptionReconciliationRetryDelaysNanoseconds: []
        )

        await controller.syncFromAccountProvider()
        await controller.purchaseMonthlyPro()

        XCTAssertEqual(controller.subscriptionError, .purchaseNotEntitled)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)

        await controller.restorePurchases()

        XCTAssertEqual(controller.subscriptionError, .restoreNotEntitled)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
    }

    @MainActor
    func testProviderFailureRemainsDistinctAndDoesNotStartBackendReconciliation() async {
        let user = AccountUser(id: "signed-in-free", displayName: "Free User", emailAddress: "free@example.com")
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        subscriptionPurchasing.purchaseError = .underlying("Provider unavailable")
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: StubEntitlementService(access: .signedInFree),
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") },
            subscriptionReconciliationRetryDelaysNanoseconds: []
        )

        await controller.syncFromAccountProvider()
        await controller.purchaseMonthlyPro()

        XCTAssertEqual(controller.subscriptionError, .underlying("Provider unavailable"))
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
    }

    @MainActor
    func testPromotionCodeClaimUsesBackendRedeemerAndRefreshesAccess() async throws {
        let user = AccountUser(id: "signed-in-free", displayName: "Free User", emailAddress: "free@example.com")
        let entitlementService = MutableStubEntitlementService(access: .signedInFree)
        let promotionCodeRedeemer = StubPromotionCodeRedeemer()
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            accountProfileResolver: StubAccountProfileResolver(user: user),
            entitlementService: entitlementService,
            subscriptionPurchasing: StubSubscriptionPurchasing(),
            promotionCodeRedeemer: promotionCodeRedeemer,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") },
            subscriptionReconciliationRetryDelaysNanoseconds: []
        )

        await controller.syncFromAccountProvider()
        try await controller.claimPromotionCode(" tune-pro-2026 ")

        XCTAssertEqual(promotionCodeRedeemer.codes, ["tune-pro-2026"])
        XCTAssertEqual(controller.accessMode, .signedInFree)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
        XCTAssertEqual(controller.subscriptionError, .redemptionReconciliationDelayed)

        entitlementService.access = .signedInPro
        await controller.syncFromAccountProvider()

        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
    }

    private func isolatedUserDefaults() -> UserDefaults {
        let suiteName = "AccessLimitsTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func loadAccessPolicyContract() throws -> AccessPolicyContract {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let contractURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/contracts/access-policy.json")
        let data = try Data(contentsOf: contractURL)
        return try JSONDecoder().decode(AccessPolicyContract.self, from: data)
    }

    private func fixedDate(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    private func libraryDocument(
        snapshot: TuneAVLibrarySnapshot?,
        updatedAt: Date
    ) -> TuneAVLibraryDocument {
        TuneAVLibraryDocument(
            snapshot: snapshot,
            updatedAt: updatedAt,
            revision: 1,
            etag: "\"revision-1\""
        )
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
        id: String = "station",
        streamURL: String? = nil,
        createdAt: String? = "2026-04-30T10:00:00Z",
        deletedAt: String? = nil
    ) -> FavoriteStationRecord {
        FavoriteStationRecord(
            station: stationRecord(id: id, streamURL: streamURL),
            createdAt: createdAt,
            deletedAt: deletedAt
        )
    }

    private func recentRecord(
        id: String = "station",
        lastPlayedAt: String? = "2026-04-30T10:00:00Z",
        deletedAt: String? = nil
    ) -> RecentStationRecord {
        RecentStationRecord(
            station: stationRecord(id: id),
            lastPlayedAt: lastPlayedAt,
            deletedAt: deletedAt
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

    private func stationRecord(id: String = "station", streamURL: String? = nil) -> StationRecord {
        StationRecord(
            id: id,
            name: "Station \(id)",
            country: "Spain",
            countryCode: "ES",
            state: nil,
            language: "Spanish",
            languageCodes: "es",
            tags: "radio",
            streamURL: streamURL ?? "https://example.com/\(id).mp3",
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

private struct AccessPolicyContract: Decodable {
    let appId: String
    let schemaVersion: Int
    let accessModes: [String: AccessPolicyModeContract]
}

private struct AccessPolicyModeContract: Decodable {
    let planTier: String
    let capabilities: AccessCapabilitiesContract
    let limits: AccessLimitsContract
}

private struct AccessCapabilitiesContract: Decodable {
    let isSignedIn: Bool
    let canUseBackend: Bool
    let canUsePremiumFeatures: Bool
    let canUseCloudSync: Bool
    let canManagePlan: Bool

    var tuneavValue: AccessCapabilities {
        AccessCapabilities(
            isSignedIn: isSignedIn,
            canUseBackend: canUseBackend,
            canAccessPremiumFeatures: canUsePremiumFeatures,
            canUseCloudSync: canUseCloudSync,
            canManagePlan: canManagePlan
        )
    }
}

private struct AccessLimitsContract: Decodable {
    let favoriteStations: Int?
    let recentStations: Int?
    let discoveredTracks: Int?
    let savedTracks: Int?
    let aviActionsPerDay: Int?
    let lyricsSearchesPerDay: Int?
    let webSearchesPerDay: Int?
    let youtubeSearchesPerDay: Int?
    let appleMusicSearchesPerDay: Int?
    let spotifySearchesPerDay: Int?
    let discoverySharesPerDay: Int?

    var tuneavValue: AccessLimits {
        AccessLimits(
            favoriteStations: favoriteStations,
            recentStations: recentStations,
            discoveredTracks: discoveredTracks,
            savedTracks: savedTracks,
            aviActionsPerDay: aviActionsPerDay,
            lyricsSearchesPerDay: lyricsSearchesPerDay,
            webSearchesPerDay: webSearchesPerDay ?? youtubeSearchesPerDay,
            youtubeSearchesPerDay: youtubeSearchesPerDay,
            appleMusicSearchesPerDay: appleMusicSearchesPerDay,
            spotifySearchesPerDay: spotifySearchesPerDay,
            discoverySharesPerDay: discoverySharesPerDay
        )
    }
}

@MainActor
private struct StubAccountService: AVAccountService {
    let user: AccountUser?
    var token: String? = "test-token"

    var isAvailable: Bool { true }
    var providerSessionUser: AccountUser? { user }

    func restoreSession() async -> AVAccountSessionRestoreResult {
        guard let user else { return .signedOut }
        return .active(user)
    }

    func getToken() async throws -> String? {
        token
    }

    func signInWithApple() async throws {}

    func signInWithGoogle() async throws {}

    func signOut() async throws {}
}

@MainActor
private struct StubAccountProfileResolver: AccountProfileResolving {
    var user: AccountUser?
    var error: Error?
    var summary: AccountSummary?

    init(user: AccountUser? = nil, error: Error? = nil, summary: AccountSummary? = nil) {
        self.user = user
        self.error = error
        self.summary = summary
    }

    func resolveCurrentAccountUser() async throws -> AccountUser {
        if let error {
            throw error
        }
        guard let user else {
            throw AccountProfileResolverError.missingInternalUserId
        }
        return user
    }

    func resolvedAccountSummary(for userID: String) -> AccountSummary? {
        guard summary?.id == userID else { return nil }
        return summary
    }
}

@MainActor
private final class CountingAccountProfileResolver: AccountProfileResolving {
    let user: AccountUser
    private(set) var resolveCount = 0

    init(user: AccountUser) {
        self.user = user
    }

    func resolveCurrentAccountUser() async throws -> AccountUser {
        resolveCount += 1
        return user
    }
}

@MainActor
private final class MutableStubAccountProfileResolver: AccountProfileResolving {
    var user: AccountUser

    init(user: AccountUser) {
        self.user = user
    }

    func resolveCurrentAccountUser() async throws -> AccountUser {
        user
    }
}

@MainActor
private struct StubEntitlementService: EntitlementService {
    let access: ResolvedAccess

    func resolveAccess(for user: AccountUser?) -> ResolvedAccess {
        user == nil ? .guest : access
    }

    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess {
        resolveAccess(for: user)
    }
}

@MainActor
private final class MutableStubEntitlementService: EntitlementService {
    var access: ResolvedAccess

    init(access: ResolvedAccess) {
        self.access = access
    }

    func resolveAccess(for user: AccountUser?) -> ResolvedAccess {
        user == nil ? .guest : access
    }

    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess {
        resolveAccess(for: user)
    }
}

@MainActor
private final class SequenceStubEntitlementService: EntitlementService {
    private let accesses: [ResolvedAccess]
    private(set) var refreshCount = 0

    init(accesses: [ResolvedAccess]) {
        self.accesses = accesses
    }

    func resolveAccess(for user: AccountUser?) -> ResolvedAccess {
        user == nil ? .guest : accesses.first ?? .signedInFree
    }

    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess {
        guard user != nil else { return .guest }
        defer { refreshCount += 1 }
        return accesses[min(refreshCount, accesses.count - 1)]
    }
}

@MainActor
private final class SuspendingEntitlementService: EntitlementService {
    private let access: ResolvedAccess
    private let refreshedAccess: ResolvedAccess
    private var shouldSuspendNextRefresh = false
    private var refreshIsSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var refreshCount = 0

    init(access: ResolvedAccess, refreshedAccess: ResolvedAccess? = nil) {
        self.access = access
        self.refreshedAccess = refreshedAccess ?? access
    }

    func resolveAccess(for user: AccountUser?) -> ResolvedAccess {
        user == nil ? .guest : access
    }

    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess {
        guard user != nil else { return .guest }
        refreshCount += 1
        if shouldSuspendNextRefresh {
            shouldSuspendNextRefresh = false
            refreshIsSuspended = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            refreshIsSuspended = false
        }
        return refreshedAccess
    }

    func suspendNextRefresh() {
        shouldSuspendNextRefresh = true
    }

    func waitUntilRefreshIsSuspended() async {
        while !refreshIsSuspended {
            await Task.yield()
        }
    }

    func resumeRefresh() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class MutableStubAccountService: AVAccountService {
    private var user: AccountUser?
    private let token: String?
    private let restoreResult: AVAccountSessionRestoreResult?
    private(set) var didSignOut = false

    init(user: AccountUser?, token: String? = "test-token", restoreResult: AVAccountSessionRestoreResult? = nil) {
        self.user = user
        self.token = token
        self.restoreResult = restoreResult
    }

    var isAvailable: Bool { true }
    var providerSessionUser: AccountUser? { user }

    func restoreSession() async -> AVAccountSessionRestoreResult {
        if let restoreResult {
            return restoreResult
        }
        guard let user else { return .signedOut }
        return .active(user)
    }

    func getToken() async throws -> String? {
        token
    }

    func signInWithApple() async throws {}

    func signInWithGoogle() async throws {}

    func signOut() async throws {
        didSignOut = true
        user = nil
    }

    func setUser(_ user: AccountUser?) {
        self.user = user
    }
}

@MainActor
private final class StubSubscriptionPurchasing: TuneAVSubscriptionPurchasing {
    private(set) var loadedOfferUserIDs: [String] = []
    private(set) var purchaseUserIDs: [String] = []
    private(set) var restoreUserIDs: [String] = []
    var purchaseError: TuneAVSubscriptionPurchaseError?
    var restoreError: TuneAVSubscriptionPurchaseError?

    func prepare(for user: AccountUser?) async throws {
        _ = try userID(user)
    }

    func loadMonthlyOffer(for user: AccountUser?) async throws -> TuneAVSubscriptionOffer {
        let id = try userID(user)
        loadedOfferUserIDs.append(id)
        return TuneAVSubscriptionOffer(
            identifier: "$rc_monthly",
            productIdentifier: "tuneav_pro_monthly",
            localizedTitle: "Tune AV Pro",
            localizedPrice: "$4.99"
        )
    }

    func purchaseMonthlyPro(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        let id = try userID(user)
        purchaseUserIDs.append(id)
        if let purchaseError {
            throw purchaseError
        }
        return TuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: id)
    }

    func restorePurchases(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        let id = try userID(user)
        restoreUserIDs.append(id)
        if let restoreError {
            throw restoreError
        }
        return TuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: id)
    }

    private func userID(_ user: AccountUser?) throws -> String {
        guard let id = user?.id else {
            throw TuneAVSubscriptionPurchaseError.missingAccountUser
        }
        return id
    }
}

@MainActor
private final class StubPromotionCodeRedeemer: TuneAVPromotionCodeRedeeming {
    private(set) var codes: [String] = []
    var error: Error?

    func redeemPromotionCode(_ code: String) async throws -> TuneAVPromoCodeRedemptionResponse {
        if let error {
            throw error
        }
        codes.append(code)
        return TuneAVPromoCodeRedemptionResponse(
            appId: "tuneav",
            userId: "signed-in-free",
            code: code,
            campaignId: "campaign-1",
            redemptionId: "redemption-1",
            entitlement: TuneAVPromoCodeEntitlement(
                appId: "tuneav",
                userId: "signed-in-free",
                planTier: "pro",
                accessMode: "signedInPro",
                status: "active",
                source: "promo"
            )
        )
    }
}

private extension ResolvedAccess {
    static let signedInFree = ResolvedAccess(
        platformUserId: nil,
        planTier: .free,
        accessMode: .signedInFree,
        capabilities: .forMode(.signedInFree),
        limits: .forMode(.signedInFree)
    )

    static let signedInPro = ResolvedAccess(
        platformUserId: nil,
        planTier: .pro,
        accessMode: .signedInPro,
        capabilities: .forMode(.signedInPro),
        limits: .forMode(.signedInPro)
    )
}
