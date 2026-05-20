struct SelectedStationDetail: Identifiable {
    let station: Station
    let queueSource: AudioPlayerService.PlaybackQueue.Source
    let queueStations: [Station]

    var id: String {
        station.id
    }
}

struct AviStationDetailSelection {
    let resolvedStation: Station
    let detail: SelectedStationDetail
}

struct AviStationOpenSelection {
    let resolvedStation: Station
    let detail: SelectedStationDetail
    let presentation: String
    let isFullPlayer: Bool
    let selectedTab: AppShellTab
}

struct AviStationDetailBuilder {
    let enrichStation: (Station) -> Station
    let enrichStations: ([Station]) -> [Station]

    func detail(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: [Station]
    ) -> SelectedStationDetail {
        SelectedStationDetail(
            station: enrichStation(station),
            queueSource: queueSource,
            queueStations: enrichStations(queue)
        )
    }

    func playbackQueue(
        stations: [Station],
        fallbackStation: Station
    ) -> [Station] {
        stations.isEmpty ? [fallbackStation] : stations
    }

    func selection(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station]
    ) -> AviStationDetailSelection {
        let resolvedStation = enrichStation(station)
        let detail = SelectedStationDetail(
            station: resolvedStation,
            queueSource: queueSource,
            queueStations: enrichStations(queue(resolvedStation))
        )

        return AviStationDetailSelection(
            resolvedStation: resolvedStation,
            detail: detail
        )
    }

    func openDetailSelection(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station],
        presentation: String
    ) -> AviStationOpenSelection {
        openSelection(
            station: station,
            queueSource: queueSource,
            queue: queue,
            presentation: presentation,
            isFullPlayer: false
        )
    }

    func openFullPlayerSelection(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station],
        presentation: String
    ) -> AviStationOpenSelection {
        openSelection(
            station: station,
            queueSource: queueSource,
            queue: queue,
            presentation: presentation,
            isFullPlayer: true
        )
    }

    private func openSelection(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station],
        presentation: String,
        isFullPlayer: Bool
    ) -> AviStationOpenSelection {
        let selection = selection(
            station: station,
            queueSource: queueSource,
            queue: queue
        )

        return AviStationOpenSelection(
            resolvedStation: selection.resolvedStation,
            detail: selection.detail,
            presentation: presentation,
            isFullPlayer: isFullPlayer,
            selectedTab: .avi
        )
    }
}
