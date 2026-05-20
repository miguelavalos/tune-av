import Foundation

typealias TrackArtwork = TuneAVTrackArtwork
typealias TrackArtworkService = TuneAVTrackArtworkService

enum TuneAVURLSessions {
    static let catalog: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 32 * 1024 * 1024
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    static let artwork: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 96 * 1024 * 1024
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    static let account: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()
}

struct StationService {
    typealias SearchFilters = TuneAVStationSearchFilters

    private let service: TuneAVStationService

    init(session: URLSession = TuneAVURLSessions.catalog) {
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

    init(
        session: URLSession = TuneAVURLSessions.catalog,
        avalsysBaseURL: URL?,
        avalsysPopularBaseURL: URL?,
        radioBrowserBaseURL: URL = URL(string: "https://de1.api.radio-browser.info/json/stations/search")!,
        backendGate: TuneAVBackendHealthGate = .shared,
        responseCache: TuneAVStationResponseCache = .shared
    ) {
        self.service = TuneAVStationService(
            session: session,
            avalsysBaseURL: avalsysBaseURL,
            avalsysPopularBaseURL: avalsysPopularBaseURL,
            radioBrowserBaseURL: radioBrowserBaseURL,
            fallbacks: TuneAVStationFallbacks(
                unnamed: L10n.string("stationService.fallback.unnamed"),
                unknownCountry: L10n.string("stationService.fallback.unknownCountry"),
                unknownLanguage: L10n.string("stationService.fallback.unknownLanguage"),
                noTags: L10n.string("stationService.fallback.noTags")
            ),
            invalidResponseMessage: L10n.string("stationService.error.invalidResponse"),
            backendGate: backendGate,
            responseCache: responseCache
        )
    }

    func searchStations(filters: SearchFilters) async throws -> [Station] {
        var localizedFilters = filters
        localizedFilters.locale = L10n.locale.identifier
        return try await service.searchStations(filters: localizedFilters)
    }

    func popularStations(filters: SearchFilters) async throws -> [Station] {
        var localizedFilters = filters
        localizedFilters.locale = L10n.locale.identifier
        return try await service.popularStations(filters: localizedFilters)
    }
}
