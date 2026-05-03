import SwiftData
import SwiftUI

enum CloudSyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date)
    case conflict
    case failed
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [FavoriteStation] = []
    @Published private(set) var recents: [RecentStation] = []
    @Published private(set) var discoveries: [DiscoveredTrack] = []
    @Published private(set) var settings: AppSettings
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .idle

    private let context: ModelContext
    private var appDataService: AVTunesysAppDataService?
    private let tombstoneEncoder = JSONEncoder()
    private let tombstoneDecoder = JSONDecoder()
    private var isApplyingRemoteSnapshot = false
    private var pushTask: Task<Void, Never>?

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

    func recordPlayback(of station: Station, recentLimit: Int? = nil) {
        if let existing = recents.first(where: { $0.stationID == station.id }) {
            existing.name = station.name
            existing.country = station.country
            existing.countryCode = station.countryCode
            existing.state = station.state
            existing.language = station.language
            existing.languageCodes = station.languageCodes
            existing.tags = station.tags
            existing.streamURL = station.streamURL
            existing.faviconURL = station.faviconURL
            existing.bitrate = station.bitrate
            existing.codec = station.codec
            existing.homepageURL = station.homepageURL
            existing.votes = station.votes
            existing.clickCount = station.clickCount
            existing.clickTrend = station.clickTrend
            existing.isHLS = station.isHLS
            existing.hasExtendedInfo = station.hasExtendedInfo
            existing.hasSSLError = station.hasSSLError
            existing.lastCheckOKAt = station.lastCheckOKAt
            existing.geoLatitude = station.geoLatitude
            existing.geoLongitude = station.geoLongitude
            existing.lastPlayedAt = .now
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
        guard let limit else { return true }
        if isSavedDiscoveredTrack(title: title, artist: artist, station: station) {
            return true
        }

        return savedDiscoveriesCount < limit
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
            existing.playedAt = .now
            if markInteresting {
                existing.markedInterestedAt = existing.markedInterestedAt ?? .now
                existing.hiddenAt = nil
            }
            existing.artworkURL = artworkURL?.absoluteString ?? existing.artworkURL
            existing.stationArtworkURL = station.displayArtworkURL?.absoluteString ?? existing.stationArtworkURL
        } else {
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
            context.insert(FavoriteStation(station: station))
        }

        if recents.contains(where: { $0.stationID == station.id }) == false {
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
        recents.map(Station.init(recent:))
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

    func clearLocalData() {
        for favorite in favorites {
            rememberFavoriteDeletion(for: Station(favorite: favorite))
            context.delete(favorite)
        }

        for recent in recents {
            rememberRecentDeletion(for: Station(recent: recent))
            context.delete(recent)
        }

        for discovery in discoveries {
            rememberDiscoveryDeletion(for: discovery)
            context.delete(discovery)
        }

        settings.preferredCountry = ""
        settings.preferredLanguage = ""
        settings.preferredTag = ""
        settings.lastPlayedStationID = nil
        settings.sleepTimerMinutes = nil
        settings.updatedAt = .now

        saveAndRefresh()
    }

    func setAppDataService(_ service: AVTunesysAppDataService?) {
        appDataService = service
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

            switch AVTunesysLibrarySyncPlanner.decision(
                localSnapshot: localSnapshot,
                localUpdatedAt: latestLocalUpdateAt(),
                remoteDocument: remoteDocument
            ) {
            case .pullRemote(let remoteSnapshot):
                let mergedSnapshot = AVTunesysLibrarySnapshotMerger.merged(
                    local: localSnapshot,
                    remote: remoteSnapshot
                )
                applyRemoteSnapshot(mergedSnapshot)
                if mergedSnapshot != remoteSnapshot {
                    try await appDataService.pushLibrary(mergedSnapshot)
                }
            case .pushLocal:
                try await appDataService.pushLibrary(localSnapshot)
            case .noContent, .alreadyCurrent:
                break
            }

            cloudSyncStatus = .synced(.now)
        } catch AVTunesysAppDataError.conflict {
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
        } catch AVTunesysAppDataError.conflict {
            cloudSyncStatus = .conflict
        } catch {
            cloudSyncStatus = .failed
        }
    }

    func clearCloudSyncStatus() {
        cloudSyncStatus = .idle
    }

    func setCloudSyncStatusForUITests(_ status: CloudSyncStatus) {
        guard ProcessInfo.processInfo.environment["AVTUNESYS_UI_TESTS"] == "1" else {
            return
        }

        cloudSyncStatus = status
    }

    private func trimRecents(limit: Int) {
        for item in AVTunesysCollectionRules.overflow(in: recents, limit: limit, sortedBy: { $0.lastPlayedAt > $1.lastPlayedAt }) {
            rememberRecentDeletion(for: Station(recent: item))
            context.delete(item)
        }
    }

    private func trimDiscoveries(limit: Int) {
        for item in AVTunesysCollectionRules.overflow(in: discoveries, limit: limit, sortedBy: { $0.playedAt > $1.playedAt }) {
            rememberDiscoveryDeletion(for: item)
            context.delete(item)
        }
    }

    private func normalizedTrackValue(_ value: String?) -> String? {
        AVTunesysText.normalizedValue(value)
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
                let snapshotToPush: AVTunesysLibrarySnapshot
                if let remoteSnapshot = remoteDocument.snapshot {
                    snapshotToPush = AVTunesysLibrarySnapshotMerger.merged(
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
            } catch AVTunesysAppDataError.conflict {
                await refreshCloudLibraryIfNeeded()
            } catch {
                cloudSyncStatus = .failed
            }
        }
    }

    private func librarySnapshot() -> AVTunesysLibrarySnapshot {
        AVTunesysLibrarySnapshot(
            favorites: favorites.map {
                FavoriteStationRecord(
                    station: Station(favorite: $0).appDataRecord,
                    createdAt: AVTunesysAppDataService.isoString(from: $0.createdAt)
                )
            } + tombstoneRecords(resource: "favorites", type: FavoriteStationRecord.self),
            recents: recents.map {
                RecentStationRecord(
                    station: Station(recent: $0).appDataRecord,
                    lastPlayedAt: AVTunesysAppDataService.isoString(from: $0.lastPlayedAt)
                )
            } + tombstoneRecords(resource: "recents", type: RecentStationRecord.self),
            discoveries: discoveries.map(\.appDataRecord) + tombstoneRecords(resource: "discoveries", type: DiscoveredTrackRecord.self),
            settings: AppSettingsRecord(
                preferredCountry: settings.preferredCountry,
                preferredLanguage: settings.preferredLanguage,
                preferredTag: settings.preferredTag,
                lastPlayedStationID: settings.lastPlayedStationID,
                sleepTimerMinutes: settings.sleepTimerMinutes,
                updatedAt: AVTunesysAppDataService.isoString(from: settings.updatedAt)
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

    private func applyRemoteSnapshot(_ snapshot: AVTunesysLibrarySnapshot) {
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
                    identityKey: AVTunesysLibrarySnapshotMerger.stationIdentityKey(favorite.station),
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
                    identityKey: AVTunesysLibrarySnapshotMerger.stationIdentityKey(recent.station),
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
        AVTunesysDateCoding.date(from: value)
    }

    private func rememberFavoriteDeletion(for station: Station) {
        let deletedAt = Date.now
        rememberTombstone(
            resource: "favorites",
            identityKey: Self.stationIdentityKey(for: station),
            payload: FavoriteStationRecord(
                station: station.appDataRecord,
                deletedAt: AVTunesysAppDataService.isoString(from: deletedAt)
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
                deletedAt: AVTunesysAppDataService.isoString(from: deletedAt)
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
                playedAt: AVTunesysAppDataService.isoString(from: discovery.playedAt),
                markedInterestedAt: discovery.markedInterestedAt.map(AVTunesysAppDataService.isoString(from:)),
                hiddenAt: discovery.hiddenAt.map(AVTunesysAppDataService.isoString(from:)),
                deletedAt: AVTunesysAppDataService.isoString(from: deletedAt)
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
        guard let payloadJSON = try? String(data: tombstoneEncoder.encode(payload), encoding: .utf8) else {
            return
        }

        let resourceKey = "\(resource):\(identityKey)"
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
        let resourceKey = "\(resource):\(identityKey)"
        for tombstone in tombstones() where tombstone.resourceKey == resourceKey {
            context.delete(tombstone)
        }
    }

    private func tombstoneRecords<Record: Decodable>(resource: String, type: Record.Type) -> [Record] {
        tombstones()
            .filter { $0.resource == resource }
            .compactMap { tombstone in
                guard let data = tombstone.payloadJSON.data(using: .utf8) else {
                    return nil
                }

                return try? tombstoneDecoder.decode(Record.self, from: data)
            }
    }

    private func tombstones() -> [LibrarySyncTombstone] {
        (try? context.fetch(FetchDescriptor<LibrarySyncTombstone>())) ?? []
    }

    private static func stationIdentityKey(for station: Station) -> String {
        AVTunesysLibrarySnapshotMerger.stationIdentityKey(station.appDataRecord)
    }
}
