import Foundation
import os

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
        case requestFailed(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse(let message):
                return message
            case .requestFailed(let statusCode):
                return "Station service request failed with status \(statusCode)."
            }
        }
    }

    private let avalsysBaseURL: URL?
    private let avalsysPopularBaseURL: URL?
    private let radioBrowserBaseURL: URL
    private let session: URLSession
    private let fallbacks: TuneAVStationFallbacks
    private let invalidResponseMessage: String
    private let backendGate: TuneAVBackendHealthGate
    private let responseCache: TuneAVStationResponseCache

    init(
        session: URLSession = TuneAVURLSessions.catalog,
        avalsysBaseURL: URL? = TuneAVStationService.defaultAVALSYSBaseURL(path: "/v1/tune/stations/search"),
        avalsysPopularBaseURL: URL? = TuneAVStationService.defaultAVALSYSBaseURL(path: "/v1/tune/stations/popular"),
        radioBrowserBaseURL: URL = URL(string: "https://de1.api.radio-browser.info/json/stations/search")!,
        fallbacks: TuneAVStationFallbacks = .english,
        invalidResponseMessage: String = "The station service returned an invalid response.",
        backendGate: TuneAVBackendHealthGate = .shared,
        responseCache: TuneAVStationResponseCache = .shared
    ) {
        self.session = session
        self.avalsysBaseURL = avalsysBaseURL
        self.avalsysPopularBaseURL = avalsysPopularBaseURL
        self.radioBrowserBaseURL = radioBrowserBaseURL
        self.fallbacks = fallbacks
        self.invalidResponseMessage = invalidResponseMessage
        self.backendGate = backendGate
        self.responseCache = responseCache
    }

    static func defaultAVALSYSBaseURL(path: String) -> URL? {
        guard let baseURL = TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL") else {
            return nil
        }
        return baseURL.appending(path: path)
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

        if let avalsysBaseURL, await backendGate.canAttempt() {
            do {
                let stations = try await searchAVALSYS(filters: normalizedFilters, baseURL: avalsysBaseURL)
                await backendGate.recordSuccess()
                return stations
            } catch {
                await backendGate.recordFailure()
                // Radio Browser remains the app's emergency catalog fallback.
            }
        }

        return try await searchRadioBrowser(filters: normalizedFilters)
    }

    func popularStations(filters: TuneAVStationSearchFilters) async throws -> [Station] {
        var popularFilters = filters
        popularFilters.query = ""
        popularFilters.allowsEmptySearch = true

        let trimmedCountryCode = popularFilters.countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLanguage = popularFilters.language.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = popularFilters.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocale = popularFilters.locale.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedFilters = NormalizedStationSearchFilters(
            query: "",
            country: "",
            countryCode: trimmedCountryCode,
            language: trimmedLanguage,
            tag: trimmedTag,
            locale: trimmedLocale,
            limit: popularFilters.limit
        )

        if let avalsysPopularBaseURL, await backendGate.canAttempt() {
            do {
                let stations = try await searchAVALSYS(filters: normalizedFilters, baseURL: avalsysPopularBaseURL, surface: "home")
                await backendGate.recordSuccess()
                return stations
            } catch ServiceError.requestFailed(let statusCode) where statusCode == 404 {
                // Older API deployments may not have the semantic popular endpoint yet.
                return try await searchStations(filters: popularFilters)
            } catch {
                await backendGate.recordFailure()
                return try await searchRadioBrowser(filters: normalizedFilters)
            }
        }

        return try await searchStations(filters: popularFilters)
    }

    private func searchAVALSYS(filters: NormalizedStationSearchFilters, baseURL: URL, surface: String? = nil) async throws -> [Station] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            filters.query.isEmpty ? nil : URLQueryItem(name: "q", value: filters.query),
            filters.country.isEmpty ? nil : URLQueryItem(name: "country", value: filters.country),
            filters.countryCode.isEmpty ? nil : URLQueryItem(name: "countryCode", value: filters.countryCode),
            filters.language.isEmpty ? nil : URLQueryItem(name: "language", value: filters.language),
            filters.tag.isEmpty ? nil : URLQueryItem(name: "tag", value: filters.tag),
            filters.locale.isEmpty ? nil : URLQueryItem(name: "locale", value: filters.locale),
            surface.map { URLQueryItem(name: "surface", value: $0) },
            URLQueryItem(name: "limit", value: String(filters.limit))
        ]
        .compactMap { $0 }

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let cacheKey = "avalsys|\(url.absoluteString)"
        return try await responseCache.stations(for: cacheKey) { etag in
            let response = try await decodedResponse(
                TuneAVStationSearchResponseDTO.self,
                url: url,
                timeoutInterval: 4,
                etag: etag
            )
            switch response {
            case .notModified:
                return .notModified
            case .value(let dto, let etag):
                let stations = applyExactTagFilterIfNeeded(deduplicatedStations(dto.resolvedStations), tag: filters.tag, limit: filters.limit)
                return .updated(stations, etag: etag)
            }
        }
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

        let cacheKey = "radioBrowser|\(url.absoluteString)"
        return try await responseCache.stations(for: cacheKey) { _ in
            let response = try await decodedResponse([RadioBrowserStationDTO].self, url: url)
            guard case .value(let stations, _) = response else {
                throw ServiceError.invalidResponse(invalidResponseMessage)
            }
            let resolvedStations = stations.compactMap { $0.station(fallbacks: fallbacks) }
            return .updated(applyExactTagFilterIfNeeded(deduplicatedStations(resolvedStations), tag: filters.tag, limit: filters.limit), etag: nil)
        }
    }

    private func decodedResponse<T: Decodable>(
        _ type: T.Type,
        url: URL,
        timeoutInterval: TimeInterval = 15,
        etag: String? = nil
    ) async throws -> TuneAVDecodedResponse<T> {
        var request = URLRequest(url: url)
        request.setValue("TuneAV/0.1", forHTTPHeaderField: "User-Agent")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        request.timeoutInterval = timeoutInterval

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse(invalidResponseMessage)
        }
        if httpResponse.statusCode == 304 {
            return .notModified
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw ServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return .value(try JSONDecoder().decode(type, from: data), etag: httpResponse.value(forHTTPHeaderField: "ETag"))
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

    private func deduplicatedStations(_ stations: [Station]) -> [Station] {
        var resolvedStations: [Station] = []
        var indexesByKey: [String: Int] = [:]

        for station in stations {
            let keys = station.stationResultIdentityKeys
            if let existingIndex = keys.compactMap({ indexesByKey[$0] }).min() {
                if station.stationResultPreferenceRank > resolvedStations[existingIndex].stationResultPreferenceRank {
                    resolvedStations[existingIndex] = station
                    for key in keys {
                        indexesByKey[key] = existingIndex
                    }
                }
                continue
            }

            let nextIndex = resolvedStations.count
            resolvedStations.append(station)
            for key in keys {
                indexesByKey[key] = nextIndex
            }
        }

        return resolvedStations
    }
}

