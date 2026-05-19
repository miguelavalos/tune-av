struct HomeHeaderContentState {
    let statusTitle: String
    let liveNowStatus: String
    let currentStation: Station?
    let recentCount: Int
    let favoriteCount: Int
    let showsLiveNowPanel: Bool
}

struct HomeHeroContentState {
    let isLoading: Bool
    let hasPopularStations: Bool
    let errorMessage: String?
    let station: Station?
    let presentation: HomeStationPresentation?
    let isFavorite: Bool
    let isCurrentStation: Bool
    let isPlaying: Bool
    let isStationLoading: Bool
    let stationFeedback: TuneAVStationFeedback?
}

enum HomeContentStateBuilder {
    static func headerState(
        isLoading: Bool,
        currentStation: Station?,
        playbackStatusLabel: String,
        recentCount: Int,
        favoriteCount: Int,
        hasPersonalActivity: Bool,
        featuredStation: Station?
    ) -> HomeHeaderContentState {
        let statusTitle = if isLoading {
            L10n.string("shell.status.refreshing")
        } else if currentStation == nil {
            L10n.string("shell.status.live")
        } else {
            playbackStatusLabel
        }

        return HomeHeaderContentState(
            statusTitle: statusTitle,
            liveNowStatus: playbackStatusLabel,
            currentStation: currentStation,
            recentCount: recentCount,
            favoriteCount: favoriteCount,
            showsLiveNowPanel: currentStation == nil && !hasPersonalActivity && featuredStation == nil
        )
    }

    static func heroState(
        isLoading: Bool,
        displayedPopularStations: [Station],
        errorMessage: String?,
        featuredStation: Station?,
        presentation: HomeStationPresentation?,
        isFavorite: Bool,
        isCurrentStation: Bool,
        isPlaying: Bool,
        isStationLoading: Bool,
        stationFeedback: TuneAVStationFeedback?
    ) -> HomeHeroContentState {
        HomeHeroContentState(
            isLoading: isLoading,
            hasPopularStations: !displayedPopularStations.isEmpty,
            errorMessage: errorMessage,
            station: featuredStation,
            presentation: presentation,
            isFavorite: isFavorite,
            isCurrentStation: isCurrentStation,
            isPlaying: isCurrentStation && isPlaying,
            isStationLoading: isCurrentStation && isStationLoading,
            stationFeedback: stationFeedback
        )
    }
}
