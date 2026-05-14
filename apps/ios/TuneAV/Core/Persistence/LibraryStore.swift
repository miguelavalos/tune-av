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
    private static let userSummaryRefreshInterval: TimeInterval = 300
    private static let listeningSessionBatchSize = 5

    private let context: ModelContext
    private var appDataService: TuneAVAppDataService?
    private var backendService: TuneAVAppDataService?
    private let tombstoneEncoder = JSONEncoder()
    private let tombstoneDecoder = JSONDecoder()
    private var isApplyingRemoteSnapshot = false
    private var pushTask: Task<Void, Never>?
    private var userSummaryFetchedAt: Date?
    private var userSummaryRefreshTask: Task<Void, Never>?
    private var pendingListeningSessions: [TuneAVListeningSessionDraft] = []
    private var listeningSessionUploadTask: Task<Void, Never>?

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
        refresh()
    }

    func refresh() {
        let favoriteDescriptor = FetchDescriptor<FavoriteStation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let recentDescriptor = FetchDescriptor<RecentStation>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        let discoveryDescriptor = FetchDescriptor<DiscoveredTrack>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )

        favorites = (try? context.fetch(favoriteDescriptor)) ?? []
        recents = (try? context.fetch(recentDescriptor)) ?? []
        discoveries = (try? context.fetch(discoveryDescriptor)) ?? []

        if let currentSettings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            settings = currentSettings
        }
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

        saveAndRefresh()
    }

    func rememberStationSnapshots(_ stations: [Station]) {
        guard !stations.isEmpty else { return }

        var didUpdate = false
        for station in stations {
            if let favorite = favorites.first(where: { $0.stationID == station.id }) {
                favorite.updateStationSnapshot(station)
                didUpdate = true
            }

            if let recent = recents.first(where: { $0.stationID == station.id }) {
                recent.updateStationSnapshot(station)
                didUpdate = true
            }
        }

        guard didUpdate else { return }
        saveAndRefresh()
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
        saveAndRefresh()
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

        saveAndRefresh()
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
        discovery.hiddenAt = .now
        discovery.markedInterestedAt = nil
        saveAndRefresh()
    }

    func restoreDiscovery(_ discovery: DiscoveredTrack) {
        discovery.hiddenAt = nil
        saveAndRefresh()
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

        if let existing = discoveries.first(where: { $0.discoveryID == discoveryID }) {
            removeTombstone(resource: "discoveries", identityKey: discoveryID)
            existing.playedAt = .now
            if markInteresting {
                existing.markedInterestedAt = existing.markedInterestedAt ?? .now
                existing.hiddenAt = nil
            }
            existing.artworkURL = artworkURL?.absoluteString ?? existing.artworkURL
            existing.stationArtworkURL = nil
        } else {
            removeTombstone(resource: "discoveries", identityKey: discoveryID)
            context.insert(
                DiscoveredTrack(
                    title: normalizedTitle,
                    artist: normalizedArtist,
                    station: station,
                    artworkURL: artworkURL,
                    markedInterestedAt: markInteresting ? .now : nil
                )
            )
        }

        trimDiscoveries(limit: discoveryLimit ?? 100)
        saveAndRefresh()
    }

    func removeDiscovery(_ discovery: DiscoveredTrack) {
        rememberDiscoveryDeletion(for: discovery)
        context.delete(discovery)
        saveAndRefresh()
    }

    func clearDiscoveries() {
        for discovery in discoveries {
            rememberDiscoveryDeletion(for: discovery)
            context.delete(discovery)
        }

        saveAndRefresh()
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
        saveAndRefresh()
    }

    func favoriteStations() -> [Station] {
        favorites.map(Station.init(favorite:))
    }

    func recentStations() -> [Station] {
        Self.uniqueRecentStations(from: recents)
    }

    func setPreferredTag(_ tag: String?) {
        settings.preferredTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        settings.updatedAt = .now
        saveAndRefresh()
    }

    func setPreferredCountry(_ countryCode: String?) {
        settings.preferredCountry = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        settings.updatedAt = .now
        saveAndRefresh()
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
        settings.sleepTimerMinutes = nil
        settings.updatedAt = .now

        saveAndRefresh()
    }

    func setAppDataService(_ service: TuneAVAppDataService?) {
        appDataService = service
    }

    func setBackendService(_ service: TuneAVAppDataService?) {
        backendService = service
        if service == nil {
            userSummary = nil
            userSummaryFetchedAt = nil
            userSummaryRefreshState = .unavailable
            userSummaryRefreshTask?.cancel()
            userSummaryRefreshTask = nil
            listeningSessionUploadTask?.cancel()
            listeningSessionUploadTask = nil
            pendingListeningSessions.removeAll()
        }
    }

    func refreshUserSummary(force: Bool = false) async {
        guard let backendService, backendService.isConfigured() else {
            userSummary = nil
            userSummaryFetchedAt = nil
            userSummaryRefreshState = .unavailable
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
            userSummaryRefreshState = .loading
            do {
                let summary = try await backendService.fetchUserSummary(limit: 12)
                userSummary = summary
                userSummaryFetchedAt = .now
                userSummaryRefreshState = summary.hasAnyActivity ? .loaded : .empty
            } catch AVAccountAPIClientError.missingToken, AVAccountAPIClientError.missingBaseURL {
                userSummary = nil
                userSummaryFetchedAt = nil
                userSummaryRefreshState = .unavailable
            } catch {
                userSummary = nil
                userSummaryFetchedAt = nil
                userSummaryRefreshState = .failed
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

        if pendingListeningSessions.count >= Self.listeningSessionBatchSize {
            flushListeningSessionUploads()
        } else {
            scheduleListeningSessionUpload()
        }
    }

    private func scheduleListeningSessionUpload() {
        guard listeningSessionUploadTask == nil else { return }

        listeningSessionUploadTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            flushListeningSessionUploads()
        }
    }

    private func flushListeningSessionUploads() {
        listeningSessionUploadTask?.cancel()
        listeningSessionUploadTask = nil

        guard let backendService, backendService.isConfigured() else {
            pendingListeningSessions.removeAll()
            return
        }
        guard !pendingListeningSessions.isEmpty else { return }

        let sessions = pendingListeningSessions
        pendingListeningSessions.removeAll(keepingCapacity: true)

        Task {
            try? await backendService.recordListeningSessions(sessions)
        }
    }

    func refreshCloudLibraryIfNeeded() async {
        guard let appDataService, appDataService.isConfigured() else {
            cloudSyncStatus = .idle
            return
        }

        do {
            cloudSyncStatus = .syncing
            let remoteDocument = try await appDataService.pullLibrary()
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
                if snapshotToPush != localSnapshot {
                    applyRemoteSnapshot(snapshotToPush)
                }
            case .noContent, .alreadyCurrent:
                break
            }

            cloudSyncStatus = .synced(.now)
        } catch TuneAVAppDataError.conflict {
            cloudSyncStatus = .conflict
        } catch {
            cloudSyncStatus = .failed
            return
        }
    }

    func overwriteCloudLibraryWithLocalData() async {
        guard let appDataService, appDataService.isConfigured() else {
            cloudSyncStatus = .idle
            return
        }

        do {
            cloudSyncStatus = .syncing
            try await appDataService.overwriteLibrary(librarySnapshot())
            cloudSyncStatus = .synced(.now)
        } catch TuneAVAppDataError.conflict {
            cloudSyncStatus = .conflict
        } catch {
            cloudSyncStatus = .failed
        }
    }

    func clearCloudSyncStatus() {
        cloudSyncStatus = .idle
    }

    func setCloudSyncStatusForUITests(_ status: CloudSyncStatus) {
        guard TuneAVUITestEnvironment.current.isEnabled else {
            return
        }

        cloudSyncStatus = status
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

    private func saveAndRefresh() {
        try? context.save()
        refresh()
        scheduleCloudPushIfNeeded()
    }

    private func scheduleCloudPushIfNeeded() {
        guard !isApplyingRemoteSnapshot, let appDataService, appDataService.isConfigured() else {
            return
        }

        let snapshot = librarySnapshot()
        pushTask?.cancel()
        pushTask = Task { [snapshot] in
            do {
                cloudSyncStatus = .syncing
                let remoteDocument = try await appDataService.pullLibrary()
                let snapshotToPush: TuneAVLibrarySnapshot
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToPush = TuneAVLibrarySnapshotMerger.merged(
                        local: snapshot,
                        remote: remoteSnapshot
                    )
                } else {
                    snapshotToPush = snapshot
                }

                try await appDataService.pushLibrary(snapshotToPush)
                if snapshotToPush != snapshot {
                    applyRemoteSnapshot(snapshotToPush)
                }
                cloudSyncStatus = .synced(.now)
            } catch TuneAVAppDataError.conflict {
                await refreshCloudLibraryIfNeeded()
            } catch {
                cloudSyncStatus = .failed
            }
        }
    }

    private func syncStationFeedback(_ feedback: TuneAVStationFeedback?, stationID: String) {
        guard let backendService, backendService.isConfigured() else { return }

        Task {
            try? await backendService.setStationFeedback(feedback, stationID: stationID)
        }
    }

    private func syncTrackFeedback(_ feedback: TuneAVStationFeedback?, title: String?, artist: String?, stationID: String?) {
        guard
            let backendService,
            backendService.isConfigured(),
            let title = normalizedTrackValue(title)
        else { return }

        Task {
            try? await backendService.setTrackFeedback(feedback, title: title, artist: normalizedTrackValue(artist), stationID: stationID)
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
                sleepTimerMinutes: settings.sleepTimerMinutes,
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
        settings.sleepTimerMinutes = snapshot.settings.sleepTimerMinutes
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
