import AVAppShellFoundation
import AVHaptics
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

        TuneAdaptiveLayoutReader { layout in
            let contentLayoutClass = homeContentLayoutClass(for: layout)

            AVAppShellScrollableScreenScaffold(
                alignment: .leading,
                spacing: homeSpacing(for: layout),
                horizontalPadding: homeHorizontalPadding(for: layout),
                bottomPadding: homeBottomPadding(for: layout),
                maxContentWidth: homeMaxContentWidth(for: layout)
            ) {
                TuneAVTheme.shellBackground
            } content: {
                HomeHeaderContent(
                    state: screenState.headerContentState,
                    layoutClass: contentLayoutClass,
                    openAvi: openAvi
                )
                HomeHeroContent(
                    state: screenState.heroContentState,
                    layoutClass: contentLayoutClass,
                    playAction: { heroActionRouter.play($0, featuredState: screenState.featuredState) },
                    favoriteAction: toggleFavorite,
                    feedbackAction: heroActionRouter.setFeedback,
                    detailsAction: { heroActionRouter.showDetails($0, featuredState: screenState.featuredState) }
                )
                HomeRecommendationSections(
                    derivedState: screenState.derivedState,
                    layoutClass: contentLayoutClass,
                    favoriteStationIDs: favoriteStationIDs,
                    nowPlayingTracks: nowPlayingTracks,
                    stationFeedback: stationFeedback,
                    openSearchTag: openSearchTag,
                    playStation: playStation,
                    toggleFavorite: toggleFavorite,
                    showStationDetails: showStationDetails
                )
            }
        }
        .refreshable {
            await refreshHome()
        }
    }

    private func homeContentLayoutClass(for layout: TuneLayoutContext) -> TuneLayoutClass {
        layout.isPad && layout.layoutClass == .compact ? .regular : layout.layoutClass
    }

    private func homeSpacing(for layout: TuneLayoutContext) -> CGFloat {
        layout.isTabletLike ? 28 : 24
    }

    private func homeHorizontalPadding(for layout: TuneLayoutContext) -> CGFloat {
        layout.isTabletLike ? 28 : AVAppShellScreenMetric.horizontalPadding
    }

    private func homeBottomPadding(for layout: TuneLayoutContext) -> CGFloat {
        layout.isTabletLike ? 56 : bottomContentPadding
    }

    private func homeMaxContentWidth(for layout: TuneLayoutContext) -> CGFloat? {
        layout.shellContentMaxWidth
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
            togglePlayback: togglePlayback,
            playStation: playStation,
            showStationDetails: showStationDetails,
            currentFeedback: { stationFeedback[$0.id] },
            setStationFeedback: setStationFeedback
        )
    }

    private func togglePlayback() {
        AVHaptics.perform(.primaryAction)
        audioPlayer.togglePlayback()
    }

}
