import Foundation

typealias TrackArtwork = TuneAVTrackArtwork
typealias TrackArtworkService = TuneAVTrackArtworkService

struct StationService {
    typealias SearchFilters = TuneAVStationSearchFilters

    private let service: TuneAVStationService

    init(session: URLSession = .shared) {
        self.service = TuneAVStationService(
            session: session,
            fallbacks: TuneAVStationFallbacks(
                unnamed: L10n.string("stationService.fallback.unnamed"),
                unknownCountry: L10n.string("stationService.fallback.unknownCountry"),
                unknownLanguage: L10n.string("stationService.fallback.unknownLanguage"),
                noTags: L10n.string("stationService.fallback.noTags")
            ),
            invalidResponseMessage: L10n.string("stationService.error.invalidResponse")
        )
    }

    func searchStations(filters: SearchFilters) async throws -> [Station] {
        var localizedFilters = filters
        localizedFilters.locale = L10n.locale.identifier
        return try await service.searchStations(filters: localizedFilters)
    }
}
