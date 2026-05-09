import Foundation

struct TuneAVStationSearchFilters {
    var query: String
    var country: String = ""
    var countryCode: String = ""
    var language: String = ""
    var tag: String = ""
    var locale: String = ""
    var limit: Int = 30
    var allowsEmptySearch: Bool = false
}

struct TuneAVStationFallbacks {
    var unnamed: String
    var unknownCountry: String
    var unknownLanguage: String
    var noTags: String

    static let english = TuneAVStationFallbacks(
        unnamed: "Unnamed station",
        unknownCountry: "Unknown country",
        unknownLanguage: "Unknown language",
        noTags: "radio"
    )
}

struct TuneAVStationService {
    enum ServiceError: LocalizedError {
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let message):
                return message
            }
        }
    }

    private let avalsysBaseURL: URL?
    private let radioBrowserBaseURL: URL
    private let session: URLSession
    private let fallbacks: TuneAVStationFallbacks
    private let invalidResponseMessage: String

    init(
        session: URLSession = .shared,
        avalsysBaseURL: URL? = URL(string: "https://api-account-av-preview.avalsys.com/v1/tune/stations/search")!,
        radioBrowserBaseURL: URL = URL(string: "https://de1.api.radio-browser.info/json/stations/search")!,
        fallbacks: TuneAVStationFallbacks = .english,
        invalidResponseMessage: String = "The station service returned an invalid response."
    ) {
        self.session = session
        self.avalsysBaseURL = avalsysBaseURL
        self.radioBrowserBaseURL = radioBrowserBaseURL
        self.fallbacks = fallbacks
        self.invalidResponseMessage = invalidResponseMessage
    }

    func searchStations(filters: TuneAVStationSearchFilters) async throws -> [Station] {
        let trimmedQuery = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = filters.country.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountryCode = filters.countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLanguage = filters.language.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = filters.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocale = filters.locale.trimmingCharacters(in: .whitespacesAndNewlines)

        guard filters.allowsEmptySearch || !trimmedQuery.isEmpty || !trimmedCountry.isEmpty || !trimmedCountryCode.isEmpty || !trimmedLanguage.isEmpty || !trimmedTag.isEmpty else {
            return []
        }

        let normalizedFilters = NormalizedStationSearchFilters(
            query: trimmedQuery,
            country: trimmedCountry,
            countryCode: trimmedCountryCode,
            language: trimmedLanguage,
            tag: trimmedTag,
            locale: trimmedLocale,
            limit: filters.limit
        )

        if let avalsysBaseURL {
            do {
                return try await searchAVALSYS(filters: normalizedFilters, baseURL: avalsysBaseURL)
            } catch {
                // Radio Browser remains the app's emergency catalog fallback.
            }
        }

        return try await searchRadioBrowser(filters: normalizedFilters)
    }

    private func searchAVALSYS(filters: NormalizedStationSearchFilters, baseURL: URL) async throws -> [Station] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            filters.query.isEmpty ? nil : URLQueryItem(name: "q", value: filters.query),
            filters.country.isEmpty ? nil : URLQueryItem(name: "country", value: filters.country),
            filters.countryCode.isEmpty ? nil : URLQueryItem(name: "countryCode", value: filters.countryCode),
            filters.language.isEmpty ? nil : URLQueryItem(name: "language", value: filters.language),
            filters.tag.isEmpty ? nil : URLQueryItem(name: "tag", value: filters.tag),
            filters.locale.isEmpty ? nil : URLQueryItem(name: "locale", value: filters.locale),
            URLQueryItem(name: "limit", value: String(filters.limit))
        ]
        .compactMap { $0 }

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let response = try await decodedResponse(TuneAVStationSearchResponseDTO.self, url: url)
        return applyExactTagFilterIfNeeded(response.resolvedStations, tag: filters.tag, limit: filters.limit)
    }

    private func searchRadioBrowser(filters: NormalizedStationSearchFilters) async throws -> [Station] {
        var components = URLComponents(url: radioBrowserBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            filters.query.isEmpty ? nil : URLQueryItem(name: "name", value: filters.query),
            filters.country.isEmpty ? nil : URLQueryItem(name: "country", value: filters.country),
            filters.countryCode.isEmpty ? nil : URLQueryItem(name: "countrycode", value: filters.countryCode),
            filters.language.isEmpty ? nil : URLQueryItem(name: "language", value: filters.language),
            filters.tag.isEmpty ? nil : URLQueryItem(name: "tag", value: filters.tag),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: String(filters.limit))
        ]
        .compactMap { $0 }

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let stations = try await decodedResponse([RadioBrowserStationDTO].self, url: url)
        let resolvedStations = stations.compactMap { $0.station(fallbacks: fallbacks) }

        return applyExactTagFilterIfNeeded(resolvedStations, tag: filters.tag, limit: filters.limit)
    }

    private func decodedResponse<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("TuneAV/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw ServiceError.invalidResponse(invalidResponseMessage)
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func applyExactTagFilterIfNeeded(_ resolvedStations: [Station], tag: String, limit: Int) -> [Station] {
        guard !tag.isEmpty else {
            return resolvedStations
        }

        let exactTagMatches = resolvedStations.filter { station in
            station.matchesTag(tag)
        }

        if !exactTagMatches.isEmpty {
            return Array(exactTagMatches.prefix(limit))
        }

        return resolvedStations
    }
}

