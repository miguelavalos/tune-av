import Foundation

struct StationService {
    typealias SearchFilters = TuneAVStationSearchFilters

    private let service: TuneAVStationService

    init(session: URLSession = .shared) {
        self.service = TuneAVStationService(session: session)
    }

    func searchStations(filters: SearchFilters) async throws -> [Station] {
        try await service.searchStations(filters: filters)
    }
}
