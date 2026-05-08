import Foundation
import OSLog

enum BackendConnectionStatus: Equatable {
    case notConfigured
    case missingToken
    case accessRefreshFailed
    case ready

    var title: String {
        switch self {
        case .notConfigured:
            return L10n.string("mac.backend.waitingConfig")
        case .missingToken:
            return L10n.string("mac.backend.waitingToken")
        case .accessRefreshFailed:
            return L10n.string("mac.backend.accessRefreshFailed")
        case .ready:
            return L10n.string("mac.backend.ready")
        }
    }
}

enum AccountConnectionState: Equatable {
    case localOnly
    case waitingForToken
    case accessRefreshFailed
    case connectedFree
    case connectedPro

    var title: String {
        switch self {
        case .localOnly:
            return L10n.string("profile.status.guest")
        case .waitingForToken:
            return L10n.string("mac.account.waiting")
        case .accessRefreshFailed:
            return L10n.string("mac.account.refreshFailed")
        case .connectedFree:
            return L10n.string("profile.status.free")
        case .connectedPro:
            return L10n.string("profile.status.pro")
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [Station]
    @Published private(set) var recents: [Station]
    @Published private(set) var discoveries: [DiscoveredTrack]
    @Published var preferredTag: String
    @Published var preferredCountryCode: String?
    @Published private(set) var sleepTimerMinutes: Int?
    @Published private(set) var accessMode: AccessMode
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .idle
    @Published private(set) var cloudSyncConflictSummary: CloudSyncConflictSummary?
    @Published private(set) var cloudSyncFailureTitle: String?
    @Published private(set) var backendConnectionStatus: BackendConnectionStatus = .notConfigured
    @Published private(set) var backendConnectionFailureTitle: String?
    @Published var upgradePrompt: UpgradePromptContext?

    private let defaults: UserDefaults
    private let favoritesKey = "tuneav.mac.favorites"
    private let recentsKey = "tuneav.mac.recents"
    private let discoveriesKey = "tuneav.mac.discoveries"
    private let tombstonesKey = "tuneav.mac.syncTombstones"
    private let favoriteCreatedAtKey = "tuneav.mac.favoriteCreatedAt"
    private let recentLastPlayedAtKey = "tuneav.mac.recentLastPlayedAt"
    private let preferredTagKey = "tuneav.mac.preferredTag"
    private let preferredCountryKey = "tuneav.mac.preferredCountry"
    private let sleepTimerMinutesKey = "tuneav.mac.sleepTimerMinutes"
    private let lastPlayedStationIDKey = "tuneav.mac.lastPlayedStationID"
    private let accessModeKey = "tuneav.mac.accessMode"
    private let lastLocalUpdatedAtKey = "tuneav.mac.lastLocalUpdatedAt"
    private let accessController: MacAccessController
    private let dailyUsageLimiter: TuneAVDailyUsageLimiter
    private var appDataClient: MacTuneAVLibrarySyncing?
    private var backendBaseURL: URL?
    private var backendTokenProvider: (() async throws -> String?)?
    private var backendURLSession: URLSession = .shared
    private var isApplyingRemoteSnapshot = false
    private var pushTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private let syncLogger = Logger(subsystem: "com.avalsys.tuneav.mac", category: "sync")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.accessController = MacAccessController(defaults: defaults, accessModeKey: accessModeKey)
        self.dailyUsageLimiter = TuneAVDailyUsageLimiter(
            defaults: defaults,
            keyStyle: .dateScoped(prefix: "tuneav.mac.daily."),
            limitedFeatures: LimitedFeature.dailyUsageLimitedFeatures
        )
        self.favorites = Self.loadStations(forKey: favoritesKey, defaults: defaults)
        self.recents = Self.loadStations(forKey: recentsKey, defaults: defaults)
        self.discoveries = Self.loadDiscoveries(forKey: discoveriesKey, defaults: defaults)
        self.preferredTag = defaults.string(forKey: preferredTagKey) ?? ""
        self.preferredCountryCode = defaults.string(forKey: preferredCountryKey)
        self.sleepTimerMinutes = Self.optionalInt(forKey: sleepTimerMinutesKey, defaults: defaults)
        self.accessMode = accessController.accessMode
        self.favorites = TuneAVCollectionRules.trimmed(Self.loadStations(forKey: favoritesKey, defaults: defaults), limit: accessController.limits.favoriteStations)
        self.recents = TuneAVCollectionRules.trimmed(Self.loadStations(forKey: recentsKey, defaults: defaults), limit: accessController.limits.recentStations)
        self.discoveries = TuneAVCollectionRules.trimmed(Self.loadDiscoveries(forKey: discoveriesKey, defaults: defaults), limit: accessController.limits.discoveredTracks)
        self.discoveries = Self.trimmedSavedDiscoveries(self.discoveries, limit: accessController.limits.savedTracks)
    }

    var capabilities: AccessCapabilities {
        accessController.capabilities
    }

    var planTier: PlanTier {
        accessController.planTier
    }

    var limits: AccessLimits {
        accessController.limits
    }

    var lastPlayedStationID: String? {
        defaults.string(forKey: lastPlayedStationIDKey)
    }

    var isCloudSyncConfigured: Bool {
        appDataClient?.isConfigured() == true
    }

    var canRunCloudSync: Bool {
        capabilities.canUseCloudSync && isCloudSyncConfigured
    }

    var canRetryBackendConnection: Bool {
        !canRunCloudSync && backendConnectionStatus != .ready && backendBaseURL != nil && backendTokenProvider != nil
    }

    var canClearCloudSyncStatus: Bool {
        cloudSyncStatus != .idle && cloudSyncStatus != .syncing
    }

    var canResolveCloudConflict: Bool {
        cloudSyncStatus == .conflict && canRunCloudSync
    }

    var cloudSyncReadinessTitle: String {
        if canRunCloudSync {
            return L10n.string("audio.status.ready")
        }
        if backendConnectionStatus == .missingToken || backendConnectionStatus == .accessRefreshFailed {
            return backendConnectionStatus.title
        }
        if !capabilities.canUseCloudSync {
            return L10n.string("mac.sync.proOnly")
        }
        if backendConnectionStatus == .ready {
            return L10n.string("mac.sync.notConfigured")
        }
        return backendConnectionStatus.title
    }

    var cloudSyncBlockerDescription: String? {
        guard !canRunCloudSync else { return nil }

        switch backendConnectionStatus {
        case .missingToken:
            return L10n.string("mac.sync.blocker.connect")
        case .accessRefreshFailed:
            return L10n.string("mac.sync.blocker.refresh")
        case .notConfigured:
            if !capabilities.canUseCloudSync {
                return L10n.string("mac.sync.blocker.pro")
            }
            return L10n.string("mac.sync.blocker.backendConfig")
        case .ready:
            if !capabilities.canUseCloudSync {
                return L10n.string("mac.sync.blocker.pro")
            }
            return L10n.string("mac.sync.blocker.syncConfig")
        }
    }

    var accessModeIsBackendManaged: Bool {
        backendConnectionStatus == .ready
    }

    var accessModeSourceTitle: String {
        accessModeIsBackendManaged ? L10n.string("mac.backend.access") : L10n.string("mac.backend.localFallback")
    }

    var accountConnectionState: AccountConnectionState {
        switch backendConnectionStatus {
        case .notConfigured:
            return .localOnly
        case .missingToken:
            return .waitingForToken
        case .accessRefreshFailed:
            return .accessRefreshFailed
        case .ready:
            return planTier == .pro ? .connectedPro : .connectedFree
        }
    }

    var favoritesUsage: LimitUsageSummary {
        LimitUsageSummary(used: favorites.count, limit: limits.favoriteStations)
    }

    var recentsUsage: LimitUsageSummary {
        LimitUsageSummary(used: recents.count, limit: limits.recentStations)
    }

    var discoveriesUsage: LimitUsageSummary {
        LimitUsageSummary(used: discoveries.count, limit: limits.discoveredTracks)
    }

    var savedTracksUsage: LimitUsageSummary {
        LimitUsageSummary(used: savedDiscoveriesCount, limit: limits.savedTracks)
    }

    func dailyUsage(for feature: LimitedFeature) -> LimitUsageSummary {
        LimitUsageSummary(used: dailyUsageLimiter.usageCount(for: feature), limit: dailyLimit(for: feature))
    }

    func configureBackendClients(
        baseURL: URL? = MacAppConfig.avAccountAPIBaseURL,
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        refreshCloudLibrary: Bool = false
    ) async {
        let supportedBaseURL = baseURL?.isSupportedAVAccountBaseURL == true ? baseURL : nil
        backendBaseURL = supportedBaseURL
        backendTokenProvider = tokenProvider
        backendURLSession = urlSession

        guard let baseURL = supportedBaseURL else {
            backendConnectionStatus = .notConfigured
            backendConnectionFailureTitle = nil
            setAppDataClient(nil)
            return
        }
        guard let token = try? await tokenProvider(), !token.isEmpty else {
            backendConnectionStatus = .missingToken
            backendConnectionFailureTitle = nil
            setAppDataClient(nil)
            return
        }

        let accessClient = AVAccountMacAccessClient(
            baseURL: baseURL,
            tokenProvider: tokenProvider,
            urlSession: urlSession
        )
        let didRefreshAccess = await accessController.refresh(using: accessClient)
        accessMode = accessController.accessMode
        applyCurrentAccessLimits()
        guard didRefreshAccess else {
            backendConnectionStatus = accessController.lastRefreshError?.isAccessTokenFailure == true ? .missingToken : .accessRefreshFailed
            backendConnectionFailureTitle = accessController.lastRefreshError?.accessFailureTitle
            setAppDataClient(nil)
            return
        }

        backendConnectionStatus = .ready
        backendConnectionFailureTitle = nil
        cloudSyncStatus = .idle
        cloudSyncConflictSummary = nil
        cloudSyncFailureTitle = nil
        syncLogger.info("Backend ready. plan=\(String(describing: self.planTier), privacy: .public) cloud=\(self.capabilities.canUseCloudSync, privacy: .public)")
        guard capabilities.canUseCloudSync else {
            setAppDataClient(nil)
            return
        }
        setAppDataClient(
            MacTuneAVAppDataClient(
                baseURL: baseURL,
                tokenProvider: tokenProvider,
                urlSession: urlSession
            )
        )
        if refreshCloudLibrary {
            await refreshCloudLibraryIfNeeded()
        }
    }

    func retryBackendConnection() async {
        guard let backendTokenProvider else {
            backendConnectionStatus = .notConfigured
            backendConnectionFailureTitle = nil
            setAppDataClient(nil)
            return
        }

        await configureBackendClients(
            baseURL: backendBaseURL,
            tokenProvider: backendTokenProvider,
            urlSession: backendURLSession
        )
    }

    func isFavorite(_ station: Station) -> Bool {
        let identityKey = Self.stationIdentityKey(for: station)
        return favorites.contains {
            $0.id == station.id || Self.stationIdentityKey(for: $0) == identityKey
        }
    }

    func toggleFavorite(_ station: Station) {
        let identityKey = Self.stationIdentityKey(for: station)
        if let index = favorites.firstIndex(where: { $0.id == station.id || Self.stationIdentityKey(for: $0) == identityKey }) {
            rememberFavoriteDeletion(for: favorites[index])
            removeTimestamp(identityKey: Self.stationIdentityKey(for: favorites[index]), key: favoriteCreatedAtKey)
            favorites.remove(at: index)
        } else {
            if let limit = limits.favoriteStations, favorites.count >= limit {
                upgradePrompt = .favorites(current: favorites.count, limit: limit)
                return
            }

            removeTombstone(resource: "favorites", identityKey: identityKey)
            setTimestamp(.now, identityKey: identityKey, key: favoriteCreatedAtKey)
            favorites.insert(station, at: 0)
        }

        persist(stations: favorites, key: favoritesKey)
    }

    func toggleFavorite(for station: Station) {
        toggleFavorite(station)
    }

    func recordPlayback(of station: Station, recentLimit: Int? = nil) {
        removeTombstone(resource: "recents", identityKey: Self.stationIdentityKey(for: station))
        let previousRecents = recents
        recents = TuneAVCollectionRules.movingToFront(station, in: recents, limit: recentLimit ?? limits.recentStations)
        rememberRecentDeletions(forRemovedFrom: previousRecents, keeping: recents)
        setTimestamp(.now, identityKey: Self.stationIdentityKey(for: station), key: recentLastPlayedAtKey)
        defaults.set(station.id, forKey: lastPlayedStationIDKey)
        persist(stations: recents, key: recentsKey)
    }

    func isDiscoveredTrack(title: String?, artist: String?, station: Station?) -> Bool {
        discovery(for: title, artist: artist, station: station) != nil
    }

    func isSavedDiscoveredTrack(title: String?, artist: String?, station: Station?) -> Bool {
        discovery(for: title, artist: artist, station: station)?.isMarkedInteresting == true
    }

    var savedDiscoveriesCount: Int {
        discoveries.filter(\.isMarkedInteresting).count
    }

    func canMarkTrackInteresting(title: String?, artist: String?, station: Station?, limit: Int?) -> Bool {
        TuneAVSavedDiscoveryPolicy.canSaveDiscovery(
            isAlreadySaved: isSavedDiscoveredTrack(title: title, artist: artist, station: station),
            savedCount: savedDiscoveriesCount,
            limit: limit
        )
    }

    func recordDiscoveredTrack(title: String?, artist: String?, station: Station?, artworkURL: URL?, discoveryLimit: Int? = nil) {
        saveDiscoveredTrack(
            title: title,
            artist: artist,
            station: station,
            artworkURL: artworkURL,
            markInteresting: false,
            discoveryLimit: discoveryLimit
        )
    }

    func markTrackInteresting(title: String?, artist: String?, station: Station?, artworkURL: URL?, discoveryLimit: Int? = nil) {
        if let limit = limits.savedTracks, !canMarkTrackInteresting(title: title, artist: artist, station: station, limit: limit) {
            upgradePrompt = .savedTracks(current: savedDiscoveriesCount, limit: limit)
            return
        }
        saveDiscoveredTrack(
            title: title,
            artist: artist,
            station: station,
            artworkURL: artworkURL,
            markInteresting: true,
            discoveryLimit: discoveryLimit
        )
    }

    @discardableResult
    func toggleDiscoverySaved(_ discovery: DiscoveredTrack, savedLimit: Int? = nil) -> Bool {
        guard let index = discoveries.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return false }
        if discoveries[index].isMarkedInteresting {
            discoveries[index].markedInterestedAt = nil
        } else {
            let limit = savedLimit ?? limits.savedTracks
            if let limit, savedDiscoveriesCount >= limit {
                upgradePrompt = .savedTracks(current: savedDiscoveriesCount, limit: limit)
                return false
            }
            discoveries[index].markedInterestedAt = .now
            discoveries[index].hiddenAt = nil
        }
        persist(discoveries: discoveries)
        return true
    }

