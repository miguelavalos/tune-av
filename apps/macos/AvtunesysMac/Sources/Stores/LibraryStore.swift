import Foundation

enum CloudSyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date)
    case conflict
    case failed
}

struct CloudSyncConflictSummary: Equatable {
    let localFavoritesCount: Int
    let localRecentsCount: Int
    let localDiscoveriesCount: Int
    let localUpdatedAt: Date
    let cloudFavoritesCount: Int?
    let cloudRecentsCount: Int?
    let cloudDiscoveriesCount: Int?
    let cloudUpdatedAt: Date?

    var hasCloudSnapshot: Bool {
        cloudFavoritesCount != nil || cloudRecentsCount != nil || cloudDiscoveriesCount != nil
    }
}

struct LimitUsageSummary: Equatable {
    let used: Int
    let limit: Int?

    var title: String {
        guard let limit else {
            return "\(used) used"
        }
        return "\(used) of \(limit)"
    }
}

enum BackendConnectionStatus: Equatable {
    case notConfigured
    case missingToken
    case accessRefreshFailed
    case ready

    var title: String {
        switch self {
        case .notConfigured:
            return "Waiting for backend config"
        case .missingToken:
            return "Waiting for account token"
        case .accessRefreshFailed:
            return "Access refresh failed"
        case .ready:
            return "Backend ready"
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
            return "Local"
        case .waitingForToken:
            return "Waiting for account"
        case .accessRefreshFailed:
            return "Account refresh failed"
        case .connectedFree:
            return "Connected Free"
        case .connectedPro:
            return "Connected Pro"
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
    @Published private(set) var accessMode: AccessMode
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .idle
    @Published private(set) var cloudSyncConflictSummary: CloudSyncConflictSummary?
    @Published private(set) var cloudSyncFailureTitle: String?
    @Published private(set) var backendConnectionStatus: BackendConnectionStatus = .notConfigured
    @Published private(set) var backendConnectionFailureTitle: String?
    @Published var upgradePrompt: UpgradePromptContext?

    private let defaults: UserDefaults
    private let favoritesKey = "avtunesys.mac.favorites"
    private let recentsKey = "avtunesys.mac.recents"
    private let discoveriesKey = "avtunesys.mac.discoveries"
    private let preferredTagKey = "avtunesys.mac.preferredTag"
    private let preferredCountryKey = "avtunesys.mac.preferredCountry"
    private let accessModeKey = "avtunesys.mac.accessMode"
    private let lastLocalUpdatedAtKey = "avtunesys.mac.lastLocalUpdatedAt"
    private let accessController: MacAccessController
    private var appDataClient: MacAVTunesysLibrarySyncing?
    private var backendBaseURL: URL?
    private var backendTokenProvider: (() async throws -> String?)?
    private var backendURLSession: URLSession = .shared
    private var isApplyingRemoteSnapshot = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.accessController = MacAccessController(defaults: defaults, accessModeKey: accessModeKey)
        self.favorites = Self.loadStations(forKey: favoritesKey, defaults: defaults)
        self.recents = Self.loadStations(forKey: recentsKey, defaults: defaults)
        self.discoveries = Self.loadDiscoveries(forKey: discoveriesKey, defaults: defaults)
        self.preferredTag = defaults.string(forKey: preferredTagKey) ?? "ambient"
        self.preferredCountryCode = defaults.string(forKey: preferredCountryKey)
        self.accessMode = accessController.accessMode
        self.favorites = AVTunesysCollectionRules.trimmed(Self.loadStations(forKey: favoritesKey, defaults: defaults), limit: AccessLimits.forMode(accessMode).favoriteStations)
        self.recents = AVTunesysCollectionRules.trimmed(Self.loadStations(forKey: recentsKey, defaults: defaults), limit: AccessLimits.forMode(accessMode).recentStations)
        self.discoveries = AVTunesysCollectionRules.trimmed(Self.loadDiscoveries(forKey: discoveriesKey, defaults: defaults), limit: AccessLimits.forMode(accessMode).discoveredTracks)
        self.discoveries = Self.trimmedSavedDiscoveries(self.discoveries, limit: AccessLimits.forMode(accessMode).savedTracks)
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
            return "Ready"
        }
        if backendConnectionStatus == .missingToken || backendConnectionStatus == .accessRefreshFailed {
            return backendConnectionStatus.title
        }
        if !capabilities.canUseCloudSync {
            return "Pro only"
        }
        if backendConnectionStatus == .ready {
            return "Cloud sync not configured"
        }
        return backendConnectionStatus.title
    }

