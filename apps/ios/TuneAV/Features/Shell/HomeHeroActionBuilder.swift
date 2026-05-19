enum HomeHeroPlaybackAction {
    case toggleCurrent
    case play(AudioPlayerService.PlaybackQueue.Source, [Station])
}

enum HomeHeroDetailsAction {
    case show(AudioPlayerService.PlaybackQueue.Source, [Station])
}

enum HomeHeroActionBuilder {
    static func playbackAction(
        isCurrentStation: Bool,
        featuredState: HomeFeaturedStationState
    ) -> HomeHeroPlaybackAction {
        if isCurrentStation {
            return .toggleCurrent
        }

        return .play(featuredState.queueSource, featuredState.queueStations)
    }

    static func detailsAction(featuredState: HomeFeaturedStationState) -> HomeHeroDetailsAction {
        .show(featuredState.queueSource, featuredState.queueStations)
    }

    static func toggledFeedback(
        currentFeedback: TuneAVStationFeedback?,
        selectedFeedback: TuneAVStationFeedback
    ) -> TuneAVStationFeedback? {
        currentFeedback == selectedFeedback ? nil : selectedFeedback
    }
}
