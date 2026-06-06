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
            recents: mergedRecents(local.recents, remote.recents),
            discoveries: mergedDiscoveries(local.discoveries, remote.discoveries),
            settings: local.settings
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
        .sorted { $0.date < $1.date }
        .map(\.record)
    }

    private static func mergedRecents(
        _ local: [RecentStationRecord],
        _ remote: [RecentStationRecord]
    ) -> [RecentStationRecord] {
        newestDatedByKey(
            datedRecords(local + remote, date: recentUpdateDate),
            key: { stationIdentityKey($0.station) }
        )
        .sorted { $0.date > $1.date }
        .map(\.record)
    }

    private static func mergedDiscoveries(
        _ local: [DiscoveredTrackRecord],
        _ remote: [DiscoveredTrackRecord]
    ) -> [DiscoveredTrackRecord] {
        newestDatedByKey(
            datedRecords(local + remote, date: discoveryUpdateDate),
            key: { $0.discoveryID }
        )
        .sorted { $0.date > $1.date }
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

    private static func recentUpdateDate(_ recent: RecentStationRecord) -> Date {
        [recent.lastPlayedAt, recent.deletedAt]
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
        hasLibraryCollections
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
    let updatedAt: String?

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
        deletedAt: String? = nil,
        updatedAt: String? = nil
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
        self.updatedAt = updatedAt
    }
}

struct AppSettingsRecord: Codable, Equatable {
    let preferredCountry: String
    let preferredLanguage: String
    let preferredTag: String
    let lastPlayedStationID: String?
    let lastOpenedStationID: String?
    let lastOpenedStationPresentation: String?
    let sleepTimerMinutes: Int?
    let keepScreenAwake: Bool
    let warnBeforeCellularPlayback: Bool
    let openLastStationOnLaunch: Bool
    let autoSkipUnstableStreams: Bool
    let updatedAt: String

    init(
        preferredCountry: String,
        preferredLanguage: String,
        preferredTag: String,
        lastPlayedStationID: String?,
        lastOpenedStationID: String? = nil,
        lastOpenedStationPresentation: String? = nil,
        sleepTimerMinutes: Int?,
        keepScreenAwake: Bool = false,
        warnBeforeCellularPlayback: Bool = false,
        openLastStationOnLaunch: Bool = false,
        autoSkipUnstableStreams: Bool = false,
        updatedAt: String
    ) {
        self.preferredCountry = preferredCountry
        self.preferredLanguage = preferredLanguage
        self.preferredTag = preferredTag
        self.lastPlayedStationID = lastPlayedStationID
        self.lastOpenedStationID = lastOpenedStationID
        self.lastOpenedStationPresentation = lastOpenedStationPresentation
        self.sleepTimerMinutes = sleepTimerMinutes
        self.keepScreenAwake = keepScreenAwake
        self.warnBeforeCellularPlayback = warnBeforeCellularPlayback
        self.openLastStationOnLaunch = openLastStationOnLaunch
        self.autoSkipUnstableStreams = autoSkipUnstableStreams
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case preferredCountry
        case preferredLanguage
        case preferredTag
        case lastPlayedStationID
        case lastOpenedStationID
        case lastOpenedStationPresentation
        case sleepTimerMinutes
        case keepScreenAwake
        case warnBeforeCellularPlayback
        case openLastStationOnLaunch
        case autoSkipUnstableStreams
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredCountry = try container.decodeIfPresent(String.self, forKey: .preferredCountry) ?? ""
        preferredLanguage = try container.decodeIfPresent(String.self, forKey: .preferredLanguage) ?? ""
        preferredTag = try container.decodeIfPresent(String.self, forKey: .preferredTag) ?? ""
        lastPlayedStationID = try container.decodeIfPresent(String.self, forKey: .lastPlayedStationID)
        lastOpenedStationID = try container.decodeIfPresent(String.self, forKey: .lastOpenedStationID)
        lastOpenedStationPresentation = try container.decodeIfPresent(String.self, forKey: .lastOpenedStationPresentation)
        sleepTimerMinutes = try container.decodeIfPresent(Int.self, forKey: .sleepTimerMinutes)
        keepScreenAwake = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? false
        warnBeforeCellularPlayback = try container.decodeIfPresent(Bool.self, forKey: .warnBeforeCellularPlayback) ?? false
        openLastStationOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .openLastStationOnLaunch) ?? false
        autoSkipUnstableStreams = try container.decodeIfPresent(Bool.self, forKey: .autoSkipUnstableStreams) ?? false
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? "1970-01-01T00:00:00.000Z"
    }

    var hasMeaningfulContent: Bool {
        !preferredCountry.isEmpty ||
            !preferredLanguage.isEmpty ||
            !preferredTag.isEmpty ||
            lastPlayedStationID != nil ||
            lastOpenedStationID != nil ||
            lastOpenedStationPresentation != nil ||
            keepScreenAwake ||
            warnBeforeCellularPlayback ||
            openLastStationOnLaunch ||
            autoSkipUnstableStreams
    }

    static var empty: AppSettingsRecord {
        AppSettingsRecord(
            preferredCountry: "",
            preferredLanguage: "",
            preferredTag: "",
            lastPlayedStationID: nil,
            lastOpenedStationID: nil,
            lastOpenedStationPresentation: nil,
            sleepTimerMinutes: nil,
            keepScreenAwake: false,
            warnBeforeCellularPlayback: false,
            openLastStationOnLaunch: false,
            autoSkipUnstableStreams: false,
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
    let canonicalStationId: String?
    let category: String?
    let visibility: String?
    let qualityScore: Int?
    let enrichmentStatus: String?
    let metadataUpdatedAt: String?
    let artwork: StationArtwork?
    let editorial: StationEditorial?

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