    var cloudSyncBlockerDescription: String? {
        guard !canRunCloudSync else { return nil }

        switch backendConnectionStatus {
        case .missingToken:
            return "Connect an account before syncing this Mac."
        case .accessRefreshFailed:
            return "Refresh backend access before syncing this Mac."
        case .notConfigured:
            if !capabilities.canUseCloudSync {
                return "Cloud Sync is available with Pro access."
            }
            return "Backend configuration is missing for this build."
        case .ready:
            if !capabilities.canUseCloudSync {
                return "Cloud Sync is available with Pro access."
            }
            return "Backend access is ready, but Cloud Sync is not configured."
        }
    }

    var accessModeIsBackendManaged: Bool {
        backendConnectionStatus == .ready
    }

    var accessModeSourceTitle: String {
        accessModeIsBackendManaged ? "Backend access" : "Local fallback"
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
        LimitUsageSummary(used: dailyUsageCount(for: feature), limit: dailyLimit(for: feature))
    }

    func configureBackendClients(
        baseURL: URL? = MacAppConfig.avAccountAPIBaseURL,
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared
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
        guard capabilities.canUseCloudSync else {
            setAppDataClient(nil)
            return
        }
        setAppDataClient(
            MacAVTunesysAppDataClient(
                baseURL: baseURL,
                tokenProvider: tokenProvider,
                urlSession: urlSession
            )
        )
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
        favorites.contains(where: { $0.id == station.id })
    }

    func toggleFavorite(_ station: Station) {
        if let index = favorites.firstIndex(where: { $0.id == station.id }) {
            favorites.remove(at: index)
        } else {
            if let limit = limits.favoriteStations, favorites.count >= limit {
                upgradePrompt = .favorites(current: favorites.count, limit: limit)
                return
            }

            favorites.insert(station, at: 0)
        }

        persist(stations: favorites, key: favoritesKey)
    }

    func recordPlayback(of station: Station) {
        recents = AVTunesysCollectionRules.movingToFront(station, in: recents, limit: limits.recentStations)
        persist(stations: recents, key: recentsKey)
    }

    func recordDiscoveredTrack(title: String?, artist: String?, station: Station?, artworkURL: URL?) {
        saveDiscoveredTrack(title: title, artist: artist, station: station, artworkURL: artworkURL, markInteresting: false)
    }

    func markTrackInteresting(title: String?, artist: String?, station: Station?, artworkURL: URL?) {
        if let limit = limits.savedTracks, savedDiscoveriesCount >= limit {
            upgradePrompt = .savedTracks(current: savedDiscoveriesCount, limit: limit)
            return
        }
        saveDiscoveredTrack(title: title, artist: artist, station: station, artworkURL: artworkURL, markInteresting: true)
    }

    func toggleDiscoverySaved(_ discovery: DiscoveredTrack) {
        guard let index = discoveries.firstIndex(where: { $0.discoveryID == discovery.discoveryID }) else { return }
        if discoveries[index].isMarkedInteresting {
            discoveries[index].markedInterestedAt = nil
        } else {
            if let limit = limits.savedTracks, savedDiscoveriesCount >= limit {
                upgradePrompt = .savedTracks(current: savedDiscoveriesCount, limit: limit)
                return
            }
            discoveries[index].markedInterestedAt = .now
            discoveries[index].hiddenAt = nil
        }
        persist(discoveries: discoveries)
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
        discoveries.removeAll { $0.discoveryID == discovery.discoveryID }
        persist(discoveries: discoveries)
    }

    func clearDiscoveries() {
        discoveries = []
        persist(discoveries: discoveries)
    }

    func station(for stationID: String?) -> Station? {
        guard let stationID else { return nil }
        return favorites.first(where: { $0.id == stationID }) ?? recents.first(where: { $0.id == stationID })
    }

