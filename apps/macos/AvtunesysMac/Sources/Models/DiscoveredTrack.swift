import Foundation

struct DiscoveredTrack: Identifiable, Hashable, Codable {
    let discoveryID: String
    var title: String
    var artist: String?
    var stationID: String
    var stationName: String
    var artworkURL: String?
    var stationArtworkURL: String?
    var playedAt: Date
    var markedInterestedAt: Date?
    var hiddenAt: Date?

    var id: String { discoveryID }

    init(
        title: String,
        artist: String?,
        station: Station,
        artworkURL: URL?,
        playedAt: Date = .now,
        markedInterestedAt: Date? = nil,
        hiddenAt: Date? = nil
    ) {
        let normalizedTitle = AVTunesysDiscoveredTrackSupport.normalizedValue(title) ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = AVTunesysDiscoveredTrackSupport.normalizedValue(artist)
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
        self.discoveryID = record.discoveryID
        self.title = AVTunesysDiscoveredTrackSupport.normalizedValue(record.title) ?? record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = AVTunesysDiscoveredTrackSupport.normalizedValue(record.artist)
        self.stationID = record.stationID
        self.stationName = record.stationName
        self.artworkURL = record.artworkURL
        self.stationArtworkURL = record.stationArtworkURL
        self.playedAt = AVTunesysDateCoding.date(from: record.playedAt)
        self.markedInterestedAt = record.markedInterestedAt.map(AVTunesysDateCoding.date(from:))
        self.hiddenAt = record.hiddenAt.map(AVTunesysDateCoding.date(from:))
    }

    var isMarkedInteresting: Bool {
        markedInterestedAt != nil
    }

    var isHidden: Bool {
        hiddenAt != nil
    }

    var artistDisplayText: String {
        artistNormalized ?? "Live now"
    }

    var searchQuery: String {
        if let artistNormalized {
            return "\(artistNormalized) \(title)"
        }
        return title
    }

    var resolvedArtworkURL: URL? {
        AVTunesysDiscoveredTrackSupport.resolvedURL(artworkURL)
    }

    var resolvedStationArtworkURL: URL? {
        AVTunesysDiscoveredTrackSupport.resolvedURL(stationArtworkURL)
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
            playedAt: AVTunesysDateCoding.string(from: playedAt),
            markedInterestedAt: markedInterestedAt.map(AVTunesysDateCoding.string(from:)),
            hiddenAt: hiddenAt.map(AVTunesysDateCoding.string(from:))
        )
    }

    private var artistNormalized: String? {
        AVTunesysDiscoveredTrackSupport.normalizedValue(artist)
    }

    static func makeID(title: String, artist: String?, stationID: String) -> String {
        AVTunesysDiscoveredTrackSupport.makeID(title: title, artist: artist, stationID: stationID)
    }
}
