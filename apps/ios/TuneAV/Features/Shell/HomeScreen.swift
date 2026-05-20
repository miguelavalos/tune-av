import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let stations: [Station]
    let isLoading: Bool
    let errorMessage: String?
    let recentStations: [Station]
    let favoriteStations: [Station]
    let lastPlayedStation: Station?
    let discoveries: [DiscoveredTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let feedContext: HomeFeedContext
    let preferredTag: String
    let preferredCountryCode: String
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let openAvi: () -> Void
    let openSearchTag: (String) -> Void
    let refreshHome: () async -> Void
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let setStationFeedback: (Station, TuneAVStationFeedback?) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    @State private var browserDestination: BrowserDestination?

    var body: some View {
        let screenState = homeScreenState
        let heroActionRouter = homeHeroActionRouter

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HomeHeaderContent(
                    state: screenState.headerContentState,
                    openAvi: openAvi
                )
                HomeHeroContent(
                    state: screenState.heroContentState,
                    playAction: { heroActionRouter.play($0, featuredState: screenState.featuredState) },
                    favoriteAction: toggleFavorite,
                    feedbackAction: heroActionRouter.setFeedback,
                    detailsAction: { heroActionRouter.showDetails($0, featuredState: screenState.featuredState) }
                )
                HomeRecommendationSections(
                    derivedState: screenState.derivedState,
                    favoriteStationIDs: favoriteStationIDs,
                    nowPlayingTracks: nowPlayingTracks,
                    stationFeedback: stationFeedback,
                    openSearchTag: openSearchTag,
                    playStation: playStation,
                    toggleFavorite: toggleFavorite,
                    showStationDetails: showStationDetails
                )
            }
            .shellScreenContentPadding(bottom: bottomContentPadding)
        }
        .shellScreenScrollBehavior()
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .refreshable {
            await refreshHome()
        }
    }

    private var homeScreenState: HomeScreenState {
        HomeScreenStateBuilder.build(
            stations: stations,
            isLoading: isLoading,
            errorMessage: errorMessage,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            lastPlayedStation: lastPlayedStation,
            discoveries: discoveries,
            stationFeedback: stationFeedback,
            feedContext: feedContext,
            preferredTag: preferredTag,
            preferredCountryCode: preferredCountryCode,
            favoriteStationIDs: favoriteStationIDs,
            currentStation: audioPlayer.currentStation,
            playbackStatusLabel: audioPlayer.status.label,
            isCurrentStation: audioPlayer.isCurrent(_:),
            isPlaying: audioPlayer.isPlaying,
            isStationLoading: audioPlayer.isLoading,
            currentTrackTitle: audioPlayer.currentTrackTitle,
            currentTrackArtist: audioPlayer.currentTrackArtist
        )
    }

    private var homeHeroActionRouter: HomeHeroActionRouter {
        HomeHeroActionRouter(
            isCurrentStation: audioPlayer.isCurrent(_:),
            togglePlayback: audioPlayer.togglePlayback,
            playStation: playStation,
            showStationDetails: showStationDetails,
            currentFeedback: { stationFeedback[$0.id] },
            setStationFeedback: setStationFeedback
        )
    }

}
