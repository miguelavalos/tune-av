struct SelectedStationDetail: Identifiable {
    let station: Station
    let queueSource: AudioPlayerService.PlaybackQueue.Source
    let queueStations: [Station]

    var id: String {
        station.id
    }
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
}
