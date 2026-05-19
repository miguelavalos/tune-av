import SwiftUI

extension AppShellView {
    func makeHomeScreen(
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
        preferredCountryCode: String,
        bottomContentPadding: CGFloat,
        favoriteStationIDs: Set<String>,
        nowPlayingTracks: [String: NowPlayingTrack],
        openAvi: @escaping () -> Void,
        openSearchTag: @escaping (String) -> Void,
        refreshHome: @escaping () async -> Void,
        playStation: @escaping (Station, TuneAVPlaybackQueueSource, [Station]?) -> Void,
        toggleFavorite: @escaping (Station) -> Void,
        setStationFeedback: @escaping (Station, TuneAVStationFeedback?) -> Void,
        showStationDetails: @escaping (Station, TuneAVPlaybackQueueSource, [Station]?) -> Void
    ) -> some View {
        HomeScreen(
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
            bottomContentPadding: bottomContentPadding,
            favoriteStationIDs: favoriteStationIDs,
            nowPlayingTracks: nowPlayingTracks,
            openAvi: openAvi,
            openSearchTag: openSearchTag,
            refreshHome: refreshHome,
            playStation: playStation,
            toggleFavorite: toggleFavorite,
            setStationFeedback: setStationFeedback,
            showStationDetails: showStationDetails
        )
    }

    func makeSearchScreen(
        query: Binding<String>,
        activeTag: Binding<String?>,
        selectedCountryCode: Binding<String?>,
        discoveryMode: Binding<TuneAVStationDiscoveryMode>,
        results: [Station],
        isLoading: Bool,
        errorMessage: String?,
        tags: [String],
        bottomContentPadding: CGFloat,
        favoriteStationIDs: Set<String>,
        nowPlayingTracks: [String: NowPlayingTrack],
        stationFeedback: [String: TuneAVStationFeedback],
        playStation: @escaping (Station, TuneAVPlaybackQueueSource, [Station]?) -> Void,
        toggleFavorite: @escaping (Station) -> Void,
        showStationDetails: @escaping (Station, TuneAVPlaybackQueueSource, [Station]?) -> Void
    ) -> some View {
        SearchScreen(
            query: query,
            activeTag: activeTag,
            selectedCountryCode: selectedCountryCode,
            discoveryMode: discoveryMode,
            results: results,
            isLoading: isLoading,
            errorMessage: errorMessage,
            tags: tags,
            bottomContentPadding: bottomContentPadding,
            favoriteStationIDs: favoriteStationIDs,
            nowPlayingTracks: nowPlayingTracks,
            stationFeedback: stationFeedback,
            playStation: playStation,
            toggleFavorite: toggleFavorite,
            showStationDetails: showStationDetails
        )
    }

    func makeLibraryScreen(
        favorites: [Station],
        recents: [Station],
        discoveries: [DiscoveredTrack],
        summary: TuneAVUserSummary?,
        requestedMode: Binding<RadioLibraryMode?>,
        requestedOverview: Binding<Bool?>,
        bottomContentPadding: CGFloat,
        favoriteStationIDs: Set<String>,
        nowPlayingTracks: [String: NowPlayingTrack],
        stationFeedback: [String: TuneAVStationFeedback],
        openAccountAction: @escaping () -> Void,
        startSignInAction: @escaping () -> Void,
        openSearchAction: @escaping () -> Void,
        playStation: @escaping (Station, TuneAVPlaybackQueueSource, [Station]?) -> Void,
        toggleFavorite: @escaping (Station) -> Void,
        showStationDetails: @escaping (Station, TuneAVPlaybackQueueSource, [Station]?, RadioLibraryMode?, Bool?) -> Void
    ) -> some View {
        LibraryScreen(
            favorites: favorites,
            recents: recents,
            discoveries: discoveries,
            summary: summary,
            requestedMode: requestedMode,
            requestedOverview: requestedOverview,
            bottomContentPadding: bottomContentPadding,
            favoriteStationIDs: favoriteStationIDs,
            nowPlayingTracks: nowPlayingTracks,
            stationFeedback: stationFeedback,
            openAccountAction: openAccountAction,
            startSignInAction: startSignInAction,
            openSearchAction: openSearchAction,
            playStation: playStation,
            toggleFavorite: toggleFavorite,
            showStationDetails: showStationDetails
        )
    }

    func makeMusicScreen(
        discoveries: [DiscoveredTrack],
        summary: TuneAVUserSummary?,
        historyStationFilter: Binding<Station?>,
        requestedMusicMode: Binding<MusicContentMode?>,
        requestedMusicOverview: Binding<Bool?>,
        bottomContentPadding: CGFloat,
        openDiscoveryStation: @escaping (DiscoveredTrack) -> Void,
        openDiscoveryStationInfo: @escaping (DiscoveredTrack) -> Void,
        openDiscoveryInfo: @escaping (DiscoveredTrack, MusicContentMode?) -> Void,
        openArtistInfo: @escaping (DiscoveryArtistSummary, MusicContentMode?) -> Void,
        stationArtworkURL: @escaping (DiscoveredTrack) -> URL?,
        trackFeedback: @escaping (DiscoveredTrack) -> TuneAVStationFeedback?,
        openSearchAction: @escaping () -> Void,
        openAccountAction: @escaping () -> Void,
        startSignInAction: @escaping () -> Void,
        toggleDiscoverySaved: @escaping (DiscoveredTrack) -> Void,
        hideDiscovery: @escaping (DiscoveredTrack) -> Void,
        restoreDiscovery: @escaping (DiscoveredTrack) -> Void,
        removeDiscovery: @escaping (DiscoveredTrack) -> Void,
        clearDiscoveries: @escaping () -> Void
    ) -> some View {
        MusicScreen(
            discoveries: discoveries,
            summary: summary,
            historyStationFilter: historyStationFilter,
            requestedMusicMode: requestedMusicMode,
            requestedMusicOverview: requestedMusicOverview,
            bottomContentPadding: bottomContentPadding,
            openDiscoveryStation: openDiscoveryStation,
            openDiscoveryStationInfo: openDiscoveryStationInfo,
            openDiscoveryInfo: openDiscoveryInfo,
            openArtistInfo: openArtistInfo,
            stationArtworkURL: stationArtworkURL,
            trackFeedback: trackFeedback,
            openSearchAction: openSearchAction,
            openAccountAction: openAccountAction,
            startSignInAction: startSignInAction,
            toggleDiscoverySaved: toggleDiscoverySaved,
            hideDiscovery: hideDiscovery,
            restoreDiscovery: restoreDiscovery,
            removeDiscovery: removeDiscovery,
            clearDiscoveries: clearDiscoveries
        )
    }

    func makeProfileScreen(
        mode: ProfileScreen.Mode,
        startSignInFlow: @escaping (Bool) -> Void,
        bottomContentPadding: CGFloat
    ) -> some View {
        ProfileScreen(
            mode: mode,
            startSignInFlow: startSignInFlow,
            bottomContentPadding: bottomContentPadding
        )
    }
}