    func useDailyFeatureIfAllowed(_ feature: LimitedFeature) -> Bool {
        guard let limit = dailyLimit(for: feature) else { return true }
        let key = dailyCounterKey(for: feature)
        let current = dailyUsageCount(for: feature)
        guard current < limit else {
            upgradePrompt = .dailyFeature(feature, current: current, limit: limit)
            return false
        }
        defaults.set(current + 1, forKey: key)
        return true
    }

    func useDailyFeatureIfAllowed(_ feature: LimitedFeature, usageKey: String) -> Bool {
        let normalizedUsageKey = Self.normalizedUsageKey(usageKey)
        guard !normalizedUsageKey.isEmpty else {
            return useDailyFeatureIfAllowed(feature)
        }

        guard let limit = dailyLimit(for: feature) else { return true }
        let keysKey = dailyUsageKeysKey(for: feature)
        var usageKeys = dailyUsageKeys(for: feature)
        if usageKeys.contains(normalizedUsageKey) {
            return true
        }

        let current = max(dailyUsageCount(for: feature), usageKeys.count)
        guard current < limit else {
            upgradePrompt = .dailyFeature(feature, current: current, limit: limit)
            return false
        }

        usageKeys.insert(normalizedUsageKey)
        let sortedUsageKeys = usageKeys.sorted()
        defaults.set(sortedUsageKeys, forKey: keysKey)
        defaults.set(max(current + 1, sortedUsageKeys.count), forKey: dailyCounterKey(for: feature))
        return true
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

    private func applyCurrentAccessLimits() {
        favorites = AVTunesysCollectionRules.trimmed(favorites, limit: limits.favoriteStations)
        recents = AVTunesysCollectionRules.trimmed(recents, limit: limits.recentStations)
        discoveries = AVTunesysCollectionRules.trimmed(discoveries, limit: limits.discoveredTracks)
        discoveries = Self.trimmedSavedDiscoveries(discoveries, limit: limits.savedTracks)
        persist(stations: favorites, key: favoritesKey)
        persist(stations: recents, key: recentsKey)
        persist(discoveries: discoveries)
    }

    func updatePreferredTag(_ tag: String) {
        guard preferredTag != tag else { return }
        preferredTag = tag
        defaults.set(tag, forKey: preferredTagKey)
        markLocalUpdated()
    }

    func updatePreferredCountryCode(_ code: String?) {
        guard preferredCountryCode != code else { return }
        preferredCountryCode = code
        if let code {
            defaults.set(code, forKey: preferredCountryKey)
        } else {
            defaults.removeObject(forKey: preferredCountryKey)
        }
        markLocalUpdated()
    }

    func clearLocalState() {
        favorites = []
        recents = []
        discoveries = []
        preferredTag = "ambient"
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
        defaults.set(preferredTag, forKey: preferredTagKey)
        defaults.removeObject(forKey: preferredCountryKey)
        defaults.set(accessMode.rawValue, forKey: accessModeKey)
        clearCurrentDailyUsage()
        preferredCountryCode = nil
        markLocalUpdated()
    }

    func librarySnapshot() -> AVTunesysLibrarySnapshot {
        let snapshotTimestamp = AVTunesysDateCoding.string(from: storedLocalUpdatedAt() ?? .now)
        return AVTunesysLibrarySnapshot(
            favorites: favorites.map {
                FavoriteStationRecord(
                    station: $0.appDataRecord,
                    createdAt: snapshotTimestamp
                )
            },
            recents: recents.map {
                RecentStationRecord(
                    station: $0.appDataRecord,
                    lastPlayedAt: snapshotTimestamp
                )
            },
            discoveries: discoveries.map(\.appDataRecord),
            settings: AppSettingsRecord(
                preferredCountry: preferredCountryCode ?? "",
                preferredLanguage: "",
                preferredTag: preferredTag,
                lastPlayedStationID: recents.first?.id,
                sleepTimerMinutes: nil,
                updatedAt: snapshotTimestamp
            )
        )
    }

    func applyLibrarySnapshot(_ snapshot: AVTunesysLibrarySnapshot) {
        let wasApplyingRemoteSnapshot = isApplyingRemoteSnapshot
        favorites = snapshot.favorites.map { Station(record: $0.station) }
        recents = snapshot.recents.map { Station(record: $0.station) }
        discoveries = snapshot.discoveries.map(DiscoveredTrack.init(record:))
        preferredCountryCode = snapshot.settings.preferredCountry.isEmpty ? nil : snapshot.settings.preferredCountry
        preferredTag = snapshot.settings.preferredTag.isEmpty ? "ambient" : snapshot.settings.preferredTag

        persist(stations: favorites, key: favoritesKey)
        persist(stations: recents, key: recentsKey)
        persist(discoveries: discoveries)
        defaults.set(preferredTag, forKey: preferredTagKey)
        if let preferredCountryCode {
            defaults.set(preferredCountryCode, forKey: preferredCountryKey)
        } else {
            defaults.removeObject(forKey: preferredCountryKey)
        }

        if !wasApplyingRemoteSnapshot {
            markLocalUpdated()
        }
    }

    func setAppDataClient(_ client: MacAVTunesysLibrarySyncing?) {
        appDataClient = client
        if client == nil {
            cloudSyncStatus = .idle
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
        }
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

            switch AVTunesysLibrarySyncPlanner.decision(
                localSnapshot: localSnapshot,
                localUpdatedAt: latestLocalUpdatedAt(localSnapshot: localSnapshot),
                remoteDocument: remoteDocument
            ) {
            case .pullRemote(let remoteSnapshot):
                let mergedSnapshot = AVTunesysLibrarySnapshotMerger.merged(local: localSnapshot, remote: remoteSnapshot)
                applyRemoteSnapshot(mergedSnapshot, updatedAt: remoteDocument.updatedAt)
                if mergedSnapshot != remoteSnapshot {
                    conflictSummary = makeConflictSummary(localSnapshot: mergedSnapshot, remoteDocument: remoteDocument)
                    try await appDataClient.pushLibrary(mergedSnapshot)
                    markLocalUpdated()
                }
            case .pushLocal:
                try await appDataClient.pushLibrary(localSnapshot)
                markLocalUpdated()
            case .noContent, .alreadyCurrent:
                break
            }

            cloudSyncStatus = .synced(.now)
            cloudSyncConflictSummary = nil
            cloudSyncFailureTitle = nil
        } catch {
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
            markLocalUpdated()
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

    private func handleCloudSyncError(_ error: Error, conflictSummary: CloudSyncConflictSummary?) {
        if case AVTunesysAppDataError.conflict = error {
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
        localSnapshot: AVTunesysLibrarySnapshot,
        remoteDocument: AVTunesysLibraryDocument?
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

    private static var emptyLibrarySnapshot: AVTunesysLibrarySnapshot {
        AVTunesysLibrarySnapshot(
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

    private var savedDiscoveriesCount: Int {
        discoveries.filter(\.isMarkedInteresting).count
    }

    private static func trimmedSavedDiscoveries(_ discoveries: [DiscoveredTrack], limit: Int?) -> [DiscoveredTrack] {
        guard let limit else { return discoveries }
        var remainingSavedTracks = limit
        return discoveries.map { discovery in
            guard discovery.isMarkedInteresting else { return discovery }
            guard remainingSavedTracks > 0 else {
                var unsavedDiscovery = discovery
                unsavedDiscovery.markedInterestedAt = nil
                return unsavedDiscovery
            }
            remainingSavedTracks -= 1
            return discovery
        }
    }

    private func saveDiscoveredTrack(title: String?, artist: String?, station: Station?, artworkURL: URL?, markInteresting: Bool) {
        guard let station, let normalizedTitle = normalizedTrackValue(title) else { return }
        let normalizedArtist = normalizedTrackValue(artist)
        let discoveryID = DiscoveredTrack.makeID(title: normalizedTitle, artist: normalizedArtist, stationID: station.id)

        if let index = discoveries.firstIndex(where: { $0.discoveryID == discoveryID }) {
            discoveries[index].playedAt = .now
            discoveries[index].artworkURL = artworkURL?.absoluteString ?? discoveries[index].artworkURL
            discoveries[index].stationArtworkURL = station.displayArtworkURL?.absoluteString ?? discoveries[index].stationArtworkURL
            if markInteresting {
                discoveries[index].markedInterestedAt = discoveries[index].markedInterestedAt ?? .now
                discoveries[index].hiddenAt = nil
            }
        } else {
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

        discoveries = AVTunesysCollectionRules.trimmed(discoveries.sorted { $0.playedAt > $1.playedAt }, limit: limits.discoveredTracks)
        persist(discoveries: discoveries)
    }

    private func normalizedTrackValue(_ value: String?) -> String? {
        AVTunesysText.normalizedValue(value)
    }

    private func dailyCounterKey(for feature: LimitedFeature) -> String {
        let day = AVTunesysDateCoding.dayIdentifier()
        return "avtunesys.mac.daily.\(feature.rawValue).\(day)"
    }

    private func dailyUsageKeysKey(for feature: LimitedFeature) -> String {
        "\(dailyCounterKey(for: feature)).keys"
    }

    private func dailyUsageKeys(for feature: LimitedFeature) -> Set<String> {
        Set(
            defaults.stringArray(forKey: dailyUsageKeysKey(for: feature))?
                .map(Self.normalizedUsageKey)
                .filter { !$0.isEmpty } ?? []
        )
    }

    private func dailyUsageCount(for feature: LimitedFeature) -> Int {
        guard Self.dailyLimitedFeatures.contains(feature) else { return 0 }
        return max(defaults.integer(forKey: dailyCounterKey(for: feature)), dailyUsageKeys(for: feature).count)
    }

    private func clearCurrentDailyUsage() {
        for feature in Self.dailyLimitedFeatures {
            defaults.removeObject(forKey: dailyCounterKey(for: feature))
            defaults.removeObject(forKey: dailyUsageKeysKey(for: feature))
        }
    }

    private func dailyLimit(for feature: LimitedFeature) -> Int? {
        guard Self.dailyLimitedFeatures.contains(feature) else { return nil }
        return limits.limit(for: feature)
    }

    private static let dailyLimitedFeatures: Set<LimitedFeature> = [
        .lyricsSearch,
        .webSearch,
        .youtubeSearch,
        .appleMusicSearch,
        .spotifySearch,
        .discoveryShare
    ]

    private static func normalizedUsageKey(_ usageKey: String) -> String {
        usageKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func loadStations(forKey key: String, defaults: UserDefaults) -> [Station] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Station].self, from: data)) ?? []
    }

    private static func loadDiscoveries(forKey key: String, defaults: UserDefaults) -> [DiscoveredTrack] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DiscoveredTrack].self, from: data)) ?? []
    }

