import Foundation

struct HomeFeedSnapshot: Equatable {
    var stations: [Station] = []
    var recentStations: [Station] = []
    var favoriteStations: [Station] = []
    var feedContext: HomeFeedContext = .popularWorldwide
}

struct HomeFeedResult {
    let stations: [Station]
    let context: HomeFeedContext
}

enum HomeFeedContext: Equatable {
    /// Stores the region code so the visible country name can be localized at render time.
    case popularInCountry(String)
    case popularWorldwide
    case preferredGenre(String)
}

struct AppShellHomeFeed {
    let stationService: StationService
    let localizedCountryName: (String) -> String
    let resolvedDeviceCountryCode: () -> String?
    var cache: HomeFeedCache = .shared

    @MainActor
    func load(preferredTag: String = "", limit: Int = 12) async throws -> HomeFeedResult {
        if let cachedFeed = cachedFeed(preferredTag: preferredTag, limit: limit) {
            return cachedFeed
        }

        return try await loadRemote(preferredTag: preferredTag, limit: limit)
    }

    @MainActor
    func refresh(preferredTag: String = "", limit: Int = 12) async throws -> HomeFeedResult {
        try await loadRemote(preferredTag: preferredTag, limit: limit)
    }

    @MainActor
    func prefetchInitialFeed(preferredTag: String = "", limit: Int = 12) async {
        _ = try? await load(preferredTag: preferredTag, limit: limit)
    }

    @MainActor
    private func loadRemote(preferredTag: String = "", limit: Int = 12) async throws -> HomeFeedResult {
        let normalizedPreferredTag = preferredTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let localeIdentifier = AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "tuneav.appLanguage")).rawValue
        if !normalizedPreferredTag.isEmpty {
            let genreStations = try await stationService.popularStations(
                filters: .init(
                    query: "",
                    tag: normalizedPreferredTag,
                    locale: localeIdentifier,
                    limit: limit,
                    allowsEmptySearch: true
                )
            )
            let result = HomeFeedResult(stations: genreStations, context: .preferredGenre(normalizedPreferredTag))
            cache.save(result, for: cacheKey(preferredTag: preferredTag, limit: limit))
            return result
        }

        let regionCode = resolvedDeviceCountryCode()
        let stations = try await stationService.popularStations(
            filters: .init(
                query: "",
                countryCode: regionCode ?? "",
                locale: localeIdentifier,
                limit: limit,
                allowsEmptySearch: true
            )
        )
        let context: HomeFeedContext
        if let regionCode, !stations.isEmpty {
            context = .popularInCountry(regionCode)
        } else {
            context = .popularWorldwide
        }

        let result = HomeFeedResult(stations: stations, context: context)
        cache.save(result, for: cacheKey(preferredTag: preferredTag, limit: limit))
        return result
    }

    static func defaultEditorialStations(
        currentStation: Station?,
        recentStations: [Station],
        favoriteStations: [Station],
        samples: [Station] = Station.samples
    ) -> [Station] {
        var seen = Set<String>()
        let candidates =
            [currentStation].compactMap { $0 } +
            recentStations +
            favoriteStations +
            samples

        return candidates.filter { station in
            seen.insert(station.id).inserted
        }
    }

    static func mergeUniqueStations(primary: [Station], secondary: [Station], limit: Int) -> [Station] {
        var seen = Set<String>()
        var merged: [Station] = []

        for station in primary + secondary {
            guard seen.insert(station.id).inserted else { continue }
            merged.append(station)
            if merged.count == limit {
                break
            }
        }

        return merged
    }

    static func resolvedDeviceCountryCode(locale: Locale = .autoupdatingCurrent, fallback: Locale = .current) -> String? {
        let code = locale.region?.identifier ?? fallback.region?.identifier
        guard let code, !code.isEmpty else { return nil }
        return TuneAVCountry.sanitizedCode(code)
    }

    private func cachedFeed(preferredTag: String, limit: Int) -> HomeFeedResult? {
        cache.load(for: cacheKey(preferredTag: preferredTag, limit: limit)).map { cached in
            HomeFeedResult(stations: Array(cached.stations.prefix(limit)), context: cached.context)
        }
    }

    private func cacheKey(preferredTag: String, limit: Int) -> HomeFeedCache.Key {
        HomeFeedCache.Key(
            localeIdentifier: AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "tuneav.appLanguage")).rawValue,
            countryCode: resolvedDeviceCountryCode(),
            preferredTag: preferredTag,
            language: nil,
            limit: limit
        )
    }
}

