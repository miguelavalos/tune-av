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
    let localSavedDiscoveriesCount: Int
    let localUpdatedAt: Date
    let cloudFavoritesCount: Int?
    let cloudSavedDiscoveriesCount: Int?
    let cloudUpdatedAt: Date?

    var hasCloudSnapshot: Bool {
        cloudFavoritesCount != nil || cloudSavedDiscoveriesCount != nil
    }
}

struct LimitUsageSummary: Equatable {
    let used: Int
    let limit: Int?

    var title: String {
        guard let limit else {
            return L10n.string("mac.usage.used", used)
        }
        return "\(used) of \(limit)"
    }
}

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
    private struct DatedRecord<Record> {
        let record: Record
        let date: Date
    }

    static func merged(local: TuneAVLibrarySnapshot, remote: TuneAVLibrarySnapshot) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshot(
            favorites: mergedFavorites(local.favorites, remote.favorites),
            savedDiscoveries: mergedSavedDiscoveries(local.savedDiscoveries, remote.savedDiscoveries)
        )
    }

    static func canonicalized(_ snapshot: TuneAVLibrarySnapshot) -> TuneAVLibrarySnapshot {
        merged(
            local: snapshot,
            remote: TuneAVLibrarySnapshot(favorites: [], savedDiscoveries: [])
        )
    }

    private static func mergedFavorites(
        _ local: [FavoriteStationRecord],
        _ remote: [FavoriteStationRecord]
    ) -> [FavoriteStationRecord] {
        newestDatedByKey(
            datedRecords(local + remote, date: favoriteUpdateDate),
            key: { stationIdentityKey($0.station) }
        )
        .sorted {
            if $0.date == $1.date {
                return stationIdentityKey($0.record.station) < stationIdentityKey($1.record.station)
            }
            return $0.date > $1.date
        }
        .map(\.record)
    }

    private static func mergedSavedDiscoveries(
        _ local: [DiscoveredTrackRecord],
        _ remote: [DiscoveredTrackRecord]
    ) -> [DiscoveredTrackRecord] {
        newestDatedByKey(
            datedRecords(local + remote, date: discoveryUpdateDate),
            key: { discoveryIdentityKey($0) }
        )
        .sorted {
            if $0.date == $1.date {
                return discoveryIdentityKey($0.record) < discoveryIdentityKey($1.record)
            }
            return $0.date > $1.date
        }
        .map(\.record)
    }

    private static func datedRecords<Record>(
        _ records: [Record],
        date: (Record) -> Date
    ) -> [DatedRecord<Record>] {
        records.map { DatedRecord(record: $0, date: date($0)) }
    }

    private static func newestDatedByKey<Record>(
        _ records: [DatedRecord<Record>],
        key: (Record) -> String
    ) -> [DatedRecord<Record>] {
        var values: [String: DatedRecord<Record>] = [:]
        for datedRecord in records {
            let recordKey = key(datedRecord.record)
            guard let current = values[recordKey] else {
                values[recordKey] = datedRecord
                continue
            }

            if datedRecord.date >= current.date {
                values[recordKey] = datedRecord
            }
        }

        return Array(values.values)
    }

    private static func discoveryUpdateDate(_ discovery: DiscoveredTrackRecord) -> Date {
        [
            discovery.updatedAt,
            discovery.playedAt,
            discovery.markedInterestedAt,
            discovery.hiddenAt,
            discovery.deletedAt
        ]
        .compactMap { $0 }
        .map(date)
        .max() ?? date(discovery.playedAt)
    }

    private static func favoriteUpdateDate(_ favorite: FavoriteStationRecord) -> Date {
        [favorite.createdAt, favorite.deletedAt]
            .compactMap { $0 }
            .map(date)
            .max() ?? .distantPast
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

    static func discoveryIdentityKey(_ discovery: DiscoveredTrackRecord) -> String {
        if let trackKey = normalizedIdentityValue(discovery.trackKey) {
            return "track:\(trackKey)"
        }

        return "track:\(TuneAVDiscoveredTrackSupport.appDataFallbackTrackKey(title: discovery.title, artist: discovery.artist))"
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
    let savedDiscoveries: [DiscoveredTrackRecord]

    var hasMeaningfulContent: Bool {
        hasLibraryCollections
    }

    var hasLibraryCollections: Bool {
        !favorites.isEmpty || !savedDiscoveries.isEmpty
    }

    init(
        favorites: [FavoriteStationRecord],
        savedDiscoveries: [DiscoveredTrackRecord] = []
    ) {
        self.favorites = favorites
        self.savedDiscoveries = savedDiscoveries
    }

    private enum CodingKeys: String, CodingKey {
        case favorites
        case savedDiscoveries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try container.decode([FavoriteStationRecord].self, forKey: .favorites)
        savedDiscoveries = try container.decodeIfPresent([DiscoveredTrackRecord].self, forKey: .savedDiscoveries) ?? []
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
    let trackKey: String?
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
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case discoveryID
        case trackKey
        case title
        case artist
        case stationID
        case stationName
        case artworkURL
        case stationArtworkURL
        case playedAt
        case markedInterestedAt
        case hiddenAt
        case deletedAt
        case updatedAt
    }

    init(
        discoveryID: String,
        trackKey: String? = nil,
        title: String,
        artist: String?,
        stationID: String,
        stationName: String,
        artworkURL: String?,
        stationArtworkURL: String?,
        playedAt: String,
        markedInterestedAt: String? = nil,
        hiddenAt: String? = nil,
        deletedAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.discoveryID = discoveryID
        self.trackKey = trackKey
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
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        stationID = try container.decodeIfPresent(String.self, forKey: .stationID) ?? "unknown-station"
        stationName = try container.decodeIfPresent(String.self, forKey: .stationName) ?? stationID
        artworkURL = try container.decodeIfPresent(String.self, forKey: .artworkURL)
        stationArtworkURL = try container.decodeIfPresent(String.self, forKey: .stationArtworkURL)
        markedInterestedAt = try container.decodeIfPresent(String.self, forKey: .markedInterestedAt)
        hiddenAt = try container.decodeIfPresent(String.self, forKey: .hiddenAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        playedAt = try container.decodeIfPresent(String.self, forKey: .playedAt)
            ?? markedInterestedAt
            ?? updatedAt
            ?? deletedAt
            ?? TuneAVDateCoding.string(from: .distantPast)

        trackKey = try container.decodeIfPresent(String.self, forKey: .trackKey)
        discoveryID = try container.decodeIfPresent(String.self, forKey: .discoveryID)
            ?? TuneAVDiscoveredTrackSupport.makeID(title: title, artist: artist, stationID: stationID)
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
    let canonicalStationId: String?
    let category: String?
    let visibility: String?
    let qualityScore: Int?
    let enrichmentStatus: String?
    let metadataUpdatedAt: String?
    let artwork: StationArtwork?
    let editorial: StationEditorial?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case country
        case countryCode
        case state
        case language
        case languageCodes
        case tags
        case streamURL
        case faviconURL
        case bitrate
        case codec
        case homepageURL
        case votes
        case clickCount
        case clickTrend
        case isHLS
        case hasExtendedInfo
        case hasSSLError
        case lastCheckOKAt
        case geoLatitude
        case geoLongitude
        case canonicalStationId
        case category
        case visibility
        case qualityScore
        case enrichmentStatus
        case metadataUpdatedAt
        case artwork
        case editorial
    }

    init(
        id: String,
        name: String,
        country: String,
        countryCode: String?,
        state: String?,
        language: String,
        languageCodes: String?,
        tags: String,
        streamURL: String,
        faviconURL: String?,
        bitrate: Int?,
        codec: String?,
        homepageURL: String?,
        votes: Int?,
        clickCount: Int?,
        clickTrend: Int?,
        isHLS: Bool?,
        hasExtendedInfo: Bool?,
        hasSSLError: Bool?,
        lastCheckOKAt: String?,
        geoLatitude: Double?,
        geoLongitude: Double?,
        canonicalStationId: String? = nil,
        category: String? = nil,
        visibility: String? = nil,
        qualityScore: Int? = nil,
        enrichmentStatus: String? = nil,
        metadataUpdatedAt: String? = nil,
        artwork: StationArtwork? = nil,
        editorial: StationEditorial? = nil
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.countryCode = countryCode
        self.state = state
        self.language = language
        self.languageCodes = languageCodes
        self.tags = tags
        self.streamURL = streamURL
        self.faviconURL = faviconURL
        self.bitrate = bitrate
        self.codec = codec
        self.homepageURL = homepageURL
        self.votes = votes
        self.clickCount = clickCount
        self.clickTrend = clickTrend
        self.isHLS = isHLS
        self.hasExtendedInfo = hasExtendedInfo
        self.hasSSLError = hasSSLError
        self.lastCheckOKAt = lastCheckOKAt
        self.geoLatitude = geoLatitude
        self.geoLongitude = geoLongitude
        self.canonicalStationId = canonicalStationId
        self.category = category
        self.visibility = visibility
        self.qualityScore = qualityScore
        self.enrichmentStatus = enrichmentStatus
        self.metadataUpdatedAt = metadataUpdatedAt
        self.artwork = artwork
        self.editorial = editorial
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // Cloud deletion tombstones intentionally keep only station identity.
        // Preserve them during sync while remaining strict about id and name.
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        tags = try container.decodeIfPresent(String.self, forKey: .tags) ?? ""
        streamURL = try container.decodeIfPresent(String.self, forKey: .streamURL) ?? ""

        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        languageCodes = try container.decodeIfPresent(String.self, forKey: .languageCodes)
        faviconURL = try container.decodeIfPresent(String.self, forKey: .faviconURL)
        bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        homepageURL = try container.decodeIfPresent(String.self, forKey: .homepageURL)
        votes = try container.decodeIfPresent(Int.self, forKey: .votes)
        clickCount = try container.decodeIfPresent(Int.self, forKey: .clickCount)
        clickTrend = try container.decodeIfPresent(Int.self, forKey: .clickTrend)
        isHLS = try container.decodeIfPresent(Bool.self, forKey: .isHLS)
        hasExtendedInfo = try container.decodeIfPresent(Bool.self, forKey: .hasExtendedInfo)
        hasSSLError = try container.decodeIfPresent(Bool.self, forKey: .hasSSLError)
        lastCheckOKAt = try container.decodeIfPresent(String.self, forKey: .lastCheckOKAt)
        geoLatitude = try container.decodeIfPresent(Double.self, forKey: .geoLatitude)
        geoLongitude = try container.decodeIfPresent(Double.self, forKey: .geoLongitude)
        canonicalStationId = try container.decodeIfPresent(String.self, forKey: .canonicalStationId)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        qualityScore = try container.decodeIfPresent(Int.self, forKey: .qualityScore)
        enrichmentStatus = try container.decodeIfPresent(String.self, forKey: .enrichmentStatus)
        metadataUpdatedAt = try container.decodeIfPresent(String.self, forKey: .metadataUpdatedAt)
        artwork = try container.decodeIfPresent(StationArtwork.self, forKey: .artwork)
        editorial = try container.decodeIfPresent(StationEditorial.self, forKey: .editorial)
    }
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
            geoLongitude: record.geoLongitude,
            canonicalStationId: record.canonicalStationId,
            category: record.category,
            visibility: record.visibility,
            qualityScore: record.qualityScore,
            enrichmentStatus: record.enrichmentStatus,
            metadataUpdatedAt: record.metadataUpdatedAt,
            artwork: record.artwork,
            editorial: record.editorial
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
            geoLongitude: geoLongitude,
            canonicalStationId: canonicalStationId,
            category: category,
            visibility: visibility,
            qualityScore: qualityScore,
            enrichmentStatus: enrichmentStatus,
            metadataUpdatedAt: metadataUpdatedAt,
            artwork: artwork,
            editorial: editorial
        )
    }
}
