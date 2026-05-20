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

    func testRootStartupSyncPolicyAllowsAutomaticLibrarySyncAfterInterval() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = RootStartupSyncPolicy(
            accountIsAvailable: true,
            isSignedIn: true,
            lastLibrarySyncRequestedAt: now.addingTimeInterval(-RootStartupSyncPolicy.automaticLibrarySyncInterval),
            now: now
        )

        XCTAssertTrue(policy.shouldRefreshAccountState)
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

        XCTAssertEqual(limits.favoriteStations, 500)
        XCTAssertEqual(limits.recentStations, 200)
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

    func testLibrarySnapshotMergerKeepsNewestRecentForSameStation() {
        let local = librarySnapshot(
            recents: [recentRecord(id: "los-40", lastPlayedAt: "2026-04-30T10:10:00Z")],
            updatedAt: "2026-04-30T10:10:00Z"
        )
        let remote = librarySnapshot(
            recents: [recentRecord(id: "los-40", lastPlayedAt: "2026-04-30T09:10:00Z")],
            updatedAt: "2026-04-30T09:10:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.recents.count, 1)
        XCTAssertEqual(merged.recents.first?.lastPlayedAt, "2026-04-30T10:10:00Z")
    }

    func testLibrarySnapshotMergerKeepsRecentDeletionWhenItIsNewestChange() {
        let local = librarySnapshot(
            recents: [recentRecord(id: "los-40", deletedAt: "2026-04-30T10:30:00Z")],
            updatedAt: "2026-04-30T10:30:00Z"
        )
        let remote = librarySnapshot(
            recents: [recentRecord(id: "los-40", lastPlayedAt: "2026-04-30T10:10:00Z")],
            updatedAt: "2026-04-30T10:10:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.recents.count, 1)
        XCTAssertEqual(merged.recents.first?.deletedAt, "2026-04-30T10:30:00Z")
    }

    func testLibrarySnapshotMergerKeepsNewestDiscoveryAction() {
        let local = librarySnapshot(
            discoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    markedInterestedAt: "2026-04-30T10:05:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:05:00Z"
        )
        let remote = librarySnapshot(
            discoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    hiddenAt: "2026-04-30T10:10:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:10:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.discoveries.count, 1)
        XCTAssertEqual(merged.discoveries.first?.hiddenAt, "2026-04-30T10:10:00Z")
        XCTAssertNil(merged.discoveries.first?.markedInterestedAt)
    }

    func testLibrarySnapshotMergerKeepsDiscoveryDeletionWhenItIsNewestChange() {
        let local = librarySnapshot(
            discoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    deletedAt: "2026-04-30T10:30:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:30:00Z"
        )
        let remote = librarySnapshot(
            discoveries: [
                discoveryRecord(
                    id: "los-40-track",
                    playedAt: "2026-04-30T10:00:00Z",
                    markedInterestedAt: "2026-04-30T10:05:00Z"
                )
            ],
            updatedAt: "2026-04-30T10:05:00Z"
        )

        let merged = TuneAVLibrarySnapshotMerger.merged(local: local, remote: remote)

        XCTAssertEqual(merged.discoveries.count, 1)
        XCTAssertEqual(merged.discoveries.first?.deletedAt, "2026-04-30T10:30:00Z")
        XCTAssertNil(merged.discoveries.first?.markedInterestedAt)
    }

    @MainActor
    func testDailyFeatureCountersBlockAtGuestLimit() {
        let userDefaults = isolatedUserDefaults()
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
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
    func testProDailyFeaturesRemainAllowedWithoutDailyLimit() {
        let user = AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            entitlementService: StubEntitlementService(access: ResolvedAccess(
                planTier: .pro,
                accessMode: .signedInPro,
                capabilities: .forMode(.signedInPro),
                limits: .forMode(.signedInPro)
            )),
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

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
    func testSignOutFromProAccountReturnsToGuestLocalOnlyAccess() async throws {
        let accountService = MutableStubAccountService(
            user: AccountUser(id: "pro-user", displayName: "Pro User", emailAddress: "pro@example.com")
        )
        let controller = AccessController(
            accountService: accountService,
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
    func testGuestCannotStartSubscriptionPurchaseBoundary() async {
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        let controller = AccessController(
            accountService: StubAccountService(user: nil),
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
    func testPurchaseRefreshesAccessAndWaitsForBackendEntitlementAuthority() async {
        let user = AccountUser(id: "signed-in-free", displayName: "Free User", emailAddress: "free@example.com")
        let entitlementService = MutableStubEntitlementService(access: .signedInFree)
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            entitlementService: entitlementService,
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.loadMonthlySubscriptionOffer()

        XCTAssertEqual(controller.subscriptionOffer?.localizedPrice, "$4.99")
        XCTAssertEqual(subscriptionPurchasing.loadedOfferUserIDs, [user.id])

        await controller.purchaseMonthlyPro()

        XCTAssertEqual(controller.accessMode, .signedInFree)
        XCTAssertTrue(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertEqual(controller.subscriptionReconciliationSource, .purchase)
        XCTAssertEqual(subscriptionPurchasing.purchaseUserIDs, [user.id])

        entitlementService.access = .signedInPro
        await controller.syncFromAccountProvider()

        XCTAssertEqual(controller.accessMode, .signedInPro)
        XCTAssertFalse(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertNil(controller.subscriptionReconciliationSource)
    }

    @MainActor
    func testRestoreRefreshesAccessWithRestoreReconciliationSource() async {
        let user = AccountUser(id: "signed-in-free", displayName: "Free User", emailAddress: "free@example.com")
        let entitlementService = MutableStubEntitlementService(access: .signedInFree)
        let subscriptionPurchasing = StubSubscriptionPurchasing()
        let controller = AccessController(
            accountService: StubAccountService(user: user),
            entitlementService: entitlementService,
            subscriptionPurchasing: subscriptionPurchasing,
            userDefaults: isolatedUserDefaults(),
            now: { self.fixedDate("2026-04-30T10:00:00Z") }
        )

        await controller.restorePurchases()

        XCTAssertEqual(controller.accessMode, .signedInFree)
        XCTAssertTrue(controller.isWaitingForSubscriptionReconciliation)
        XCTAssertEqual(controller.subscriptionReconciliationSource, .restore)
        XCTAssertEqual(subscriptionPurchasing.restoreUserIDs, [user.id])
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
        recents: [RecentStationRecord] = [],
        discoveries: [DiscoveredTrackRecord] = [],
        updatedAt: String
    ) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: favorites,
            recents: recents,
            discoveries: discoveries,
            settings: AppSettingsRecord(
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
        deletedAt: String? = nil
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
            deletedAt: deletedAt
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

    var isAvailable: Bool { true }
    var currentUser: AccountUser? { user }

    func getToken() async throws -> String? {
        nil
    }

    func signInWithApple() async throws {}

    func signInWithGoogle() async throws {}

    func signOut() async throws {}
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
private final class MutableStubAccountService: AVAccountService {
    private var user: AccountUser?

    init(user: AccountUser?) {
        self.user = user
    }

    var isAvailable: Bool { true }
    var currentUser: AccountUser? { user }

    func getToken() async throws -> String? {
        nil
    }

    func signInWithApple() async throws {}

    func signInWithGoogle() async throws {}

    func signOut() async throws {
        user = nil
    }
}

@MainActor
private final class StubSubscriptionPurchasing: TuneAVSubscriptionPurchasing {
    private(set) var loadedOfferUserIDs: [String] = []
    private(set) var purchaseUserIDs: [String] = []
    private(set) var restoreUserIDs: [String] = []

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
        return TuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: id)
    }

    func restorePurchases(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        let id = try userID(user)
        restoreUserIDs.append(id)
        return TuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: id)
    }

    private func userID(_ user: AccountUser?) throws -> String {
        guard let id = user?.id else {
            throw TuneAVSubscriptionPurchaseError.missingAccountUser
        }
        return id
    }
}

private extension ResolvedAccess {
    static let signedInFree = ResolvedAccess(
        planTier: .free,
        accessMode: .signedInFree,
        capabilities: .forMode(.signedInFree),
        limits: .forMode(.signedInFree)
    )

    static let signedInPro = ResolvedAccess(
        planTier: .pro,
        accessMode: .signedInPro,
        capabilities: .forMode(.signedInPro),
        limits: .forMode(.signedInPro)
    )
}
