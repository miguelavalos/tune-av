import Foundation
import SwiftData

extension Station {
    init(favorite: FavoriteStation) {
        self.init(
            id: favorite.stationID,
            name: favorite.name,
            country: favorite.country,
            countryCode: favorite.countryCode,
            state: favorite.state,
            language: favorite.language,
            languageCodes: favorite.languageCodes,
            tags: favorite.tags,
            streamURL: favorite.streamURL,
            faviconURL: favorite.faviconURL,
            bitrate: favorite.bitrate,
            codec: favorite.codec,
            homepageURL: favorite.homepageURL,
            votes: favorite.votes,
            clickCount: favorite.clickCount,
            clickTrend: favorite.clickTrend,
            isHLS: favorite.isHLS,
            hasExtendedInfo: favorite.hasExtendedInfo,
            hasSSLError: favorite.hasSSLError,
            lastCheckOKAt: favorite.lastCheckOKAt,
            geoLatitude: favorite.geoLatitude,
            geoLongitude: favorite.geoLongitude
        )
    }

    init(recent: RecentStation) {
        self.init(
            id: recent.stationID,
            name: recent.name,
            country: recent.country,
            countryCode: recent.countryCode,
            state: recent.state,
            language: recent.language,
            languageCodes: recent.languageCodes,
            tags: recent.tags,
            streamURL: recent.streamURL,
            faviconURL: recent.faviconURL,
            bitrate: recent.bitrate,
            codec: recent.codec,
            homepageURL: recent.homepageURL,
            votes: recent.votes,
            clickCount: recent.clickCount,
            clickTrend: recent.clickTrend,
            isHLS: recent.isHLS,
            hasExtendedInfo: recent.hasExtendedInfo,
            hasSSLError: recent.hasSSLError,
            lastCheckOKAt: recent.lastCheckOKAt,
            geoLatitude: recent.geoLatitude,
            geoLongitude: recent.geoLongitude
        )
    }
}

extension Station {
    func cardDetailText(preferCountryName: Bool) -> String? {
        cardDetailText(
            preferCountryName: preferCountryName,
            unknownValues: Station.unknownDetailValues,
            locale: L10n.locale
        )
    }

    var statusBadges: [String] {
        var badges: [String] = []
        if hasSSLError == true { badges.append(L10n.string("station.status.sslIssue")) }
        if let lastCheckOKAt, !lastCheckOKAt.isEmpty { badges.append(L10n.string("station.status.checked")) }
        return badges
    }

}

@Model
final class FavoriteStation {
    @Attribute(.unique) var stationID: String
    var name: String
    var country: String
    var countryCode: String?
    var state: String?
    var language: String
    var languageCodes: String?
    var tags: String
    var streamURL: String
    var faviconURL: String?
    var bitrate: Int?
    var codec: String?
    var homepageURL: String?
    var votes: Int?
    var clickCount: Int?
    var clickTrend: Int?
    var isHLS: Bool?
    var hasExtendedInfo: Bool?
    var hasSSLError: Bool?
    var lastCheckOKAt: String?
    var geoLatitude: Double?
    var geoLongitude: Double?
    var createdAt: Date

    init(station: Station, createdAt: Date = .now) {
        self.stationID = station.id
        self.name = station.name
        self.country = station.country
        self.countryCode = station.countryCode
        self.state = station.state
        self.language = station.language
        self.languageCodes = station.languageCodes
        self.tags = station.tags
        self.streamURL = station.streamURL
        self.faviconURL = station.faviconURL
        self.bitrate = station.bitrate
        self.codec = station.codec
        self.homepageURL = station.homepageURL
        self.votes = station.votes
        self.clickCount = station.clickCount
        self.clickTrend = station.clickTrend
        self.isHLS = station.isHLS
        self.hasExtendedInfo = station.hasExtendedInfo
        self.hasSSLError = station.hasSSLError
        self.lastCheckOKAt = station.lastCheckOKAt
        self.geoLatitude = station.geoLatitude
        self.geoLongitude = station.geoLongitude
        self.createdAt = createdAt
    }
}

@Model
final class LibrarySyncTombstone {
    @Attribute(.unique) var resourceKey: String
    var resource: String
    var identityKey: String
    var payloadJSON: String
    var deletedAt: Date

    init(resource: String, identityKey: String, payloadJSON: String, deletedAt: Date = .now) {
        self.resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        self.resource = resource
        self.identityKey = identityKey
        self.payloadJSON = payloadJSON
        self.deletedAt = deletedAt
    }
}

@Model
final class RecentStation {
    @Attribute(.unique) var stationID: String
    var name: String
    var country: String
    var countryCode: String?
    var state: String?
    var language: String
    var languageCodes: String?
    var tags: String
    var streamURL: String
    var faviconURL: String?
    var bitrate: Int?
    var codec: String?
    var homepageURL: String?
    var votes: Int?
    var clickCount: Int?
    var clickTrend: Int?
    var isHLS: Bool?
    var hasExtendedInfo: Bool?
    var hasSSLError: Bool?
    var lastCheckOKAt: String?
    var geoLatitude: Double?
    var geoLongitude: Double?
    var lastPlayedAt: Date