private enum TuneAVDecodedResponse<T> {
    case value(T, etag: String?)
    case notModified
}

actor TuneAVStationResponseCache {
    static let shared = TuneAVStationResponseCache()

    private struct Entry {
        let stations: [Station]
        let etag: String?
        let cachedAt: Date
    }

    enum LoadResult {
        case updated([Station], etag: String?)
        case notModified
    }

    private let maxAge: TimeInterval
    private let maxEntries: Int
    private var entries: [String: Entry] = [:]
    private var inFlightRequests: [String: Task<LoadResult, Error>] = [:]

    init(maxAge: TimeInterval = 120, maxEntries: Int = 80) {
        self.maxAge = maxAge
        self.maxEntries = maxEntries
    }

    func stations(for key: String, load: @escaping @Sendable (String?) async throws -> LoadResult) async throws -> [Station] {
        if let cached = cachedStations(for: key) {
            return cached
        }
        if let inFlightRequest = inFlightRequests[key] {
            return try resolveLoadResult(try await inFlightRequest.value, staleEntry: entries[key], key: key)
        }

        let staleEntry = entries[key]
        let task = Task {
            try await load(staleEntry?.etag)
        }
        inFlightRequests[key] = task

        do {
            let result = try await task.value
            inFlightRequests[key] = nil
            return try resolveLoadResult(result, staleEntry: staleEntry, key: key)
        } catch {
            inFlightRequests[key] = nil
            throw error
        }
    }

    private func resolveLoadResult(_ result: LoadResult, staleEntry: Entry?, key: String) throws -> [Station] {
        switch result {
        case .updated(let stations, let etag):
            save(stations, etag: etag, for: key)
            return stations
        case .notModified:
            guard let staleEntry else {
                throw TuneAVStationService.ServiceError.invalidResponse("Station cache revalidation returned without a cached response.")
            }
            save(staleEntry.stations, etag: staleEntry.etag, for: key)
            return staleEntry.stations
        }
    }

    private func cachedStations(for key: String, now: Date = .now) -> [Station]? {
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.cachedAt) <= maxAge else {
            return nil
        }
        return entry.stations
    }

    private func save(_ stations: [Station], etag: String?, for key: String, now: Date = .now) {
        removeExpiredEntries(now: now)
        if entries.count >= maxEntries,
           let oldestKey = entries.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key {
            entries[oldestKey] = nil
        }
        entries[key] = Entry(stations: stations, etag: etag, cachedAt: now)
    }

    private func removeExpiredEntries(now: Date) {
        for (key, entry) in entries where now.timeIntervalSince(entry.cachedAt) > maxAge {
            entries[key] = nil
        }
    }

    func clearMemoryCache() {
        entries.removeAll(keepingCapacity: false)
    }
}

