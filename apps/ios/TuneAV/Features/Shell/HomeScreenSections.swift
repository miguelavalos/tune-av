import SwiftUI

struct HomeHeaderContent: View {
    let state: HomeHeaderContentState
    let openAvi: () -> Void

    var body: some View {
        ShellBrandHeader(statusTitle: state.statusTitle)

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("shell.home.title"))
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(L10n.string("shell.home.subtitle"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        HomeAviBrief(
            currentStation: state.currentStation,
            recentCount: state.recentCount,
            favoriteCount: state.favoriteCount,
            emotion: TuneAVAviEmotionResolver.homeEmotion(
                currentStation: state.currentStation,
                recentCount: state.recentCount,
                favoriteCount: state.favoriteCount
            ),
            openAvi: openAvi
        )

        if state.showsLiveNowPanel {
            LiveNowPanel(currentStation: state.currentStation, status: state.liveNowStatus)
        }
    }
}

struct HomeHeroContent: View {
    let state: HomeHeroContentState
    let playAction: (Station) -> Void
    let favoriteAction: (Station) -> Void
    let feedbackAction: (TuneAVStationFeedback, Station) -> Void
    let detailsAction: (Station) -> Void

    @ViewBuilder
    var body: some View {
        if state.isLoading && state.station == nil && !state.hasPopularStations {
            StationCardSkeletonGroup()
        } else if let errorMessage = state.errorMessage {
            EmptyLibraryState(
                title: L10n.string("shell.home.error.title"),
                detail: errorMessage
            )
        } else if let station = state.station, let presentation = state.presentation {
            HomeTuningDeskHero(
                station: station,
                presentation: presentation,
                isFavorite: state.isFavorite,
                isCurrentStation: state.isCurrentStation,
                isPlaying: state.isPlaying,
                isLoading: state.isStationLoading,
                stationFeedback: state.stationFeedback,
                playAction: { playAction(station) },
                favoriteAction: { favoriteAction(station) },
                feedbackAction: { feedbackAction($0, station) },
                detailsAction: { detailsAction(station) }
            )
        } else {
            EmptyLibraryState(
                title: L10n.string("shell.home.empty.title"),
                detail: L10n.string("shell.home.empty.detail")
            )
        }
    }
}

struct HomeRecommendationSections: View {
    let derivedState: HomeDerivedState
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let openSearchTag: (String) -> Void
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    @ViewBuilder
    var body: some View {
        if !derivedState.moodGenreTags.isEmpty {
            HomeMoodGenreDesk(tags: derivedState.moodGenreTags, selectTag: openSearchTag)
        }

        if !derivedState.displayedAviPickStations.isEmpty {
            homeStationCarouselSection(
                title: L10n.string("shell.home.aviPicks.title"),
                subtitle: L10n.string("shell.home.aviPicks.subtitle"),
                accessibilityIdentifier: "home.section.aviPicks",
                stations: derivedState.displayedAviPickStations,
                queueSource: .homeDiscovery,
                stationInsight: { derivedState.recommendationInsights[$0.id] }
            )
        }

        if !derivedState.displayedAroundYouStations.isEmpty {
            homeStationCarouselSection(
                title: L10n.string("shell.home.aroundYou.title"),
                subtitle: L10n.string("shell.home.aroundYou.subtitle"),
                accessibilityIdentifier: "home.section.aroundYou",
                stations: derivedState.displayedAroundYouStations,
                queueSource: .homeDiscovery,
                stationInsight: { derivedState.recommendationInsights[$0.id] }
            )
        }

        if !derivedState.displayedRecentStations.isEmpty || !derivedState.displayedFavoriteStations.isEmpty {
            homeStationCarouselSection(
                title: L10n.string("shell.home.recentsFavorites.title"),
                subtitle: L10n.string("shell.home.recentsFavorites.subtitle"),
                accessibilityIdentifier: "home.section.recentsFavorites",
                stations: derivedState.displayedRecentAndFavoriteStations,
                queueSource: .homeRecents,
                stationInsight: { station in stationFeedback[station.id]?.localizedState }
            )
        }
    }

    private func homeStationCarouselSection(
        title: String,
        subtitle: String,
        accessibilityIdentifier: String,
        stations: [Station],
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        stationInsight: @escaping (Station) -> String?
    ) -> some View {
        StationSection(
            title: title,
            subtitle: subtitle,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            StationCompactCarousel(
                stations: stations,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: nowPlayingTracks,
                stationInsight: stationInsight,
                stationFeedback: stationFeedback,
                queueSource: queueSource,
                queueStations: stations,
                playStation: playStation,
                toggleFavorite: toggleFavorite,
                showStationDetails: showStationDetails
            )
        }
    }
}
