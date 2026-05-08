import Foundation

enum TuneAVLibraryStationLogic {
    static func filteredStations(_ stations: [Station], query: String) -> [Station] {
        guard let trimmedQuery = TuneAVText.normalizedValue(query) else { return stations }

        return stations.filter { station in
            station.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            station.country.localizedCaseInsensitiveContains(trimmedQuery) ||
            station.tags.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}
