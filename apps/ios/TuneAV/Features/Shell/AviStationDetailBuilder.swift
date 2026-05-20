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
}