private struct NormalizedStationSearchFilters {
    let query: String
    let country: String
    let countryCode: String
    let language: String
    let tag: String
    let locale: String
    let limit: Int
}

private struct TuneAVStationSearchResponseDTO: Decodable {
    let stations: [TuneAVStationDTO]

    var resolvedStations: [Station] {
        stations.compactMap(\.station)
    }
}

private struct TuneAVStationDTO: Decodable {
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
        case artwork
        case editorial
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decode(String.self, forKey: .country)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        language = try container.decode(String.self, forKey: .language)
        languageCodes = TuneAVStationDTO.decodeStringOrArray(container, forKey: .languageCodes)
        tags = try container.decode(String.self, forKey: .tags)
        streamURL = try container.decode(String.self, forKey: .streamURL)
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
        artwork = try container.decodeIfPresent(StationArtwork.self, forKey: .artwork)
        editorial = try container.decodeIfPresent(StationEditorial.self, forKey: .editorial)
    }

    var station: Station? {
        let trimmedStreamURL = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStreamURL.isEmpty else { return nil }

        return Station(
            id: id,
            name: name,
            country: country,
            countryCode: countryCode,
            state: state,
            language: language,
            languageCodes: languageCodes,
            tags: tags,
            streamURL: trimmedStreamURL,
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
            artwork: artwork,
            editorial: editorial
        )
    }

    private static func decodeStringOrArray(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return normalizedOptional(string)
        }

        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            let joined = values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
            return normalizedOptional(joined)
        }

        return nil
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Station {
    func matchesTag(_ rawTag: String) -> Bool {
        let requestedTag = normalizedTagToken(rawTag)
        guard !requestedTag.isEmpty else { return false }

        return tags
            .split(separator: ",")
            .map { normalizedTagToken(String($0)) }
            .contains(requestedTag)
    }

    func normalizedTagToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct RadioBrowserStationDTO: Decodable {
    let stationuuid: String
    let name: String
    let country: String?
    let countrycode: String?
    let state: String?
    let language: String?
    let languagecodes: String?
    let tags: String?
    let url: String?
    let url_resolved: String?
    let favicon: String?
    let bitrate: Int?
    let codec: String?
    let homepage: String?
    let votes: Int?
    let clickcount: Int?
    let clicktrend: Int?
    let hls: Int?
    let has_extended_info: Bool?
    let ssl_error: Int?
    let lastcheckoktime_iso8601: String?
    let geo_lat: Double?
    let geo_long: Double?
    let lastcheckok: Int?

    func station(fallbacks: TuneAVStationFallbacks) -> Station? {
        let stream = (url_resolved?.isEmpty == false ? url_resolved : url) ?? ""
        guard !stream.isEmpty else { return nil }
        guard (lastcheckok ?? 1) == 1 else { return nil }

        return Station(
            id: stationuuid,
            name: normalized(name, fallback: fallbacks.unnamed),
            country: normalized(country, fallback: fallbacks.unknownCountry),
            countryCode: normalizedOptional(countrycode),
            state: normalizedOptional(state),
            language: normalized(language, fallback: fallbacks.unknownLanguage),
            languageCodes: normalizedOptional(languagecodes),
            tags: normalized(tags, fallback: fallbacks.noTags),
            streamURL: stream,
            faviconURL: normalizedOptionalURL(favicon),
            bitrate: bitrate,
            codec: normalizedOptional(codec),
            homepageURL: normalizedOptionalURL(homepage),
            votes: votes,
            clickCount: clickcount,
            clickTrend: clicktrend,
            isHLS: hls.map { $0 == 1 },
            hasExtendedInfo: has_extended_info,
            hasSSLError: ssl_error.map { $0 == 1 },
            lastCheckOKAt: normalizedOptional(lastcheckoktime_iso8601),
            geoLatitude: geo_lat,
            geoLongitude: geo_long
        )
    }

    private func normalized(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedOptionalURL(_ value: String?) -> String? {
        guard let candidate = normalizedOptional(value), URL(string: candidate) != nil else {
            return nil
        }
        return candidate
    }
}