    init(station: Station, lastPlayedAt: Date = .now) {
        self.stationID = station.id
        self.name = station.name
        self.country = station.country
        self.countryCode = station.countryCode
        self.state = station.state
        self.language = station.language
        self.languageCodes = station.languageCodes
        self.tags = station.tags
        self.streamURL = station.streamURL
        self.faviconURL = station.faviconURL
        self.bitrate = station.bitrate
        self.codec = station.codec
        self.homepageURL = station.homepageURL
        self.votes = station.votes
        self.clickCount = station.clickCount
        self.clickTrend = station.clickTrend
        self.isHLS = station.isHLS
        self.hasExtendedInfo = station.hasExtendedInfo
        self.hasSSLError = station.hasSSLError
        self.lastCheckOKAt = station.lastCheckOKAt
        self.geoLatitude = station.geoLatitude
        self.geoLongitude = station.geoLongitude
        self.lastPlayedAt = lastPlayedAt
    }
}

@Model
final class DiscoveredTrack {
    @Attribute(.unique) var discoveryID: String
    var title: String
    var artist: String?
    var stationID: String
    var stationName: String
    var artworkURL: String?
    var stationArtworkURL: String?
    var playedAt: Date
    var markedInterestedAt: Date?
    var hiddenAt: Date?

    init(
        title: String,
        artist: String?,
        station: Station,
        artworkURL: URL?,
        playedAt: Date = .now,
        markedInterestedAt: Date? = nil,
        hiddenAt: Date? = nil
    ) {
        let normalizedArtist = TuneAVDiscoveredTrackSupport.normalizedValue(artist)
        let normalizedTitle = TuneAVDiscoveredTrackSupport.normalizedValue(title) ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.discoveryID = Self.makeID(title: normalizedTitle, artist: normalizedArtist, stationID: station.id)
        self.title = normalizedTitle
        self.artist = normalizedArtist
        self.stationID = station.id
        self.stationName = station.name
        self.artworkURL = artworkURL?.absoluteString
        self.stationArtworkURL = station.displayArtworkURL?.absoluteString
        self.playedAt = playedAt
        self.markedInterestedAt = markedInterestedAt
        self.hiddenAt = hiddenAt
    }

    init(record: DiscoveredTrackRecord) {
        let normalizedArtist = TuneAVDiscoveredTrackSupport.normalizedValue(record.artist)
        self.discoveryID = record.discoveryID
        self.title = TuneAVDiscoveredTrackSupport.normalizedValue(record.title) ?? record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = normalizedArtist
        self.stationID = record.stationID
        self.stationName = record.stationName
        self.artworkURL = record.artworkURL
        self.stationArtworkURL = record.stationArtworkURL
        self.playedAt = Self.date(from: record.playedAt)
        self.markedInterestedAt = record.markedInterestedAt.map(Self.date(from:))
        self.hiddenAt = record.hiddenAt.map(Self.date(from:))
    }

    static func makeID(title: String, artist: String?, stationID: String) -> String {
        TuneAVDiscoveredTrackSupport.makeID(title: title, artist: artist, stationID: stationID, locale: L10n.locale)
    }

    private static func date(from value: String) -> Date {
        TuneAVDateCoding.date(from: value)
    }
}

extension DiscoveredTrack: TuneAVMusicLibraryDiscovery {
    var isMarkedInteresting: Bool {
        markedInterestedAt != nil
    }

    var isHidden: Bool {
        hiddenAt != nil
    }

    var artistDisplayText: String {
        TuneAVDiscoveredTrackSupport.artistDisplayText(artist, liveFallback: L10n.string("player.track.liveNow"))
    }

    var searchQuery: String {
        TuneAVDiscoveredTrackSupport.searchQuery(title: title, artist: artist)
    }

    var resolvedArtworkURL: URL? {
        TuneAVDiscoveredTrackSupport.resolvedURL(artworkURL)
    }

    var resolvedStationArtworkURL: URL? {
        TuneAVDiscoveredTrackSupport.resolvedURL(stationArtworkURL)
    }

    var appDataRecord: DiscoveredTrackRecord {
        DiscoveredTrackRecord(
            discoveryID: discoveryID,
            title: title,
            artist: artist,
            stationID: stationID,
            stationName: stationName,
            artworkURL: artworkURL,
            stationArtworkURL: stationArtworkURL,
            playedAt: Self.isoString(from: playedAt),
            markedInterestedAt: markedInterestedAt.map(Self.isoString(from:)),
            hiddenAt: hiddenAt.map(Self.isoString(from:))
        )
    }
    private static func isoString(from date: Date) -> String {
        TuneAVDateCoding.string(from: date)
    }
}

@Model
final class AppSettings {
    var preferredCountry: String
    var preferredLanguage: String
    var preferredTag: String
    var lastPlayedStationID: String?
    var sleepTimerMinutes: Int?
    var updatedAt: Date

    init(
        preferredCountry: String = "",
        preferredLanguage: String = "",
        preferredTag: String = "",
        lastPlayedStationID: String? = nil,
        sleepTimerMinutes: Int? = nil,
        updatedAt: Date = .now
    ) {
        self.preferredCountry = preferredCountry
        self.preferredLanguage = preferredLanguage
        self.preferredTag = preferredTag
        self.lastPlayedStationID = lastPlayedStationID
        self.sleepTimerMinutes = sleepTimerMinutes
        self.updatedAt = updatedAt
    }
}
