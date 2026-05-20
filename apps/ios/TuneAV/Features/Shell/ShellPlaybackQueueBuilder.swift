enum ShellPlaybackQueueBuilder {
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
