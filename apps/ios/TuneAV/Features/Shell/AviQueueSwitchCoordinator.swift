enum AviQueueSwitchCoordinator {
    static func options(
        currentSource: AudioPlayerService.PlaybackQueue.Source,
        playbackQueueStations: [Station],
        stations: [Station],
        favoriteStations: [Station],
        recentStations: [Station]
    ) -> [AviQueueSwitchOption] {
        var options: [AviQueueSwitchOption] = []

        if !playbackQueueStations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: currentSource,
                    title: L10n.string("shell.queue.currentOption", currentSource.displayTitle),
                    stations: playbackQueueStations
                )
            )
        }

        if !stations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: .homeDiscovery,
                    title: L10n.string("shell.queue.popular"),
                    stations: stations
                )
            )
        }

        if !favoriteStations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: .libraryFavorites,
                    title: L10n.string("shell.queue.saved"),
                    stations: favoriteStations
                )
            )
        }

        if !recentStations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: .libraryRecents,
                    title: L10n.string("shell.queue.recent"),
                    stations: recentStations
                )
            )
        }

        var seen = Set<String>()
        return options.filter { option in
            let key = "\(option.source.shortTitle)|\(option.stations.map(\.id).joined(separator: ","))"
            return seen.insert(key).inserted
        }
    }

    static func queue(for currentStation: Station, option: AviQueueSwitchOption) -> [Station] {
        option.stations.contains(where: { $0.id == currentStation.id })
            ? option.stations
            : [currentStation] + option.stations
    }
}
