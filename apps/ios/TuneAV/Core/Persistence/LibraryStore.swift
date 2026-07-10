import OSLog
import AVExternalLinkFoundation
import SwiftData
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [FavoriteStation] = []
    @Published private(set) var recents: [RecentStation] = []
    @Published private(set) var discoveries: [DiscoveredTrack] = []
    @Published private(set) var stationFeedback: [String: TuneAVStationFeedback] = [:]
    @Published private(set) var trackFeedback: [String: TuneAVStationFeedback] = [:]
    @Published private(set) var settings: AppSettings
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .idle
    @Published private(set) var userSummary: TuneAVUserSummary?
    @Published private(set) var userSummaryRefreshState: TuneAVUserSummaryRefreshState = .idle
    @Published private(set) var syncDiagnostics = TuneAVSyncDiagnostics()

    private static let stationFeedbackStorageKey = "tuneav.stationFeedback.v1"
    private static let trackFeedbackStorageKey = "tuneav.trackFeedback.v1"
    static let pendingLibraryOperationsStorageKey = "tuneav.pendingLibraryOperations.v1"
    private static let pendingFeedbackUploadsStorageKey = "tuneav.pendingFeedbackUploads.v1"
    private static let pendingListeningSessionsStorageKey = "tuneav.pendingListeningSessions.v1"
    private static let userSummaryRefreshInterval: TimeInterval = 300
    private static let cloudLibraryRefreshInterval: TimeInterval = 300
    private static let discoveryRefreshInterval: TimeInterval = 60
    private static let listeningSessionBatchSize = 5
    private static let maxPendingListeningSessions = 50
    private static let maxPendingListeningSessionAge: TimeInterval = 7 * 24 * 60 * 60
    private static let listeningSessionRetryBaseDelay: TimeInterval = 30
    private static let listeningSessionRetryMaxDelay: TimeInterval = 300
    private static let listeningSessionRetryJitterFraction = 0.2
    private static let feedbackSyncRetryBaseDelay: TimeInterval = 5
    private static let feedbackSyncRetryMaxDelay: TimeInterval = 120
    private static let feedbackSyncRetryJitterFraction = 0.2
    private static let librarySyncRetryBaseDelay: TimeInterval = 5
    private static let librarySyncRetryMaxDelay: TimeInterval = 120
    private static let librarySyncRetryJitterFraction = 0.2
    private static let maxCloudDiscoveryRecords = 1_000
    private static let cloudPushDebounce: Duration = .seconds(2)

    private let context: ModelContext
    private let userDefaults: UserDefaults
    private let analyticsLogger = Logger(subsystem: "com.avalsys.tuneav", category: "listening-analytics")
    private var appDataService: TuneAVAppDataService?
    private var backendService: TuneAVAppDataService?
    private var backendServiceUserID: String?
    private let tombstoneEncoder = JSONEncoder()
    private let tombstoneDecoder = JSONDecoder()
    private var isApplyingRemoteSnapshot = false
    private var proRealtimeProjectionCursor = TuneAVProRealtimeProjectionCursor()
    private var pushTask: Task<Void, Never>?
    private var cloudLibraryRefreshTask: Task<Void, Never>?
    private var cloudLibraryRefreshedAt: Date?
    private var userSummaryFetchedAt: Date?
    private var userSummaryRefreshTask: Task<Void, Never>?
    private var pendingListeningSessions: [TuneAVListeningSessionDraft] = []
    private var listeningSessionUploadRetryCount = 0
    private var listeningSessionUploadTask: Task<Void, Never>?
    private var listeningSessionFlushTask: Task<Void, Never>?
    private var stationFeedbackSyncTasks: [String: Task<Void, Never>] = [:]
    private var trackFeedbackSyncTasks: [String: Task<Void, Never>] = [:]
    private var librarySyncTasks: [String: Task<Void, Never>] = [:]
    private var librarySyncTokens: [String: UUID] = [:]
    private var librarySyncRetryCounts: [String: Int] = [:]
    private var activePendingLibraryOperationUserID: String?
    private var stationFeedbackSyncTokens: [String: UUID] = [:]
    private var trackFeedbackSyncTokens: [String: UUID] = [:]
    private var stationFeedbackSyncRetryCounts: [String: Int] = [:]
    private var trackFeedbackSyncRetryCounts: [String: Int] = [:]
    private var pendingFeedbackUploads: [String: TuneAVPendingFeedbackUpload] = [:]
    private var pendingLibraryOperations: [String: TuneAVPendingLibraryOperation] = [:]
    private var stationFeedbackRecords: [String: TuneAVLocalFeedbackRecord] = [:]
    private var trackFeedbackRecords: [String: TuneAVLocalFeedbackRecord] = [:]
    private var localFeedbackRetention = TuneAVLocalFeedbackRetention.forMode(.guest)
    private let initialLocalFeedbackRetention = TuneAVLocalFeedbackRetention.maximumLocalRetention
    private var shouldUploadFeedbackToBackend = false
    private var shouldRestoreFeedbackFromCloud = false

    private enum CloudLibraryItemOperation: Equatable {
        case upsert
        case delete
    }

    private enum RefreshScope {
        case favorites
        case recents
        case discoveries
        case settings
        case favoritesAndRecents
        case recentsAndSettings
        case discoveriesAndSettings
        case all

        var shouldPushCloud: Bool {
            switch self {
            case .favorites, .all:
                return true
            case .recents, .discoveries, .settings, .favoritesAndRecents, .recentsAndSettings, .discoveriesAndSettings:
                return false
            }
        }
    }

    init(container: ModelContainer, userDefaults: UserDefaults = .standard) {
        self.context = ModelContext(container)
        self.userDefaults = userDefaults

        if let existingSettings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            self.settings = existingSettings
        } else {
            let settings = AppSettings()
            context.insert(settings)
            try? context.save()
            self.settings = settings
        }

        let loadedStationFeedback = Self.loadStationFeedbackRecords()
        let loadedTrackFeedback = Self.loadTrackFeedbackRecords()
        stationFeedbackRecords = TuneAVLocalFeedbackStore.bounded(
            loadedStationFeedback.records,
            maxCount: initialLocalFeedbackRetention.stationFeedbackLimit
        )
        trackFeedbackRecords = TuneAVLocalFeedbackStore.bounded(
            loadedTrackFeedback.records,
            maxCount: initialLocalFeedbackRetention.trackFeedbackLimit
        )
        stationFeedback = stationFeedbackRecords.mapValues(\.feedback)
        trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
        if loadedStationFeedback.needsPersistence || stationFeedbackRecords != loadedStationFeedback.records {
            Self.saveStationFeedbackRecords(stationFeedbackRecords)
        }
        if loadedTrackFeedback.needsPersistence || trackFeedbackRecords != loadedTrackFeedback.records {
            Self.saveTrackFeedbackRecords(trackFeedbackRecords)
        }
        pendingListeningSessions = Self.loadPendingListeningSessions(maxCount: Self.maxPendingListeningSessions)
        updatePendingListeningSessionDiagnostic()
        pendingLibraryOperations = LibraryStorePendingLibraryOperationPersistence.load(
            storageKey: Self.pendingLibraryOperationsStorageKey,
            userDefaults: userDefaults
        )
        pendingFeedbackUploads = Self.loadPendingFeedbackUploads()
        syncDiagnostics.pendingFeedbackUploadCount = pendingFeedbackUploads.count
        if !pendingListeningSessions.isEmpty {
            analyticsLogger.debug(
                "Restored pending listening sessions pending=\(self.pendingListeningSessions.count, privacy: .public)"
            )
        }
        refresh()
    }

    func refresh() {
        refresh(.all)
    }

    private func refresh(_ scope: RefreshScope) {
        switch scope {
        case .favorites:
            refreshFavorites()
        case .recents:
            refreshRecents()
        case .discoveries:
            refreshDiscoveries()
        case .settings:
            refreshSettings()
        case .favoritesAndRecents:
            refreshFavorites()
            refreshRecents()
        case .recentsAndSettings:
            refreshRecents()
            refreshSettings()
        case .discoveriesAndSettings:
            refreshDiscoveries()
            refreshSettings()
        case .all:
            refreshFavorites()
            refreshRecents()
            refreshDiscoveries()
            refreshSettings()
        }
    }

    private func refreshFavorites() {
        let favoriteDescriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let nextFavorites = (try? context.fetch(favoriteDescriptor)) ?? []
        guard favoriteSignature(favorites) != favoriteSignature(nextFavorites) else { return }
        favorites = nextFavorites
    }

    private func refreshRecents() {
        let recentDescriptor = FetchDescriptor<RecentStation>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        let nextRecents = (try? context.fetch(recentDescriptor)) ?? []
        guard recentSignature(recents) != recentSignature(nextRecents) else { return }
        recents = nextRecents
    }

    private func refreshDiscoveries() {
        let discoveryDescriptor = FetchDescriptor<DiscoveredTrack>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        let nextDiscoveries = (try? context.fetch(discoveryDescriptor)) ?? []
        guard discoverySignature(discoveries) != discoverySignature(nextDiscoveries) else { return }
        discoveries = nextDiscoveries
    }

    private func refreshSettings() {
        if let currentSettings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            settings = currentSettings
        }
    }

    private func favoriteSignature(_ items: [FavoriteStation]) -> [String] {
        items.map { favorite in
            [
                favorite.stationID,
                TuneAVAppDataService.isoString(from: favorite.createdAt),
                favorite.stationSnapshotJSON ?? ""
            ].joined(separator: "\u{1F}")
        }
    }

    private func recentSignature(_ items: [RecentStation]) -> [String] {
        items.map { recent in
            [
                recent.stationID,
                TuneAVAppDataService.isoString(from: recent.lastPlayedAt),
                recent.stationSnapshotJSON ?? ""
            ].joined(separator: "\u{1F}")
        }
    }

    private func discoverySignature(_ items: [DiscoveredTrack]) -> [String] {
        items.map { discovery in
            [
                discovery.discoveryID,
                TuneAVAppDataService.isoString(from: discovery.playedAt),
                discovery.markedInterestedAt.map(TuneAVAppDataService.isoString(from:)) ?? "",
                discovery.hiddenAt.map(TuneAVAppDataService.isoString(from:)) ?? "",
                discovery.artworkURL ?? "",
                discovery.stationArtworkURL ?? ""
            ].joined(separator: "\u{1F}")
        }
    }

    private func setCloudSyncStatus(_ status: CloudSyncStatus) {
        guard cloudSyncStatus != status else { return }
        cloudSyncStatus = status
    }

    private func setUserSummaryRefreshState(_ state: TuneAVUserSummaryRefreshState) {
        guard userSummaryRefreshState != state else { return }
        userSummaryRefreshState = state
    }

    private func updateSyncDiagnostics(_ update: (inout TuneAVSyncDiagnostics) -> Void) {
        var nextDiagnostics = syncDiagnostics
        update(&nextDiagnostics)
        guard nextDiagnostics != syncDiagnostics else { return }
        syncDiagnostics = nextDiagnostics
    }

    func isFavorite(_ station: Station) -> Bool {
        let identityKey = Self.stationIdentityKey(for: station)
        return favorites.contains {
            $0.stationID == station.id || Self.stationIdentityKey(for: Station(favorite: $0)) == identityKey
        }
    }

    func toggleFavorite(for station: Station) {
        let identityKey = Self.stationIdentityKey(for: station)
        let operation: (CloudLibraryItemOperation, FavoriteStationRecord)
        if let existing = favorites.first(where: { $0.stationID == station.id || Self.stationIdentityKey(for: Station(favorite: $0)) == identityKey }) {
            operation = (.delete, rememberFavoriteDeletion(for: Station(favorite: existing)))
            context.delete(existing)
        } else {
            let createdAt = Date.now
            let record = FavoriteStationRecord(
                station: station.appDataRecord,
                createdAt: TuneAVAppDataService.isoString(from: createdAt)
            )
            removeTombstone(resource: "favorites", identityKey: identityKey)
            context.insert(FavoriteStation(station: station, createdAt: createdAt))
            operation = (.upsert, record)
        }

        saveAndRefresh(.favorites, syncsCloud: false)
        enqueueFavoriteLibraryOperation(operation.0, record: operation.1)
    }

    func rememberStationSnapshots(_ stations: [Station]) {
        guard !stations.isEmpty else { return }

        let favoritesByID = Dictionary(favorites.map { ($0.stationID, $0) }, uniquingKeysWith: { first, _ in first })
        let recentsByID = Dictionary(recents.map { ($0.stationID, $0) }, uniquingKeysWith: { first, _ in first })
        var didUpdate = false
        for station in stations {
            if let favorite = favoritesByID[station.id] {
                didUpdate = favorite.updateStationSnapshot(station) || didUpdate
            }

            if let recent = recentsByID[station.id] {
                didUpdate = recent.updateStationSnapshot(station) || didUpdate
            }
        }

        guard didUpdate else { return }
        saveAndRefresh(.favoritesAndRecents)
    }

    func recordPlayback(of station: Station, recentLimit: Int? = nil) {
        let identityKey = Self.stationIdentityKey(for: station)
        if let existing = recents.first(where: { $0.stationID == station.id || Self.stationIdentityKey(for: Station(recent: $0)) == identityKey }) {
            updateRecent(existing, with: station)
            for duplicate in recents where duplicate !== existing && Self.stationIdentityKey(for: Station(recent: duplicate)) == identityKey {
                context.delete(duplicate)
            }
        } else {
            context.insert(RecentStation(station: station))
        }

        settings.lastPlayedStationID = station.id
        settings.updatedAt = .now
        trimRecents(limit: recentLimit ?? 20)
        saveAndRefresh(.recentsAndSettings)
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

    var tunedDiscoveries: [DiscoveredTrack] {
        tunedDiscoveriesFromFeedback()
    }

    private func discovery(for title: String?, artist: String?, station: Station?) -> DiscoveredTrack? {
        guard
            let station,
            let normalizedTitle = normalizedTrackValue(title)
        else {
            return nil
        }

        let discoveryID = DiscoveredTrack.makeID(
            title: normalizedTitle,
            artist: normalizedTrackValue(artist),
            stationID: station.id
        )
        return discoveries.first { $0.discoveryID == discoveryID }
    }

    func canMarkTrackInteresting(title: String?, artist: String?, station: Station?, limit: Int?) -> Bool {
        TuneAVSavedDiscoveryPolicy.canSaveDiscovery(
            isAlreadySaved: isSavedDiscoveredTrack(title: title, artist: artist, station: station),
            savedCount: savedDiscoveriesCount,
            limit: limit
        )
    }

    func markTrackInteresting(title: String?, artist: String?, station: Station?, artworkURL: URL?, discoveryLimit: Int? = nil) {
        saveDiscoveredTrack(
            title: title,
            artist: artist,
            station: station,
            artworkURL: artworkURL,
            markInteresting: true,
            discoveryLimit: discoveryLimit
        )
    }

    func toggleDiscoverySaved(_ discovery: DiscoveredTrack, savedLimit: Int? = nil) -> Bool {
        let now = Date.now
        var operation = CloudLibraryItemOperation.upsert
        var operationRecord: DiscoveredTrackRecord?
        if discovery.isMarkedInteresting {
            operation = .delete
            operationRecord = rememberSavedDiscoveryDeletion(for: discovery)
            discovery.markedInterestedAt = nil
        } else {
            if let savedLimit, savedDiscoveriesCount >= savedLimit {
                return false
            }

            discovery.markedInterestedAt = now
            discovery.hiddenAt = nil
        }

        discovery.updatedAt = now
        if operation == .upsert {
            operationRecord = discovery.appDataRecord
        }
        saveAndRefresh(.discoveries, syncsCloud: false)
        if let operationRecord {
            enqueueSavedDiscoveryLibraryOperation(operation, record: operationRecord)
        }
        return true
    }

    func toggleDiscoveredTrackSaved(title: String?, artist: String?, station: Station?, artworkURL: URL?, savedLimit: Int? = nil, discoveryLimit: Int? = nil) -> Bool {
        if let existing = discovery(for: title, artist: artist, station: station) {
            return toggleDiscoverySaved(existing, savedLimit: savedLimit)
        }

        if let savedLimit, savedDiscoveriesCount >= savedLimit {
            return false
        }

        markTrackInteresting(
            title: title,
            artist: artist,
            station: station,
            artworkURL: artworkURL,
            discoveryLimit: discoveryLimit
        )
        return true
    }

    func hideDiscovery(_ discovery: DiscoveredTrack) {
        guard discovery.hiddenAt == nil || discovery.isMarkedInteresting else { return }
        let now = Date.now
        discovery.hiddenAt = now
        discovery.markedInterestedAt = nil
        discovery.updatedAt = now
        saveAndRefresh(.discoveries)
    }

    func restoreDiscovery(_ discovery: DiscoveredTrack) {
        guard discovery.hiddenAt != nil else { return }
        let now = Date.now
        discovery.hiddenAt = nil
        discovery.updatedAt = now
        saveAndRefresh(.discoveries)
    }

    func feedback(for station: Station) -> TuneAVStationFeedback? {
        stationFeedback[station.id]
    }

    func configureLocalFeedbackRetention(for accessMode: AccessMode) {
        let retention = TuneAVLocalFeedbackRetention.forMode(accessMode)
        shouldUploadFeedbackToBackend = accessMode != .guest
        shouldRestoreFeedbackFromCloud = accessMode == .signedInPro
        guard retention != localFeedbackRetention else { return }
        localFeedbackRetention = retention
        pruneLocalFeedbackIfNeeded()
    }

    func setFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        var nextRecords = stationFeedbackRecords
        if let feedback {
            nextRecords[station.id] = TuneAVLocalFeedbackRecord(feedback: feedback, updatedAt: TuneAVDateCoding.string(from: .now))
        } else {
            nextRecords.removeValue(forKey: station.id)
        }

        nextRecords = TuneAVLocalFeedbackStore.bounded(nextRecords, maxCount: localFeedbackRetention.stationFeedbackLimit)
        guard nextRecords != stationFeedbackRecords else { return }
        stationFeedbackRecords = nextRecords
        stationFeedback = nextRecords.mapValues(\.feedback)
        Self.saveStationFeedbackRecords(nextRecords)
        guard shouldUploadFeedbackToBackend else { return }
        rememberPendingStationFeedbackUpload(feedback, stationID: station.id)
        syncStationFeedback(feedback, stationID: station.id)
    }

    func feedbackForDiscoveredTrack(title: String?, artist: String?) -> TuneAVStationFeedback? {
        guard let key = discoveredTrackFeedbackKey(title: title, artist: artist) else { return nil }
        return trackFeedback[key]
    }

    func feedback(for discovery: DiscoveredTrack) -> TuneAVStationFeedback? {
        feedbackForDiscoveredTrack(title: discovery.title, artist: discovery.artist)
    }

    func setFeedbackForDiscoveredTrack(_ feedback: TuneAVStationFeedback?, title: String?, artist: String?, stationID: String? = nil) {
        guard let key = discoveredTrackFeedbackKey(title: title, artist: artist) else { return }

        var nextRecords = trackFeedbackRecords
        if let feedback {
            nextRecords[key] = TuneAVLocalFeedbackRecord(
                feedback: feedback,
                updatedAt: TuneAVDateCoding.string(from: .now),
                title: title,
                artist: artist,
                stationID: stationID
            )
        } else {
            nextRecords.removeValue(forKey: key)
        }

        nextRecords = TuneAVLocalFeedbackStore.bounded(nextRecords, maxCount: localFeedbackRetention.trackFeedbackLimit)
        guard nextRecords != trackFeedbackRecords else { return }
        trackFeedbackRecords = nextRecords
        trackFeedback = nextRecords.mapValues(\.feedback)
        Self.saveTrackFeedbackRecords(nextRecords)
        guard shouldUploadFeedbackToBackend else { return }
        let normalizedTitle = normalizedTrackValue(title)
        let normalizedArtist = normalizedTrackValue(artist)
        rememberPendingTrackFeedbackUpload(feedback, feedbackKey: key, title: normalizedTitle, artist: normalizedArtist, stationID: stationID)
        syncTrackFeedback(feedback, title: normalizedTitle, artist: normalizedArtist, stationID: stationID)
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

    private func saveDiscoveredTrack(
        title: String?,
        artist: String?,
        station: Station?,
        artworkURL: URL?,
        markInteresting: Bool,
        discoveryLimit: Int? = nil
    ) {
        guard
            let station,
            let normalizedTitle = normalizedTrackValue(title)
        else {
            return
        }

        let normalizedArtist = normalizedTrackValue(artist)
        let discoveryID = DiscoveredTrack.makeID(
            title: normalizedTitle,
            artist: normalizedArtist,
            stationID: station.id
        )
        let discoveryIdentityKey = Self.savedDiscoveryIdentityKey(title: normalizedTitle, artist: normalizedArtist)
        let now = Date.now
        let nextArtworkURL = artworkURL?.absoluteString
        var operationRecord: DiscoveredTrackRecord?

        if let existing = discoveries.first(where: { $0.discoveryID == discoveryID }) {
            if !markInteresting,
               now.timeIntervalSince(existing.playedAt) < Self.discoveryRefreshInterval,
               (nextArtworkURL == nil || nextArtworkURL == existing.artworkURL) {
                return
            }

            if markInteresting {
                removeTombstone(resource: "savedDiscoveries", identityKey: discoveryID)
                removeTombstone(resource: "savedDiscoveries", identityKey: discoveryIdentityKey)
            }
            existing.playedAt = now
            if markInteresting {
                existing.markedInterestedAt = existing.markedInterestedAt ?? now
                existing.hiddenAt = nil
            }
            existing.artworkURL = nextArtworkURL ?? existing.artworkURL
            existing.stationArtworkURL = nil
            existing.updatedAt = now
            if markInteresting {
                operationRecord = existing.appDataRecord
            }
        } else {
            if markInteresting {
                removeTombstone(resource: "savedDiscoveries", identityKey: discoveryID)
                removeTombstone(resource: "savedDiscoveries", identityKey: discoveryIdentityKey)
            }
            let discovery = DiscoveredTrack(
                title: normalizedTitle,
                artist: normalizedArtist,
                station: station,
                artworkURL: artworkURL,
                markedInterestedAt: markInteresting ? now : nil
            )
            context.insert(discovery)
            if markInteresting {
                operationRecord = discovery.appDataRecord
            }
        }

        trimDiscoveries(limit: discoveryLimit ?? 100)
        saveAndRefresh(.discoveries, syncsCloud: false)
        if let operationRecord {
            enqueueSavedDiscoveryLibraryOperation(.upsert, record: operationRecord)
        }
    }

    func removeDiscovery(_ discovery: DiscoveredTrack) {
        let wasMarkedInteresting = discovery.isMarkedInteresting
        let operationRecord = wasMarkedInteresting ? rememberSavedDiscoveryDeletion(for: discovery) : nil
        context.delete(discovery)
        saveAndRefresh(.discoveries, syncsCloud: false)
        if let operationRecord {
            enqueueSavedDiscoveryLibraryOperation(.delete, record: operationRecord)
        }
    }

    func clearDiscoveries() {
        guard !discoveries.isEmpty else { return }

        let removedSavedDiscovery = discoveries.contains(where: \.isMarkedInteresting)
        for discovery in discoveries {
            if discovery.isMarkedInteresting {
                rememberSavedDiscoveryDeletion(for: discovery)
            }
            context.delete(discovery)
        }

        discoveries = []
        saveAndRefresh(.discoveries, syncsCloud: removedSavedDiscovery)
    }

    func station(for stationID: String?) -> Station? {
        guard let stationID else { return nil }

        if let favorite = favorites.first(where: { $0.stationID == stationID }) {
            return Station(favorite: favorite)
        }

        if let recent = recents.first(where: { $0.stationID == stationID }) {
            return Station(recent: recent)
        }

        return nil
    }

    func ensureSeededStation(_ station: Station, favorite: Bool) {
        if favorite, !isFavorite(station) {
            removeTombstone(resource: "favorites", identityKey: Self.stationIdentityKey(for: station))
            context.insert(FavoriteStation(station: station))
        }

        if recents.contains(where: { $0.stationID == station.id }) == false {
            context.insert(RecentStation(station: station))
        }

        settings.lastPlayedStationID = station.id
        settings.updatedAt = .now
        saveAndRefresh(.all, syncsCloud: favorite)
    }

    func favoriteStations() -> [Station] {
        favorites.map(Station.init(favorite:))
    }

    func recentStations() -> [Station] {
        Self.uniqueRecentStations(from: recents)
    }

    func setPreferredTag(_ tag: String?) {
        let preferredTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard settings.preferredTag != preferredTag else { return }
        settings.preferredTag = preferredTag
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func setPreferredCountry(_ countryCode: String?) {
        let preferredCountry = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard settings.preferredCountry != preferredCountry else { return }
        settings.preferredCountry = preferredCountry
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func setKeepScreenAwake(_ isEnabled: Bool) {
        guard settings.keepScreenAwake != isEnabled else { return }
        settings.keepScreenAwake = isEnabled
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func setWarnBeforeCellularPlayback(_ isEnabled: Bool) {
        guard settings.warnBeforeCellularPlayback != isEnabled else { return }
        settings.warnBeforeCellularPlayback = isEnabled
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func setOpenLastStationOnLaunch(_ isEnabled: Bool) {
        guard settings.openLastStationOnLaunch != isEnabled else { return }
        settings.openLastStationOnLaunch = isEnabled
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func setAutoSkipUnstableStreams(_ isEnabled: Bool) {
        guard settings.autoSkipUnstableStreams != isEnabled else { return }
        settings.autoSkipUnstableStreams = isEnabled
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func setExternalSearchEngine(_ engine: AVExternalSearchEngine) {
        guard settings.externalSearchEngine != engine.rawValue else { return }
        settings.externalSearchEngine = engine.rawValue
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func setExternalWebOpenMode(_ mode: AVExternalWebOpenMode) {
        guard settings.externalWebOpenMode != mode.rawValue else { return }
        settings.externalWebOpenMode = mode.rawValue
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func rememberOpenedStation(_ station: Station, presentation: String) {
        guard settings.lastOpenedStationID != station.id || settings.lastOpenedStationPresentation != presentation else { return }
        settings.lastOpenedStationID = station.id
        settings.lastOpenedStationPresentation = presentation
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func clearOpenedStationPresentation() {
        guard settings.lastOpenedStationPresentation != nil else { return }
        settings.lastOpenedStationPresentation = nil
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func clearFavorites(propagatesToCloud: Bool = false) {
        for favorite in favorites {
            if propagatesToCloud {
                rememberFavoriteDeletion(for: Station(favorite: favorite))
            }
            context.delete(favorite)
        }
        saveAndRefresh(.favorites, syncsCloud: propagatesToCloud)
    }

    func clearRecents(propagatesToCloud: Bool = false) {
        for recent in recents {
            context.delete(recent)
        }
        settings.lastPlayedStationID = nil
        settings.lastOpenedStationID = nil
        settings.lastOpenedStationPresentation = nil
        settings.updatedAt = .now
        saveAndRefresh(.recentsAndSettings)
    }

    func clearDiscoveries(propagatesToCloud: Bool = false) {
        let removedSavedDiscovery = discoveries.contains(where: \.isMarkedInteresting)
        for discovery in discoveries {
            if propagatesToCloud, discovery.isMarkedInteresting {
                rememberSavedDiscoveryDeletion(for: discovery)
            }
            context.delete(discovery)
        }
        saveAndRefresh(.discoveries, syncsCloud: propagatesToCloud && removedSavedDiscovery)
    }

    func resetSettings() {
        settings.preferredCountry = ""
        settings.preferredLanguage = ""
        settings.preferredTag = ""
        settings.lastPlayedStationID = nil
        settings.lastOpenedStationID = nil
        settings.lastOpenedStationPresentation = nil
        settings.sleepTimerMinutes = nil
        settings.keepScreenAwake = false
        settings.warnBeforeCellularPlayback = false
        settings.openLastStationOnLaunch = false
        settings.autoSkipUnstableStreams = false
        settings.externalSearchEngine = AVExternalSearchEngine.duckDuckGo.rawValue
        settings.externalWebOpenMode = AVExternalWebOpenMode.inApp.rawValue
        settings.updatedAt = .now
        saveAndRefresh(.settings)
    }

    func clearLocalData(propagatesToCloud: Bool = false) {
        for favorite in favorites {
            if propagatesToCloud {
                rememberFavoriteDeletion(for: Station(favorite: favorite))
            }
            context.delete(favorite)
        }

        for recent in recents {
            context.delete(recent)
        }

        var removedSavedDiscovery = false
        for discovery in discoveries {
            if propagatesToCloud, discovery.isMarkedInteresting {
                rememberSavedDiscoveryDeletion(for: discovery)
                removedSavedDiscovery = true
            }
            context.delete(discovery)
        }

        if !propagatesToCloud {
            for tombstone in tombstones() {
                context.delete(tombstone)
            }
        }

        settings.preferredCountry = ""
        settings.preferredLanguage = ""
        settings.preferredTag = ""
        settings.lastPlayedStationID = nil
        settings.lastOpenedStationID = nil
        settings.lastOpenedStationPresentation = nil
        settings.sleepTimerMinutes = nil
        settings.keepScreenAwake = false
        settings.warnBeforeCellularPlayback = false
        settings.openLastStationOnLaunch = false
        settings.autoSkipUnstableStreams = false
        settings.externalSearchEngine = AVExternalSearchEngine.duckDuckGo.rawValue
        settings.externalWebOpenMode = AVExternalWebOpenMode.inApp.rawValue
        settings.updatedAt = .now

        saveAndRefresh(.all, syncsCloud: propagatesToCloud && (removedSavedDiscovery || !favorites.isEmpty))
    }

    func setAppDataService(_ service: TuneAVAppDataService?) {
        let previousService = appDataService
        appDataService = service
        if previousService !== service {
            stopPendingLibraryOperations()
            pushTask?.cancel()
            pushTask = nil
            cloudLibraryRefreshTask?.cancel()
            cloudLibraryRefreshTask = nil
            cloudLibraryRefreshedAt = nil
        }
        if service == nil {
            setCloudSyncStatus(.idle)
        } else {
            schedulePendingLibraryOperationsForCurrentUser()
        }
    }

    func setBackendService(_ service: TuneAVAppDataService?, userID: String? = nil) {
        let previousService = backendService
        let previousUserID = backendServiceUserID
        backendService = service
        backendServiceUserID = service == nil ? nil : userID
        if previousUserID != backendServiceUserID {
            proRealtimeProjectionCursor.reset()
            stopPendingLibraryOperations()
        }
        updatePendingListeningSessionDiagnostic()
        if previousService !== service {
            listeningSessionUploadTask?.cancel()
            listeningSessionUploadTask = nil
        }
        if service == nil {
            userSummary = nil
            userSummaryFetchedAt = nil
            setUserSummaryRefreshState(.unavailable)
            userSummaryRefreshTask?.cancel()
            userSummaryRefreshTask = nil
            listeningSessionFlushTask?.cancel()
            listeningSessionFlushTask = nil
            listeningSessionUploadRetryCount = 0
            stationFeedbackSyncTasks.values.forEach { $0.cancel() }
            stationFeedbackSyncTasks.removeAll()
            stationFeedbackSyncTokens.removeAll()
            stationFeedbackSyncRetryCounts.removeAll()
            trackFeedbackSyncTasks.values.forEach { $0.cancel() }
            trackFeedbackSyncTasks.removeAll()
            trackFeedbackSyncTokens.removeAll()
            trackFeedbackSyncRetryCounts.removeAll()
            updateSyncDiagnostics {
                $0.pendingListeningSessionCount = uploadablePendingListeningSessions().count
                $0.pendingFeedbackUploadCount = pendingFeedbackUploads.count
                $0.lastSummaryFetchAt = nil
            }
            analyticsLogger.debug("Kept pending listening sessions after backend disconnect")
            persistPendingListeningSessions()
        } else if !uploadablePendingListeningSessions().isEmpty {
            scheduleListeningSessionUpload()
        }
        if service != nil {
            schedulePendingFeedbackUploadsForCurrentUser()
            if appDataService === service {
                schedulePendingLibraryOperationsForCurrentUser()
            }
        }
    }

    func refreshUserSummary(force: Bool = false) async {
        guard let backendService, backendService.isConfigured() else {
            userSummary = nil
            userSummaryFetchedAt = nil
            setUserSummaryRefreshState(.unavailable)
            return
        }

        if !force, let userSummaryFetchedAt, Date().timeIntervalSince(userSummaryFetchedAt) < Self.userSummaryRefreshInterval, userSummary != nil {
            return
        }

        if let userSummaryRefreshTask {
            await userSummaryRefreshTask.value
            return
        }

        let task = Task { @MainActor in
            setUserSummaryRefreshState(.loading)
            do {
                let summary = try await backendService.fetchUserSummary(limit: 12)
                guard self.backendService === backendService else { return }
                userSummary = summary
                userSummaryFetchedAt = .now
                updateSyncDiagnostics { $0.lastSummaryFetchAt = userSummaryFetchedAt }
                setUserSummaryRefreshState(summary.hasAnyActivity ? .loaded : .empty)
            } catch AVAccountAPIClientError.missingToken, AVAccountAPIClientError.missingBaseURL {
                guard self.backendService === backendService else { return }
                userSummary = nil
                userSummaryFetchedAt = nil
                setUserSummaryRefreshState(.unavailable)
            } catch {
                guard self.backendService === backendService else { return }
                userSummary = nil
                userSummaryFetchedAt = nil
                setUserSummaryRefreshState(.failed)
            }
        }

        userSummaryRefreshTask = task
        await task.value
        userSummaryRefreshTask = nil
    }

    func recordListeningSession(
        station: Station,
        startedAt: Date,
        endedAt: Date,
        source: String,
        endedReason: String,
        trackDetectedCount: Int
    ) {
        guard AppConfig.isListeningAnalyticsUploadEnabled else { return }
        guard let backendService, backendService.isConfigured() else { return }
        let duration = max(0, Int(endedAt.timeIntervalSince(startedAt).rounded()))
        guard duration >= 10 else { return }

        pendingListeningSessions.append(
            TuneAVListeningSessionDraft(
                station: station,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: duration,
                source: source,
                endedReason: endedReason,
                trackDetectedCount: trackDetectedCount,
                userID: backendServiceUserID
            )
        )

        pendingListeningSessions = LibraryStoreListeningSessionBuffer.bounded(
            pendingListeningSessions,
            maxCount: Self.maxPendingListeningSessions
        )
        updatePendingListeningSessionDiagnostic()
        persistPendingListeningSessions()
        analyticsLogger.debug(
            "Queued listening session pending=\(self.pendingListeningSessions.count, privacy: .public)"
        )

        if uploadablePendingListeningSessions().count >= Self.listeningSessionBatchSize {
            flushListeningSessionUploads()
        } else {
            scheduleListeningSessionUpload()
        }
    }

    func flushPendingListeningSessions() {
        flushListeningSessionUploads()
    }

    private func scheduleListeningSessionUpload() {
        guard listeningSessionUploadTask == nil else { return }

        let delay = LibraryStoreListeningSessionRetryPolicy.delay(
            retryCount: listeningSessionUploadRetryCount,
            baseDelay: Self.listeningSessionRetryBaseDelay,
            maxDelay: Self.listeningSessionRetryMaxDelay,
            jitterFraction: Self.listeningSessionRetryJitterFraction
        )
        analyticsLogger.debug(
            "Scheduled listening session upload pending=\(self.pendingListeningSessions.count, privacy: .public) retryCount=\(self.listeningSessionUploadRetryCount, privacy: .public) delaySeconds=\(delay, privacy: .public)"
        )
        listeningSessionUploadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard !Task.isCancelled else { return }
            flushListeningSessionUploads()
        }
    }

    private func flushListeningSessionUploads() {
        listeningSessionUploadTask?.cancel()
        listeningSessionUploadTask = nil
        guard listeningSessionFlushTask == nil else { return }

        guard let backendService, backendService.isConfigured() else {
            analyticsLogger.debug("Kept pending listening sessions because backend is unavailable")
            updatePendingListeningSessionDiagnostic()
            persistPendingListeningSessions()
            return
        }
        let sessions = uploadablePendingListeningSessions()
        guard !sessions.isEmpty else { return }

        let sessionIDs = Set(sessions.map(\.id))
        pendingListeningSessions.removeAll { sessionIDs.contains($0.id) }
        updatePendingListeningSessionDiagnostic()
        analyticsLogger.debug(
            "Uploading listening sessions count=\(sessions.count, privacy: .public) retryCount=\(self.listeningSessionUploadRetryCount, privacy: .public)"
        )

        listeningSessionFlushTask = Task { @MainActor in
            do {
                let result = try await backendService.recordListeningSessions(sessions)
                guard self.backendService === backendService else {
                    requeueInterruptedListeningSessionUpload(sessions, reason: "backend_changed")
                    return
                }
                finishListeningSessionUpload(didUpload: true, sessions: sessions, result: result, incrementRetry: false)
            } catch is CancellationError {
                guard self.backendService === backendService else {
                    requeueInterruptedListeningSessionUpload(sessions, reason: "backend_changed")
                    return
                }
                finishListeningSessionUpload(didUpload: false, sessions: sessions, result: nil, incrementRetry: false)
            } catch {
                guard self.backendService === backendService else {
                    requeueInterruptedListeningSessionUpload(sessions, reason: "backend_changed")
                    return
                }
                finishListeningSessionUpload(didUpload: false, sessions: sessions, result: nil, incrementRetry: true)
            }
        }
    }

    private func finishListeningSessionUpload(
        didUpload: Bool,
        sessions: [TuneAVListeningSessionDraft],
        result: TuneAVListeningSessionsUploadResult?,
        incrementRetry: Bool
    ) {
        listeningSessionFlushTask = nil

        guard didUpload else {
            if incrementRetry {
                listeningSessionUploadRetryCount += 1
            }
            pendingListeningSessions.insert(contentsOf: sessions, at: 0)
            pendingListeningSessions = LibraryStoreListeningSessionBuffer.bounded(
                pendingListeningSessions,
                maxCount: Self.maxPendingListeningSessions
            )
            updatePendingListeningSessionDiagnostic()
            persistPendingListeningSessions()
            analyticsLogger.debug(
                "Listening session upload failed requeued=\(sessions.count, privacy: .public) pending=\(self.pendingListeningSessions.count, privacy: .public) retryCount=\(self.listeningSessionUploadRetryCount, privacy: .public)"
            )
            scheduleListeningSessionUpload()
            return
        }

        listeningSessionUploadRetryCount = 0
        updatePendingListeningSessionDiagnostic()
        persistPendingListeningSessions()
        analyticsLogger.debug(
            "Listening session upload finished sent=\(sessions.count, privacy: .public) accepted=\(result?.accepted ?? 0, privacy: .public) duplicate=\(result?.duplicate ?? 0, privacy: .public) rejected=\(result?.rejected ?? 0, privacy: .public) pending=\(self.pendingListeningSessions.count, privacy: .public)"
        )
        let uploadableCount = uploadablePendingListeningSessions().count
        guard uploadableCount > 0 else { return }
        if uploadableCount >= Self.listeningSessionBatchSize {
            flushListeningSessionUploads()
        } else {
            scheduleListeningSessionUpload()
        }
    }

    private func requeueInterruptedListeningSessionUpload(_ sessions: [TuneAVListeningSessionDraft], reason: String) {
        listeningSessionFlushTask = nil

        pendingListeningSessions.insert(contentsOf: sessions, at: 0)
        pendingListeningSessions = LibraryStoreListeningSessionBuffer.bounded(
            pendingListeningSessions,
            maxCount: Self.maxPendingListeningSessions
        )
        updatePendingListeningSessionDiagnostic()
        persistPendingListeningSessions()
        analyticsLogger.debug(
            "Listening session upload interrupted reason=\(reason, privacy: .public) requeued=\(sessions.count, privacy: .public) pending=\(self.pendingListeningSessions.count, privacy: .public)"
        )
        guard let backendService, backendService.isConfigured() else { return }
        scheduleListeningSessionUpload()
    }

    func refreshCloudLibraryIfNeeded(force: Bool = false) async {
        guard let appDataService, appDataService.isConfigured() else {
            setCloudSyncStatus(.idle)
            return
        }

        if !force,
           let cloudLibraryRefreshedAt,
           Date().timeIntervalSince(cloudLibraryRefreshedAt) < Self.cloudLibraryRefreshInterval {
            return
        }

        if let cloudLibraryRefreshTask {
            await cloudLibraryRefreshTask.value
            return
        }

        let task = Task { @MainActor in
            await performCloudLibraryRefresh(using: appDataService)
        }
        cloudLibraryRefreshTask = task
        await task.value
        cloudLibraryRefreshTask = nil
    }

    func handleProRealtimeInvalidation(_ projection: TuneAVProLibraryProjection) async {
        let refreshPlan = proRealtimeProjectionCursor.consume(projection)
        if refreshPlan.refreshFeedback {
            await refreshCloudFeedbackIfNeeded(force: true)
        }
        if refreshPlan.refreshLibrary {
            await refreshCloudLibraryIfNeeded(force: true)
        }
    }

    func refreshCloudFeedbackIfNeeded(force: Bool = false) async {
        guard shouldRestoreFeedbackFromCloud else { return }
        guard let backendService, backendService.isConfigured() else { return }

        if !force,
           let userSummaryFetchedAt,
           Date().timeIntervalSince(userSummaryFetchedAt) < Self.userSummaryRefreshInterval {
            return
        }

        do {
            let snapshot = try await backendService.fetchFeedbackSnapshot()
            guard self.backendService === backendService else { return }
            applyProRealtimeFeedback(
                stationFeedback: snapshot.stationFeedback,
                trackFeedback: snapshot.trackFeedback
            )
            await refreshUserSummary(force: true)
        } catch {
            return
        }
    }

    private func applyProRealtimeFeedback(
        stationFeedback remoteStationFeedback: [TuneAVStationFeedbackRecord],
        trackFeedback remoteTrackFeedback: [TuneAVTrackFeedbackRecord]
    ) {
        let nextStationRecords = TuneAVRealtimeFeedbackProjection.stationFeedbackRecords(from: remoteStationFeedback)
        if nextStationRecords != stationFeedbackRecords {
            stationFeedbackRecords = TuneAVLocalFeedbackStore.bounded(nextStationRecords, maxCount: localFeedbackRetention.stationFeedbackLimit)
            stationFeedback = stationFeedbackRecords.mapValues(\.feedback)
            Self.saveStationFeedbackRecords(stationFeedbackRecords)
        }

        let nextTrackRecords = TuneAVRealtimeFeedbackProjection.trackFeedbackRecords(from: remoteTrackFeedback)
        if nextTrackRecords != trackFeedbackRecords {
            trackFeedbackRecords = TuneAVLocalFeedbackStore.bounded(nextTrackRecords, maxCount: localFeedbackRetention.trackFeedbackLimit)
            trackFeedback = trackFeedbackRecords.mapValues(\.feedback)
            Self.saveTrackFeedbackRecords(trackFeedbackRecords)
        }
    }

    private func performCloudLibraryRefresh(using appDataService: TuneAVAppDataService) async {
        do {
            setCloudSyncStatus(.syncing)
            let remoteDocument = try await appDataService.pullLibrary()
            guard self.appDataService === appDataService else { return }
            updateSyncDiagnostics { $0.lastCloudPullAt = .now }
            let localSnapshot = librarySnapshot()

            switch TuneAVLibrarySyncPlanner.decision(
                localSnapshot: localSnapshot,
                localUpdatedAt: latestLocalUpdateAt(),
                remoteDocument: remoteDocument
            ) {
            case .pullRemote(let remoteSnapshot):
                let mergedSnapshot = cloudBoundedSnapshot(
                    TuneAVLibrarySnapshotMerger.merged(
                        local: localSnapshot,
                        remote: remoteSnapshot
                    )
                )
                applyRemoteSnapshot(mergedSnapshot)
                if mergedSnapshot != remoteSnapshot {
                    try await appDataService.pushLibrary(mergedSnapshot)
                    guard self.appDataService === appDataService else { return }
                    updateSyncDiagnostics { $0.lastCloudPushAt = .now }
                    clearSyncedTombstones()
                }
            case .pushLocal:
                let snapshotToPush: TuneAVLibrarySnapshot
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToPush = cloudBoundedSnapshot(
                        TuneAVLibrarySnapshotMerger.merged(
                            local: localSnapshot,
                            remote: remoteSnapshot
                        )
                    )
                } else {
                    snapshotToPush = localSnapshot
                }

                try await appDataService.pushLibrary(snapshotToPush)
                guard self.appDataService === appDataService else { return }
                updateSyncDiagnostics { $0.lastCloudPushAt = .now }
                clearSyncedTombstones()
                if snapshotToPush != localSnapshot {
                    applyRemoteSnapshot(snapshotToPush)
                }
            case .noContent, .alreadyCurrent:
                break
            }

            setCloudSyncStatus(.synced(.now))
            cloudLibraryRefreshedAt = .now
        } catch TuneAVAppDataError.conflict {
            guard self.appDataService === appDataService else { return }
            setCloudSyncStatus(.conflict)
        } catch {
            guard self.appDataService === appDataService else { return }
            setCloudSyncStatus(.failed)
            return
        }
    }

    func overwriteCloudLibraryWithLocalData() async {
        guard let appDataService, appDataService.isConfigured() else {
            setCloudSyncStatus(.idle)
            return
        }

        do {
            setCloudSyncStatus(.syncing)
            try await appDataService.overwriteLibrary(librarySnapshot())
            clearSyncedTombstones()
            setCloudSyncStatus(.synced(.now))
        } catch TuneAVAppDataError.conflict {
            setCloudSyncStatus(.conflict)
        } catch {
            setCloudSyncStatus(.failed)
        }
    }

    func clearCloudSyncStatus() {
        setCloudSyncStatus(.idle)
    }

    func setCloudSyncStatusForUITests(_ status: CloudSyncStatus) {
        guard TuneAVUITestEnvironment.current.isEnabled else {
            return
        }

        setCloudSyncStatus(status)
    }

    private func trimRecents(limit: Int) {
        for item in TuneAVCollectionRules.overflow(in: recents, limit: limit, sortedBy: { $0.lastPlayedAt > $1.lastPlayedAt }) {
            context.delete(item)
        }
    }

    private func updateRecent(_ recent: RecentStation, with station: Station) {
        recent.name = station.name
        recent.country = station.country
        recent.countryCode = station.countryCode
        recent.state = station.state
        recent.language = station.language
        recent.languageCodes = station.languageCodes
        recent.tags = station.tags
        recent.streamURL = station.streamURL
        recent.faviconURL = station.faviconURL
        recent.bitrate = station.bitrate
        recent.codec = station.codec
        recent.homepageURL = station.homepageURL
        recent.votes = station.votes
        recent.clickCount = station.clickCount
        recent.clickTrend = station.clickTrend
        recent.isHLS = station.isHLS
        recent.hasExtendedInfo = station.hasExtendedInfo
        recent.hasSSLError = station.hasSSLError
        recent.lastCheckOKAt = station.lastCheckOKAt
        recent.geoLatitude = station.geoLatitude
        recent.geoLongitude = station.geoLongitude
        recent.updateStationSnapshot(station)
        recent.lastPlayedAt = .now
    }

    private static func uniqueRecentStations(from recents: [RecentStation]) -> [Station] {
        var seen = Set<String>()
        var stations: [Station] = []

        for recent in recents {
            let station = Station(recent: recent)
            let identityKey = stationIdentityKey(for: station)
            guard seen.insert(identityKey).inserted else { continue }
            stations.append(station)
        }

        return stations
    }

    private func trimDiscoveries(limit: Int) {
        for item in TuneAVCollectionRules.overflow(in: discoveries, limit: limit, sortedBy: { $0.playedAt > $1.playedAt }) {
            context.delete(item)
        }
    }

    private func normalizedTrackValue(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)
    }

    private func discoveredTrackFeedbackKey(title: String?, artist: String?) -> String? {
        guard
            let normalizedTitle = normalizedTrackValue(title)
        else { return nil }

        return Self.trackFeedbackKey(title: normalizedTitle, artist: normalizedTrackValue(artist))
    }

    private func tunedDiscoveriesFromFeedback() -> [DiscoveredTrack] {
        let localDiscoveriesByFeedbackKey = Dictionary(
            discoveries.compactMap { discovery -> (String, DiscoveredTrack)? in
                guard let key = discoveredTrackFeedbackKey(title: discovery.title, artist: discovery.artist) else { return nil }
                return (key, discovery)
            },
            uniquingKeysWith: { first, second in
                first.playedAt >= second.playedAt ? first : second
            }
        )

        return trackFeedbackRecords
            .compactMap { key, record -> DiscoveredTrack? in
                if let localDiscovery = localDiscoveriesByFeedbackKey[key] {
                    return localDiscovery
                }
                guard let title = record.title else { return nil }
                let updatedAt = TuneAVDateCoding.date(from: record.updatedAt)
                let stationID = record.stationID ?? "tuneav-feedback"
                let discoveryID = DiscoveredTrack.makeID(
                    title: title,
                    artist: record.artist,
                    stationID: stationID
                )
                return DiscoveredTrack(
                    record: DiscoveredTrackRecord(
                        discoveryID: discoveryID,
                        trackKey: key,
                        title: title,
                        artist: record.artist,
                        stationID: stationID,
                        stationName: "Tune AV",
                        artworkURL: nil,
                        stationArtworkURL: nil,
                        playedAt: TuneAVDateCoding.string(from: updatedAt),
                        updatedAt: record.updatedAt
                    )
                )
            }
            .sorted { first, second in
                let firstRank = Self.feedbackSortRank(trackFeedback[Self.trackFeedbackKey(title: first.title, artist: first.artist)])
                let secondRank = Self.feedbackSortRank(trackFeedback[Self.trackFeedbackKey(title: second.title, artist: second.artist)])
                if firstRank == secondRank {
                    return first.playedAt > second.playedAt
                }
                return firstRank < secondRank
            }
    }

    private static func trackFeedbackKey(title: String, artist: String?) -> String {
        [title, artist ?? ""]
            .map { value in
                value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .lowercased()
            }
            .joined(separator: "::")
    }

    private static func feedbackSortRank(_ feedback: TuneAVStationFeedback?) -> Int {
        switch feedback {
        case .liked:
            return 0
        case .notForMe:
            return 1
        case .disliked:
            return 2
        case nil:
            return 3
        }
    }

    private static func loadStationFeedbackRecords() -> TuneAVLocalFeedbackLoadResult {
        guard let data = UserDefaults.standard.data(forKey: stationFeedbackStorageKey) else {
            return TuneAVLocalFeedbackLoadResult(records: [:], needsPersistence: false)
        }
        if let records = try? JSONDecoder().decode([String: TuneAVLocalFeedbackRecord].self, from: data) {
            return TuneAVLocalFeedbackLoadResult(records: records, needsPersistence: false)
        }
        let migrated = (try? JSONDecoder().decode([String: TuneAVStationFeedback].self, from: data)) ?? [:]
        return TuneAVLocalFeedbackLoadResult(
            records: TuneAVLocalFeedbackStore.records(fromLegacy: migrated, updatedAt: .now),
            needsPersistence: !migrated.isEmpty
        )
    }

    private static func saveStationFeedbackRecords(_ feedback: [String: TuneAVLocalFeedbackRecord]) {
        guard !feedback.isEmpty else {
            UserDefaults.standard.removeObject(forKey: stationFeedbackStorageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(feedback) else { return }
        UserDefaults.standard.set(data, forKey: stationFeedbackStorageKey)
    }

    private static func loadTrackFeedbackRecords() -> TuneAVLocalFeedbackLoadResult {
        guard let data = UserDefaults.standard.data(forKey: trackFeedbackStorageKey) else {
            return TuneAVLocalFeedbackLoadResult(records: [:], needsPersistence: false)
        }
        if let records = try? JSONDecoder().decode([String: TuneAVLocalFeedbackRecord].self, from: data) {
            let canonicalRecords = TuneAVLocalFeedbackStore.canonicalizedTrackRecords(records)
            return TuneAVLocalFeedbackLoadResult(records: canonicalRecords, needsPersistence: canonicalRecords != records)
        }
        let migrated = (try? JSONDecoder().decode([String: TuneAVStationFeedback].self, from: data)) ?? [:]
        let records = TuneAVLocalFeedbackStore.canonicalizedTrackRecords(
            TuneAVLocalFeedbackStore.records(fromLegacy: migrated, updatedAt: .now)
        )
        return TuneAVLocalFeedbackLoadResult(
            records: records,
            needsPersistence: !migrated.isEmpty
        )
    }

    private static func saveTrackFeedbackRecords(_ feedback: [String: TuneAVLocalFeedbackRecord]) {
        guard !feedback.isEmpty else {
            UserDefaults.standard.removeObject(forKey: trackFeedbackStorageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(feedback) else { return }
        UserDefaults.standard.set(data, forKey: trackFeedbackStorageKey)
    }

    private static func loadPendingFeedbackUploads() -> [String: TuneAVPendingFeedbackUpload] {
        guard let data = UserDefaults.standard.data(forKey: pendingFeedbackUploadsStorageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: TuneAVPendingFeedbackUpload].self, from: data)) ?? [:]
    }

    private static func savePendingFeedbackUploads(_ uploads: [String: TuneAVPendingFeedbackUpload]) {
        guard !uploads.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pendingFeedbackUploadsStorageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(uploads) else { return }
        UserDefaults.standard.set(data, forKey: pendingFeedbackUploadsStorageKey)
    }

    private func pruneLocalFeedbackIfNeeded() {
        let nextStationRecords = TuneAVLocalFeedbackStore.bounded(
            stationFeedbackRecords,
            maxCount: localFeedbackRetention.stationFeedbackLimit
        )
        if nextStationRecords != stationFeedbackRecords {
            stationFeedbackRecords = nextStationRecords
            stationFeedback = nextStationRecords.mapValues(\.feedback)
            Self.saveStationFeedbackRecords(nextStationRecords)
        }

        let nextTrackRecords = TuneAVLocalFeedbackStore.bounded(
            trackFeedbackRecords,
            maxCount: localFeedbackRetention.trackFeedbackLimit
        )
        if nextTrackRecords != trackFeedbackRecords {
            trackFeedbackRecords = nextTrackRecords
            trackFeedback = nextTrackRecords.mapValues(\.feedback)
            Self.saveTrackFeedbackRecords(nextTrackRecords)
        }
    }

    private func saveAndRefresh(_ scope: RefreshScope = .all, syncsCloud: Bool? = nil) {
        guard context.hasChanges else { return }
        try? context.save()
        refresh(scope)
        if syncsCloud ?? scope.shouldPushCloud {
            scheduleCloudPushIfNeeded()
        }
    }

    private func scheduleCloudPushIfNeeded() {
        guard !isApplyingRemoteSnapshot, let appDataService, appDataService.isConfigured() else {
            return
        }

        pushTask?.cancel()
        pushTask = Task { [appDataService] in
            do {
                try await Task.sleep(for: Self.cloudPushDebounce)
                guard !Task.isCancelled, self.appDataService === appDataService else { return }

                let snapshot = librarySnapshot()
                setCloudSyncStatus(.syncing)
                let remoteDocument = try await appDataService.pullLibrary()
                try Task.checkCancellation()
                guard self.appDataService === appDataService else { return }
                updateSyncDiagnostics { $0.lastCloudPullAt = .now }
                let snapshotToPush: TuneAVLibrarySnapshot
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToPush = cloudBoundedSnapshot(
                        TuneAVLibrarySnapshotMerger.merged(
                            local: snapshot,
                            remote: remoteSnapshot
                        )
                    )
                } else {
                    snapshotToPush = snapshot
                }

                try Task.checkCancellation()
                try await appDataService.pushLibrary(snapshotToPush)
                try Task.checkCancellation()
                guard self.appDataService === appDataService else { return }
                updateSyncDiagnostics { $0.lastCloudPushAt = .now }
                clearSyncedTombstones()
                if snapshotToPush != snapshot {
                    applyRemoteSnapshot(snapshotToPush)
                }
                setCloudSyncStatus(.synced(.now))
            } catch TuneAVAppDataError.conflict {
                guard self.appDataService === appDataService else { return }
                await refreshCloudLibraryIfNeeded(force: true)
            } catch is CancellationError {
                return
            } catch {
                guard self.appDataService === appDataService else { return }
                setCloudSyncStatus(.failed)
            }
        }
    }

    private func enqueueFavoriteLibraryOperation(
        _ operation: CloudLibraryItemOperation,
        record: FavoriteStationRecord
    ) {
        guard !isApplyingRemoteSnapshot,
              appDataService?.isConfigured() == true,
              let userID = backendServiceUserID
        else { return }

        rememberPendingLibraryOperation(
            TuneAVPendingLibraryOperation(
                resource: .favorites,
                action: operation == .upsert ? .upsert : .delete,
                userID: userID,
                identityKey: TuneAVLibrarySnapshotMerger.stationIdentityKey(record.station),
                favoriteRecord: record,
                discoveryRecord: nil,
                updatedAt: TuneAVDateCoding.string(from: .now)
            )
        )
        schedulePendingLibraryOperationsForCurrentUser()
    }

    private func enqueueSavedDiscoveryLibraryOperation(
        _ operation: CloudLibraryItemOperation,
        record: DiscoveredTrackRecord
    ) {
        guard !isApplyingRemoteSnapshot,
              appDataService?.isConfigured() == true,
              let userID = backendServiceUserID
        else { return }

        rememberPendingLibraryOperation(
            TuneAVPendingLibraryOperation(
                resource: .savedDiscoveries,
                action: operation == .upsert ? .upsert : .delete,
                userID: userID,
                identityKey: TuneAVLibrarySnapshotMerger.discoveryIdentityKey(record),
                favoriteRecord: nil,
                discoveryRecord: record,
                updatedAt: TuneAVDateCoding.string(from: .now)
            )
        )
        schedulePendingLibraryOperationsForCurrentUser()
    }

    private func rememberPendingLibraryOperation(_ operation: TuneAVPendingLibraryOperation) {
        let key = operation.storageKey
        librarySyncTasks[key]?.cancel()
        librarySyncTasks[key] = nil
        librarySyncTokens[key] = nil
        librarySyncRetryCounts[key] = nil
        pendingLibraryOperations = TuneAVPendingLibraryOutbox.upserting(
            operation,
            into: pendingLibraryOperations
        )
        persistPendingLibraryOperations()
    }

    private func schedulePendingLibraryOperationsForCurrentUser() {
        guard let appDataService,
              appDataService.isConfigured(),
              let userID = backendServiceUserID
        else { return }

        if activePendingLibraryOperationUserID != userID {
            stopPendingLibraryOperations()
            activePendingLibraryOperationUserID = userID
        }

        for operation in pendingLibraryOperations.values where operation.userID == userID {
            guard librarySyncTasks[operation.storageKey] == nil else { continue }
            startPendingLibraryOperation(
                operation,
                retryCount: 0,
                appDataService: appDataService
            )
        }
    }

    private func startPendingLibraryOperation(
        _ operation: TuneAVPendingLibraryOperation,
        retryCount: Int,
        appDataService: TuneAVAppDataService
    ) {
        let key = operation.storageKey
        let token = UUID()
        let delay = retryCount == 0
            ? 1
            : LibraryStoreListeningSessionRetryPolicy.delay(
                retryCount: retryCount - 1,
                baseDelay: Self.librarySyncRetryBaseDelay,
                maxDelay: Self.librarySyncRetryMaxDelay,
                jitterFraction: Self.librarySyncRetryJitterFraction
            )

        librarySyncTokens[key] = token
        librarySyncRetryCounts[key] = retryCount
        librarySyncTasks[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                guard let self,
                      !Task.isCancelled,
                      self.backendServiceUserID == operation.userID,
                      self.appDataService === appDataService,
                      self.pendingLibraryOperations[key]?.id == operation.id,
                      self.librarySyncTokens[key] == token
                else { return }
                try await self.sendPendingLibraryOperation(
                    operation,
                    using: appDataService
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.backendServiceUserID == operation.userID,
                      self.appDataService === appDataService,
                      self.pendingLibraryOperations[key]?.id == operation.id,
                      self.librarySyncTokens[key] == token
                else { return }
                if retryCount == 0 {
                    self.analyticsLogger.debug(
                        "Library cloud item operation failed; retry scheduled resource=\(operation.resource.rawValue, privacy: .public)"
                    )
                }
                self.startPendingLibraryOperation(
                    operation,
                    retryCount: retryCount + 1,
                    appDataService: appDataService
                )
                return
            }

            guard let self,
                  self.pendingLibraryOperations[key]?.id == operation.id,
                  self.librarySyncTokens[key] == token
            else { return }
            self.pendingLibraryOperations[key] = nil
            self.librarySyncTasks[key] = nil
            self.librarySyncTokens[key] = nil
            self.librarySyncRetryCounts[key] = nil
            self.persistPendingLibraryOperations()
            self.updateSyncDiagnostics { $0.lastCloudPushAt = .now }
        }
    }

    private func sendPendingLibraryOperation(
        _ operation: TuneAVPendingLibraryOperation,
        using appDataService: TuneAVAppDataService
    ) async throws {
        switch (operation.resource, operation.action) {
        case (.favorites, .upsert):
            guard let record = operation.favoriteRecord else {
                throw TuneAVPendingLibraryOperationError.invalidPayload
            }
            try await appDataService.upsertFavorite(record)
        case (.favorites, .delete):
            guard let record = operation.favoriteRecord else {
                throw TuneAVPendingLibraryOperationError.invalidPayload
            }
            try await appDataService.deleteFavorite(record)
        case (.savedDiscoveries, .upsert):
            guard let record = operation.discoveryRecord else {
                throw TuneAVPendingLibraryOperationError.invalidPayload
            }
            try await appDataService.upsertSavedDiscovery(record)
        case (.savedDiscoveries, .delete):
            guard let record = operation.discoveryRecord else {
                throw TuneAVPendingLibraryOperationError.invalidPayload
            }
            try await appDataService.deleteSavedDiscovery(record)
        }
    }

    private func persistPendingLibraryOperations() {
        LibraryStorePendingLibraryOperationPersistence.save(
            pendingLibraryOperations,
            storageKey: Self.pendingLibraryOperationsStorageKey,
            userDefaults: userDefaults
        )
    }

    private func stopPendingLibraryOperations() {
        librarySyncTasks.values.forEach { $0.cancel() }
        librarySyncTasks.removeAll()
        librarySyncTokens.removeAll()
        librarySyncRetryCounts.removeAll()
        activePendingLibraryOperationUserID = nil
    }

    private func syncStationFeedback(_ feedback: TuneAVStationFeedback?, stationID: String) {
        guard shouldUploadFeedbackToBackend else { return }
        guard let backendService, backendService.isConfigured() else { return }

        let token = UUID()
        stationFeedbackSyncTasks[stationID]?.cancel()
        stationFeedbackSyncTokens[stationID] = token
        stationFeedbackSyncRetryCounts[stationID] = 0
        startStationFeedbackSync(feedback, stationID: stationID, token: token, retryCount: 0, backendService: backendService)
    }

    private func startStationFeedbackSync(
        _ feedback: TuneAVStationFeedback?,
        stationID: String,
        token: UUID,
        retryCount: Int,
        backendService: TuneAVAppDataService
    ) {
        let delay = retryCount == 0
            ? 1
            : LibraryStoreListeningSessionRetryPolicy.delay(
                retryCount: retryCount - 1,
                baseDelay: Self.feedbackSyncRetryBaseDelay,
                maxDelay: Self.feedbackSyncRetryMaxDelay,
                jitterFraction: Self.feedbackSyncRetryJitterFraction
            )

        stationFeedbackSyncRetryCounts[stationID] = retryCount
        stationFeedbackSyncTasks[stationID] = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                guard !Task.isCancelled,
                      self.backendService === backendService,
                      self.stationFeedbackSyncTokens[stationID] == token
                else { return }
                try await backendService.setStationFeedback(feedback, stationID: stationID)
            } catch is CancellationError {
                return
            } catch {
                guard self.backendService === backendService else { return }
                retryStationFeedbackSyncIfCurrent(
                    feedback,
                    stationID: stationID,
                    token: token,
                    retryCount: retryCount + 1,
                    backendService: backendService
                )
                return
            }
            guard self.backendService === backendService else { return }
            clearStationFeedbackSyncIfCurrent(stationID: stationID, token: token)
        }
    }

    private func syncTrackFeedback(_ feedback: TuneAVStationFeedback?, title: String?, artist: String?, stationID: String?) {
        guard shouldUploadFeedbackToBackend else { return }
        guard
            let backendService,
            backendService.isConfigured(),
            let title = normalizedTrackValue(title),
            let feedbackKey = discoveredTrackFeedbackKey(title: title, artist: artist)
        else { return }

        let normalizedArtist = normalizedTrackValue(artist)
        let token = UUID()
        trackFeedbackSyncTasks[feedbackKey]?.cancel()
        trackFeedbackSyncTokens[feedbackKey] = token
        trackFeedbackSyncRetryCounts[feedbackKey] = 0
        startTrackFeedbackSync(
            feedback,
            feedbackKey: feedbackKey,
            title: title,
            artist: normalizedArtist,
            stationID: stationID,
            token: token,
            retryCount: 0,
            backendService: backendService
        )
    }

    private func startTrackFeedbackSync(
        _ feedback: TuneAVStationFeedback?,
        feedbackKey: String,
        title: String,
        artist: String?,
        stationID: String?,
        token: UUID,
        retryCount: Int,
        backendService: TuneAVAppDataService
    ) {
        let delay = retryCount == 0
            ? 1
            : LibraryStoreListeningSessionRetryPolicy.delay(
                retryCount: retryCount - 1,
                baseDelay: Self.feedbackSyncRetryBaseDelay,
                maxDelay: Self.feedbackSyncRetryMaxDelay,
                jitterFraction: Self.feedbackSyncRetryJitterFraction
            )

        trackFeedbackSyncRetryCounts[feedbackKey] = retryCount
        trackFeedbackSyncTasks[feedbackKey] = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
                guard !Task.isCancelled,
                      self.backendService === backendService,
                      self.trackFeedbackSyncTokens[feedbackKey] == token
                else { return }
                try await backendService.setTrackFeedback(feedback, title: title, artist: artist, stationID: stationID)
            } catch is CancellationError {
                return
            } catch {
                guard self.backendService === backendService else { return }
                retryTrackFeedbackSyncIfCurrent(
                    feedback,
                    feedbackKey: feedbackKey,
                    title: title,
                    artist: artist,
                    stationID: stationID,
                    token: token,
                    retryCount: retryCount + 1,
                    backendService: backendService
                )
                return
            }
            guard self.backendService === backendService else { return }
            clearTrackFeedbackSyncIfCurrent(feedbackKey: feedbackKey, token: token)
        }
    }

    private func retryStationFeedbackSyncIfCurrent(
        _ feedback: TuneAVStationFeedback?,
        stationID: String,
        token: UUID,
        retryCount: Int,
        backendService: TuneAVAppDataService
    ) {
        guard stationFeedbackSyncTokens[stationID] == token else { return }
        startStationFeedbackSync(feedback, stationID: stationID, token: token, retryCount: retryCount, backendService: backendService)
    }

    private func retryTrackFeedbackSyncIfCurrent(
        _ feedback: TuneAVStationFeedback?,
        feedbackKey: String,
        title: String,
        artist: String?,
        stationID: String?,
        token: UUID,
        retryCount: Int,
        backendService: TuneAVAppDataService
    ) {
        guard trackFeedbackSyncTokens[feedbackKey] == token else { return }
        startTrackFeedbackSync(
            feedback,
            feedbackKey: feedbackKey,
            title: title,
            artist: artist,
            stationID: stationID,
            token: token,
            retryCount: retryCount,
            backendService: backendService
        )
    }

    private func clearStationFeedbackSyncIfCurrent(stationID: String, token: UUID) {
        guard stationFeedbackSyncTokens[stationID] == token else { return }
        stationFeedbackSyncTasks[stationID] = nil
        stationFeedbackSyncTokens[stationID] = nil
        stationFeedbackSyncRetryCounts[stationID] = nil
        clearPendingFeedbackUpload(key: TuneAVPendingFeedbackUpload.stationKey(stationID))
    }

    private func clearTrackFeedbackSyncIfCurrent(feedbackKey: String, token: UUID) {
        guard trackFeedbackSyncTokens[feedbackKey] == token else { return }
        trackFeedbackSyncTasks[feedbackKey] = nil
        trackFeedbackSyncTokens[feedbackKey] = nil
        trackFeedbackSyncRetryCounts[feedbackKey] = nil
        clearPendingFeedbackUpload(key: TuneAVPendingFeedbackUpload.trackKey(feedbackKey))
    }

    private func rememberPendingStationFeedbackUpload(_ feedback: TuneAVStationFeedback?, stationID: String) {
        guard let userID = backendServiceUserID else { return }
        let key = TuneAVPendingFeedbackUpload.stationKey(stationID)
        pendingFeedbackUploads[key] = TuneAVPendingFeedbackUpload(
            kind: .station,
            userID: userID,
            key: key,
            feedback: feedback,
            stationID: stationID,
            title: nil,
            artist: nil,
            updatedAt: TuneAVDateCoding.string(from: .now)
        )
        updateSyncDiagnostics { $0.pendingFeedbackUploadCount = pendingFeedbackUploads.count }
        Self.savePendingFeedbackUploads(pendingFeedbackUploads)
    }

    private func rememberPendingTrackFeedbackUpload(
        _ feedback: TuneAVStationFeedback?,
        feedbackKey: String,
        title: String?,
        artist: String?,
        stationID: String?
    ) {
        guard let userID = backendServiceUserID, let title else { return }
        let key = TuneAVPendingFeedbackUpload.trackKey(feedbackKey)
        pendingFeedbackUploads[key] = TuneAVPendingFeedbackUpload(
            kind: .track,
            userID: userID,
            key: key,
            feedback: feedback,
            stationID: stationID,
            title: title,
            artist: artist,
            updatedAt: TuneAVDateCoding.string(from: .now)
        )
        updateSyncDiagnostics { $0.pendingFeedbackUploadCount = pendingFeedbackUploads.count }
        Self.savePendingFeedbackUploads(pendingFeedbackUploads)
    }

    private func clearPendingFeedbackUpload(key: String) {
        guard pendingFeedbackUploads[key] != nil else { return }
        pendingFeedbackUploads[key] = nil
        updateSyncDiagnostics { $0.pendingFeedbackUploadCount = pendingFeedbackUploads.count }
        Self.savePendingFeedbackUploads(pendingFeedbackUploads)
    }

    private func schedulePendingFeedbackUploadsForCurrentUser() {
        guard let userID = backendServiceUserID else { return }
        for upload in pendingFeedbackUploads.values where upload.userID == userID {
            switch upload.kind {
            case .station:
                guard let stationID = upload.stationID else { continue }
                syncStationFeedback(upload.feedback, stationID: stationID)
            case .track:
                guard let title = upload.title else { continue }
                syncTrackFeedback(upload.feedback, title: title, artist: upload.artist, stationID: upload.stationID)
            }
        }
    }

    private func librarySnapshot() -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: favorites.map {
                FavoriteStationRecord(
                    station: Station(favorite: $0).appDataRecord,
                    createdAt: TuneAVAppDataService.isoString(from: $0.createdAt)
                )
            } + tombstoneRecords(resource: "favorites", type: FavoriteStationRecord.self),
            savedDiscoveries: savedDiscoveryRecords() + tombstoneRecords(resource: "savedDiscoveries", type: DiscoveredTrackRecord.self)
        )
    }

    private func cloudBoundedSnapshot(_ snapshot: TuneAVLibrarySnapshot) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: snapshot.favorites,
            savedDiscoveries: cloudBoundedDiscoveryRecords(snapshot.savedDiscoveries.filter { $0.deletedAt == nil })
                + snapshot.savedDiscoveries.filter { $0.deletedAt != nil }
        )
    }

    private func cloudBoundedDiscoveryRecords(_ records: [DiscoveredTrackRecord]) -> [DiscoveredTrackRecord] {
        records
            .sorted { lhs, rhs in
                let lhsPinned = lhs.markedInterestedAt != nil
                let rhsPinned = rhs.markedInterestedAt != nil
                if lhsPinned != rhsPinned {
                    return lhsPinned
                }

                let lhsDate = [lhs.updatedAt, lhs.markedInterestedAt, lhs.hiddenAt, lhs.deletedAt, lhs.playedAt]
                    .compactMap { $0 }
                    .map(TuneAVDateCoding.date(from:))
                    .max() ?? .distantPast
                let rhsDate = [rhs.updatedAt, rhs.markedInterestedAt, rhs.hiddenAt, rhs.deletedAt, rhs.playedAt]
                    .compactMap { $0 }
                    .map(TuneAVDateCoding.date(from:))
                    .max() ?? .distantPast
                return lhsDate > rhsDate
            }
            .prefix(Self.maxCloudDiscoveryRecords)
            .map { $0 }
    }

    private func latestLocalUpdateAt() -> Date {
        let timestamps =
            favorites.map(\.createdAt) +
            tombstones().filter { $0.resource == "favorites" || $0.resource == "savedDiscoveries" }.map(\.deletedAt) +
            discoveries.filter(\.isMarkedInteresting).flatMap { discovery in
                [discovery.markedInterestedAt, discovery.updatedAt].compactMap { $0 }
            }
        return timestamps.max() ?? .distantPast
    }

    private func latestLocalLibraryUpdateAt() -> Date {
        let timestamps =
            favorites.map(\.createdAt) +
            tombstones().filter { $0.resource == "favorites" || $0.resource == "savedDiscoveries" }.map(\.deletedAt) +
            discoveries.filter(\.isMarkedInteresting).flatMap { discovery in
                [discovery.markedInterestedAt, discovery.updatedAt].compactMap { $0 }
            }
        return timestamps.max() ?? .distantPast
    }

    private func applyRemoteSnapshot(_ snapshot: TuneAVLibrarySnapshot) {
        isApplyingRemoteSnapshot = true
        defer { isApplyingRemoteSnapshot = false }

        for favorite in favorites {
            context.delete(favorite)
        }

        for tombstone in tombstones() where tombstone.resource == "favorites" || tombstone.resource == "savedDiscoveries" {
            context.delete(tombstone)
        }

        for favorite in snapshot.favorites {
            if let deletedAt = favorite.deletedAt {
                rememberTombstone(
                    resource: "favorites",
                    identityKey: TuneAVLibrarySnapshotMerger.stationIdentityKey(favorite.station),
                    payload: favorite,
                    deletedAt: Self.date(from: deletedAt)
                )
                continue
            }

            context.insert(
                FavoriteStation(
                    station: Station(record: favorite.station),
                    createdAt: favorite.createdAt.map(Self.date(from:)) ?? .distantPast
                )
            )
        }

        let localDiscoveriesByID = Dictionary(discoveries.map { ($0.discoveryID, $0) }, uniquingKeysWith: { first, _ in first })
        let localDiscoveriesByIdentity = Dictionary(
            discoveries.map { (savedDiscoveryIdentityKey(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for discovery in snapshot.savedDiscoveries {
            let discoveryIdentityKey = TuneAVLibrarySnapshotMerger.discoveryIdentityKey(discovery)
            if let deletedAt = discovery.deletedAt {
                rememberTombstone(
                    resource: "savedDiscoveries",
                    identityKey: discoveryIdentityKey,
                    payload: discovery,
                    deletedAt: Self.date(from: deletedAt)
                )
                if let existing = localDiscoveriesByID[discovery.discoveryID] ?? localDiscoveriesByIdentity[discoveryIdentityKey] {
                    existing.markedInterestedAt = nil
                    existing.updatedAt = Self.date(from: deletedAt)
                }
                continue
            }

            if let existing = localDiscoveriesByID[discovery.discoveryID] ?? localDiscoveriesByIdentity[discoveryIdentityKey] {
                existing.markedInterestedAt = discovery.markedInterestedAt.map(Self.date(from:)) ?? Self.date(from: discovery.updatedAt ?? discovery.playedAt)
                existing.hiddenAt = nil
                existing.artworkURL = discovery.artworkURL ?? existing.artworkURL
                existing.stationArtworkURL = discovery.stationArtworkURL ?? existing.stationArtworkURL
                existing.updatedAt = discovery.updatedAt.map(Self.date(from:)) ?? existing.updatedAt
            } else {
                context.insert(DiscoveredTrack(record: discovery))
            }
        }

        try? context.save()
        refresh()
    }

    private static func date(from value: String) -> Date {
        TuneAVDateCoding.date(from: value)
    }

    @discardableResult
    private func rememberFavoriteDeletion(for station: Station) -> FavoriteStationRecord {
        let deletedAt = Date.now
        let record = FavoriteStationRecord(
            station: station.appDataRecord,
            deletedAt: TuneAVAppDataService.isoString(from: deletedAt)
        )
        rememberTombstone(
            resource: "favorites",
            identityKey: Self.stationIdentityKey(for: station),
            payload: record,
            deletedAt: deletedAt
        )
        return record
    }

    @discardableResult
    private func rememberSavedDiscoveryDeletion(for discovery: DiscoveredTrack) -> DiscoveredTrackRecord {
        let deletedAt = Date.now
        let record = DiscoveredTrackRecord(
            discoveryID: discovery.discoveryID,
            trackKey: discovery.trackKey,
            title: discovery.title,
            artist: discovery.artist,
            stationID: discovery.stationID,
            stationName: discovery.stationName,
            artworkURL: discovery.artworkURL,
            stationArtworkURL: discovery.stationArtworkURL,
            playedAt: TuneAVAppDataService.isoString(from: discovery.playedAt),
            markedInterestedAt: discovery.markedInterestedAt.map(TuneAVAppDataService.isoString(from:)),
            hiddenAt: discovery.hiddenAt.map(TuneAVAppDataService.isoString(from:)),
            deletedAt: TuneAVAppDataService.isoString(from: deletedAt),
            updatedAt: TuneAVAppDataService.isoString(from: deletedAt)
        )
        rememberTombstone(
            resource: "savedDiscoveries",
            identityKey: savedDiscoveryIdentityKey(for: discovery),
            payload: record,
            deletedAt: deletedAt
        )
        return record
    }

    private func rememberTombstone<Payload: Encodable>(
        resource: String,
        identityKey: String,
        payload: Payload,
        deletedAt: Date
    ) {
        guard let payloadJSON = TuneAVLibraryTombstoneCoding.payloadJSON(for: payload, encoder: tombstoneEncoder) else {
            return
        }

        let resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        if let existing = tombstones().first(where: { $0.resourceKey == resourceKey }) {
            existing.payloadJSON = payloadJSON
            existing.deletedAt = deletedAt
        } else {
            context.insert(
                LibrarySyncTombstone(
                    resource: resource,
                    identityKey: identityKey,
                    payloadJSON: payloadJSON,
                    deletedAt: deletedAt
                )
            )
        }
    }

    private func savedDiscoveryIdentityKey(for discovery: DiscoveredTrack) -> String {
        TuneAVLibrarySnapshotMerger.discoveryIdentityKey(discovery.appDataRecord)
    }

    private static func savedDiscoveryIdentityKey(title: String, artist: String?) -> String {
        "track:\(TuneAVDiscoveredTrackSupport.trackKey(title: title, artist: artist, locale: L10n.locale))"
    }

    private func removeTombstone(resource: String, identityKey: String) {
        let resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        for tombstone in tombstones() where tombstone.resourceKey == resourceKey {
            context.delete(tombstone)
        }
    }

    private func hasTombstone(resource: String, identityKey: String) -> Bool {
        let resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        return tombstones().contains { $0.resourceKey == resourceKey }
    }

    private func tombstoneRecords<Record: Decodable>(resource: String, type: Record.Type) -> [Record] {
        let sharedTombstones = tombstones()
            .filter { $0.resource == resource }
            .sorted { $0.deletedAt > $1.deletedAt }
            .map(\.sharedTombstone)
        return TuneAVLibraryTombstoneCoding.records(for: resource, in: sharedTombstones, as: type, decoder: tombstoneDecoder)
    }

    private func tombstones() -> [LibrarySyncTombstone] {
        (try? context.fetch(FetchDescriptor<LibrarySyncTombstone>())) ?? []
    }

    private func savedDiscoveryRecords() -> [DiscoveredTrackRecord] {
        discoveries
            .filter(\.isMarkedInteresting)
            .sorted { lhs, rhs in
                let lhsDate = [lhs.updatedAt, lhs.markedInterestedAt, lhs.playedAt].compactMap { $0 }.max() ?? lhs.playedAt
                let rhsDate = [rhs.updatedAt, rhs.markedInterestedAt, rhs.playedAt].compactMap { $0 }.max() ?? rhs.playedAt
                return lhsDate > rhsDate
            }
            .prefix(Self.maxCloudDiscoveryRecords)
            .map(\.appDataRecord)
    }

    private func clearSyncedTombstones() {
        let currentTombstones = tombstones()
        guard !currentTombstones.isEmpty else { return }
        currentTombstones.forEach(context.delete)
        try? context.save()
    }

    private static func stationIdentityKey(for station: Station) -> String {
        TuneAVLibrarySnapshotMerger.stationIdentityKey(station.appDataRecord)
    }

    private static func loadPendingListeningSessions(maxCount: Int) -> [TuneAVListeningSessionDraft] {
        LibraryStoreListeningSessionPersistence.load(
            storageKey: pendingListeningSessionsStorageKey,
            maxCount: maxCount,
            maxAge: maxPendingListeningSessionAge
        )
    }

    private func persistPendingListeningSessions() {
        LibraryStoreListeningSessionPersistence.save(
            pendingListeningSessions,
            storageKey: Self.pendingListeningSessionsStorageKey,
            maxCount: Self.maxPendingListeningSessions,
            maxAge: Self.maxPendingListeningSessionAge
        )
    }

    private func uploadablePendingListeningSessions() -> [TuneAVListeningSessionDraft] {
        guard let backendServiceUserID else { return [] }
        return pendingListeningSessions.filter { $0.userID == backendServiceUserID }
    }

    private func updatePendingListeningSessionDiagnostic() {
        updateSyncDiagnostics {
            $0.pendingListeningSessionCount = uploadablePendingListeningSessions().count
        }
    }
}

enum LibraryStoreListeningSessionBuffer {
    static func bounded(
        _ sessions: [TuneAVListeningSessionDraft],
        maxCount: Int
    ) -> [TuneAVListeningSessionDraft] {
        trimmed(deduplicated(sessions), maxCount: maxCount)
    }

    static func deduplicated(_ sessions: [TuneAVListeningSessionDraft]) -> [TuneAVListeningSessionDraft] {
        var seenSessionIDs = Set<String>()
        var uniqueSessions: [TuneAVListeningSessionDraft] = []

        for session in sessions.reversed() where seenSessionIDs.insert(session.id).inserted {
            uniqueSessions.append(session)
        }

        return uniqueSessions.reversed()
    }

    static func trimmed(
        _ sessions: [TuneAVListeningSessionDraft],
        maxCount: Int
    ) -> [TuneAVListeningSessionDraft] {
        guard maxCount > 0 else { return [] }
        guard sessions.count > maxCount else { return sessions }
        return Array(sessions.suffix(maxCount))
    }
}

struct TuneAVPendingLibraryOperation: Codable, Equatable {
    enum Resource: String, Codable {
        case favorites
        case savedDiscoveries
    }

    enum Action: String, Codable {
        case upsert
        case delete
    }

    let id: UUID
    let resource: Resource
    let action: Action
    let userID: String
    let identityKey: String
    let favoriteRecord: FavoriteStationRecord?
    let discoveryRecord: DiscoveredTrackRecord?
    let updatedAt: String

    init(
        id: UUID = UUID(),
        resource: Resource,
        action: Action,
        userID: String,
        identityKey: String,
        favoriteRecord: FavoriteStationRecord?,
        discoveryRecord: DiscoveredTrackRecord?,
        updatedAt: String
    ) {
        self.id = id
        self.resource = resource
        self.action = action
        self.userID = userID
        self.identityKey = identityKey
        self.favoriteRecord = favoriteRecord
        self.discoveryRecord = discoveryRecord
        self.updatedAt = updatedAt
    }

    var storageKey: String {
        "\(userID):\(resource.rawValue):\(identityKey)"
    }
}

enum TuneAVPendingLibraryOutbox {
    static func upserting(
        _ operation: TuneAVPendingLibraryOperation,
        into operations: [String: TuneAVPendingLibraryOperation]
    ) -> [String: TuneAVPendingLibraryOperation] {
        var nextOperations = operations
        nextOperations[operation.storageKey] = operation
        return nextOperations
    }
}

enum LibraryStorePendingLibraryOperationPersistence {
    static func load(
        storageKey: String,
        userDefaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [String: TuneAVPendingLibraryOperation] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [:] }
        return (try? decoder.decode([String: TuneAVPendingLibraryOperation].self, from: data)) ?? [:]
    }

    static func save(
        _ operations: [String: TuneAVPendingLibraryOperation],
        storageKey: String,
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        guard !operations.isEmpty else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? encoder.encode(operations) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

enum TuneAVPendingLibraryOperationError: Error {
    case invalidPayload
}

struct TuneAVPendingFeedbackUpload: Codable, Equatable {
    enum Kind: String, Codable {
        case station
        case track
    }

    let kind: Kind
    let userID: String
    let key: String
    let feedback: TuneAVStationFeedback?
    let stationID: String?
    let title: String?
    let artist: String?
    let updatedAt: String

    static func stationKey(_ stationID: String) -> String {
        "station:\(stationID)"
    }

    static func trackKey(_ feedbackKey: String) -> String {
        "track:\(feedbackKey)"
    }
}

struct TuneAVSyncDiagnostics: Equatable {
    var lastCloudPullAt: Date?
    var lastCloudPushAt: Date?
    var lastSummaryFetchAt: Date?
    var pendingListeningSessionCount: Int = 0
    var pendingFeedbackUploadCount: Int = 0

    var isSummaryStale: Bool {
        let latestLibrarySyncAt = [lastCloudPullAt, lastCloudPushAt].compactMap { $0 }.max()
        guard let latestLibrarySyncAt else { return false }
        guard let lastSummaryFetchAt else { return true }
        return lastSummaryFetchAt < latestLibrarySyncAt
    }
}

struct TuneAVLocalFeedbackRetention: Equatable {
    let stationFeedbackLimit: Int
    let trackFeedbackLimit: Int

    static let maximumLocalRetention = TuneAVLocalFeedbackRetention(stationFeedbackLimit: 300, trackFeedbackLimit: 300)

    static func forMode(_ accessMode: AccessMode) -> TuneAVLocalFeedbackRetention {
        switch accessMode {
        case .guest:
            TuneAVLocalFeedbackRetention(stationFeedbackLimit: 50, trackFeedbackLimit: 50)
        case .signedInFree:
            TuneAVLocalFeedbackRetention(stationFeedbackLimit: 100, trackFeedbackLimit: 100)
        case .signedInPro:
            maximumLocalRetention
        }
    }
}

enum LibraryStoreListeningSessionPersistence {
    static func load(
        storageKey: String,
        userDefaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder(),
        maxCount: Int,
        maxAge: TimeInterval,
        now: Date = Date()
    ) -> [TuneAVListeningSessionDraft] {
        guard let data = userDefaults.data(forKey: storageKey),
              let sessions = try? decoder.decode([TuneAVListeningSessionDraft].self, from: data) else {
            return []
        }

        return LibraryStoreListeningSessionBuffer.bounded(
            retained(sessions, maxAge: maxAge, now: now),
            maxCount: maxCount
        )
    }

    static func save(
        _ sessions: [TuneAVListeningSessionDraft],
        storageKey: String,
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        maxCount: Int,
        maxAge: TimeInterval,
        now: Date = Date()
    ) {
        let boundedSessions = LibraryStoreListeningSessionBuffer.bounded(
            retained(sessions, maxAge: maxAge, now: now),
            maxCount: maxCount
        )
        guard !boundedSessions.isEmpty else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? encoder.encode(boundedSessions) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private static func retained(
        _ sessions: [TuneAVListeningSessionDraft],
        maxAge: TimeInterval,
        now: Date
    ) -> [TuneAVListeningSessionDraft] {
        guard maxAge > 0 else { return [] }
        let oldestAllowedEndedAt = now.addingTimeInterval(-maxAge)
        return sessions.filter { $0.endedAt >= oldestAllowedEndedAt && $0.endedAt <= now }
    }
}

enum LibraryStoreListeningSessionRetryPolicy {
    static func delay(
        retryCount: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        jitterFraction: Double,
        randomFraction: () -> Double = { Double.random(in: 0...1) }
    ) -> TimeInterval {
        guard baseDelay > 0, maxDelay > 0 else { return 0 }

        let boundedRetryCount = max(0, min(retryCount, 10))
        let exponentialDelay = baseDelay * pow(2, Double(boundedRetryCount))
        let cappedDelay = min(exponentialDelay, maxDelay)
        let boundedJitter = max(0, min(jitterFraction, 1))
        let jitterMultiplier = 1 + ((max(0, min(randomFraction(), 1)) * 2) - 1) * boundedJitter

        return min(cappedDelay * jitterMultiplier, maxDelay)
    }
}

private extension LibrarySyncTombstone {
    var sharedTombstone: TuneAVLibraryTombstone {
        TuneAVLibraryTombstone(
            resource: resource,
            identityKey: identityKey,
            payloadJSON: payloadJSON,
            deletedAt: deletedAt
        )
    }
}
