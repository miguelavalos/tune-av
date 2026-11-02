import AVAppShellFoundation
import AVAviFoundation
import SwiftUI

struct HomeHeaderContent: View {
    let state: HomeHeaderContentState
    var layoutClass: TuneLayoutClass = .compact
    var surpriseReason: String? = nil
    let openAvi: () -> Void
    var surpriseMe: (() -> Void)? = nil

    var body: some View {
        if layoutClass.isTabletLike {
            VStack(alignment: .leading, spacing: 18) {
                homeBriefContent
            }
            .padding(.bottom, 8)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ShellBrandHeader(statusTitle: state.statusTitle)
                homeBriefContent
            }
        }
    }

    @ViewBuilder
    private var homeBriefContent: some View {
        HomeAviBrief(
            currentStation: state.currentStation,
            recentCount: state.recentCount,
            favoriteCount: state.favoriteCount,
            returningStation: state.returningStation,
            surpriseReason: surpriseReason,
            emotion: TuneAVAviEmotionResolver.homeEmotion(
                currentStation: state.currentStation,
                recentCount: state.recentCount,
                favoriteCount: state.favoriteCount
            ),
            openAvi: openAvi
        )

        if let surpriseMe {
            AVAviPrimaryActionButton(
                title: L10n.string("shell.home.surprise.action"),
                systemImage: "sparkles",
                accessibilityIdentifier: "home.surprise",
                action: surpriseMe
            )
        }

        if state.showsLiveNowPanel {
            LiveNowPanel(currentStation: state.currentStation, status: state.liveNowStatus)
        }
    }
}

struct HomeHeroContent: View {
    let state: HomeHeroContentState
    var layoutClass: TuneLayoutClass = .compact
    let playAction: (Station) -> Void
    let favoriteAction: (Station) -> Void
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
                layoutClass: layoutClass,
                playAction: { playAction(station) },
                favoriteAction: { favoriteAction(station) },
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
    var layoutClass: TuneLayoutClass = .compact
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let openSearchTag: (String) -> Void
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    @ViewBuilder
    var body: some View {
        if !forYouStations.isEmpty {
            homeStationCarouselSection(
                title: L10n.string("shell.home.featured.frontPage"),
                accessibilityIdentifier: "home.section.forYou",
                stations: forYouStations,
                queueSource: .homeDiscovery,
                stationInsight: { derivedState.recommendationInsights[$0.id] }
            )
        }

        if !derivedState.moodGenreTags.isEmpty {
            HomeMoodGenreDesk(tags: derivedState.moodGenreTags, selectTag: openSearchTag)
        }

        if !derivedState.displayedRecentStations.isEmpty || !derivedState.displayedFavoriteStations.isEmpty {
            homeStationCarouselSection(
                title: L10n.string("shell.home.recentsFavorites.title"),
                accessibilityIdentifier: "home.section.recentsFavorites",
                stations: derivedState.displayedRecentAndFavoriteStations,
                queueSource: .homeRecents,
                stationInsight: { station in stationFeedback[station.id]?.localizedState }
            )
        }
    }

    private var forYouStations: [Station] {
        var seen = Set<String>()
        return (derivedState.displayedAviPickStations + derivedState.displayedAroundYouStations).filter { seen.insert($0.id).inserted }
    }

    private func homeStationCarouselSection(
        title: String,
        accessibilityIdentifier: String,
        stations: [Station],
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        stationInsight: @escaping (Station) -> String?
    ) -> some View {
        StationSection(
            title: title,
            subtitle: "",
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            StationCompactCarousel(
                stations: stations,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: nowPlayingTracks,
                stationInsight: stationInsight,
                stationFeedback: stationFeedback,
                layoutClass: layoutClass,
                queueSource: queueSource,
                queueStations: stations,
                playStation: playStation,
                toggleFavorite: toggleFavorite,
                showStationDetails: showStationDetails
            )
        }
    }
}
