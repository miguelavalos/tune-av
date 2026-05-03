import Foundation

struct StationService {
    typealias SearchFilters = AVTunesysStationSearchFilters

    private let service: AVTunesysStationService

    init(session: URLSession = .shared) {
        self.service = AVTunesysStationService(session: session)
    }

    func searchStations(filters: SearchFilters) async throws -> [Station] {
        try await service.searchStations(filters: filters)
    }
}
