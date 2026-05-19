struct HomeHeroActionRouter {
    let isCurrentStation: (Station) -> Bool
    let togglePlayback: () -> Void
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]) -> Void
    let currentFeedback: (Station) -> TuneAVStationFeedback?
    let setStationFeedback: (Station, TuneAVStationFeedback?) -> Void

    func play(_ station: Station, featuredState: HomeFeaturedStationState) {
        switch HomeHeroActionBuilder.playbackAction(
            isCurrentStation: isCurrentStation(station),
            featuredState: featuredState
        ) {
        case .toggleCurrent:
            togglePlayback()
        case .play(let queueSource, let queueStations):
            playStation(station, queueSource, queueStations)
        }
    }

    func showDetails(_ station: Station, featuredState: HomeFeaturedStationState) {
        switch HomeHeroActionBuilder.detailsAction(featuredState: featuredState) {
        case .show(let queueSource, let queueStations):
            showStationDetails(station, queueSource, queueStations)
        }
    }

    func setFeedback(_ feedback: TuneAVStationFeedback, for station: Station) {
        let nextFeedback = HomeHeroActionBuilder.toggledFeedback(
            currentFeedback: currentFeedback(station),
            selectedFeedback: feedback
        )
        setStationFeedback(station, nextFeedback)
    }
}
