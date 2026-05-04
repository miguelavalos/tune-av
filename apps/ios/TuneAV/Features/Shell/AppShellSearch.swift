import Foundation

struct AppShellSearchRequest: Equatable {
    let query: String
    let tag: String?
    let countryCode: String?

    init(query: String, tag: String?, countryCode: String?) {
        self.query = TuneAVText.normalizedValue(query) ?? ""
        self.tag = TuneAVText.normalizedValue(tag)
        self.countryCode = TuneAVCountry.sanitizedCode(countryCode)
    }

    var key: String {
        "\(query)|\(tag ?? "")|\(countryCode ?? "")"
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
            return try await loadWorldwideDiscoveryStations(
                limit: 12,
                tag: request.tag,
                recentStations: recentStations,
                favoriteStations: favoriteStations
            )
        }

        return try await stationService.searchStations(
            filters: .init(
                query: request.query,
                countryCode: request.countryCode ?? "",
                tag: request.tag ?? "",
                limit: request.searchLimit,
                allowsEmptySearch: request.query.isEmpty
            )
        )
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
            merged = AppShellHomeFeed.mergeUniqueStations(
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
        samples.filter { station in
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
}
