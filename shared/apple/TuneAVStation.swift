import Foundation

struct StationArtwork: Hashable, Codable {
    let status: String
    let url: String?
    let version: String?
}

struct StationEditorial: Hashable, Codable {
    let summary: String
    let primaryFormat: String
    let secondaryFormats: [String]
    let musicIntensity: String
    let speechIntensity: String
    let languages: [String]
    let audience: [String]
    let programming: [String]
    let sourceUrls: [String]
    let confidence: String
    let reviewStatus: String
    let updatedAt: String
}

struct Station: Identifiable, Hashable, Codable {
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
    let artwork: StationArtwork?
    let editorial: StationEditorial?

    init(
        id: String,
        name: String,
        country: String,
        countryCode: String? = nil,
        state: String? = nil,
        language: String,
        languageCodes: String? = nil,
        tags: String,
        streamURL: String,
        faviconURL: String? = nil,
        bitrate: Int? = nil,
        codec: String? = nil,
        homepageURL: String? = nil,
        votes: Int? = nil,
        clickCount: Int? = nil,
        clickTrend: Int? = nil,
        isHLS: Bool? = nil,
        hasExtendedInfo: Bool? = nil,
        hasSSLError: Bool? = nil,
        lastCheckOKAt: String? = nil,
        geoLatitude: Double? = nil,
        geoLongitude: Double? = nil,
        canonicalStationId: String? = nil,
        category: String? = nil,
        visibility: String? = nil,
        qualityScore: Int? = nil,
        enrichmentStatus: String? = nil,
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
        self.artwork = artwork
        self.editorial = editorial
    }
}

extension Station {
    static var unknownCountryValues: [String] {
        [
            L10n.string("stationService.fallback.unknownCountry"),
            "Unknown country",
            "País desconocido",
            "País desconegut",
            "Pays inconnu",
            "Unbekanntes Land"
        ]
    }

    static var unknownDetailValues: [String] {
        [
            L10n.string("stationService.fallback.unknownCountry"),
            L10n.string("stationService.fallback.unknownLanguage"),
            "Unknown country",
            "Unknown language",
            "País desconocido",
            "Idioma desconocido",
            "País desconegut",
            "Idioma desconegut",
            "Pays inconnu",
            "Langue inconnue",
            "Unbekanntes Land",
            "Unbekannte Sprache"
        ]
    }

    static let samples: [Station] = [
        Station(
            id: "groove-salad",
            name: "SomaFM Groove Salad",
            country: "United States",
            countryCode: "US",
            language: "English",
            tags: "ambient,chillout,electronic",
            streamURL: "https://ice1.somafm.com/groovesalad-128-mp3",
            bitrate: 128,
            codec: "MP3",
            homepageURL: "https://somafm.com/groovesalad/"
        ),
        Station(
            id: "bbc-radio-1",
            name: "BBC Radio 1",
            country: "United Kingdom",
            countryCode: "GB",
            language: "English",
            tags: "pop,charts,live",
            streamURL: "https://stream.live.vc.bbcmedia.co.uk/bbc_radio_one",
            bitrate: 128,
            codec: "AAC",
            homepageURL: "https://www.bbc.co.uk/sounds/play/live:bbc_radio_one"
        ),
        Station(
            id: "los-40",
            name: "Los 40",
            country: "Spain",
            countryCode: "ES",
            language: "Spanish",
            tags: "pop,latin,hits",
            streamURL: "https://25653.live.streamtheworld.com/LOS40.mp3",
            bitrate: 128,
            codec: "MP3",
            homepageURL: "https://los40.com/"
        ),
        Station(
            id: "fip",
            name: "FIP",
            country: "France",
            countryCode: "FR",
            language: "French",
            tags: "eclectic,chill,jazz",
            streamURL: "https://icecast.radiofrance.fr/fip-hifi.aac",
            bitrate: 320,
            codec: "AAC",
            homepageURL: "https://www.radiofrance.fr/fip"
        )
    ]

    var shortMeta: String {
        [country, language]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var detailLine: String {
        [state, country, language]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }

    var primaryDetailLine: String {
        detailLine
    }

    var flagEmoji: String? {
        guard let code = TuneAVCountry.sanitizedCode(countryCode) else { return nil }
        return TuneAVCountry(code: code, name: code).flag
    }

    var tagsList: [String] {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var normalizedTags: [String] {
        tagsList
    }

    var technicalBadges: [String] {
        var badges: [String] = []
        if let codec, !codec.isEmpty { badges.append(codec) }
        if let bitrate, bitrate > 0 { badges.append("\(bitrate) kbps") }
        if isHLS == true { badges.append("HLS") }
        if hasExtendedInfo == true { badges.append("Extended info") }
        return badges
    }

    var popularityBadges: [String] {
        var badges: [String] = []
        if let votes, votes > 0 { badges.append("\(votes) votes") }
        if let clickCount, clickCount > 0 { badges.append("\(clickCount) clicks") }
        if let clickTrend, clickTrend > 0 { badges.append("+\(clickTrend) trend") }
        return badges
    }

    var initials: String {
        TuneAVInitials.make(from: name)
    }

    var displayArtworkURL: URL? {
        nil
    }

    var displayArtworkUsesFaviconProxy: Bool {
        false
    }

    var fallbackArtwork: TuneAVFallbackArtwork {
        TuneAVFallbackArtwork.select(for: self)
    }

    var resolvedHomepageURL: URL? {
        guard let homepageURL = TuneAVText.normalizedValue(homepageURL) else {
            return nil
        }
        return URL(string: homepageURL)
    }

    var shareText: String {
        if let homepageURL = TuneAVText.normalizedValue(homepageURL) {
            return "\(name)\n\(homepageURL)"
        }

        return "\(name)\n\(streamURL)"
    }

    func cardDetailText(
        preferCountryName: Bool,
        unknownValues: [String],
        locale: Locale = .current
    ) -> String? {
        let normalizedLanguage = TuneAVText.normalizedValue(language, excluding: unknownValues, locale: locale)
        let normalizedCountry = TuneAVText.normalizedValue(country, excluding: unknownValues, locale: locale)
        let normalizedState = TuneAVText.normalizedValue(state, excluding: unknownValues, locale: locale)

        if let normalizedLanguage {
            return normalizedLanguage
        }

        if let normalizedState {
            return normalizedState
        }

        if preferCountryName, let normalizedCountry {
            return normalizedCountry
        }

        return normalizedCountry
    }

    func hasResolvedCountry(unknownCountryValues: [String], locale: Locale = .current) -> Bool {
        if TuneAVCountry.sanitizedCode(countryCode) != nil {
            return true
        }

        return TuneAVText.normalizedValue(country, excluding: unknownCountryValues, locale: locale) != nil
    }
}
