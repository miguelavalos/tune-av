enum HomeFeaturedStationSource: Equatable {
    case current
    case lastPlayed
    case recent
    case favorite
    case popular
}

struct HomeFeaturedStationState {
    let station: Station?
    let source: HomeFeaturedStationSource?
    let queueSource: AudioPlayerService.PlaybackQueue.Source
    let queueStations: [Station]

    var stationID: String? {
        station?.id
    }
}

enum HomeFeaturedStationBuilder {
    static func build(
        currentStation: Station?,
        lastPlayedStation: Station?,
        recentStations: [Station],
        favoriteStations: [Station],
        stations: [Station]
    ) -> HomeFeaturedStationState {
        let source = featuredSource(
            currentStation: currentStation,
            lastPlayedStation: lastPlayedStation,
            favoriteStations: favoriteStations,
            stations: stations
        )
        let station = featuredStation(
            for: source,
            currentStation: currentStation,
            lastPlayedStation: lastPlayedStation,
            favoriteStations: favoriteStations,
            stations: stations
        )
        let queueStations = queueStations(
            for: source,
            currentStation: currentStation,
            lastPlayedStation: lastPlayedStation,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            stations: stations
        )
        let queueSource = queueSource(
            for: source,
            lastPlayedStation: lastPlayedStation,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            lastPlayedQueueStations: queueStations
        )

        return HomeFeaturedStationState(
            station: station,
            source: source,
            queueSource: queueSource,
            queueStations: queueStations
        )
    }

    private static func featuredSource(
        currentStation: Station?,
        lastPlayedStation: Station?,
        favoriteStations: [Station],
        stations: [Station]
    ) -> HomeFeaturedStationSource? {
        if currentStation != nil {
            return .current
        }
        if lastPlayedStation != nil {
            return .lastPlayed
        }
        if !favoriteStations.isEmpty {
            return .favorite
        }
        if !stations.isEmpty {
            return .popular
        }
        return nil
    }

    private static func featuredStation(
        for source: HomeFeaturedStationSource?,
        currentStation: Station?,
        lastPlayedStation: Station?,
        favoriteStations: [Station],
        stations: [Station]
    ) -> Station? {
        switch source {
        case .current:
            return currentStation
        case .lastPlayed:
            return lastPlayedStation
        case .recent:
            return nil
        case .favorite:
            return favoriteStations.first
        case .popular:
            return stations.first
        case .none:
            return nil
        }
    }

    private static func queueSource(
        for source: HomeFeaturedStationSource?,
        lastPlayedStation: Station?,
        recentStations: [Station],
        favoriteStations: [Station],
        lastPlayedQueueStations: [Station]
    ) -> AudioPlayerService.PlaybackQueue.Source {
        switch source {
        case .current:
            return .singleStation
        case .lastPlayed:
            return lastPlayedQueueSource(
                lastPlayedStation: lastPlayedStation,
                recentStations: recentStations,
                favoriteStations: favoriteStations,
                lastPlayedQueueStations: lastPlayedQueueStations
            )
        case .recent:
            return .homeRecents
        case .favorite:
            return .homeFavorites
        case .popular, .none:
            return .homeDiscovery
        }
    }

    private static func queueStations(
        for source: HomeFeaturedStationSource?,
        currentStation: Station?,
        lastPlayedStation: Station?,
        recentStations: [Station],
        favoriteStations: [Station],
        stations: [Station]
    ) -> [Station] {
        switch source {
        case .current:
            return currentStation.map { [$0] } ?? []
        case .lastPlayed:
            return lastPlayedQueueStations(
                lastPlayedStation: lastPlayedStation,
                recentStations: recentStations,
                favoriteStations: favoriteStations,
                stations: stations
            )
        case .recent:
            return recentStations
        case .favorite:
            return favoriteStations
        case .popular, .none:
            return stations
        }
    }

    private static func lastPlayedQueueSource(
        lastPlayedStation: Station?,
        recentStations: [Station],
        favoriteStations: [Station],
        lastPlayedQueueStations: [Station]
    ) -> AudioPlayerService.PlaybackQueue.Source {
        guard let lastPlayedStation else { return .singleStation }
        if favoriteStations.contains(where: { $0.id == lastPlayedStation.id }), favoriteStations.count > 1 {
            return .homeFavorites
        }
        if recentStations.contains(where: { $0.id == lastPlayedStation.id }), recentStations.count > 1 {
            return .homeRecents
        }
        return lastPlayedQueueStations.count > 1 ? .homeRecents : .singleStation
    }

    private static func lastPlayedQueueStations(
        lastPlayedStation: Station?,
        recentStations: [Station],
        favoriteStations: [Station],
        stations: [Station]
    ) -> [Station] {
        guard let lastPlayedStation else { return [] }
        if favoriteStations.contains(where: { $0.id == lastPlayedStation.id }), favoriteStations.count > 1 {
            return favoriteStations
        }
        if recentStations.contains(where: { $0.id == lastPlayedStation.id }), recentStations.count > 1 {
            return recentStations
        }
        return AppShellNowPlayingPreviews.uniqueStations([lastPlayedStation] + favoriteStations + recentStations + stations)
    }
}
