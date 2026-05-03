import Foundation

struct AVTunesysStationSearchFilters {
    var query: String
    var country: String = ""
    var countryCode: String = ""
    var language: String = ""
    var tag: String = ""
    var limit: Int = 30
    var allowsEmptySearch: Bool = false
}

struct AVTunesysStationFallbacks {
    var unnamed: String
    var unknownCountry: String
    var unknownLanguage: String
    var noTags: String

    static let english = AVTunesysStationFallbacks(
        unnamed: "Unnamed station",
        unknownCountry: "Unknown country",
        unknownLanguage: "Unknown language",
        noTags: "radio"
    )
}

struct AVTunesysStationService {
    enum ServiceError: LocalizedError {
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let message):
                return message
            }
        }
    }

    private let baseURL = URL(string: "https://de1.api.radio-browser.info/json/stations/search")!
    private let session: URLSession
    private let fallbacks: AVTunesysStationFallbacks
    private let invalidResponseMessage: String

    init(
        session: URLSession = .shared,
        fallbacks: AVTunesysStationFallbacks = .english,
        invalidResponseMessage: String = "The station service returned an invalid response."
    ) {
        self.session = session
        self.fallbacks = fallbacks
        self.invalidResponseMessage = invalidResponseMessage
    }

    func searchStations(filters: AVTunesysStationSearchFilters) async throws -> [Station] {
        let trimmedQuery = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = filters.country.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountryCode = filters.countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLanguage = filters.language.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = filters.tag.trimmingCharacters(in: .whitespacesAndNewlines)

        guard filters.allowsEmptySearch || !trimmedQuery.isEmpty || !trimmedCountry.isEmpty || !trimmedCountryCode.isEmpty || !trimmedLanguage.isEmpty || !trimmedTag.isEmpty else {
            return []
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            trimmedQuery.isEmpty ? nil : URLQueryItem(name: "name", value: trimmedQuery),
            trimmedCountry.isEmpty ? nil : URLQueryItem(name: "country", value: trimmedCountry),
            trimmedCountryCode.isEmpty ? nil : URLQueryItem(name: "countrycode", value: trimmedCountryCode),
            trimmedLanguage.isEmpty ? nil : URLQueryItem(name: "language", value: trimmedLanguage),
            trimmedTag.isEmpty ? nil : URLQueryItem(name: "tag", value: trimmedTag),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: String(filters.limit))
        ]
        .compactMap { $0 }

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("AVTunesys/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw ServiceError.invalidResponse(invalidResponseMessage)
        }

        let stations = try JSONDecoder().decode([RadioBrowserStationDTO].self, from: data)
        let resolvedStations = stations.compactMap { $0.station(fallbacks: fallbacks) }

        guard !trimmedTag.isEmpty else {
            return resolvedStations
        }

        let exactTagMatches = resolvedStations.filter { station in
            station.matchesTag(trimmedTag)
        }

        if !exactTagMatches.isEmpty {
            return Array(exactTagMatches.prefix(filters.limit))
        }

        return resolvedStations
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

    func station(fallbacks: AVTunesysStationFallbacks) -> Station? {
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