    @discardableResult
    func toggleDiscoveredTrackSaved(
        title: String?,
        artist: String?,
        station: Station?,
        artworkURL: URL?,
        savedLimit: Int? = nil,
        discoveryLimit: Int? = nil
    ) -> Bool {
        if let existing = discovery(for: title, artist: artist, station: station) {
            return toggleDiscoverySaved(existing, savedLimit: savedLimit)
        }
        let limit = savedLimit ?? limits.savedTracks
        if let limit, savedDiscoveriesCount >= limit {
            upgradePrompt = .savedTracks(current: savedDiscoveriesCount, limit: limit)
            return false
        }
        markTrackInteresting(title: title, artist: artist, station: station, artworkURL: artworkURL, discoveryLimit: discoveryLimit)
        return true
    }

    func hideDiscovery(_ discovery: DiscoveredTrack) {
        guard let index = discoveries.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        discoveries[index].hiddenAt = .now
        discoveries[index].markedInterestedAt = nil
        persist(discoveries: discoveries)
    }

    func restoreDiscovery(_ discovery: DiscoveredTrack) {
        guard let index = discoveries.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        discoveries[index].hiddenAt = nil
        persist(discoveries: discoveries)
    }

    func removeDiscovery(_ discovery: DiscoveredTrack) {
        rememberDiscoveryDeletion(for: discovery)
        discoveries.removeAll { $0.discoveryID == discovery.discoveryID }
        persist(discoveries: discoveries)
    }

