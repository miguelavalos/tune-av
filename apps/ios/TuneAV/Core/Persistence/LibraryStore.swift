import OSLog
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

    private static let stationFeedbackStorageKey = "tuneav.stationFeedback.v1"
    private static let trackFeedbackStorageKey = "tuneav.trackFeedback.v1"
    private static let pendingListeningSessionsStorageKey = "tuneav.pendingListeningSessions.v1"
    private static let userSummaryRefreshInterval: TimeInterval = 300
    private static let cloudLibraryRefreshInterval: TimeInterval = 300
    private static let discoveryRefreshInterval: TimeInterval = 60
    private static let listeningSessionBatchSize = 5
    private static let maxPendingListeningSessions = 50
    private static let listeningSessionRetryBaseDelay: TimeInterval = 30
    private static let listeningSessionRetryMaxDelay: TimeInterval = 300
    private static let listeningSessionRetryJitterFraction = 0.2
    private static let cloudPushDebounce: Duration = .seconds(2)

    private let context: ModelContext
    private let analyticsLogger = Logger(subsystem: "com.avalsys.tuneav", category: "listening-analytics")
    private var appDataService: TuneAVAppDataService?
    private var backendService: TuneAVAppDataService?
    private let tombstoneEncoder = JSONEncoder()
    private let tombstoneDecoder = JSONDecoder()
    private var isApplyingRemoteSnapshot = false
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
    private var stationFeedbackSyncTokens: [String: UUID] = [:]
    private var trackFeedbackSyncTokens: [String: UUID] = [:]

    private enum RefreshScope {
        case favorites
        case recents
        case discoveries
        case settings
        case favoritesAndRecents
        case recentsAndSettings
        case discoveriesAndSettings
        case all
    }

    init(container: ModelContainer) {
        self.context = ModelContext(container)

        if let existingSettings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            self.settings = existingSettings
        } else {
            let settings = AppSettings()
            context.insert(settings)
            try? context.save()
            self.settings = settings
        }

        stationFeedback = Self.loadStationFeedback()
        trackFeedback = Self.loadTrackFeedback()
        pendingListeningSessions = Self.loadPendingListeningSessions(maxCount: Self.maxPendingListeningSessions)
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

    func isFavorite(_ station: Station) -> Bool {
        let identityKey = Self.stationIdentityKey(for: station)
        return favorites.contains {
            $0.stationID == station.id || Self.stationIdentityKey(for: Station(favorite: $0)) == identityKey
        }
    }

    func toggleFavorite(for station: Station) {
        let identityKey = Self.stationIdentityKey(for: station)
        if let existing = favorites.first(where: { $0.stationID == station.id || Self.stationIdentityKey(for: Station(favorite: $0)) == identityKey }) {
            rememberFavoriteDeletion(for: Station(favorite: existing))
            context.delete(existing)
        } else {
            removeTombstone(resource: "favorites", identityKey: identityKey)
            context.insert(FavoriteStation(station: station))
        }

        saveAndRefresh(.favorites)
    }

    func rememberStationSnapshots(_ stations: [Station]) {
        guard !stations.isEmpty else { return }

        var didUpdate = false
        for station in stations {
            if let favorite = favorites.first(where: { $0.stationID == station.id }) {
                didUpdate = favorite.updateStationSnapshot(station) || didUpdate
            }

            if let recent = recents.first(where: { $0.stationID == station.id }) {
                didUpdate = recent.updateStationSnapshot(station) || didUpdate
            }
        }

        guard didUpdate else { return }
        saveAndRefresh(.favoritesAndRecents)
    }

    func recordPlayback(of station: Station, recentLimit: Int? = nil) {
        let identityKey = Self.stationIdentityKey(for: station)
        removeTombstone(resource: "recents", identityKey: identityKey)
        if let existing = recents.first(where: { $0.stationID == station.id || Self.stationIdentityKey(for: Station(recent: $0)) == identityKey }) {
            updateRecent(existing, with: station)
            for duplicate in recents where duplicate !== existing && Self.stationIdentityKey(for: Station(recent: duplicate)) == identityKey {
                rememberRecentDeletion(for: Station(recent: duplicate))
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
        if discovery.isMarkedInteresting {
            discovery.markedInterestedAt = nil
        } else {
            if let savedLimit, savedDiscoveriesCount >= savedLimit {
                return false
            }

            discovery.markedInterestedAt = .now
            discovery.hiddenAt = nil
        }

        saveAndRefresh(.discoveries)
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
        discovery.hiddenAt = .now
        discovery.markedInterestedAt = nil
        saveAndRefresh(.discoveries)
    }

    func restoreDiscovery(_ discovery: DiscoveredTrack) {
        guard discovery.hiddenAt != nil else { return }
        discovery.hiddenAt = nil
        saveAndRefresh(.discoveries)
    }

    func feedback(for station: Station) -> TuneAVStationFeedback? {
        stationFeedback[station.id]
    }

    func setFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        var nextFeedback = stationFeedback
        if let feedback {
            nextFeedback[station.id] = feedback
        } else {
            nextFeedback.removeValue(forKey: station.id)
        }

        guard nextFeedback != stationFeedback else { return }
        stationFeedback = nextFeedback
        Self.saveStationFeedback(stationFeedback)
        syncStationFeedback(feedback, stationID: station.id)
    }

    func feedbackForDiscoveredTrack(title: String?, artist: String?) -> TuneAVStationFeedback? {
        guard let key = discoveredTrackFeedbackKey(title: title, artist: artist) else { return nil }
        return trackFeedback[key]
    }

    func feedback(for discovery: DiscoveredTrack) -> TuneAVStationFeedback? {
        feedbackForDiscoveredTrack(title: discovery.title, artist: discovery.artist)
    }

    func setFeedbackForDiscoveredTrack(_ feedback: TuneAVStationFeedback?, title: String?, artist: String?) {
        guard let key = discoveredTrackFeedbackKey(title: title, artist: artist) else { return }

        var nextFeedback = trackFeedback
        if let feedback {
            nextFeedback[key] = feedback
        } else {
            nextFeedback.removeValue(forKey: key)
        }

        guard nextFeedback != trackFeedback else { return }
        trackFeedback = nextFeedback
        Self.saveTrackFeedback(trackFeedback)
        syncTrackFeedback(feedback, title: title, artist: artist, stationID: nil)
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

        let now = Date.now
        let nextArtworkURL = artworkURL?.absoluteString

        if let existing = discoveries.first(where: { $0.discoveryID == discoveryID }) {
            if !markInteresting,
               now.timeIntervalSince(existing.playedAt) < Self.discoveryRefreshInterval,
               (nextArtworkURL == nil || nextArtworkURL == existing.artworkURL) {
                return
            }

            removeTombstone(resource: "discoveries", identityKey: discoveryID)
            existing.playedAt = now
            if markInteresting {
                existing.markedInterestedAt = existing.markedInterestedAt ?? now
                existing.hiddenAt = nil
            }
            existing.artworkURL = nextArtworkURL ?? existing.artworkURL
            existing.stationArtworkURL = nil
        } else {
            removeTombstone(resource: "discoveries", identityKey: discoveryID)
            context.insert(
                DiscoveredTrack(
                    title: normalizedTitle,
                    artist: normalizedArtist,
                    station: station,
                    artworkURL: artworkURL,
                    markedInterestedAt: markInteresting ? now : nil
                )
            )
        }

        trimDiscoveries(limit: discoveryLimit ?? 100)
        saveAndRefresh(.discoveries)
    }

    func removeDiscovery(_ discovery: DiscoveredTrack) {
        rememberDiscoveryDeletion(for: discovery)
        context.delete(discovery)
        saveAndRefresh(.discoveries)
    }

    func clearDiscoveries() {
        guard !discoveries.isEmpty else { return }

        for discovery in discoveries {
            rememberDiscoveryDeletion(for: discovery)
            context.delete(discovery)
        }

        discoveries = []
        saveAndRefresh(.discoveries)
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
            removeTombstone(resource: "recents", identityKey: Self.stationIdentityKey(for: station))
            context.insert(RecentStation(station: station))
        }

        settings.lastPlayedStationID = station.id
        settings.updatedAt = .now
        saveAndRefresh(.all)
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
        saveAndRefresh(.favorites)
    }

    func clearRecents(propagatesToCloud: Bool = false) {
        for recent in recents {
            if propagatesToCloud {
                rememberRecentDeletion(for: Station(recent: recent))
            }
            context.delete(recent)
        }
        settings.lastPlayedStationID = nil
        settings.lastOpenedStationID = nil
        settings.lastOpenedStationPresentation = nil
        settings.updatedAt = .now
        saveAndRefresh(.recentsAndSettings)
    }

    func clearDiscoveries(propagatesToCloud: Bool = false) {
        for discovery in discoveries {
            if propagatesToCloud {
                rememberDiscoveryDeletion(for: discovery)
            }
            context.delete(discovery)
        }
        saveAndRefresh(.discoveries)
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
            if propagatesToCloud {
                rememberRecentDeletion(for: Station(recent: recent))
            }
            context.delete(recent)
        }

        for discovery in discoveries {
            if propagatesToCloud {
                rememberDiscoveryDeletion(for: discovery)
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
        settings.updatedAt = .now

        saveAndRefresh()
    }

    func setAppDataService(_ service: TuneAVAppDataService?) {
        let previousService = appDataService
        appDataService = service
        if previousService !== service {
            pushTask?.cancel()
            pushTask = nil
            cloudLibraryRefreshTask?.cancel()
            cloudLibraryRefreshTask = nil
            cloudLibraryRefreshedAt = nil
        }
        if service == nil {
            setCloudSyncStatus(.idle)
        }
    }

    func setBackendService(_ service: TuneAVAppDataService?) {
        backendService = service
        if service == nil {
            userSummary = nil
            userSummaryFetchedAt = nil
            setUserSummaryRefreshState(.unavailable)
            userSummaryRefreshTask?.cancel()
            userSummaryRefreshTask = nil
            listeningSessionUploadTask?.cancel()
            listeningSessionUploadTask = nil
            listeningSessionFlushTask?.cancel()
            listeningSessionFlushTask = nil
            listeningSessionUploadRetryCount = 0
            stationFeedbackSyncTasks.values.forEach { $0.cancel() }
            stationFeedbackSyncTasks.removeAll()
            stationFeedbackSyncTokens.removeAll()
            trackFeedbackSyncTasks.values.forEach { $0.cancel() }
            trackFeedbackSyncTasks.removeAll()
            trackFeedbackSyncTokens.removeAll()
            pendingListeningSessions.removeAll()
            analyticsLogger.debug("Cleared pending listening sessions after backend disconnect")
            persistPendingListeningSessions()
        } else if !pendingListeningSessions.isEmpty {
            scheduleListeningSessionUpload()
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
                trackDetectedCount: trackDetectedCount
            )
        )

        pendingListeningSessions = LibraryStoreListeningSessionBuffer.bounded(
            pendingListeningSessions,
            maxCount: Self.maxPendingListeningSessions
        )
        persistPendingListeningSessions()
        analyticsLogger.debug(
            "Queued listening session pending=\(self.pendingListeningSessions.count, privacy: .public)"
        )

        if pendingListeningSessions.count >= Self.listeningSessionBatchSize {
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
            pendingListeningSessions.removeAll()
            analyticsLogger.debug("Discarded pending listening sessions because backend is unavailable")
            persistPendingListeningSessions()
            return
        }
        guard !pendingListeningSessions.isEmpty else { return }

        let sessions = pendingListeningSessions
        pendingListeningSessions.removeAll(keepingCapacity: true)
        analyticsLogger.debug(
            "Uploading listening sessions count=\(sessions.count, privacy: .public) retryCount=\(self.listeningSessionUploadRetryCount, privacy: .public)"
        )

        listeningSessionFlushTask = Task { @MainActor in
            do {
                let result = try await backendService.recordListeningSessions(sessions)
                guard self.backendService === backendService else { return }
                finishListeningSessionUpload(didUpload: true, sessions: sessions, result: result)
            } catch is CancellationError {
                return
            } catch {
                guard self.backendService === backendService else { return }
                finishListeningSessionUpload(didUpload: false, sessions: sessions, result: nil)
            }
        }
    }

    private func finishListeningSessionUpload(
        didUpload: Bool,
        sessions: [TuneAVListeningSessionDraft],
        result: TuneAVListeningSessionsUploadResult?
    ) {
        listeningSessionFlushTask = nil

        guard didUpload else {
            listeningSessionUploadRetryCount += 1
            pendingListeningSessions.insert(contentsOf: sessions, at: 0)
            pendingListeningSessions = LibraryStoreListeningSessionBuffer.bounded(
                pendingListeningSessions,
                maxCount: Self.maxPendingListeningSessions
            )
            persistPendingListeningSessions()
            analyticsLogger.debug(
                "Listening session upload failed requeued=\(sessions.count, privacy: .public) pending=\(self.pendingListeningSessions.count, privacy: .public) retryCount=\(self.listeningSessionUploadRetryCount, privacy: .public)"
            )
            scheduleListeningSessionUpload()
            return
        }

        listeningSessionUploadRetryCount = 0
        persistPendingListeningSessions()
        analyticsLogger.debug(
            "Listening session upload finished sent=\(sessions.count, privacy: .public) accepted=\(result?.accepted ?? 0, privacy: .public) duplicate=\(result?.duplicate ?? 0, privacy: .public) rejected=\(result?.rejected ?? 0, privacy: .public) pending=\(self.pendingListeningSessions.count, privacy: .public)"
        )
        guard !pendingListeningSessions.isEmpty else { return }
        if pendingListeningSessions.count >= Self.listeningSessionBatchSize {
            flushListeningSessionUploads()
        } else {
            scheduleListeningSessionUpload()
        }
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

    private func performCloudLibraryRefresh(using appDataService: TuneAVAppDataService) async {
        do {
            setCloudSyncStatus(.syncing)
            let remoteDocument = try await appDataService.pullLibrary()
            guard self.appDataService === appDataService else { return }
            let localSnapshot = librarySnapshot()

            switch TuneAVLibrarySyncPlanner.decision(
                localSnapshot: localSnapshot,
                localUpdatedAt: latestLocalUpdateAt(),
                remoteDocument: remoteDocument
            ) {
            case .pullRemote(let remoteSnapshot):
                let mergedSnapshot = TuneAVLibrarySnapshotMerger.merged(
                    local: localSnapshot,
                    remote: remoteSnapshot
                )
                applyRemoteSnapshot(mergedSnapshot)
                if mergedSnapshot != remoteSnapshot {
                    try await appDataService.pushLibrary(mergedSnapshot)
                    guard self.appDataService === appDataService else { return }
                }
            case .pushLocal:
                let snapshotToPush: TuneAVLibrarySnapshot
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToPush = TuneAVLibrarySnapshotMerger.merged(
                        local: localSnapshot,
                        remote: remoteSnapshot
                    )
                } else {
                    snapshotToPush = localSnapshot
                }

                try await appDataService.pushLibrary(snapshotToPush)
                guard self.appDataService === appDataService else { return }
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
            rememberRecentDeletion(for: Station(recent: item))
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
            rememberDiscoveryDeletion(for: item)
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

        return TuneAVDiscoveredTrackSupport.makeID(
            title: normalizedTitle,
            artist: normalizedTrackValue(artist),
            stationID: "track"
        )
    }

    private static func loadStationFeedback() -> [String: TuneAVStationFeedback] {
        guard let data = UserDefaults.standard.data(forKey: stationFeedbackStorageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: TuneAVStationFeedback].self, from: data)) ?? [:]
    }

    private static func saveStationFeedback(_ feedback: [String: TuneAVStationFeedback]) {
        guard let data = try? JSONEncoder().encode(feedback) else { return }
        UserDefaults.standard.set(data, forKey: stationFeedbackStorageKey)
    }

    private static func loadTrackFeedback() -> [String: TuneAVStationFeedback] {
        guard let data = UserDefaults.standard.data(forKey: trackFeedbackStorageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: TuneAVStationFeedback].self, from: data)) ?? [:]
    }

    private static func saveTrackFeedback(_ feedback: [String: TuneAVStationFeedback]) {
        guard let data = try? JSONEncoder().encode(feedback) else { return }
        UserDefaults.standard.set(data, forKey: trackFeedbackStorageKey)
    }

    private func saveAndRefresh(_ scope: RefreshScope = .all) {
        guard context.hasChanges else { return }
        try? context.save()
        refresh(scope)
        scheduleCloudPushIfNeeded()
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
                let snapshotToPush: TuneAVLibrarySnapshot
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToPush = TuneAVLibrarySnapshotMerger.merged(
                        local: snapshot,
                        remote: remoteSnapshot
                    )
                } else {
                    snapshotToPush = snapshot
                }

                try Task.checkCancellation()
                try await appDataService.pushLibrary(snapshotToPush)
                try Task.checkCancellation()
                guard self.appDataService === appDataService else { return }
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

    private func syncStationFeedback(_ feedback: TuneAVStationFeedback?, stationID: String) {
        guard let backendService, backendService.isConfigured() else { return }

        let token = UUID()
        stationFeedbackSyncTasks[stationID]?.cancel()
        stationFeedbackSyncTokens[stationID] = token
        stationFeedbackSyncTasks[stationID] = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled,
                      self.backendService === backendService,
                      self.stationFeedbackSyncTokens[stationID] == token
                else { return }
                try await backendService.setStationFeedback(feedback, stationID: stationID)
            } catch is CancellationError {
                return
            } catch {
                guard self.backendService === backendService else { return }
                clearStationFeedbackSyncIfCurrent(stationID: stationID, token: token)
                return
            }
            guard self.backendService === backendService else { return }
            clearStationFeedbackSyncIfCurrent(stationID: stationID, token: token)
        }
    }

    private func syncTrackFeedback(_ feedback: TuneAVStationFeedback?, title: String?, artist: String?, stationID: String?) {
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
        trackFeedbackSyncTasks[feedbackKey] = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled,
                      self.backendService === backendService,
                      self.trackFeedbackSyncTokens[feedbackKey] == token
                else { return }
                try await backendService.setTrackFeedback(feedback, title: title, artist: normalizedArtist, stationID: stationID)
            } catch is CancellationError {
                return
            } catch {
                guard self.backendService === backendService else { return }
                clearTrackFeedbackSyncIfCurrent(feedbackKey: feedbackKey, token: token)
                return
            }
            guard self.backendService === backendService else { return }
            clearTrackFeedbackSyncIfCurrent(feedbackKey: feedbackKey, token: token)
        }
    }

    private func clearStationFeedbackSyncIfCurrent(stationID: String, token: UUID) {
        guard stationFeedbackSyncTokens[stationID] == token else { return }
        stationFeedbackSyncTasks[stationID] = nil
        stationFeedbackSyncTokens[stationID] = nil
    }

    private func clearTrackFeedbackSyncIfCurrent(feedbackKey: String, token: UUID) {
        guard trackFeedbackSyncTokens[feedbackKey] == token else { return }
        trackFeedbackSyncTasks[feedbackKey] = nil
        trackFeedbackSyncTokens[feedbackKey] = nil
    }

    private func librarySnapshot() -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: favorites.map {
                FavoriteStationRecord(
                    station: Station(favorite: $0).appDataRecord,
                    createdAt: TuneAVAppDataService.isoString(from: $0.createdAt)
                )
            } + tombstoneRecords(resource: "favorites", type: FavoriteStationRecord.self),
            recents: recents.map {
                RecentStationRecord(
                    station: Station(recent: $0).appDataRecord,
                    lastPlayedAt: TuneAVAppDataService.isoString(from: $0.lastPlayedAt)
                )
            } + tombstoneRecords(resource: "recents", type: RecentStationRecord.self),
            discoveries: discoveries.map(\.appDataRecord) + tombstoneRecords(resource: "discoveries", type: DiscoveredTrackRecord.self),
            settings: AppSettingsRecord(
                preferredCountry: settings.preferredCountry,
                preferredLanguage: settings.preferredLanguage,
                preferredTag: settings.preferredTag,
                lastPlayedStationID: settings.lastPlayedStationID,
                lastOpenedStationID: settings.lastOpenedStationID,
                lastOpenedStationPresentation: settings.lastOpenedStationPresentation,
                sleepTimerMinutes: nil,
                keepScreenAwake: settings.keepScreenAwake,
                warnBeforeCellularPlayback: settings.warnBeforeCellularPlayback,
                openLastStationOnLaunch: settings.openLastStationOnLaunch,
                autoSkipUnstableStreams: settings.autoSkipUnstableStreams,
                updatedAt: TuneAVAppDataService.isoString(from: settings.updatedAt)
            )
        )
    }

    private func latestLocalUpdateAt() -> Date {
        let timestamps =
            favorites.map(\.createdAt) +
            recents.map(\.lastPlayedAt) +
            tombstones().map(\.deletedAt) +
            discoveries.flatMap { discovery in
                [
                    discovery.playedAt,
                    discovery.markedInterestedAt,
                    discovery.hiddenAt
                ].compactMap { $0 }
            } +
            [settings.updatedAt]
        return timestamps.max() ?? .distantPast
    }

    private func applyRemoteSnapshot(_ snapshot: TuneAVLibrarySnapshot) {
        isApplyingRemoteSnapshot = true
        defer { isApplyingRemoteSnapshot = false }

        for favorite in favorites {
            context.delete(favorite)
        }

        for recent in recents {
            context.delete(recent)
        }

        for discovery in discoveries {
            context.delete(discovery)
        }

        for tombstone in tombstones() {
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

        for recent in snapshot.recents {
            if let deletedAt = recent.deletedAt {
                rememberTombstone(
                    resource: "recents",
                    identityKey: TuneAVLibrarySnapshotMerger.stationIdentityKey(recent.station),
                    payload: recent,
                    deletedAt: Self.date(from: deletedAt)
                )
                continue
            }

            context.insert(
                RecentStation(
                    station: Station(record: recent.station),
                    lastPlayedAt: recent.lastPlayedAt.map(Self.date(from:)) ?? .distantPast
                )
            )
        }

        for discovery in snapshot.discoveries {
            if let deletedAt = discovery.deletedAt {
                rememberTombstone(
                    resource: "discoveries",
                    identityKey: discovery.discoveryID,
                    payload: discovery,
                    deletedAt: Self.date(from: deletedAt)
                )
                continue
            }

            context.insert(DiscoveredTrack(record: discovery))
        }

        settings.preferredCountry = snapshot.settings.preferredCountry
        settings.preferredLanguage = snapshot.settings.preferredLanguage
        settings.preferredTag = snapshot.settings.preferredTag
        settings.lastPlayedStationID = snapshot.settings.lastPlayedStationID
        settings.lastOpenedStationID = snapshot.settings.lastOpenedStationID
        settings.lastOpenedStationPresentation = snapshot.settings.lastOpenedStationPresentation
        settings.sleepTimerMinutes = nil
        settings.keepScreenAwake = snapshot.settings.keepScreenAwake
        settings.warnBeforeCellularPlayback = snapshot.settings.warnBeforeCellularPlayback
        settings.openLastStationOnLaunch = snapshot.settings.openLastStationOnLaunch
        settings.autoSkipUnstableStreams = snapshot.settings.autoSkipUnstableStreams
        settings.updatedAt = Self.date(from: snapshot.settings.updatedAt)

        try? context.save()
        refresh()
    }

    private static func date(from value: String) -> Date {
        TuneAVDateCoding.date(from: value)
    }

    private func rememberFavoriteDeletion(for station: Station) {
        let deletedAt = Date.now
        rememberTombstone(
            resource: "favorites",
            identityKey: Self.stationIdentityKey(for: station),
            payload: FavoriteStationRecord(
                station: station.appDataRecord,
                deletedAt: TuneAVAppDataService.isoString(from: deletedAt)
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
                deletedAt: TuneAVAppDataService.isoString(from: deletedAt)
            ),
            deletedAt: deletedAt
        )
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
                playedAt: TuneAVAppDataService.isoString(from: discovery.playedAt),
                markedInterestedAt: discovery.markedInterestedAt.map(TuneAVAppDataService.isoString(from:)),
                hiddenAt: discovery.hiddenAt.map(TuneAVAppDataService.isoString(from:)),
                deletedAt: TuneAVAppDataService.isoString(from: deletedAt)
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

    private func removeTombstone(resource: String, identityKey: String) {
        let resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        for tombstone in tombstones() where tombstone.resourceKey == resourceKey {
            context.delete(tombstone)
        }
    }

    private func tombstoneRecords<Record: Decodable>(resource: String, type: Record.Type) -> [Record] {
        TuneAVLibraryTombstoneCoding.records(for: resource, in: tombstones().map(\.sharedTombstone), as: type, decoder: tombstoneDecoder)
    }

    private func tombstones() -> [LibrarySyncTombstone] {
        (try? context.fetch(FetchDescriptor<LibrarySyncTombstone>())) ?? []
    }

    private static func stationIdentityKey(for station: Station) -> String {
        TuneAVLibrarySnapshotMerger.stationIdentityKey(station.appDataRecord)
    }

    private static func loadPendingListeningSessions(maxCount: Int) -> [TuneAVListeningSessionDraft] {
        LibraryStoreListeningSessionPersistence.load(
            storageKey: pendingListeningSessionsStorageKey,
            maxCount: maxCount
        )
    }

    private func persistPendingListeningSessions() {
        LibraryStoreListeningSessionPersistence.save(
            pendingListeningSessions,
            storageKey: Self.pendingListeningSessionsStorageKey,
            maxCount: Self.maxPendingListeningSessions
        )
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

enum LibraryStoreListeningSessionPersistence {
    static func load(
        storageKey: String,
        userDefaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder(),
        maxCount: Int
    ) -> [TuneAVListeningSessionDraft] {
        guard let data = userDefaults.data(forKey: storageKey),
              let sessions = try? decoder.decode([TuneAVListeningSessionDraft].self, from: data) else {
            return []
        }

        return LibraryStoreListeningSessionBuffer.bounded(sessions, maxCount: maxCount)
    }

    static func save(
        _ sessions: [TuneAVListeningSessionDraft],
        storageKey: String,
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        maxCount: Int
    ) {
        let boundedSessions = LibraryStoreListeningSessionBuffer.bounded(sessions, maxCount: maxCount)
        guard !boundedSessions.isEmpty else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? encoder.encode(boundedSessions) else { return }
        userDefaults.set(data, forKey: storageKey)
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