struct HomeFeedCache: @unchecked Sendable {
    struct Key {
        let localeIdentifier: String
        let countryCode: String?
        let preferredTag: String
        let language: String?
        let limit: Int
    }

    struct CachedFeed {
        let stations: [Station]
        let context: HomeFeedContext
        let cachedAt: Date
    }

    static let shared = HomeFeedCache()

    private let userDefaults: UserDefaults
    private let maxAge: TimeInterval
    private let memoryCache = NSCache<NSString, HomeFeedCacheBox>()

    init(userDefaults: UserDefaults = .standard, maxAge: TimeInterval = 60 * 60 * 12) {
        self.userDefaults = userDefaults
        self.maxAge = maxAge
        self.memoryCache.countLimit = 16
    }

    func load(for key: Key, now: Date = .now) -> CachedFeed? {
        let storageKey = storageKey(for: key)
        if let cached = memoryCache.object(forKey: storageKey as NSString)?.feed {
            guard now.timeIntervalSince(cached.cachedAt) <= maxAge else {
                memoryCache.removeObject(forKey: storageKey as NSString)
                userDefaults.removeObject(forKey: storageKey)
                return nil
            }
            return cached
        }

        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        guard let payload = try? JSONDecoder().decode(HomeFeedCachePayload.self, from: data) else {
            userDefaults.removeObject(forKey: storageKey)
            return nil
        }
        guard now.timeIntervalSince(payload.cachedAt) <= maxAge else {
            userDefaults.removeObject(forKey: storageKey)
            return nil
        }
        let cached = CachedFeed(stations: payload.stations, context: payload.context, cachedAt: payload.cachedAt)
        memoryCache.setObject(HomeFeedCacheBox(cached), forKey: storageKey as NSString)
        return cached
    }

    func save(_ result: HomeFeedResult, for key: Key, now: Date = .now) {
        let storageKey = storageKey(for: key)
        let cached = CachedFeed(stations: result.stations, context: result.context, cachedAt: now)
        memoryCache.setObject(HomeFeedCacheBox(cached), forKey: storageKey as NSString)

        let payload = HomeFeedCachePayload(stations: result.stations, context: result.context, cachedAt: now)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    private func storageKey(for key: Key) -> String {
        [
            "tuneav.homeFeed.v1",
            key.localeIdentifier.lowercased(),
            key.countryCode?.uppercased() ?? "global",
            key.preferredTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            key.language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
            String(key.limit)
        ].joined(separator: ".")
    }
}

private final class HomeFeedCacheBox {
    let feed: HomeFeedCache.CachedFeed

    init(_ feed: HomeFeedCache.CachedFeed) {
        self.feed = feed
    }
}

private struct HomeFeedCachePayload: Codable {
    let stations: [Station]
    let context: HomeFeedContext
    let cachedAt: Date
}

extension HomeFeedContext: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum Kind: String, Codable {
        case popularInCountry
        case popularWorldwide
        case preferredGenre
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)

        switch type {
        case .popularInCountry:
            self = .popularInCountry(try container.decode(String.self, forKey: .value))
        case .popularWorldwide:
            self = .popularWorldwide
        case .preferredGenre:
            self = .preferredGenre(try container.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .popularInCountry(let countryCode):
            try container.encode(Kind.popularInCountry, forKey: .type)
            try container.encode(countryCode, forKey: .value)
        case .popularWorldwide:
            try container.encode(Kind.popularWorldwide, forKey: .type)
        case .preferredGenre(let tag):
            try container.encode(Kind.preferredGenre, forKey: .type)
            try container.encode(tag, forKey: .value)
        }
    }
}