    func clearDiscoveries() {
        for discovery in discoveries {
            rememberDiscoveryDeletion(for: discovery)
        }
        discoveries = []
        persist(discoveries: discoveries)
    }

    func station(for stationID: String?) -> Station? {
        guard let stationID else { return nil }
        return favorites.first(where: { $0.id == stationID }) ?? recents.first(where: { $0.id == stationID })
    }

    func ensureSeededStation(_ station: Station, favorite: Bool) {
        let identityKey = Self.stationIdentityKey(for: station)
        if favorite, !isFavorite(station) {
            removeTombstone(resource: "favorites", identityKey: identityKey)
            setTimestamp(.now, identityKey: identityKey, key: favoriteCreatedAtKey)
            favorites.insert(station, at: 0)
            persist(stations: favorites, key: favoritesKey)
        }

        if recents.contains(where: { $0.id == station.id || Self.stationIdentityKey(for: $0) == identityKey }) == false {
            removeTombstone(resource: "recents", identityKey: identityKey)
            setTimestamp(.now, identityKey: identityKey, key: recentLastPlayedAtKey)
            recents.insert(station, at: 0)
            persist(stations: recents, key: recentsKey)
        }

        defaults.set(station.id, forKey: lastPlayedStationIDKey)
        markLocalUpdated()
    }

    func favoriteStations() -> [Station] {
        favorites
    }

    func recentStations() -> [Station] {
        recents
    }

    func useDailyFeatureIfAllowed(_ feature: LimitedFeature) -> Bool {
        let state = dailyUsageLimiter.useIfAllowed(feature, limit: dailyLimit(for: feature))
        guard state.isAllowed else {
            upgradePrompt = .dailyFeature(feature, current: state.currentUsage, limit: state.limit ?? 0)
            return false
        }
        return true
    }

    func useDailyFeatureIfAllowed(_ feature: LimitedFeature, usageKey: String) -> Bool {
        let state = dailyUsageLimiter.useIfAllowed(feature, limit: dailyLimit(for: feature), usageKey: usageKey)
        guard state.isAllowed else {
            upgradePrompt = .dailyFeature(feature, current: state.currentUsage, limit: state.limit ?? 0)
            return false
        }
        return true
    }

    func presentUpgradePrompt(for feature: LimitedFeature, currentUsage: Int? = nil) {
        switch feature {
        case .favoriteStations:
            let limit = limits.favoriteStations ?? favorites.count
            upgradePrompt = .favorites(current: currentUsage ?? favorites.count, limit: limit)
        case .savedTracks:
            let limit = limits.savedTracks ?? savedDiscoveriesCount
            upgradePrompt = .savedTracks(current: currentUsage ?? savedDiscoveriesCount, limit: limit)
        default:
            let limit = dailyLimit(for: feature) ?? dailyUsageLimiter.usageCount(for: feature)
            upgradePrompt = .dailyFeature(
                feature,
                current: currentUsage ?? dailyUsageLimiter.usageCount(for: feature),
                limit: limit
            )
        }
    }

