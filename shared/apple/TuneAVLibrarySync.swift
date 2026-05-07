import Foundation

struct TuneAVLibraryDocument {
    let snapshot: TuneAVLibrarySnapshot?
    let updatedAt: Date
    let revision: Int
    let etag: String?
}

enum TuneAVLibrarySyncDecision: Equatable {
    case pullRemote(TuneAVLibrarySnapshot)
    case pushLocal
    case noContent
    case alreadyCurrent
}

enum TuneAVLibrarySyncPlanner {
    static func decision(
        localSnapshot: TuneAVLibrarySnapshot,
        localUpdatedAt: Date,
        remoteDocument: TuneAVLibraryDocument
    ) -> TuneAVLibrarySyncDecision {
        let localHasContent = localSnapshot.hasMeaningfulContent

        guard let remoteSnapshot = remoteDocument.snapshot else {
            return localHasContent ? .pushLocal : .noContent
        }

        let remoteHasContent = remoteSnapshot.hasMeaningfulContent
        if !remoteHasContent {
            return localHasContent ? .pushLocal : .noContent
        }

        if !localHasContent || remoteDocument.updatedAt > localUpdatedAt {
            return .pullRemote(remoteSnapshot)
        }

        if localUpdatedAt > remoteDocument.updatedAt {
            return .pushLocal
        }

        return .alreadyCurrent
    }
}

enum TuneAVLibrarySnapshotMerger {
    static func merged(local: TuneAVLibrarySnapshot, remote: TuneAVLibrarySnapshot) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: mergedFavorites(local.favorites, remote.favorites),
            recents: mergedRecents(local.recents, remote.recents),
            discoveries: mergedDiscoveries(local.discoveries, remote.discoveries),
            settings: newestSettings(local.settings, remote.settings)
        )
    }

    private static func mergedFavorites(
        _ local: [FavoriteStationRecord],
        _ remote: [FavoriteStationRecord]
    ) -> [FavoriteStationRecord] {
        newestByKey(local + remote, key: { stationIdentityKey($0.station) }, date: favoriteUpdateDate)
            .sorted { favoriteUpdateDate($0) < favoriteUpdateDate($1) }
    }

    private static func mergedRecents(
        _ local: [RecentStationRecord],
        _ remote: [RecentStationRecord]
    ) -> [RecentStationRecord] {
        newestByKey(local + remote, key: { stationIdentityKey($0.station) }, date: recentUpdateDate)
            .sorted { recentUpdateDate($0) > recentUpdateDate($1) }
    }

    private static func mergedDiscoveries(
        _ local: [DiscoveredTrackRecord],
        _ remote: [DiscoveredTrackRecord]
    ) -> [DiscoveredTrackRecord] {
        newestByKey(local + remote, key: { $0.discoveryID }, date: discoveryUpdateDate)
            .sorted { discoveryUpdateDate($0) > discoveryUpdateDate($1) }
    }

    private static func newestSettings(_ local: AppSettingsRecord, _ remote: AppSettingsRecord) -> AppSettingsRecord {
        date(local.updatedAt) >= date(remote.updatedAt) ? local : remote
    }

    private static func newestByKey<Record>(
        _ records: [Record],
        key: (Record) -> String,
        date: (Record) -> String
    ) -> [Record] {
        var values: [String: Record] = [:]
        for record in records {
            let recordKey = key(record)
            guard let current = values[recordKey] else {
                values[recordKey] = record
                continue
            }

            if Self.date(date(record)) >= Self.date(date(current)) {
                values[recordKey] = record
            }
        }

        return Array(values.values)
    }

    private static func discoveryUpdateDate(_ discovery: DiscoveredTrackRecord) -> String {
        [
            discovery.playedAt,
            discovery.markedInterestedAt,
            discovery.hiddenAt,
            discovery.deletedAt
        ]
        .compactMap { $0 }
        .max { date($0) < date($1) } ?? discovery.playedAt
    }

    private static func favoriteUpdateDate(_ favorite: FavoriteStationRecord) -> String {
        [favorite.createdAt, favorite.deletedAt]
            .compactMap { $0 }
            .max { date($0) < date($1) } ?? "1970-01-01T00:00:00.000Z"
    }

    private static func recentUpdateDate(_ recent: RecentStationRecord) -> String {
        [recent.lastPlayedAt, recent.deletedAt]
            .compactMap { $0 }
            .max { date($0) < date($1) } ?? "1970-01-01T00:00:00.000Z"
    }

    static func stationIdentityKey(_ station: StationRecord) -> String {
        if let streamURL = normalizedIdentityValue(station.streamURL) {
            return "stream:\(streamURL)"
        }

        if let homepageURL = normalizedIdentityValue(station.homepageURL), let name = normalizedIdentityValue(station.name) {
            return "homepage-name:\(homepageURL):\(name)"
        }

        return "id:\(station.id)"
    }

    private static func normalizedIdentityValue(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty
        else {
            return nil
        }

        return normalized
    }

    private static func date(_ value: String) -> Date {
        TuneAVDateCoding.date(from: value)
    }
}

enum TuneAVAppDataError: Error {
    case conflict
}

struct TuneAVLibrarySnapshot: Codable, Equatable {
    let favorites: [FavoriteStationRecord]
    let recents: [RecentStationRecord]
    let discoveries: [DiscoveredTrackRecord]
    let settings: AppSettingsRecord

    var hasMeaningfulContent: Bool {
        !favorites.isEmpty || !recents.isEmpty || !discoveries.isEmpty || settings.hasMeaningfulContent
    }

