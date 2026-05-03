import Foundation

struct StationService {
    typealias SearchFilters = AVTunesysStationSearchFilters

    private let service: AVTunesysStationService

    init(session: URLSession = .shared) {
        self.service = AVTunesysStationService(
            session: session,
            fallbacks: AVTunesysStationFallbacks(
                unnamed: L10n.string("stationService.fallback.unnamed"),
                unknownCountry: L10n.string("stationService.fallback.unknownCountry"),
                unknownLanguage: L10n.string("stationService.fallback.unknownLanguage"),
                noTags: L10n.string("stationService.fallback.noTags")
            ),
            invalidResponseMessage: L10n.string("stationService.error.invalidResponse")
        )
    }

    func searchStations(filters: SearchFilters) async throws -> [Station] {
        try await service.searchStations(filters: filters)
    }
}