actor TuneAVBackendHealthGate {
    static let shared = TuneAVBackendHealthGate(userDefaults: .standard)
    private static let logger = Logger(subsystem: "com.avalsys.tuneav", category: "stations")

    private let failureThreshold: Int
    private let baseCooldown: TimeInterval
    private let maxCooldown: TimeInterval
    private let now: @Sendable () -> Date
    private let userDefaults: UserDefaults?
    private let unavailableUntilKey: String
    private let cooldownLevelKey: String
    private var consecutiveFailures = 0
    private var cooldownLevel = 0
    private var unavailableUntil: Date?

    init(
        failureThreshold: Int = 3,
        baseCooldown: TimeInterval = 5 * 60,
        maxCooldown: TimeInterval = 30 * 60,
        now: @escaping @Sendable () -> Date = { Date() },
        userDefaults: UserDefaults? = nil,
        storageKeyPrefix: String = "tuneav.stationBackendGate"
    ) {
        self.failureThreshold = failureThreshold
        self.baseCooldown = baseCooldown
        self.maxCooldown = maxCooldown
        self.now = now
        self.userDefaults = userDefaults
        self.unavailableUntilKey = "\(storageKeyPrefix).unavailableUntil"
        self.cooldownLevelKey = "\(storageKeyPrefix).cooldownLevel"

        if let storedUnavailableUntil = userDefaults?.object(forKey: unavailableUntilKey) as? Date, now() < storedUnavailableUntil {
            self.unavailableUntil = storedUnavailableUntil
            self.cooldownLevel = userDefaults?.integer(forKey: cooldownLevelKey) ?? 0
        } else {
            userDefaults?.removeObject(forKey: unavailableUntilKey)
            self.cooldownLevel = userDefaults?.integer(forKey: cooldownLevelKey) ?? 0
        }
    }

    func canAttempt() -> Bool {
        guard let unavailableUntil else {
            return true
        }
        if now() >= unavailableUntil {
            Self.logger.info("AVALSYS station backend cooldown expired; retrying catalog request")
            self.unavailableUntil = nil
            userDefaults?.removeObject(forKey: unavailableUntilKey)
            return true
        }
        Self.logger.info("Skipping AVALSYS station backend until \(unavailableUntil, privacy: .public)")
        return false
    }

    func recordSuccess() {
        if consecutiveFailures > 0 || unavailableUntil != nil {
            Self.logger.info("AVALSYS station backend recovered; clearing temporary cooldown")
        }
        consecutiveFailures = 0
        cooldownLevel = 0
        unavailableUntil = nil
        clearPersistedState()
    }

    func recordFailure() {
        consecutiveFailures += 1
        guard consecutiveFailures >= failureThreshold else {
            return
        }

        let multiplier = pow(2.0, Double(cooldownLevel))
        let cooldown = min(baseCooldown * multiplier, maxCooldown)
        unavailableUntil = now().addingTimeInterval(cooldown)
        Self.logger.error("AVALSYS station backend temporarily unavailable after repeated failures; cooldown \(cooldown, privacy: .public)s")
        cooldownLevel += 1
        consecutiveFailures = 0
        persistCooldownState()
    }

    private func persistCooldownState() {
        guard let unavailableUntil else {
            clearPersistedState()
            return
        }
        userDefaults?.set(unavailableUntil, forKey: unavailableUntilKey)
        userDefaults?.set(cooldownLevel, forKey: cooldownLevelKey)
    }

    private func clearPersistedState() {
        userDefaults?.removeObject(forKey: unavailableUntilKey)
        userDefaults?.removeObject(forKey: cooldownLevelKey)
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
        metadataUpdatedAt = try container.decodeIfPresent(String.self, forKey: .metadataUpdatedAt)
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
            metadataUpdatedAt: metadataUpdatedAt,
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
    var stationResultIdentityKeys: [String] {
        var keys: [String] = [id]

        if let canonicalStationId {
            keys.append(canonicalStationId)
        }

        if let streamKey = stationResultURLKey(streamURL) {
            keys.append("stream:\(streamKey)")
        }

        if let homepageURL, let homepageKey = stationResultURLKey(homepageURL) {
            keys.append("homepage:\(homepageKey)")
        }

        let nameKey = stationResultNameKey
        if !nameKey.isEmpty {
            keys.append("name:\(countryCode ?? ""):\(nameKey)")
        }

        return keys
    }

    var stationResultPreferenceRank: Int {
        var rank = qualityScore ?? 0
        if enrichmentStatus == "enriched" { rank += 60 }
        else if enrichmentStatus != nil { rank += 10 }
        if let artwork, artwork.status != "none" || artwork.url != nil { rank += 30 }
        if editorial != nil { rank += 40 }
        if canonicalStationId != nil { rank += 5 }
        return rank
    }

    var stationResultNameKey: String {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: #"\bon\s+[a-z0-9.-]+\.[a-z]{2,}\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:hd|hq|opus|aac|mp3|stream|radio)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }

    func stationResultURLKey(_ rawURL: String) -> String? {
        guard
            let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

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