    private func applyRemoteSnapshot(_ snapshot: AVTunesysLibrarySnapshot, updatedAt: Date) {
        isApplyingRemoteSnapshot = true
        applyLibrarySnapshot(snapshot)
        isApplyingRemoteSnapshot = false
        defaults.set(AVTunesysDateCoding.string(from: updatedAt), forKey: lastLocalUpdatedAtKey)
    }

    private func latestLocalUpdatedAt(localSnapshot: AVTunesysLibrarySnapshot) -> Date {
        guard localSnapshot.hasMeaningfulContent else {
            return .distantPast
        }

        return storedLocalUpdatedAt() ?? .now
    }

    private func markLocalUpdated() {
        guard !isApplyingRemoteSnapshot else { return }
        defaults.set(AVTunesysDateCoding.string(from: .now), forKey: lastLocalUpdatedAtKey)
        clearStaleSyncStatusAfterLocalMutation()
    }

    private func storedLocalUpdatedAt() -> Date? {
        guard let storedValue = defaults.string(forKey: lastLocalUpdatedAtKey) else {
            return nil
        }
        return AVTunesysDateCoding.date(from: storedValue)
    }

    private func clearStaleSyncStatusAfterLocalMutation() {
        guard cloudSyncStatus != .syncing else { return }
        cloudSyncStatus = .idle
        cloudSyncConflictSummary = nil
        cloudSyncFailureTitle = nil
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
            return "Waiting for account token"
        case .missingBaseURL:
            return "Waiting for backend config"
        case .requestFailed(let statusCode):
            return "Access request failed (\(statusCode))"
        case .avTunesysAccessMissing:
            return "AV Tunesys access missing"
        }
    }
}

private extension MacAppDataClientError {
    var failureTitle: String {
        switch self {
        case .missingToken:
            return "Waiting for account token"
        case .missingBaseURL:
            return "Waiting for backend config"
        case .requestFailed(let statusCode):
            return "Sync request failed (\(statusCode))"
        }
    }
}
