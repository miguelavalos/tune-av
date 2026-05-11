import Foundation

enum TuneAVStationDiscoveryMode: String, Equatable {
    case music
    case allRadio
}

enum TuneAVStationMusicClassifier {
    static let musicTags = [
        "pop",
        "rock",
        "electronic",
        "latin",
        "jazz",
        "chill",
        "dance",
        "classical",
        "oldies",
        "hip-hop",
        "indie"
    ]

    private static let musicSignals = Set([
        "music",
        "pop",
        "rock",
        "electronic",
        "dance",
        "latin",
        "jazz",
        "chill",
        "classical",
        "oldies",
        "hip-hop",
        "hiphop",
        "indie",
        "ambient",
        "soul",
        "blues",
        "hits",
        "charts",
        "alternative",
        "house",
        "techno",
        "country",
        "folk",
        "reggae",
        "metal",
        "rnb",
        "instrumental"
    ])

    private static let nonMusicSignals = Set([
        "news",
        "sports",
        "sport",
        "talk",
        "culture",
        "religion",
        "religious",
        "public",
        "comedy",
        "politics",
        "business",
        "finance",
        "weather",
        "traffic",
        "podcast"
    ])

    static func isMusicStation(_ station: Station) -> Bool {
        musicScore(station) > 0 && nonMusicCategory(station) == nil
    }

    static func musicScore(_ station: Station) -> Int {
        var score = 0
        let category = normalized(station.category)
        if category == "music" {
            score += 6
        } else if let category, nonMusicSignals.contains(category) {
            score -= 6
        }

        for token in normalizedTokens(from: station.tagsList) {
            if musicSignals.contains(token) {
                score += 2
            }
            if nonMusicSignals.contains(token) {
                score -= 3
            }
        }

        if let editorial = station.editorial {
            score += musicIntensityScore(editorial.musicIntensity)
            score -= speechIntensityPenalty(editorial.speechIntensity)
            if normalized(editorial.primaryFormat) == "music" {
                score += 3
            }
            let discoveryProfile = editorial.discoveryProfile
            if let discoveryProfile {
                score += max(0, min(4, discoveryProfile.musicDiscoveryScore / 25))
            }
            for token in normalizedTokens(from: editorial.secondaryFormats + editorial.programming + (discoveryProfile?.genres ?? []) + (discoveryProfile?.moods ?? [])) {
                if musicSignals.contains(token) {
                    score += 1
                }
                if nonMusicSignals.contains(token) {
                    score -= 2
                }
            }
        }

        return score
    }

    static func nonMusicCategory(_ station: Station) -> String? {
        if let category = normalized(station.category), nonMusicSignals.contains(category) {
            return category
        }

        return normalizedTokens(from: station.tagsList).first { nonMusicSignals.contains($0) }
    }

    static func isExplicitNonMusicIntent(query: String, tag: String?) -> Bool {
        let values = [query, tag].compactMap { $0 }
        return normalizedTokens(from: values).contains { nonMusicSignals.contains($0) }
    }

    static func orderedForDiscoveryMode(_ stations: [Station], mode: TuneAVStationDiscoveryMode, request: AppShellSearchRequest) -> [Station] {
        guard mode == .music else { return stations }
        guard !isExplicitNonMusicIntent(query: request.query, tag: request.tag) else { return stations }

        let scored = stations.map { station in
            (station: station, score: musicScore(station))
        }
        let musicStations = scored
            .filter { $0.score > 0 && nonMusicCategory($0.station) == nil }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return (lhs.station.clickCount ?? 0) > (rhs.station.clickCount ?? 0)
            }
            .map(\.station)

        if !musicStations.isEmpty {
            return musicStations
        }

        return scored
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .map(\.station)
    }

    private static func normalizedTokens(from values: [String]) -> [String] {
        values.flatMap { value in
            value
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
                .map(String.init)
        }
    }

    private static func normalized(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)?.lowercased()
    }

    private static func musicIntensityScore(_ value: String) -> Int {
        switch normalized(value) {
        case "high":
            return 4
        case "medium":
            return 2
        case "low":
            return 1
        default:
            return 0
        }
    }

    private static func speechIntensityPenalty(_ value: String) -> Int {
        switch normalized(value) {
        case "high":
            return 4
        case "medium":
            return 2
        default:
            return 0
        }
    }
}

struct AppShellSearchRequest: Equatable {
    let query: String
    let tag: String?
    let countryCode: String?
    let discoveryMode: TuneAVStationDiscoveryMode

