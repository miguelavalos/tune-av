import Foundation

struct HomeFeedSnapshot {
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
    case popularInCountry(String)
    case popularWorldwide
}

struct AppShellHomeFeed {
    let stationService: StationService
    let localizedCountryName: (String) -> String
    let resolvedDeviceCountryCode: () -> String?

    @MainActor
    func load(limit: Int = 8) async throws -> HomeFeedResult {
        let regionCode = resolvedDeviceCountryCode()
        let regionalStations = try await stationService.searchStations(
            filters: .init(
                query: "",
                countryCode: regionCode ?? "",
                limit: limit,
                allowsEmptySearch: regionCode == nil ? false : true
            )
        )
        let globalStations = try await stationService.searchStations(
            filters: .init(query: "", limit: limit, allowsEmptySearch: true)
        )
        let stations = Self.mergeUniqueStations(
            primary: regionalStations,
            secondary: globalStations,
            limit: limit
        )
        let context: HomeFeedContext
        if let regionCode, !regionalStations.isEmpty {
            context = .popularInCountry(localizedCountryName(regionCode))
        } else {
            context = .popularWorldwide
        }

        return HomeFeedResult(stations: stations, context: context)
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
}