    var hasLibraryCollections: Bool {
        !favorites.isEmpty || !recents.isEmpty || !discoveries.isEmpty
    }

    init(
        favorites: [FavoriteStationRecord],
        recents: [RecentStationRecord],
        discoveries: [DiscoveredTrackRecord] = [],
        settings: AppSettingsRecord
    ) {
        self.favorites = favorites
        self.recents = recents
        self.discoveries = discoveries
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case favorites
        case recents
        case discoveries
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try container.decode([FavoriteStationRecord].self, forKey: .favorites)
        recents = try container.decode([RecentStationRecord].self, forKey: .recents)
        discoveries = try container.decodeIfPresent([DiscoveredTrackRecord].self, forKey: .discoveries) ?? []
        settings = try container.decode(AppSettingsRecord.self, forKey: .settings)
    }
}

struct FavoriteStationRecord: Codable, Equatable {
    let station: StationRecord
    let createdAt: String?
    let deletedAt: String?

    init(station: StationRecord, createdAt: String? = nil, deletedAt: String? = nil) {
        self.station = station
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

struct RecentStationRecord: Codable, Equatable {
    let station: StationRecord
    let lastPlayedAt: String?
    let deletedAt: String?

    init(station: StationRecord, lastPlayedAt: String? = nil, deletedAt: String? = nil) {
        self.station = station
        self.lastPlayedAt = lastPlayedAt
        self.deletedAt = deletedAt
    }
}

struct DiscoveredTrackRecord: Codable, Equatable {
    let discoveryID: String
    let title: String
    let artist: String?
    let stationID: String
    let stationName: String
    let artworkURL: String?
    let stationArtworkURL: String?
    let playedAt: String
    let markedInterestedAt: String?
    let hiddenAt: String?
    let deletedAt: String?

    init(
        discoveryID: String,
        title: String,
        artist: String?,
        stationID: String,
        stationName: String,
        artworkURL: String?,
        stationArtworkURL: String?,
        playedAt: String,
        markedInterestedAt: String? = nil,
        hiddenAt: String? = nil,
        deletedAt: String? = nil
    ) {
        self.discoveryID = discoveryID
        self.title = title
        self.artist = artist
        self.stationID = stationID
        self.stationName = stationName
        self.artworkURL = artworkURL
        self.stationArtworkURL = stationArtworkURL
        self.playedAt = playedAt
        self.markedInterestedAt = markedInterestedAt
        self.hiddenAt = hiddenAt
        self.deletedAt = deletedAt
    }
}

struct AppSettingsRecord: Codable, Equatable {
    let preferredCountry: String
    let preferredLanguage: String
    let preferredTag: String
    let lastPlayedStationID: String?
    let sleepTimerMinutes: Int?
    let updatedAt: String

    var hasMeaningfulContent: Bool {
        !preferredCountry.isEmpty ||
            !preferredLanguage.isEmpty ||
            !preferredTag.isEmpty ||
            lastPlayedStationID != nil ||
            sleepTimerMinutes != nil
    }

    static var empty: AppSettingsRecord {
        AppSettingsRecord(
            preferredCountry: "",
            preferredLanguage: "",
            preferredTag: "",
            lastPlayedStationID: nil,
            sleepTimerMinutes: nil,
            updatedAt: "1970-01-01T00:00:00.000Z"
        )
    }
}

struct StationRecord: Codable, Equatable {
    let id: String
    let name: String
    let country: String
    let countryCode: String?
    let state: String?
    let language: String
    let languageCodes: String?
    let tags: String
    let streamURL: String
    let faviconURL: String?
    let bitrate: Int?
    let codec: String?
    let homepageURL: String?
    let votes: Int?
    let clickCount: Int?
    let clickTrend: Int?
    let isHLS: Bool?
    let hasExtendedInfo: Bool?
    let hasSSLError: Bool?
    let lastCheckOKAt: String?
    let geoLatitude: Double?
    let geoLongitude: Double?
}

extension Station {
    init(record: StationRecord) {
        self.init(
            id: record.id,
            name: record.name,
            country: record.country,
            countryCode: record.countryCode,
            state: record.state,
            language: record.language,
            languageCodes: record.languageCodes,
            tags: record.tags,
            streamURL: record.streamURL,
            faviconURL: record.faviconURL,
            bitrate: record.bitrate,
            codec: record.codec,
            homepageURL: record.homepageURL,
            votes: record.votes,
            clickCount: record.clickCount,
            clickTrend: record.clickTrend,
            isHLS: record.isHLS,
            hasExtendedInfo: record.hasExtendedInfo,
            hasSSLError: record.hasSSLError,
            lastCheckOKAt: record.lastCheckOKAt,
            geoLatitude: record.geoLatitude,
            geoLongitude: record.geoLongitude
        )
    }

    var appDataRecord: StationRecord {
        StationRecord(
            id: id,
            name: name,
            country: country,
            countryCode: countryCode,
            state: state,
            language: language,
            languageCodes: languageCodes,
            tags: tags,
            streamURL: streamURL,
            faviconURL: faviconURL,
            bitrate: bitrate,
            codec: codec,
            homepageURL: homepageURL,
            votes: votes,
            clickCount: clickCount,
            clickTrend: clickTrend,
            isHLS: isHLS,
            hasExtendedInfo: hasExtendedInfo,
            hasSSLError: hasSSLError,
            lastCheckOKAt: lastCheckOKAt,
            geoLatitude: geoLatitude,
            geoLongitude: geoLongitude
        )
    }
}