    func updateAccessMode(_ mode: AccessMode) {
        guard !accessModeIsBackendManaged else { return }
        accessController.updateAccessMode(mode)
        accessMode = accessController.accessMode
        if !capabilities.canUseCloudSync {
            setAppDataClient(nil)
            backendConnectionStatus = .notConfigured
            backendConnectionFailureTitle = nil
            clearBackendConnectionContext()
            cloudSyncStatus = .idle
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
        }
        applyCurrentAccessLimits()
    }

    func handleAccountSignedOut() {
        accessController.updateAccessMode(.guest)
        accessMode = accessController.accessMode
        setAppDataClient(nil)
        backendConnectionStatus = .notConfigured
        backendConnectionFailureTitle = nil
        clearBackendConnectionContext()
        cloudSyncStatus = .idle
        cloudSyncConflictSummary = nil
        cloudSyncFailureTitle = nil
        upgradePrompt = nil
        applyCurrentAccessLimits()
    }

    private func applyCurrentAccessLimits() {
        let previousFavorites = favorites
        let previousRecents = recents
        favorites = TuneAVCollectionRules.trimmed(favorites, limit: limits.favoriteStations)
        recents = TuneAVCollectionRules.trimmed(recents, limit: limits.recentStations)
        discoveries = TuneAVCollectionRules.trimmed(discoveries, limit: limits.discoveredTracks)
        discoveries = Self.trimmedSavedDiscoveries(discoveries, limit: limits.savedTracks)
        for removed in previousFavorites where !favorites.contains(where: { Self.stationIdentityKey(for: $0) == Self.stationIdentityKey(for: removed) }) {
            removeTimestamp(identityKey: Self.stationIdentityKey(for: removed), key: favoriteCreatedAtKey)
        }
        for removed in previousRecents where !recents.contains(where: { Self.stationIdentityKey(for: $0) == Self.stationIdentityKey(for: removed) }) {
            removeTimestamp(identityKey: Self.stationIdentityKey(for: removed), key: recentLastPlayedAtKey)
        }
        persist(stations: favorites, key: favoritesKey)
        persist(stations: recents, key: recentsKey)
        persist(discoveries: discoveries)
    }

