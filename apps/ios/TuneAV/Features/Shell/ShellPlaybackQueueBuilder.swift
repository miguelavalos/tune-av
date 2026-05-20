struct ShellRestoredLaunchSelection {
    let station: Station
    let queue: AudioPlayerService.PlaybackQueue
}

enum ShellPlaybackQueueBuilder {
    static func restoredLaunchSelection(
        lastPlayedStationID: String?,
        lastOpenedStationID: String?,
        stationForID: (String?) -> Station?,
        enrichStation: (Station) -> Station,
        favorites: [Station],
        recents: [Station],
        homeStations: [Station]
    ) -> ShellRestoredLaunchSelection? {
        guard let station = stationForID(lastPlayedStationID) ?? stationForID(lastOpenedStationID) else {
            return nil
        }

        let resolvedStation = enrichStation(station)
        let queue = restoredQueue(
            for: resolvedStation,
            favorites: favorites,
            recents: recents,
            homeStations: homeStations
        )

        return ShellRestoredLaunchSelection(station: resolvedStation, queue: queue)
    }

    static func restoredQueue(
        for station: Station,
        favorites: [Station],
        recents: [Station],
        homeStations: [Station]
    ) -> AudioPlayerService.PlaybackQueue {
        if favorites.contains(where: { $0.id == station.id }), favorites.count > 1 {
            return AudioPlayerService.PlaybackQueue(source: .libraryFavorites, stations: favorites)
        }

        if recents.contains(where: { $0.id == station.id }), recents.count > 1 {
            return AudioPlayerService.PlaybackQueue(source: .libraryRecents, stations: recents)
        }

        let fallbackQueue = uniqueStations([station] + favorites + recents + homeStations)
        return AudioPlayerService.PlaybackQueue(
            source: fallbackQueue.count > 1 ? .homeRecents : .singleStation,
            stations: fallbackQueue
        )
    }

    static func uniqueStations(_ stations: [Station]) -> [Station] {
        var seenIDs = Set<String>()
        return stations.filter { station in
            seenIDs.insert(station.id).inserted
        }
    }
}