    init(query: String, tag: String?, countryCode: String?, discoveryMode: TuneAVStationDiscoveryMode = .music) {
        self.query = TuneAVText.normalizedValue(query) ?? ""
        self.tag = TuneAVText.normalizedValue(tag)
        self.countryCode = TuneAVCountry.sanitizedCode(countryCode)
        self.discoveryMode = discoveryMode
    }

    var key: String {
        "\(query)|\(tag ?? "")|\(countryCode ?? "")|\(discoveryMode.rawValue)"
    }

    var usesWorldwideDiscovery: Bool {
        query.isEmpty && countryCode == nil
    }

    var searchLimit: Int {
        query.isEmpty ? 12 : 24
    }
}

struct AppShellSearch {
    let stationService: StationService
    let resolvedDeviceCountryCode: () -> String?
    let hasResolvedCountry: (Station) -> Bool

    @MainActor
    func load(
        request: AppShellSearchRequest,
        recentStations: [Station],
        favoriteStations: [Station]
    ) async throws -> [Station] {
        if request.usesWorldwideDiscovery {
            let stations = try await loadWorldwideDiscoveryStations(
                limit: 12,
                tag: request.tag,
                recentStations: recentStations,
                favoriteStations: favoriteStations
            )
            return TuneAVStationMusicClassifier.orderedForDiscoveryMode(stations, mode: request.discoveryMode, request: request)
        }

        let stations = try await stationService.searchStations(
            filters: .init(
                query: request.query,
                countryCode: request.countryCode ?? "",
                tag: request.tag ?? "",
                limit: request.searchLimit,
                allowsEmptySearch: request.query.isEmpty
            )
        )
        return TuneAVStationMusicClassifier.orderedForDiscoveryMode(stations, mode: request.discoveryMode, request: request)
    }

    @MainActor
    func loadWorldwideDiscoveryStations(
        limit: Int,
        tag: String?,
        recentStations: [Station],
        favoriteStations: [Station]
    ) async throws -> [Station] {
        let orderedCodes = Self.orderedDiscoveryCountryCodes(
            deviceCountryCode: resolvedDeviceCountryCode(),
            recentStations: recentStations,
            favoriteStations: favoriteStations
        )

        var merged: [Station] = []
        for code in orderedCodes {
            let stations = try await stationService.searchStations(
                filters: .init(
                    query: "",
                    countryCode: code,
                    tag: tag ?? "",
                    limit: tag == nil ? 4 : 6,
                    allowsEmptySearch: true
                )
            )
            merged = Self.mergeUniqueStations(
                primary: merged,
                secondary: stations.filter(hasResolvedCountry),
                limit: limit
            )

            if merged.count >= limit {
                break
            }
        }

        return Array(merged.prefix(limit))
    }

    static func localUITestSearchResults(
        samples: [Station] = Station.samples,
        request: AppShellSearchRequest
    ) -> [Station] {
        let matches = samples.filter { station in
            let matchesQuery =
                request.query.isEmpty
                || station.name.localizedCaseInsensitiveContains(request.query)
                || station.country.localizedCaseInsensitiveContains(request.query)
                || station.tags.localizedCaseInsensitiveContains(request.query)

            let matchesTag =
                request.tag?.isEmpty != false
                || station.tags.localizedCaseInsensitiveContains(request.tag ?? "")

            let matchesCountry =
                request.countryCode?.isEmpty != false
                || station.countryCode?.caseInsensitiveCompare(request.countryCode ?? "") == .orderedSame

            return matchesQuery && matchesTag && matchesCountry
        }
        return TuneAVStationMusicClassifier.orderedForDiscoveryMode(matches, mode: request.discoveryMode, request: request)
    }

    static func orderedDiscoveryCountryCodes(
        deviceCountryCode: String?,
        recentStations: [Station],
        favoriteStations: [Station],
        fallbackCountryCodes: [String] = ["US", "GB", "DE", "FR", "IT", "ES", "NL", "CA", "AU", "BR", "MX", "AR"]
    ) -> [String] {
        let seedCountryCodes =
            [deviceCountryCode] +
            recentStations.compactMap(\.countryCode) +
            favoriteStations.compactMap(\.countryCode) +
            fallbackCountryCodes

        var orderedCodes: [String] = []
        var seenCodes = Set<String>()
        for code in seedCountryCodes.compactMap(TuneAVCountry.sanitizedCode) where seenCodes.insert(code).inserted {
            orderedCodes.append(code)
        }

        return orderedCodes
    }

    private static func mergeUniqueStations(primary: [Station], secondary: [Station], limit: Int) -> [Station] {
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
}