    func updatePreferredTag(_ tag: String) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferredTag != trimmedTag else { return }
        preferredTag = trimmedTag
        defaults.set(trimmedTag, forKey: preferredTagKey)
        markLocalUpdated()
    }

    func setPreferredTag(_ tag: String?) {
        updatePreferredTag(tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    func updatePreferredCountryCode(_ code: String?) {
        let trimmedCode = code?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferredCountryCode != trimmedCode else { return }
        preferredCountryCode = trimmedCode
        if let trimmedCode, !trimmedCode.isEmpty {
            defaults.set(trimmedCode, forKey: preferredCountryKey)
        } else {
            preferredCountryCode = nil
            defaults.removeObject(forKey: preferredCountryKey)
        }
        markLocalUpdated()
    }

    func updateSleepTimerMinutes(_ minutes: Int?) {
        guard sleepTimerMinutes != minutes else { return }
        sleepTimerMinutes = minutes
        if let minutes {
            defaults.set(minutes, forKey: sleepTimerMinutesKey)
        } else {
            defaults.removeObject(forKey: sleepTimerMinutesKey)
        }
        markLocalUpdated()
    }

    func setPreferredCountry(_ countryCode: String?) {
        updatePreferredCountryCode(countryCode)
    }

    func clearLocalState() {
        favorites = []
        recents = []
        discoveries = []
        clearTombstones()
        preferredTag = ""
        upgradePrompt = nil
        accessController.updateAccessMode(.guest)
        accessMode = accessController.accessMode
        cloudSyncStatus = .idle
        cloudSyncConflictSummary = nil
        cloudSyncFailureTitle = nil
        backendConnectionStatus = .notConfigured
        backendConnectionFailureTitle = nil
        setAppDataClient(nil)
        clearBackendConnectionContext()
        defaults.removeObject(forKey: favoritesKey)
        defaults.removeObject(forKey: recentsKey)
        defaults.removeObject(forKey: discoveriesKey)
        defaults.removeObject(forKey: favoriteCreatedAtKey)
        defaults.removeObject(forKey: recentLastPlayedAtKey)
        defaults.set(preferredTag, forKey: preferredTagKey)
        defaults.removeObject(forKey: preferredCountryKey)
        defaults.removeObject(forKey: sleepTimerMinutesKey)
        defaults.removeObject(forKey: lastPlayedStationIDKey)
        defaults.set(accessMode.rawValue, forKey: accessModeKey)
        clearCurrentDailyUsage()
        preferredCountryCode = nil
        sleepTimerMinutes = nil
        markLocalUpdated()
    }

    func clearLocalData(propagatesToCloud: Bool = false) {
        if propagatesToCloud {
            for favorite in favorites {
                rememberFavoriteDeletion(for: favorite)
            }
            for recent in recents {
                rememberRecentDeletion(for: recent)
            }
            for discovery in discoveries {
                rememberDiscoveryDeletion(for: discovery)
            }
        }

        favorites = []
        recents = []
        discoveries = []
        if !propagatesToCloud {
            clearTombstones()
        }
        preferredTag = ""
        preferredCountryCode = nil
        sleepTimerMinutes = nil
        upgradePrompt = nil
        defaults.removeObject(forKey: favoritesKey)
        defaults.removeObject(forKey: recentsKey)
        defaults.removeObject(forKey: discoveriesKey)
        defaults.removeObject(forKey: favoriteCreatedAtKey)
        defaults.removeObject(forKey: recentLastPlayedAtKey)
        defaults.set(preferredTag, forKey: preferredTagKey)
        defaults.removeObject(forKey: preferredCountryKey)
        defaults.removeObject(forKey: sleepTimerMinutesKey)
        defaults.removeObject(forKey: lastPlayedStationIDKey)
        clearCurrentDailyUsage()
        markLocalUpdated()
    }

    func librarySnapshot() -> TuneAVLibrarySnapshot {
        let snapshotTimestamp = TuneAVDateCoding.string(from: storedLocalUpdatedAt() ?? .now)
        return TuneAVLibrarySnapshot(
            favorites: favorites.map {
                FavoriteStationRecord(
                    station: $0.appDataRecord,
                    createdAt: timestamp(identityKey: Self.stationIdentityKey(for: $0), key: favoriteCreatedAtKey)
                        .map(TuneAVDateCoding.string(from:)) ?? snapshotTimestamp
                )
            } + tombstoneRecords(resource: "favorites", type: FavoriteStationRecord.self),
            recents: recents.map {
                RecentStationRecord(
                    station: $0.appDataRecord,
                    lastPlayedAt: timestamp(identityKey: Self.stationIdentityKey(for: $0), key: recentLastPlayedAtKey)
                        .map(TuneAVDateCoding.string(from:)) ?? snapshotTimestamp
                )
            } + tombstoneRecords(resource: "recents", type: RecentStationRecord.self),
            discoveries: discoveries.map(\.appDataRecord) + tombstoneRecords(resource: "discoveries", type: DiscoveredTrackRecord.self),
            settings: AppSettingsRecord(
                preferredCountry: preferredCountryCode ?? "",
                preferredLanguage: "",
                preferredTag: preferredTag,
                lastPlayedStationID: lastPlayedStationID,
                sleepTimerMinutes: sleepTimerMinutes,
                updatedAt: snapshotTimestamp
            )
        )
    }

    func applyLibrarySnapshot(_ snapshot: TuneAVLibrarySnapshot) {
        let wasApplyingRemoteSnapshot = isApplyingRemoteSnapshot
        var nextFavorites: [Station] = []
        var nextRecents: [Station] = []
        var nextDiscoveries: [DiscoveredTrack] = []
        var nextTombstones = tombstones().filter { tombstone in
            tombstone.resource != "favorites" && tombstone.resource != "recents" && tombstone.resource != "discoveries"
        }

        for favorite in snapshot.favorites {
            if let deletedAt = favorite.deletedAt {
                let deletedIdentityKey = TuneAVLibrarySnapshotMerger.stationIdentityKey(favorite.station)
                nextFavorites.removeAll { Self.stationIdentityKey(for: $0) == deletedIdentityKey }
                nextTombstones = Self.upsertingTombstone(
                    resource: "favorites",
                    identityKey: deletedIdentityKey,
                    payload: favorite,
                    deletedAt: Self.date(from: deletedAt),
                    into: nextTombstones
                )
            } else {
                nextFavorites.append(Station(record: favorite.station))
            }
        }

        for recent in snapshot.recents {
            if let deletedAt = recent.deletedAt {
                let deletedIdentityKey = TuneAVLibrarySnapshotMerger.stationIdentityKey(recent.station)
                nextRecents.removeAll { Self.stationIdentityKey(for: $0) == deletedIdentityKey }
                nextTombstones = Self.upsertingTombstone(
                    resource: "recents",
                    identityKey: deletedIdentityKey,
                    payload: recent,
                    deletedAt: Self.date(from: deletedAt),
                    into: nextTombstones
                )
            } else {
                nextRecents.append(Station(record: recent.station))
            }
        }

        for discovery in snapshot.discoveries {
            if let deletedAt = discovery.deletedAt {
                nextDiscoveries.removeAll { $0.discoveryID == discovery.discoveryID }
                nextTombstones = Self.upsertingTombstone(
                    resource: "discoveries",
                    identityKey: discovery.discoveryID,
                    payload: discovery,
                    deletedAt: Self.date(from: deletedAt),
                    into: nextTombstones
                )
            } else {
                nextDiscoveries.append(DiscoveredTrack(record: discovery))
            }
        }

        favorites = nextFavorites
        recents = nextRecents
        discoveries = nextDiscoveries
        persist(tombstones: nextTombstones)
        preferredCountryCode = snapshot.settings.preferredCountry.isEmpty ? nil : snapshot.settings.preferredCountry
        preferredTag = snapshot.settings.preferredTag
        sleepTimerMinutes = snapshot.settings.sleepTimerMinutes
        persistTimestamps(
            snapshot.favorites.reduce(into: [String: String]()) { result, favorite in
                if let createdAt = favorite.createdAt {
                    result[TuneAVLibrarySnapshotMerger.stationIdentityKey(favorite.station)] = createdAt
                }
            },
            key: favoriteCreatedAtKey
        )
        persistTimestamps(
            snapshot.recents.reduce(into: [String: String]()) { result, recent in
                if let lastPlayedAt = recent.lastPlayedAt {
                    result[TuneAVLibrarySnapshotMerger.stationIdentityKey(recent.station)] = lastPlayedAt
                }
            },
            key: recentLastPlayedAtKey
        )

        persist(stations: favorites, key: favoritesKey)
        persist(stations: recents, key: recentsKey)
        persist(discoveries: discoveries)
        defaults.set(preferredTag, forKey: preferredTagKey)
        if let lastPlayedStationID = snapshot.settings.lastPlayedStationID {
            defaults.set(lastPlayedStationID, forKey: lastPlayedStationIDKey)
        } else {
            defaults.removeObject(forKey: lastPlayedStationIDKey)
        }
        if let preferredCountryCode {
            defaults.set(preferredCountryCode, forKey: preferredCountryKey)
        } else {
            defaults.removeObject(forKey: preferredCountryKey)
        }
        if let sleepTimerMinutes {
            defaults.set(sleepTimerMinutes, forKey: sleepTimerMinutesKey)
        } else {
            defaults.removeObject(forKey: sleepTimerMinutesKey)
        }

        if !wasApplyingRemoteSnapshot {
            markLocalUpdated()
        }
    }

    func setAppDataClient(_ client: MacTuneAVLibrarySyncing?) {
        appDataClient = client
        if client == nil {
            cloudSyncStatus = .idle
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
        }
    }

    func setAppDataService(_ service: MacTuneAVLibrarySyncing?) {
        setAppDataClient(service)
    }

    private func clearBackendConnectionContext() {
        backendBaseURL = nil
        backendTokenProvider = nil
        backendURLSession = .shared
    }

    func refreshCloudLibraryIfNeeded() async {
        guard canRunCloudSync, let appDataClient else {
            cloudSyncStatus = .idle
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
            return
        }

        var conflictSummary: CloudSyncConflictSummary?
        do {
            cloudSyncStatus = .syncing
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
            let remoteDocument = try await appDataClient.pullLibrary()
            let localSnapshot = librarySnapshot()
            conflictSummary = makeConflictSummary(localSnapshot: localSnapshot, remoteDocument: remoteDocument)
            syncLogger.info("Pulled cloud library. localFav=\(localSnapshot.favorites.count, privacy: .public) remoteFav=\(remoteDocument.snapshot?.favorites.count ?? -1, privacy: .public) localHasCollections=\(localSnapshot.hasLibraryCollections, privacy: .public) remoteHasSnapshot=\((remoteDocument.snapshot != nil), privacy: .public)")

            switch TuneAVLibrarySyncPlanner.decision(
                localSnapshot: localSnapshot,
                localUpdatedAt: latestLocalUpdatedAt(localSnapshot: localSnapshot),
                remoteDocument: remoteDocument
            ) {
            case .pullRemote(let remoteSnapshot):
                syncLogger.info("Sync decision: pullRemote remoteFav=\(remoteSnapshot.favorites.count, privacy: .public)")
                let mergedSnapshot = TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
                applyRemoteSnapshot(mergedSnapshot, updatedAt: remoteDocument.updatedAt)
                if mergedSnapshot != remoteSnapshot {
                    conflictSummary = makeConflictSummary(localSnapshot: mergedSnapshot, remoteDocument: remoteDocument)
                    try await appDataClient.pushLibrary(mergedSnapshot)
                    markLocalUpdated(scheduleCloudPush: false)
                }
            case .pushLocal:
                let snapshotToPush: TuneAVLibrarySnapshot
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToPush = TuneAVLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
                } else {
                    snapshotToPush = localSnapshot
                }
                syncLogger.info("Sync decision: pushLocal localFav=\(localSnapshot.favorites.count, privacy: .public) mergedFav=\(snapshotToPush.favorites.count, privacy: .public)")
                try await appDataClient.pushLibrary(snapshotToPush)
                if snapshotToPush != localSnapshot {
                    applyRemoteSnapshot(snapshotToPush, updatedAt: .now)
                }
                markLocalUpdated(scheduleCloudPush: false)
            case .noContent, .alreadyCurrent:
                syncLogger.info("Sync decision: noContent/alreadyCurrent")
                break
            }

            cloudSyncStatus = .synced(.now)
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
            syncLogger.info("Cloud sync finished. favorites=\(self.favorites.count, privacy: .public)")
        } catch {
            syncLogger.error("Cloud sync failed: \(String(reflecting: error), privacy: .public)")
            handleCloudSyncError(error, conflictSummary: conflictSummary)
        }
    }

    func overwriteCloudLibraryWithLocalData() async {
        guard canRunCloudSync, let appDataClient else {
            cloudSyncStatus = .idle
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
            return
        }

        var conflictSummary: CloudSyncConflictSummary?
        do {
            cloudSyncStatus = .syncing
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
            let localSnapshot = librarySnapshot()
            conflictSummary = makeConflictSummary(localSnapshot: localSnapshot, remoteDocument: nil)
            try await appDataClient.overwriteLibrary(localSnapshot)
            markLocalUpdated(scheduleCloudPush: false)
            cloudSyncStatus = .synced(.now)
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
        } catch {
            handleCloudSyncError(error, conflictSummary: conflictSummary)
        }
    }

    func replaceLocalLibraryWithCloudData() async {
        guard canRunCloudSync, let appDataClient else {
            cloudSyncStatus = .idle
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
            return
        }

        var conflictSummary: CloudSyncConflictSummary?
        do {
            cloudSyncStatus = .syncing
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
            let remoteDocument = try await appDataClient.pullLibrary()
            let localSnapshot = librarySnapshot()
            conflictSummary = makeConflictSummary(localSnapshot: localSnapshot, remoteDocument: remoteDocument)

            applyRemoteSnapshot(remoteDocument.snapshot ?? Self.emptyLibrarySnapshot, updatedAt: remoteDocument.updatedAt)

            cloudSyncStatus = .synced(.now)
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
        } catch {
            handleCloudSyncError(error, conflictSummary: conflictSummary)
        }
    }

    func clearCloudSyncStatus() {
        guard canClearCloudSyncStatus else { return }
        cloudSyncStatus = .idle
        cloudSyncConflictSummary = nil
        cloudSyncFailureTitle = nil
    }

    func setCloudSyncStatusForUITests(_ status: CloudSyncStatus) {
        guard TuneAVUITestEnvironment.current.isEnabled else {
            return
        }

        cloudSyncStatus = status
    }

    private func handleCloudSyncError(_ error: Error, conflictSummary: CloudSyncConflictSummary?) {
        if case TuneAVAppDataError.conflict = error {
            cloudSyncStatus = .conflict
            cloudSyncConflictSummary = conflictSummary
            cloudSyncFailureTitle = nil
            return
        }

        guard let appDataError = error as? MacAppDataClientError else {
            cloudSyncStatus = .failed
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = "Sync failed"
            return
        }

        switch appDataError {
        case .missingToken:
            backendConnectionStatus = .missingToken
            backendConnectionFailureTitle = nil
            setAppDataClient(nil)
        case .requestFailed(let statusCode) where statusCode == 401 || statusCode == 403:
            backendConnectionStatus = .missingToken
            backendConnectionFailureTitle = appDataError.failureTitle
            setAppDataClient(nil)
        case .missingBaseURL, .requestFailed:
            cloudSyncStatus = .failed
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = appDataError.failureTitle
        }
    }

    private func makeConflictSummary(
        localSnapshot: TuneAVLibrarySnapshot,
        remoteDocument: TuneAVLibraryDocument?
    ) -> CloudSyncConflictSummary {
        CloudSyncConflictSummary(
            localFavoritesCount: localSnapshot.favorites.count,
            localRecentsCount: localSnapshot.recents.count,
            localDiscoveriesCount: localSnapshot.discoveries.count,
            localUpdatedAt: latestLocalUpdatedAt(localSnapshot: localSnapshot),
            cloudFavoritesCount: remoteDocument?.snapshot?.favorites.count,
            cloudRecentsCount: remoteDocument?.snapshot?.recents.count,
            cloudDiscoveriesCount: remoteDocument?.snapshot?.discoveries.count,
            cloudUpdatedAt: remoteDocument?.updatedAt
        )
    }

    private static var emptyLibrarySnapshot: TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: [],
            recents: [],
            discoveries: [],
            settings: .empty
        )
    }

    private func persist(stations: [Station], key: String) {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        defaults.set(data, forKey: key)
        markLocalUpdated()
    }

    private func persist(discoveries: [DiscoveredTrack]) {
        guard let data = try? JSONEncoder().encode(discoveries) else { return }
        defaults.set(data, forKey: discoveriesKey)
        markLocalUpdated()
    }

    private static func trimmedSavedDiscoveries(_ discoveries: [DiscoveredTrack], limit: Int?) -> [DiscoveredTrack] {
        var trimmedDiscoveries = discoveries
        for index in TuneAVSavedDiscoveryPolicy.overflowSavedIndexes(in: trimmedDiscoveries, limit: limit) {
            trimmedDiscoveries[index].markedInterestedAt = nil
        }
        return trimmedDiscoveries
    }

    private func saveDiscoveredTrack(
        title: String?,
        artist: String?,
        station: Station?,
        artworkURL: URL?,
        markInteresting: Bool,
        discoveryLimit: Int? = nil
    ) {
        guard let station, let normalizedTitle = normalizedTrackValue(title) else { return }
        let normalizedArtist = normalizedTrackValue(artist)
        let discoveryID = DiscoveredTrack.makeID(title: normalizedTitle, artist: normalizedArtist, stationID: station.id)

        if let index = discoveries.firstIndex(where: { $0.discoveryID == discoveryID }) {
            removeTombstone(resource: "discoveries", identityKey: discoveryID)
            discoveries[index].playedAt = .now
            discoveries[index].artworkURL = artworkURL?.absoluteString ?? discoveries[index].artworkURL
            discoveries[index].stationArtworkURL = station.displayArtworkURL?.absoluteString ?? discoveries[index].stationArtworkURL
            if markInteresting {
                discoveries[index].markedInterestedAt = discoveries[index].markedInterestedAt ?? .now
                discoveries[index].hiddenAt = nil
            }
        } else {
            removeTombstone(resource: "discoveries", identityKey: discoveryID)
            discoveries.insert(
                DiscoveredTrack(
                    title: normalizedTitle,
                    artist: normalizedArtist,
                    station: station,
                    artworkURL: artworkURL,
                    markedInterestedAt: markInteresting ? .now : nil
                ),
                at: 0
            )
        }

        discoveries = TuneAVCollectionRules.trimmed(
            discoveries.sorted { $0.playedAt > $1.playedAt },
            limit: discoveryLimit ?? limits.discoveredTracks
        )
        persist(discoveries: discoveries)
    }

    private func discovery(for title: String?, artist: String?, station: Station?) -> DiscoveredTrack? {
        guard let station, let normalizedTitle = normalizedTrackValue(title) else { return nil }
        let normalizedArtist = normalizedTrackValue(artist)
        let discoveryID = DiscoveredTrack.makeID(title: normalizedTitle, artist: normalizedArtist, stationID: station.id)
        return discoveries.first { $0.discoveryID == discoveryID }
    }

    private func normalizedTrackValue(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)
    }

    private func clearCurrentDailyUsage() {
        dailyUsageLimiter.clearUsage(for: LimitedFeature.dailyUsageLimitedFeatures)
    }

    private func dailyLimit(for feature: LimitedFeature) -> Int? {
        guard LimitedFeature.dailyUsageLimitedFeatures.contains(feature) else { return nil }
        return limits.limit(for: feature)
    }

    private func rememberFavoriteDeletion(for station: Station) {
        let deletedAt = Date.now
        rememberTombstone(
            resource: "favorites",
            identityKey: Self.stationIdentityKey(for: station),
            payload: FavoriteStationRecord(
                station: station.appDataRecord,
                deletedAt: TuneAVDateCoding.string(from: deletedAt)
            ),
            deletedAt: deletedAt
        )
    }

    private func rememberRecentDeletion(for station: Station) {
        let deletedAt = Date.now
        rememberTombstone(
            resource: "recents",
            identityKey: Self.stationIdentityKey(for: station),
            payload: RecentStationRecord(
                station: station.appDataRecord,
                deletedAt: TuneAVDateCoding.string(from: deletedAt)
            ),
            deletedAt: deletedAt
        )
    }

    private func rememberRecentDeletions(forRemovedFrom previous: [Station], keeping current: [Station]) {
        let currentIdentityKeys = Set(current.map(Self.stationIdentityKey(for:)))
        for station in previous where !currentIdentityKeys.contains(Self.stationIdentityKey(for: station)) {
            rememberRecentDeletion(for: station)
        }
    }

    private func rememberDiscoveryDeletion(for discovery: DiscoveredTrack) {
        let deletedAt = Date.now
        rememberTombstone(
            resource: "discoveries",
            identityKey: discovery.discoveryID,
            payload: DiscoveredTrackRecord(
                discoveryID: discovery.discoveryID,
                title: discovery.title,
                artist: discovery.artist,
                stationID: discovery.stationID,
                stationName: discovery.stationName,
                artworkURL: discovery.artworkURL,
                stationArtworkURL: discovery.stationArtworkURL,
                playedAt: TuneAVDateCoding.string(from: discovery.playedAt),
                markedInterestedAt: discovery.markedInterestedAt.map(TuneAVDateCoding.string(from:)),
                hiddenAt: discovery.hiddenAt.map(TuneAVDateCoding.string(from:)),
                deletedAt: TuneAVDateCoding.string(from: deletedAt)
            ),
            deletedAt: deletedAt
        )
    }

    private func rememberTombstone<Payload: Encodable>(
        resource: String,
        identityKey: String,
        payload: Payload,
        deletedAt: Date
    ) {
        var current = tombstones()
        current = Self.upsertingTombstone(
            resource: resource,
            identityKey: identityKey,
            payload: payload,
            deletedAt: deletedAt,
            into: current
        )
        persist(tombstones: current)
    }

    private static func upsertingTombstone<Payload: Encodable>(
        resource: String,
        identityKey: String,
        payload: Payload,
        deletedAt: Date,
        into tombstones: [TuneAVLibraryTombstone]
    ) -> [TuneAVLibraryTombstone] {
        TuneAVLibraryTombstoneCoding.upserting(
            resource: resource,
            identityKey: identityKey,
            payload: payload,
            deletedAt: deletedAt,
            into: tombstones
        )
    }

    private func removeTombstone(resource: String, identityKey: String) {
        let resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        persist(tombstones: tombstones().filter { $0.resourceKey != resourceKey })
    }

    private func clearTombstones() {
        defaults.removeObject(forKey: tombstonesKey)
    }

    private func tombstoneRecords<Record: Decodable>(resource: String, type: Record.Type) -> [Record] {
        TuneAVLibraryTombstoneCoding.records(for: resource, in: tombstones(), as: type)
    }

    private func tombstones() -> [TuneAVLibraryTombstone] {
        guard let data = defaults.data(forKey: tombstonesKey) else { return [] }
        return (try? JSONDecoder().decode([TuneAVLibraryTombstone].self, from: data)) ?? []
    }

    private func persist(tombstones: [TuneAVLibraryTombstone]) {
        guard let data = try? JSONEncoder().encode(tombstones) else { return }
        defaults.set(data, forKey: tombstonesKey)
    }

    private func timestamp(identityKey: String, key: String) -> Date? {
        guard let value = timestampStrings(key: key)[identityKey] else {
            return nil
        }
        return TuneAVDateCoding.date(from: value)
    }

    private func setTimestamp(_ date: Date, identityKey: String, key: String) {
        var timestamps = timestampStrings(key: key)
        timestamps[identityKey] = TuneAVDateCoding.string(from: date)
        persistTimestamps(timestamps, key: key)
    }

    private func removeTimestamp(identityKey: String, key: String) {
        var timestamps = timestampStrings(key: key)
        timestamps.removeValue(forKey: identityKey)
        persistTimestamps(timestamps, key: key)
    }

    private func timestampStrings(key: String) -> [String: String] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func persistTimestamps(_ timestamps: [String: String], key: String) {
        guard let data = try? JSONEncoder().encode(timestamps) else { return }
        defaults.set(data, forKey: key)
    }

    private static func stationIdentityKey(for station: Station) -> String {
        TuneAVLibrarySnapshotMerger.stationIdentityKey(station.appDataRecord)
    }

    private static func date(from value: String) -> Date {
        TuneAVDateCoding.date(from: value)
    }

    private static func loadStations(forKey key: String, defaults: UserDefaults) -> [Station] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Station].self, from: data)) ?? []
    }

    private static func loadDiscoveries(forKey key: String, defaults: UserDefaults) -> [DiscoveredTrack] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DiscoveredTrack].self, from: data)) ?? []
    }

    private static func optionalInt(forKey key: String, defaults: UserDefaults) -> Int? {
        defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key)
    }

    private func applyRemoteSnapshot(_ snapshot: TuneAVLibrarySnapshot, updatedAt: Date) {
        isApplyingRemoteSnapshot = true
        applyLibrarySnapshot(snapshot)
        isApplyingRemoteSnapshot = false
        defaults.set(TuneAVDateCoding.string(from: updatedAt), forKey: lastLocalUpdatedAtKey)
    }

    private func latestLocalUpdatedAt(localSnapshot: TuneAVLibrarySnapshot) -> Date {
        guard localSnapshot.hasLibraryCollections else {
            return .distantPast
        }

        return [
            storedLocalUpdatedAt(),
            tombstones().map(\.deletedAt).max()
        ]
        .compactMap { $0 }
        .max() ?? .now
    }

    private func markLocalUpdated(scheduleCloudPush: Bool = true) {
        guard !isApplyingRemoteSnapshot else { return }
        defaults.set(TuneAVDateCoding.string(from: .now), forKey: lastLocalUpdatedAtKey)
        clearStaleSyncStatusAfterLocalMutation()
        if scheduleCloudPush {
            scheduleCloudPushIfNeeded()
        }
    }

    private func storedLocalUpdatedAt() -> Date? {
        guard let storedValue = defaults.string(forKey: lastLocalUpdatedAtKey) else {
            return nil
        }
        return TuneAVDateCoding.date(from: storedValue)
    }

    private func clearStaleSyncStatusAfterLocalMutation() {
        guard cloudSyncStatus != .syncing else { return }
        cloudSyncStatus = .idle
        cloudSyncConflictSummary = nil
        cloudSyncFailureTitle = nil
    }

    private func scheduleCloudPushIfNeeded() {
        guard canRunCloudSync, let appDataClient, !isApplyingRemoteSnapshot else {
            return
        }

        let snapshot = librarySnapshot()
        pushTask?.cancel()
        pushTask = Task { [weak self, snapshot] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.cloudSyncStatus = .syncing
                self?.cloudSyncConflictSummary = nil
                self?.cloudSyncFailureTitle = nil
            }

            do {
                let remoteDocument = try await appDataClient.pullLibrary()
                let snapshotToPush: TuneAVLibrarySnapshot
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToPush = TuneAVLibrarySnapshotMerger.merged(local: snapshot, remote: remoteSnapshot)
                } else {
                    snapshotToPush = snapshot
                }

                try await appDataClient.pushLibrary(snapshotToPush)

                await MainActor.run {
                    if snapshotToPush != snapshot {
                        self?.applyRemoteSnapshot(snapshotToPush, updatedAt: .now)
                    }
                    self?.cloudSyncStatus = .synced(.now)
                    self?.cloudSyncConflictSummary = nil
                    self?.cloudSyncFailureTitle = nil
                }
            } catch {
                await MainActor.run {
                    self?.handleCloudSyncError(error, conflictSummary: nil)
                }
            }
        }
    }

    private func scheduleCloudRefreshIfNeeded() {
        guard canRunCloudSync, !isApplyingRemoteSnapshot else {
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await self?.refreshCloudLibraryIfNeeded()
        }
    }
}

