struct HomeScreenState {
    let featuredState: HomeFeaturedStationState
    let derivedState: HomeDerivedState
    let headerContentState: HomeHeaderContentState
    let heroContentState: HomeHeroContentState
}

enum HomeScreenStateBuilder {
    static func build(
        stations: [Station],
        isLoading: Bool,
        errorMessage: String?,
        recentStations: [Station],
        favoriteStations: [Station],
        lastPlayedStation: Station?,
        discoveries: [DiscoveredTrack],
        stationFeedback: [String: TuneAVStationFeedback],
        feedContext: HomeFeedContext,
        preferredTag: String,
        preferredCountryCode: String?,
        favoriteStationIDs: Set<String>,
        currentStation: Station?,
        playbackStatusLabel: String,
        isCurrentStation: (Station) -> Bool,
        isPlaying: Bool,
        isStationLoading: Bool,
        currentTrackTitle: String?,
        currentTrackArtist: String?
    ) -> HomeScreenState {
        let featuredState = HomeFeaturedStationBuilder.build(
            currentStation: currentStation,
            lastPlayedStation: lastPlayedStation,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            stations: stations
        )
        let hasPersonalActivity = !recentStations.isEmpty || !favoriteStations.isEmpty
        let headerContentState = HomeContentStateBuilder.headerState(
            isLoading: isLoading,
            currentStation: currentStation,
            playbackStatusLabel: playbackStatusLabel,
            recentCount: recentStations.count,
            favoriteCount: favoriteStations.count,
            hasPersonalActivity: hasPersonalActivity,
            featuredStation: featuredState.station
        )
        let derivedState = HomeDerivedStateBuilder.build(
            stations: stations,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            currentStation: currentStation,
            discoveries: discoveries,
            stationFeedback: stationFeedback,
            feedContext: feedContext,
            preferredTag: preferredTag,
            preferredCountryCode: preferredCountryCode,
            featuredStationID: featuredState.stationID
        )
        let heroStation = featuredState.station
        let heroPresentation = heroStation.map {
            HomeStationPresentationBuilder.build(
                station: $0,
                source: featuredState.source,
                isCurrentStation: isCurrentStation($0),
                currentTrackTitle: currentTrackTitle,
                currentTrackArtist: currentTrackArtist,
                feedContext: feedContext
            )
        }
        let heroContentState = HomeContentStateBuilder.heroState(
            isLoading: isLoading,
            displayedPopularStations: derivedState.displayedPopularStations,
            errorMessage: errorMessage,
            featuredStation: heroStation,
            presentation: heroPresentation,
            isFavorite: heroStation.map { favoriteStationIDs.contains($0.id) } ?? false,
            isCurrentStation: heroStation.map(isCurrentStation) ?? false,
            isPlaying: isPlaying,
            isStationLoading: isStationLoading,
            stationFeedback: heroStation.flatMap { stationFeedback[$0.id] }
        )

        return HomeScreenState(
            featuredState: featuredState,
            derivedState: derivedState,
            headerContentState: headerContentState,
            heroContentState: heroContentState
        )
    }
}