private extension Error {
    var accessFailureTitle: String? {
        guard let error = self as? MacAccessRefreshError else {
            return nil
        }
        return error.failureTitle
    }
}

private extension Error {
    var isAccessTokenFailure: Bool {
        guard let error = self as? MacAccessRefreshError else {
            return false
        }

        switch error {
        case .missingToken:
            return true
        case .requestFailed(let statusCode) where statusCode == 401 || statusCode == 403:
            return true
        case .missingBaseURL, .requestFailed, .avTunesysAccessMissing:
            return false
        }
    }
}

private extension MacAccessRefreshError {
    var failureTitle: String {
        switch self {
        case .missingToken:
            return L10n.string("mac.backend.waitingToken")
        case .missingBaseURL:
            return L10n.string("mac.backend.waitingConfig")
        case .requestFailed(let statusCode):
            return L10n.string("mac.backend.accessRequestFailed", statusCode)
        case .avTunesysAccessMissing:
            return L10n.string("mac.backend.accessMissing")
        }
    }
}

private extension MacAppDataClientError {
    var failureTitle: String {
        switch self {
        case .missingToken:
            return L10n.string("mac.backend.waitingToken")
        case .missingBaseURL:
            return L10n.string("mac.backend.waitingConfig")
        case .requestFailed(let statusCode):
            return L10n.string("mac.backend.syncRequestFailed", statusCode)
        }
    }
}
