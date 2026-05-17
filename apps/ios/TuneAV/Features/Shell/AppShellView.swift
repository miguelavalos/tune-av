import SwiftUI
import UIKit

struct AppShellView: View {
    let launchContext: LaunchContext
    let startSignInFlow: (Bool) -> Void

    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var languageController: AppLanguageController
    @EnvironmentObject private var libraryStore: LibraryStore

    @StateObject private var chromeActions = AppShellChromeActions()
    @State private var selectedTab: AppShellTab
    @State private var searchQuery: String
    @State private var searchTag: String?
    @State private var searchCountryCode: String?
    @State private var searchDiscoveryMode: TuneAVStationDiscoveryMode = .music
    @State private var searchResults: [Station] = []
    @State private var searchIsLoading = false
    @State private var searchErrorMessage: String?
    @State private var homeStations: [Station] = []
    @State private var homeIsLoading = false
    @State private var homeErrorMessage: String?
    @State private var homeFeedContext: HomeFeedContext = .popularWorldwide
    @State private var homeSnapshot = HomeFeedSnapshot()
    @State private var selectedStationDetail: SelectedStationDetail?
    @State private var selectedMusicAviDetail: SelectedMusicAviDetail?
    @State private var isAviNowPlayingFullPlayer = false
    @State private var aviReturnTab: AppShellTab?
    @State private var aviReturnRadioMode: RadioLibraryMode?
    @State private var aviReturnShowsRadioOverview: Bool?
    @State private var aviReturnMusicMode: MusicContentMode?
    @State private var aviReturnShowsMusicOverview: Bool?
    @State private var requestedRadioMode: RadioLibraryMode?
    @State private var requestedRadioOverview: Bool?
    @State private var requestedMusicMode: MusicContentMode?
    @State private var requestedMusicOverview: Bool?
    @State private var musicHistoryStationFilter: Station?
    @State private var enrichedStationsByID: [String: Station] = [:]
    @State private var lastLibraryEnrichmentRequestKey: String?
    @State private var lastLibraryEnrichmentRequestAt: Date?
    @State private var stationNowPlayingTracks: [String: NowPlayingTrack] = [:]
    @State private var stationNowPlayingCache: [String: CachedStationNowPlaying] = [:]
    @State private var stationNowPlayingFailureCache: [String: Date] = [:]
    @State private var didBootstrap = false
    @State private var profileMode: ProfileScreen.Mode = .settings
    @State private var listeningSession: ActiveListeningSession?
    @State private var isShowingProPaywall = false
    @State private var isShowingFooterArtworkZoom = false

    private let stationService = StationService()
    private let stationNowPlayingService = NowPlayingService()
    private let genreTags = TuneAVStationMusicClassifier.musicTags
    private static let libraryEnrichmentRefreshInterval: TimeInterval = 300

    private var homeFeed: AppShellHomeFeed {
        AppShellHomeFeed(
            stationService: stationService,
            localizedCountryName: L10n.countryName(for:),
            resolvedDeviceCountryCode: resolvedDeviceCountryCode
        )
    }

    private var appSearch: AppShellSearch {
        AppShellSearch(
            stationService: stationService,
            resolvedDeviceCountryCode: resolvedDeviceCountryCode,
            hasResolvedCountry: hasResolvedCountry(_:)
        )
    }

    init(
        launchContext: LaunchContext = .current,
        startSignInFlow: @escaping (Bool) -> Void = { _ in }
    ) {
        self.launchContext = launchContext
        self.startSignInFlow = startSignInFlow
        _selectedTab = State(initialValue: AppShellTab(launchContext.preferredTab, preferredSearchQuery: launchContext.preferredSearchQuery))
        _searchQuery = State(initialValue: launchContext.preferredSearchQuery ?? "")
    }

    var body: some View {
        AppShellScaffold(
            selectedTab: selectedTab,
            hasFooterPlayer: audioPlayer.currentStation != nil,
            footerBackdropHeight: shellFooterBackdropHeight,
            searchAction: {
                selectedTab = .search
            },
            aviAction: {
                openContextualAvi()
            },
            selectTab: { tab in
                if tab == .avi {
                    openContextualAvi()
                } else {
                    selectedTab = tab
                }
            },
            content: {
                NavigationStack {
                    currentScreen
                }
            },
            footerPlayer: {
                if let station = audioPlayer.currentStation {
                    if selectedTab == .avi && isAviShowingCurrentStation {
                        AviExpandedFooterPlayerView(station: station) {
                            openNowPlayingFullPlayer(station)
                        } showArtworkZoom: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                isShowingFooterArtworkZoom = true
                            }
                        }
                    } else if !shouldHideFooterPlayer {
                        MiniPlayerView(station: station) {
                            openNowPlayingFullPlayer(station)
                        }
                    }
                }
            }
        )
        .environmentObject(chromeActions)
        .overlay {
            if isShowingFooterArtworkZoom, let station = audioPlayer.currentStation {
                AppShellArtworkZoomOverlay(
                    station: station,
                    artworkURL: audioPlayer.currentTrackArtworkURL,
                    title: audioPlayer.currentTrackTitle ?? station.name,
                    subtitle: audioPlayer.currentTrackArtist ?? station.name
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        isShowingFooterArtworkZoom = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(30)
            }
        }
        .onAppear {
            chromeActions.openSettings = {
                profileMode = .settings
                selectedTab = .profile
            }
            chromeActions.openAccount = {
                profileMode = .account
                selectedTab = .profile
            }
        }
        .sheet(item: Binding(
            get: { accessController.upgradePrompt },
            set: { accessController.upgradePrompt = $0 }
        )) { prompt in
            UpgradeRecommendationSheet(
                prompt: prompt,
                isGuest: accessController.accessMode == .guest,
                accountIsAvailable: accessController.accountIsAvailable,
                onPrimaryAction: {
                    accessController.upgradePrompt = nil
                    if accessController.accessMode == .guest {
                        startSignInFlow(true)
                    } else {
                        isShowingProPaywall = true
                    }
                },
                onDismiss: {
                    accessController.upgradePrompt = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingProPaywall) {
            TuneAVProPaywallView()
                .environmentObject(accessController)
        }
        .task {
            await bootstrapIfNeeded()
        }
        .task(id: homeFeedRequestKey) {
            await refreshHomePresentationAndFeed()
        }
        .task(id: searchRequestKey) {
            await loadSearchResults()
        }
        .task(id: stationNowPlayingRequestKey) {
            await loadStationNowPlayingPreviews()
        }
        .task(id: summaryRefreshRequestKey) {
            await refreshUserSummaryForVisibleTab()
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .home else { return }
            refreshHomePresentation()
        }
        .onChange(of: audioPlayer.currentStation?.id) { previousStationID, stationID in
            guard stationID != nil, let station = audioPlayer.currentStation else { return }
            libraryStore.recordPlayback(of: station, recentLimit: accessController.limits.recentStations)
            syncAviActiveSignalIfNeeded(previousStationID: previousStationID, currentStation: station)
        }
        .onChange(of: audioPlayer.status) { oldStatus, newStatus in
            handlePlaybackStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: currentTrackDiscoveryKey) { _, _ in
            recordCurrentTrackDiscovery()
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selectedTab {
        case .home:
            let stations = enrichedStations(homeSnapshot.stations)
            let recentStations = enrichedStations(homeSnapshot.recentStations)
            let favoriteStations = enrichedStations(homeSnapshot.favoriteStations)

            HomeScreen(
                stations: stations,
                isLoading: homeIsLoading,
                errorMessage: homeErrorMessage,
                recentStations: recentStations,
                favoriteStations: favoriteStations,
                lastPlayedStation: lastPlayedStation.map(enrichedStation),
                discoveries: libraryStore.discoveries,
                stationFeedback: libraryStore.stationFeedback,
                feedContext: homeSnapshot.feedContext,
                preferredTag: libraryStore.settings.preferredTag,
                preferredCountryCode: libraryStore.settings.preferredCountry,
                bottomContentPadding: shellScrollBottomPadding,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: stationNowPlayingTracks,
                openAvi: {
                    openContextualAvi()
                },
                openSearchTag: { tag in
                    searchQuery = ""
                    searchCountryCode = nil
                    searchTag = tag
                    searchDiscoveryMode = .music
                    selectedTab = .search
                },
                refreshHome: refreshHomePresentationAndFeed,
                playStation: playStation,
                toggleFavorite: toggleFavorite(_:),
                setStationFeedback: { station, feedback in
                    libraryStore.setFeedback(feedback, for: station)
                },
                showStationDetails: { station, queueSource, queue in
                    showStationDetails(station, queueSource: queueSource, queue: queue)
                }
            )
        case .search:
            let visibleSearchResults = searchResults.isEmpty
                ? searchFallbackStations(for: searchRequest)
                : searchResults
            let results = enrichedStations(visibleSearchResults)

            SearchScreen(
                query: $searchQuery,
                activeTag: $searchTag,
                selectedCountryCode: $searchCountryCode,
                discoveryMode: $searchDiscoveryMode,
                results: results,
                isLoading: searchIsLoading,
                errorMessage: searchErrorMessage,
                tags: genreTags,
                bottomContentPadding: shouldHideFooterPlayer ? 176 : shellScrollBottomPadding,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: stationNowPlayingTracks,
                stationFeedback: libraryStore.stationFeedback,
                playStation: playStation,
                toggleFavorite: toggleFavorite(_:),
                showStationDetails: { station, queueSource, queue in
                    showStationDetails(station, queueSource: queueSource, queue: queue)
                }
            )
        case .avi:
            let focusedStation = selectedStationDetail.map { enrichedStation($0.station) }
            let focusedQueueStations = selectedStationDetail.map { enrichedStations($0.queueStations) }
            let focusedQueueSource = selectedStationDetail?.queueSource ?? .singleStation
            let stations = enrichedStations(homeSnapshot.stations)
            let recentStations = enrichedRecentStations
            let favoriteStations = enrichedFavoriteStations

            AviScreen(
                currentStation: audioPlayer.currentStation,
                focusedStation: focusedStation,
                isFocusedStationActive: focusedStation.map(audioPlayer.isCurrent(_:)) ?? false,
                currentTrackTitle: TuneAVText.normalizedValue(audioPlayer.currentTrackTitle),
                currentTrackArtist: TuneAVText.normalizedValue(audioPlayer.currentTrackArtist),
                currentTrackArtworkURL: audioPlayer.currentTrackArtworkURL,
                isPlaying: audioPlayer.isPlaying,
                isLoading: audioPlayer.isLoading,
                canCyclePlaybackQueue: audioPlayer.canCyclePlaybackQueue,
                stations: stations,
                recentStations: recentStations,
                favoriteStations: favoriteStations,
                discoveries: libraryStore.discoveries,
                focusedMusicDetail: selectedMusicAviDetail,
                isNowPlayingFullPlayer: isAviNowPlayingFullPlayer,
                stationFeedback: libraryStore.stationFeedback,
                feedContext: homeSnapshot.feedContext,
                preferredTag: libraryStore.settings.preferredTag,
                preferredCountryCode: libraryStore.settings.preferredCountry,
                bottomContentPadding: shellScrollBottomPadding,
                openSearch: {
                    selectedTab = .search
                },
                openLibrary: {
                    selectedTab = .library
                },
                openPlayer: {
                    if let focusedStation, audioPlayer.isCurrent(focusedStation) {
                        audioPlayer.togglePlayback()
                    } else if let focusedStation {
                        playStation(
                            focusedStation,
                            queueSource: focusedQueueSource,
                            queue: focusedQueueStations ?? [focusedStation]
                        )
                    } else if let currentStation = audioPlayer.currentStation {
                        openNowPlayingFullPlayer(currentStation)
                    }
                },
                stopPlayback: {
                    audioPlayer.stopAndClearCurrentStation()
                    selectedStationDetail = nil
                    selectedMusicAviDetail = nil
                    isAviNowPlayingFullPlayer = false
                    selectedTab = .avi
                },
                playPrevious: audioPlayer.playPreviousInQueue,
                playNext: audioPlayer.playNextInQueue,
                playStation: { station, queue in
                    playStation(station, queueSource: .homeDiscovery, queue: queue)
                },
                toggleFavorite: toggleFavorite(_:),
                setStationFeedback: { station, feedback in
                    libraryStore.setFeedback(feedback, for: station)
                },
                showStationDetails: { station, queue in
                    showStationDetails(station, queueSource: .homeDiscovery, queue: queue)
                },
                openDiscoveryInfo: { discovery in
                    openDiscoveryInfo(discovery)
                },
                openDiscoveryStation: { discovery in
                    openDiscoveryStation(discovery)
                },
                openAccount: {
                    profileMode = .account
                    selectedTab = .profile
                },
                startSignIn: {
                    startSignInFlow(true)
                },
                openProPaywall: {
                    isShowingProPaywall = true
                },
                closeFocusedDetail: closeFocusedAviDetail
            )
        case .library:
            let favorites = enrichedFavoriteStations
            let recents = enrichedRecentStations

            LibraryScreen(
                favorites: favorites,
                recents: recents,
                discoveries: libraryStore.discoveries,
                summary: libraryStore.userSummary,
                requestedMode: $requestedRadioMode,
                requestedOverview: $requestedRadioOverview,
                bottomContentPadding: shellScrollBottomPadding,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: stationNowPlayingTracks,
                stationFeedback: libraryStore.stationFeedback,
                openAccountAction: {
                    profileMode = .account
                    selectedTab = .profile
                },
                startSignInAction: {
                    startSignInFlow(true)
                },
                playStation: playStation,
                toggleFavorite: toggleFavorite(_:),
                showStationDetails: { station, queueSource, queue, mode, showsOverview in
                    showStationDetails(
                        station,
                        queueSource: queueSource,
                        queue: queue,
                        returnRadioMode: mode,
                        returnRadioOverview: showsOverview
                    )
                }
            )
        case .music:
            MusicScreen(
                discoveries: libraryStore.discoveries,
                summary: libraryStore.userSummary,
                historyStationFilter: $musicHistoryStationFilter,
                requestedMusicMode: $requestedMusicMode,
                requestedMusicOverview: $requestedMusicOverview,
                bottomContentPadding: shellScrollBottomPadding,
                openDiscoveryStation: openDiscoveryStation(_:),
                openDiscoveryStationInfo: openDiscoveryStationInfo(_:),
                openDiscoveryInfo: { discovery, mode in
                    openDiscoveryInfo(discovery, returnMusicMode: mode)
                },
                openArtistInfo: { artist, mode in
                    openArtistInfo(artist, returnMusicMode: mode)
                },
                stationArtworkURL: { _ in nil },
                trackFeedback: { discovery in libraryStore.feedback(for: discovery) },
                openAccountAction: {
                    profileMode = .account
                    selectedTab = .profile
                },
                startSignInAction: {
                    startSignInFlow(true)
                },
                toggleDiscoverySaved: toggleDiscoverySaved(_:),
                hideDiscovery: libraryStore.hideDiscovery(_:),
                restoreDiscovery: libraryStore.restoreDiscovery(_:),
                removeDiscovery: libraryStore.removeDiscovery(_:),
                clearDiscoveries: libraryStore.clearDiscoveries
            )
        case .profile:
            ProfileScreen(
                mode: profileMode,
                startSignInFlow: startSignInFlow,
                bottomContentPadding: shellScrollBottomPadding
            )
        }
    }


    private var favoriteStations: [Station] {
        libraryStore.favoriteStations()
    }

    private var isAviShowingCurrentStation: Bool {
        guard selectedTab == .avi, let currentStation = audioPlayer.currentStation else { return false }
        guard isAviNowPlayingFullPlayer else { return false }
        guard let selectedStation = selectedStationDetail?.station else { return false }
        return selectedStation.id == currentStation.id
    }

    private var shouldHideFooterPlayer: Bool {
        selectedTab == .avi && isAviShowingCurrentStation
    }

    private var recentStations: [Station] {
        libraryStore.recentStations()
    }

    private var favoriteStationIDs: Set<String> {
        Set(libraryStore.favorites.map(\.stationID))
    }

    private var enrichedFavoriteStations: [Station] {
        enrichedStations(favoriteStations)
    }

    private var enrichedRecentStations: [Station] {
        enrichedStations(recentStations)
    }

    private var lastPlayedStation: Station? {
        libraryStore.station(for: libraryStore.settings.lastPlayedStationID)
    }

    private var searchRequestKey: String {
        "\(searchRequest.key)|\(languageController.currentLanguage.id)"
    }

    private var homeFeedRequestKey: String {
        "\(libraryStore.settings.preferredTag)|\(languageController.currentLanguage.id)"
    }

    private var searchRequest: AppShellSearchRequest {
        AppShellSearchRequest(query: searchQuery, tag: searchTag, countryCode: searchCountryCode, discoveryMode: searchDiscoveryMode)
    }

    private var shellScrollBottomPadding: CGFloat {
        // The footer is visually detached and floats above scroll content,
        // so scrollable screens need extra trailing space to bring the last row above it.
        if audioPlayer.currentStation == nil {
            return 176
        }
        return selectedTab == .avi && isAviShowingCurrentStation ? 330 : 224
    }

    private var shellFooterBackdropHeight: CGFloat {
        if audioPlayer.currentStation == nil {
            return 142
        }
        return selectedTab == .avi && isAviShowingCurrentStation ? 330 : 210
    }

    private var stationNowPlayingRequestKey: String {
        let ids = stationNowPlayingCandidates.map(\.id).joined(separator: "|")
        return "\(selectedTab)|\(isProNowPlayingEnabled)|\(ids)"
    }

    private var summaryRefreshRequestKey: String {
        switch selectedTab {
        case .library, .music:
            return "\(selectedTab)|\(accessController.accessMode)|\(accessController.accountUser?.id ?? "guest")"
        case .home, .search, .avi, .profile:
            return ""
        }
    }

    private func refreshUserSummaryForVisibleTab() async {
        guard selectedTab == .library || selectedTab == .music else { return }
        guard !launchContext.isUITesting else { return }
        await libraryStore.refreshUserSummary()
    }

    private var currentTrackDiscoveryKey: String {
        guard
            let station = audioPlayer.currentStation,
            let trackTitle = TuneAVDisplayMetadata.plausibleTitle(
                audioPlayer.currentTrackTitle,
                stationName: station.name
            ),
            let trackArtist = TuneAVDisplayMetadata.plausibleArtist(
                audioPlayer.currentTrackArtist,
                stationName: station.name
            )
        else {
            return ""
        }

        return [
            station.id,
            TuneAVText.normalizedValue(trackArtist) ?? trackArtist.lowercased(),
            TuneAVText.normalizedValue(trackTitle) ?? trackTitle.lowercased(),
            audioPlayer.currentTrackArtworkURL?.absoluteString ?? ""
        ].joined(separator: "|")
    }

    private var stationNowPlayingCandidates: [Station] {
        AppShellNowPlayingPreviews.candidateStations(
            selectedTab: selectedTab,
            homeSnapshot: homeSnapshot,
            searchResults: enrichedStations(searchResults),
            favoriteStations: enrichedFavoriteStations,
            recentStations: enrichedRecentStations,
            isEnabled: isProNowPlayingEnabled
        )
    }

    private func loadStationNowPlayingPreviews() async {
        guard isProNowPlayingEnabled else {
            clearStationNowPlayingPreviews()
            return
        }
        guard !launchContext.isUITesting else {
            clearStationNowPlayingPreviews()
            return
        }

        let supportedStations = stationNowPlayingCandidates
            .filter { stationNowPlayingService.supports($0) }
            .prefix(6)
        let supportedStationIDs = Set(supportedStations.map(\.id))

        guard !supportedStations.isEmpty else {
            clearVisibleStationNowPlayingPreviews()
            return
        }

        var nextTracks = stationNowPlayingTracks.filter { supportedStationIDs.contains($0.key) }

        for station in supportedStations {
            if Task.isCancelled { return }

            if let cached = stationNowPlayingCache[station.id], cached.isFresh {
                nextTracks[station.id] = cached.track
                continue
            }
            if let failedAt = stationNowPlayingFailureCache[station.id], Date().timeIntervalSince(failedAt) < 180 {
                continue
            }

            let track = await stationNowPlayingService.fetchTrack(for: station)
            guard !Task.isCancelled else { return }

            guard let track else {
                stationNowPlayingFailureCache[station.id] = Date()
                continue
            }
            nextTracks[station.id] = track
            stationNowPlayingCache[station.id] = CachedStationNowPlaying(track: track, fetchedAt: Date())
            stationNowPlayingFailureCache[station.id] = nil
        }

        guard stationNowPlayingTracks != nextTracks else { return }
        stationNowPlayingTracks = nextTracks
    }

    private func clearVisibleStationNowPlayingPreviews() {
        if !stationNowPlayingTracks.isEmpty {
            stationNowPlayingTracks.removeAll(keepingCapacity: true)
        }
    }

    private func clearStationNowPlayingPreviews() {
        if !stationNowPlayingTracks.isEmpty {
            stationNowPlayingTracks.removeAll(keepingCapacity: true)
        }
        if !stationNowPlayingCache.isEmpty {
            stationNowPlayingCache.removeAll(keepingCapacity: true)
        }
        if !stationNowPlayingFailureCache.isEmpty {
            stationNowPlayingFailureCache.removeAll(keepingCapacity: true)
        }
    }

    private var isProNowPlayingEnabled: Bool {
        accessController.capabilities.canAccessPremiumFeatures
    }

    private func runProAviAction(_ action: () -> Void) {
        guard accessController.capabilities.canAccessPremiumFeatures else {
            isShowingProPaywall = true
            return
        }
        action()
    }

    private func recordCurrentTrackDiscovery() {
        guard
            let station = audioPlayer.currentStation,
            let trackTitle = TuneAVDisplayMetadata.plausibleTitle(
                audioPlayer.currentTrackTitle,
                stationName: station.name
            ),
            let trackArtist = TuneAVDisplayMetadata.plausibleArtist(
                audioPlayer.currentTrackArtist,
                stationName: station.name
            )
        else {
            return
        }

        libraryStore.recordDiscoveredTrack(
            title: trackTitle,
            artist: trackArtist,
            station: station,
            artworkURL: audioPlayer.currentTrackArtworkURL,
            discoveryLimit: accessController.limits.discoveredTracks
        )
        rememberTrackForListeningSession(title: trackTitle, artist: trackArtist)
    }

    private func rememberTrackForListeningSession(title: String, artist: String?) {
        guard var session = listeningSession else { return }
        session.trackKeys.insert("\(artist ?? "")|\(title)".lowercased())
        listeningSession = session
    }

    private func applyUITestTrackMetadataIfNeeded() {
        guard launchContext.isUITesting else { return }
        guard launchContext.uiTestTrackTitle != nil || launchContext.uiTestTrackArtist != nil else { return }
        audioPlayer.applyUITestTrackMetadata(
            title: launchContext.uiTestTrackTitle,
            artist: launchContext.uiTestTrackArtist
        )
    }

    private func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        audioPlayer.setSleepTimer(minutes: libraryStore.settings.sleepTimerMinutes)
        seedUITestDataIfNeeded()

        if let preferredTab = launchContext.preferredTab {
            switch preferredTab {
            case .search:
                selectedTab = .search
            case .library:
                selectedTab = .library
            case .music:
                selectedTab = .music
            case .player:
                if let lastStation = libraryStore.station(for: libraryStore.settings.lastPlayedStationID) {
                    playStation(lastStation)
                    showStationDetails(lastStation, queueSource: .singleStation, queue: [lastStation])
                } else if let demoStation = launchContext.demoStation {
                    playStation(demoStation)
                    showStationDetails(demoStation, queueSource: .singleStation, queue: [demoStation])
                }
            case .settings:
                selectedTab = .profile
            }
        } else if launchContext.preferredSearchQuery != nil {
            selectedTab = .search
        }

        if let demoStation = launchContext.demoStation {
            libraryStore.ensureSeededStation(demoStation, favorite: launchContext.seedFavorite)
            if audioPlayer.currentStation?.id != demoStation.id {
                playStation(demoStation)
            }
            applyUITestTrackMetadataIfNeeded()
        }

        if launchContext.isUITesting, let feature = launchContext.uiTestUpgradePromptFeature {
            accessController.presentUpgradePrompt(for: feature)
        }
    }

    private func seedUITestDataIfNeeded() {
        guard launchContext.isUITesting else { return }
        guard launchContext.shouldSeedUITestLibrary else { return }
        guard libraryStore.favorites.isEmpty, libraryStore.recents.isEmpty else { return }

        let samples = Array(Station.samples.prefix(3))
        guard !samples.isEmpty else { return }

        for station in samples.prefix(2) {
            libraryStore.toggleFavorite(for: station)
        }

        for station in samples {
            libraryStore.recordPlayback(of: station, recentLimit: accessController.limits.recentStations)
        }

        if launchContext.shouldUseLocalUITestDiscovery {
            libraryStore.recordDiscoveredTrack(
                title: "Midnight City",
                artist: "M83",
                station: samples[0],
                artworkURL: nil
            )
            libraryStore.markTrackInteresting(
                title: "Sweet Disposition",
                artist: "The Temper Trap",
                station: samples[1],
                artworkURL: nil
            )
        }
    }

    private func playStation(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .singleStation,
        queue: [Station]? = nil
    ) {
        let resolvedStation = enrichedStation(station)
        let resolvedQueue = enrichedStations(queue ?? [resolvedStation])
        let playbackQueue = AudioPlayerService.PlaybackQueue(
            source: queueSource,
            stations: resolvedQueue
        )
        audioPlayer.play(station: resolvedStation, queue: playbackQueue)
        beginListeningSession(for: resolvedStation, source: queueSource)
    }

    private func beginListeningSession(for station: Station, source: AudioPlayerService.PlaybackQueue.Source) {
        if listeningSession?.station.id != station.id {
            flushListeningSession(endedReason: "station_changed")
        }

        listeningSession = ActiveListeningSession(
            station: station,
            startedAt: .now,
            source: source.analyticsSource,
            trackKeys: []
        )
    }

    private func handlePlaybackStatusChange(
        from oldStatus: AudioPlayerService.PlaybackStatus,
        to newStatus: AudioPlayerService.PlaybackStatus
    ) {
        switch newStatus {
        case .paused:
            flushListeningSession(endedReason: "paused")
        case .idle:
            flushListeningSession(endedReason: "app_closed")
        case .failed:
            flushListeningSession(endedReason: "stream_error")
        case .playing:
            if listeningSession == nil, let station = audioPlayer.currentStation {
                listeningSession = ActiveListeningSession(
                    station: station,
                    startedAt: .now,
                    source: audioPlayer.playbackQueue.source.analyticsSource,
                    trackKeys: []
                )
            }
        case .loading:
            break
        }
    }

    private func flushListeningSession(endedReason: String) {
        guard let session = listeningSession else { return }
        listeningSession = nil
        libraryStore.recordListeningSession(
            station: session.station,
            startedAt: session.startedAt,
            endedAt: .now,
            source: session.source,
            endedReason: endedReason,
            trackDetectedCount: session.trackKeys.count
        )
    }

    private func toggleFavorite(_ station: Station) {
        let resolvedStation = enrichedStation(station)

        if libraryStore.isFavorite(resolvedStation) {
            libraryStore.toggleFavorite(for: resolvedStation)
            return
        }

        let state = accessController.limitState(
            for: .favoriteStations,
            currentUsage: libraryStore.favorites.count
        )
        guard state.isAllowed else {
            accessController.presentUpgradePrompt(for: .favoriteStations, currentUsage: state.currentUsage)
            return
        }

        libraryStore.toggleFavorite(for: resolvedStation)
    }

    private func toggleDiscoverySaved(_ discovery: DiscoveredTrack) {
        if discovery.isMarkedInteresting {
            _ = libraryStore.toggleDiscoverySaved(discovery)
            return
        }

        let state = accessController.limitState(
            for: .savedTracks,
            currentUsage: libraryStore.savedDiscoveriesCount
        )
        guard state.isAllowed else {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return
        }

        _ = libraryStore.toggleDiscoverySaved(discovery, savedLimit: state.limit)
    }

    private func showStationDetails(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .singleStation,
        queue: [Station]? = nil,
        returnRadioMode: RadioLibraryMode? = nil,
        returnRadioOverview: Bool? = nil
    ) {
        aviReturnTab = selectedTab == .avi ? aviReturnTab : selectedTab
        aviReturnRadioMode = selectedTab == .library ? returnRadioMode : nil
        aviReturnShowsRadioOverview = selectedTab == .library ? returnRadioOverview : nil
        aviReturnMusicMode = nil
        aviReturnShowsMusicOverview = nil
        isAviNowPlayingFullPlayer = false
        selectedMusicAviDetail = nil
        let resolvedStation = enrichedStation(station)
        let queueStations = enrichedStations(queue ?? [resolvedStation])
        selectedStationDetail = SelectedStationDetail(
            station: resolvedStation,
            queueSource: queueSource,
            queueStations: queueStations
        )
        selectedTab = .avi
    }

    private func openNowPlayingFullPlayer(_ station: Station) {
        aviReturnTab = selectedTab == .avi ? aviReturnTab : selectedTab
        aviReturnRadioMode = nil
        aviReturnShowsRadioOverview = nil
        aviReturnMusicMode = nil
        aviReturnShowsMusicOverview = nil
        selectedMusicAviDetail = nil
        let resolvedStation = enrichedStation(station)
        selectedStationDetail = SelectedStationDetail(
            station: resolvedStation,
            queueSource: .singleStation,
            queueStations: [resolvedStation]
        )
        isAviNowPlayingFullPlayer = true
        selectedTab = .avi
    }

    private func openContextualAvi() {
        aviReturnTab = selectedTab == .avi ? aviReturnTab : selectedTab
        aviReturnRadioMode = nil
        aviReturnShowsRadioOverview = nil
        aviReturnMusicMode = nil
        aviReturnShowsMusicOverview = nil
        selectedStationDetail = nil
        selectedMusicAviDetail = nil
        isAviNowPlayingFullPlayer = false

        selectedTab = .avi
    }

    private func openDiscoveryInfo(_ discovery: DiscoveredTrack, returnMusicMode: MusicContentMode? = nil) {
        aviReturnTab = selectedTab == .avi ? aviReturnTab : selectedTab
        aviReturnRadioMode = nil
        aviReturnShowsRadioOverview = nil
        aviReturnMusicMode = selectedTab == .music ? returnMusicMode : nil
        aviReturnShowsMusicOverview = selectedTab == .music ? returnMusicMode == nil : nil
        selectedStationDetail = nil
        isAviNowPlayingFullPlayer = false
        selectedMusicAviDetail = .track(discovery)
        selectedTab = .avi
    }

    private func openDiscoveryStationInfo(_ discovery: DiscoveredTrack) {
        guard let station = libraryStore.station(for: discovery.stationID) else { return }

        showStationDetails(station, queueSource: .libraryRecents, queue: enrichedRecentStations)
    }

    private func openArtistInfo(_ summary: DiscoveryArtistSummary, returnMusicMode: MusicContentMode? = nil) {
        aviReturnTab = selectedTab == .avi ? aviReturnTab : selectedTab
        aviReturnRadioMode = nil
        aviReturnShowsRadioOverview = nil
        aviReturnMusicMode = selectedTab == .music ? returnMusicMode : nil
        aviReturnShowsMusicOverview = selectedTab == .music ? returnMusicMode == nil : nil
        selectedStationDetail = nil
        isAviNowPlayingFullPlayer = false
        selectedMusicAviDetail = .artist(summary)
        selectedTab = .avi
    }

    private func closeFocusedAviDetail() {
        selectedStationDetail = nil
        selectedMusicAviDetail = nil
        isAviNowPlayingFullPlayer = false

        if let aviReturnTab {
            if aviReturnTab == .library {
                requestedRadioMode = aviReturnRadioMode
                requestedRadioOverview = aviReturnShowsRadioOverview
            } else if aviReturnTab == .music {
                requestedMusicMode = aviReturnMusicMode
                requestedMusicOverview = aviReturnShowsMusicOverview
            }
            selectedTab = aviReturnTab
            self.aviReturnTab = nil
            aviReturnRadioMode = nil
            aviReturnShowsRadioOverview = nil
            aviReturnMusicMode = nil
            aviReturnShowsMusicOverview = nil
        }
    }

    private func syncAviActiveSignalIfNeeded(previousStationID: String?, currentStation: Station) {
        guard selectedTab == .avi else { return }
        guard let previousStationID else { return }
        guard selectedStationDetail?.station.id == previousStationID else { return }

        let queue = audioPlayer.playbackQueue.stations.isEmpty
            ? [currentStation]
            : audioPlayer.playbackQueue.stations
        selectedStationDetail = SelectedStationDetail(
            station: enrichedStation(currentStation),
            queueSource: audioPlayer.playbackQueue.source,
            queueStations: enrichedStations(queue)
        )
    }

    private func openStationHistory(_ station: Station) {
        selectedStationDetail = nil
        musicHistoryStationFilter = station
        selectedTab = .music
    }

    private func stationDiscoveries(for station: Station) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(libraryStore.discoveries)
            .filter { $0.stationID == station.id }
            .sorted { $0.playedAt > $1.playedAt }
    }

    private func enrichedStation(_ station: Station) -> Station {
        guard let cachedStation = enrichedStationsByID[station.id] else { return station }
        guard cachedStation.hasBackendEnrichment else { return station }
        guard !station.hasBackendEnrichment || cachedStation.enrichmentRank >= station.enrichmentRank else { return station }
        return cachedStation
    }

    private func enrichedStations(_ stations: [Station]) -> [Station] {
        stations.map(enrichedStation)
    }

    private func rememberBackendStations(_ stations: [Station]) {
        guard !stations.isEmpty else { return }

        var nextEnrichedStationsByID = enrichedStationsByID

        for station in stations where station.hasBackendEnrichment {
            let current = nextEnrichedStationsByID[station.id]
            guard current == nil || station.enrichmentRank >= current!.enrichmentRank else { continue }
            nextEnrichedStationsByID[station.id] = station
        }
        if nextEnrichedStationsByID != enrichedStationsByID {
            enrichedStationsByID = nextEnrichedStationsByID
        }

        libraryStore.rememberStationSnapshots(stations)
    }

    private func refreshLibraryStationEnrichment() async {
        guard !launchContext.isUITesting else { return }

        let candidates = libraryEnrichmentCandidates()
        guard !candidates.isEmpty else { return }
        let candidatesKey = libraryEnrichmentCandidatesKey(candidates)
        guard shouldRefreshLibraryEnrichment(for: candidatesKey) else { return }
        lastLibraryEnrichmentRequestKey = candidatesKey
        lastLibraryEnrichmentRequestAt = .now

        var enrichedMatches: [Station] = []
        for station in candidates {
            if Task.isCancelled { return }

            do {
                let results = try await stationService.searchStations(
                    filters: .init(
                        query: station.name,
                        country: station.country,
                        countryCode: station.countryCode ?? "",
                        language: station.language,
                        limit: 5
                    )
                )
                guard let enrichedMatch = results.bestBackendMatch(for: station) else { continue }
                enrichedMatches.append(enrichedMatch)
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }

        guard !Task.isCancelled else { return }
        guard candidatesKey == libraryEnrichmentCandidatesKey(libraryEnrichmentCandidates()) else { return }
        rememberBackendStations(enrichedMatches)
    }

    private func shouldRefreshLibraryEnrichment(for key: String, now: Date = .now) -> Bool {
        guard key == lastLibraryEnrichmentRequestKey, let lastLibraryEnrichmentRequestAt else {
            return true
        }
        return now.timeIntervalSince(lastLibraryEnrichmentRequestAt) >= Self.libraryEnrichmentRefreshInterval
    }

    private func libraryEnrichmentCandidates() -> [Station] {
        var seenIDs = Set<String>()
        let stations = [audioPlayer.currentStation].compactMap { $0 } + favoriteStations + recentStations

        return stations.reduce(into: [Station]()) { result, station in
            guard !seenIDs.contains(station.id) else { return }
            seenIDs.insert(station.id)

            let resolvedStation = enrichedStation(station)
            guard resolvedStation.enrichmentRank < 12 else { return }
            result.append(resolvedStation)
        }
        .prefix(12)
        .map { $0 }
    }

    private func libraryEnrichmentCandidatesKey(_ candidates: [Station]) -> String {
        candidates
            .map { "\($0.id):\($0.enrichmentRank)" }
            .joined(separator: "|")
    }

    private func openDiscoveryStation(_ discovery: DiscoveredTrack) {
        guard let station = libraryStore.station(for: discovery.stationID) else { return }

        playStation(station, queueSource: .libraryRecents, queue: enrichedRecentStations)
    }

    private func refreshHomeFeed(forceRemote: Bool = false) async {
        let preferredTag = libraryStore.settings.preferredTag
        homeErrorMessage = nil

        if !forceRemote {
            let immediateStations = immediateHomeFeedStations(preferredTag: preferredTag)
            if !immediateStations.stations.isEmpty {
                homeStations = immediateStations.stations
                homeFeedContext = immediateStations.context
                refreshHomePresentation()
            }
        }

        homeIsLoading = homeStations.isEmpty

        if launchContext.isUITesting && launchContext.shouldUseLocalUITestDiscovery {
            homeStations = Array(Station.samples.prefix(AppShellHomeFeed.defaultFeedLimit))
            homeFeedContext = .popularWorldwide
            refreshHomePresentation()
            homeIsLoading = false
            return
        }

        do {
            let feed = forceRemote
                ? try await homeFeed.refresh(preferredTag: preferredTag)
                : try await homeFeed.load(preferredTag: preferredTag)
            guard preferredTag == libraryStore.settings.preferredTag else {
                homeIsLoading = false
                return
            }
            rememberBackendStations(feed.stations)
            homeStations = feed.stations
            homeFeedContext = feed.context
            refreshHomePresentation()
            homeIsLoading = false
        } catch is CancellationError {
            homeIsLoading = false
        } catch {
            homeStations = defaultEditorialStations
            homeFeedContext = .popularWorldwide
            homeErrorMessage = defaultEditorialStations.isEmpty ? L10n.string("shell.error.home") : nil
            refreshHomePresentation()
            homeIsLoading = false
        }
    }

    private func immediateHomeFeedStations(preferredTag: String) -> HomeFeedResult {
        if let cached = homeFeed.cachedResult(preferredTag: preferredTag) {
            return cached
        }

        return HomeFeedResult(
            stations: defaultEditorialStations,
            context: .popularWorldwide
        )
    }

    private func refreshHomePresentation() {
        let snapshot = HomeFeedSnapshot(
            stations: homeStations,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            feedContext: homeFeedContext
        )
        guard homeSnapshot != snapshot else { return }
        homeSnapshot = snapshot
    }

    private func refreshHomePresentationAndFeed() async {
        refreshHomePresentation()
        await refreshHomeFeed()
        await refreshHomeFeed(forceRemote: true)
    }

    private func loadSearchResults() async {
        let request = searchRequest
        let requestKey = searchRequestKey

        guard shouldLoadSearchResults(for: request) else {
            searchIsLoading = false
            return
        }

        seedSearchResultsIfNeeded(for: request)
        searchIsLoading = true
        searchErrorMessage = nil

        if launchContext.isUITesting && launchContext.shouldUseLocalUITestSearch {
            let results = AppShellSearch.localUITestSearchResults(request: request)
            searchResults = results
            searchErrorMessage = nil
            searchIsLoading = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()

            let results = try await appSearch.load(
                request: request,
                recentStations: recentStations,
                favoriteStations: favoriteStations
            )
            guard requestKey == searchRequestKey else { return }

            rememberBackendStations(results)
            searchResults = results
            searchErrorMessage = nil
            searchIsLoading = false
        } catch is CancellationError {
            guard requestKey == searchRequestKey else { return }
            searchIsLoading = false
        } catch {
            guard requestKey == searchRequestKey else { return }
            let fallback = searchFallbackStations(for: request)
            searchResults = fallback
            searchErrorMessage = fallback.isEmpty ? L10n.string("shell.error.search") : nil
            searchIsLoading = false
        }
    }

    private func seedSearchResultsIfNeeded(for request: AppShellSearchRequest) {
        guard searchResults.isEmpty else { return }
        let fallback = searchFallbackStations(for: request)
        guard !fallback.isEmpty else { return }
        searchResults = fallback
    }

    private func searchFallbackStations(for request: AppShellSearchRequest) -> [Station] {
        guard request.query.isEmpty else { return [] }

        let candidates = AppShellHomeFeed.mergeUniqueStations(
            primary: homeSnapshot.stations,
            secondary: defaultEditorialStations,
            limit: request.searchLimit
        )
        let filtered = AppShellSearch.localUITestSearchResults(samples: candidates, request: request)
        if !filtered.isEmpty {
            return filtered
        }
        return request.tag == nil && request.countryCode == nil ? candidates : []
    }

    private func shouldLoadSearchResults(for request: AppShellSearchRequest) -> Bool {
        selectedTab == .search ||
            !request.query.isEmpty ||
            request.tag != nil ||
            request.countryCode != nil
    }

    private var defaultEditorialStations: [Station] {
        AppShellHomeFeed.defaultEditorialStations(
            currentStation: audioPlayer.currentStation.map(enrichedStation),
            recentStations: enrichedRecentStations,
            favoriteStations: enrichedFavoriteStations
        )
    }

    private func resolvedDeviceCountryCode() -> String? {
        AppShellHomeFeed.resolvedDeviceCountryCode()
    }

    private func hasResolvedCountry(_ station: Station) -> Bool {
        station.hasResolvedCountry(
            unknownCountryValues: Station.unknownCountryValues,
            locale: L10n.locale
        )
    }
}

private extension Station {
    var hasBackendEnrichment: Bool {
        canonicalStationId != nil ||
            category != nil ||
            visibility != nil ||
            qualityScore != nil ||
            enrichmentStatus != nil ||
            artwork != nil ||
            editorial != nil
    }

    var enrichmentRank: Int {
        var rank = 0

        if canonicalStationId != nil { rank += 1 }
        if category != nil { rank += 1 }
        if visibility != nil { rank += 1 }
        if qualityScore != nil { rank += 1 }
        if enrichmentStatus == "enriched" { rank += 4 }
        else if enrichmentStatus != nil { rank += 1 }

        if let artwork, artwork.status != "none" || artwork.url != nil {
            rank += 2
        }

        if let editorial {
            rank += 6
            if editorial.discoveryProfile != nil { rank += 4 }
            rank += min(editorial.programming.count, 3)
            rank += min(editorial.audience.count, 2)
            rank += min(editorial.secondaryFormats.count, 2)
        }

        return rank
    }
}

private extension Array where Element == Station {
    func bestBackendMatch(for station: Station) -> Station? {
        first { candidate in
            candidate.id == station.id
        } ?? first { candidate in
            guard
                let candidateCanonicalID = candidate.canonicalStationId,
                let stationCanonicalID = station.canonicalStationId
            else {
                return false
            }
            return candidateCanonicalID == stationCanonicalID
        } ?? first { candidate in
            candidate.streamURL == station.streamURL
        }
    }

    func uniquedByStationID() -> [Station] {
        var seenIDs = Set<String>()
        return filter { station in
            seenIDs.insert(station.id).inserted
        }
    }
}

private struct CachedStationNowPlaying {
    let track: NowPlayingTrack
    let fetchedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 300
    }
}

private struct SelectedStationDetail: Identifiable {
    let station: Station
    let queueSource: AudioPlayerService.PlaybackQueue.Source
    let queueStations: [Station]

    var id: String {
        station.id
    }
}

private enum SelectedMusicAviDetail: Identifiable {
    case track(DiscoveredTrack)
    case artist(DiscoveryArtistSummary)

    var id: String {
        switch self {
        case .track(let discovery):
            return "track-\(discovery.discoveryID)"
        case .artist(let summary):
            return "artist-\(summary.id)"
        }
    }
}

private struct AppShellScaffold<Content: View, FooterPlayer: View>: View {
    let selectedTab: AppShellTab
    let hasFooterPlayer: Bool
    let footerBackdropHeight: CGFloat
    let searchAction: () -> Void
    let aviAction: () -> Void
    let selectTab: (AppShellTab) -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footerPlayer: () -> FooterPlayer

    @Namespace private var footerSelectionAnimation

    var body: some View {
        ZStack {
            TuneAVTheme.shellBackground.ignoresSafeArea()

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            footer
        }
    }

    private var footer: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    TuneAVTheme.footerBackdrop.opacity(0),
                    TuneAVTheme.footerBackdrop.opacity(0.94),
                    TuneAVTheme.footerBackdrop
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: footerBackdropHeight)
            .allowsHitTesting(false)

            VStack(spacing: 10) {
                footerPlayer()

                HStack(spacing: 18) {
                    HStack {
                        AppShellFooterTabButton(
                            title: L10n.string("tab.home"),
                            systemImage: "house.fill",
                            isSelected: selectedTab == .home,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.home"
                        ) {
                            selectTab(.home)
                        }

                        AppShellFooterTabButton(
                            title: L10n.string("tab.library"),
                            systemImage: "dot.radiowaves.left.and.right",
                            isSelected: selectedTab == .library,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.library"
                        ) {
                            selectTab(.library)
                        }

                        AppShellFooterTabButton(
                            title: L10n.string("tab.music"),
                            systemImage: "music.note.list",
                            isSelected: selectedTab == .music,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.music"
                        ) {
                            selectTab(.music)
                        }

                        AppShellFooterTabButton(
                            title: L10n.string("tab.search"),
                            systemImage: "magnifyingglass",
                            isSelected: selectedTab == .search,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.search"
                        ) {
                            searchAction()
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 10)
                    .padding(.vertical, 7)
                    .background {
                        Capsule(style: .continuous)
                            .fill(TuneAVTheme.footerGlass)
                            .background(.ultraThinMaterial.opacity(0.95), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(TuneAVTheme.glassStroke, lineWidth: 1)
                            }
                        }
                    .shadow(color: TuneAVTheme.glassShadow, radius: 18, y: 10)

                    AppShellFooterAviButton(isSelected: selectedTab == .avi) {
                        aviAction()
                    }
                    .shadow(color: TuneAVTheme.glassShadow, radius: 18, y: 10)
                }
                .frame(maxWidth: 430)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, -8)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct AppShellFooterTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(TuneAVTheme.footerGlassSelected)
                        .matchedGeometryEffect(id: "footerSelection", in: selectionNamespace)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(TuneAVTheme.glassStroke, lineWidth: 0.8)
                        }
                }

                Image(systemName: displayedSystemImage)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .frame(width: 20, height: 20)
                    .symbolRenderingMode(.monochrome)
            }
            .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
            .frame(width: 64, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var displayedSystemImage: String {
        guard !isSelected else { return systemImage }
        return systemImage.replacingOccurrences(of: ".fill", with: "")
    }
}

private struct AppShellFooterAviButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(TuneAVTheme.footerGlass)
                    .background(.ultraThinMaterial.opacity(0.95), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(TuneAVTheme.glassStroke, lineWidth: 1)
                    }

                if isSelected {
                    Circle()
                        .fill(TuneAVTheme.footerGlassSelected)
                        .padding(4)

                    Circle()
                        .fill(TuneAVTheme.highlight.opacity(0.14))
                        .padding(9)
                }

                Image("AviFooterIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: isSelected ? 42 : 40, height: isSelected ? 32 : 30)
                    .opacity(isSelected ? 1 : 0.84)
                    .saturation(isSelected ? 1.06 : 0.82)
                    .padding(8)
                    .shadow(color: TuneAVTheme.highlight.opacity(isSelected ? 0.24 : 0), radius: 6, y: 2)
            }
            .frame(width: 62, height: 62)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.avi.title"))
        .accessibilityIdentifier("tab.avi")
    }
}

private struct AviExpandedFooterPlayerView: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    let station: Station
    let openPlayer: () -> Void
    let showArtworkZoom: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("shell.common.playingNow"))
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    audioPlayer.stopAndClearCurrentStation()
                } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(TuneAVTheme.cardSurface, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.accessibility.stopListening"))
                .accessibilityIdentifier("avi.footerPlayer.stop")
            }

            HStack(spacing: 14) {
                Button(action: showArtworkZoom) {
                    artwork
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.accessibility.zoomArtwork"))
                .accessibilityIdentifier("avi.footerPlayer.artworkZoom")

                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(artistLine)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(trackArtworkExists ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(titleLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.88))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 18) {
                Spacer(minLength: 0)

                queueButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.footerPlayer.previous") {
                    audioPlayer.playPreviousInQueue()
                }

                Button {
                    audioPlayer.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(audioPlayer.isPlaying ? TuneAVTheme.brandGraphite : TuneAVTheme.highlight)

                        if audioPlayer.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 62, height: 62)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avi.footerPlayer.playPause")

                queueButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.footerPlayer.next") {
                    audioPlayer.playNextInQueue()
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [TuneAVTheme.glassStroke, TuneAVTheme.highlight.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: TuneAVTheme.glassShadow.opacity(0.7), radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: openPlayer)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("shell.miniPlayer.accessibility.label", station.name))
        .accessibilityHint(L10n.string("shell.miniPlayer.accessibility.hint"))
        .accessibilityIdentifier("avi.footerPlayer.container")
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            if let artworkURL = audioPlayer.currentTrackArtworkURL {
                TuneAVRemoteArtworkImage(url: artworkURL, size: 72, scale: displayScale) {
                    StationArtworkView(station: station, size: 72)
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 72), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 72), style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.55), lineWidth: 1)
                }
            } else {
                StationArtworkView(
                    station: station,
                    size: 72,
                    animationOverlay: .none,
                    isAnimationActive: false
                )
            }

            if let feedback = currentTrackFeedback {
                Image(systemName: feedback.systemImage)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(feedback == .liked ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse)
                    .frame(width: 24, height: 24)
                    .background(feedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.86), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.78), lineWidth: 1)
                    }
                    .offset(x: -5, y: -5)
            }
        }
    }

    private var artistLine: String {
        stationDisplayLines.artistLine
    }

    private var titleLine: String {
        stationDisplayLines.titleLine
    }

    private var stationDisplayLines: TuneAVStationDisplayLines {
        TuneAVStationDisplayLines.resolve(
            station: station,
            isCurrent: audioPlayer.isCurrent(station),
            currentArtist: audioPlayer.currentTrackArtist,
            currentTitle: audioPlayer.currentTrackTitle,
            currentAlbumTitle: audioPlayer.currentTrackAlbumTitle,
            nowPlayingTrack: nil,
            detailText: station.cardDetailText(preferCountryName: station.flagEmoji == nil)
                ?? L10n.string("shell.station.row.defaultDetail"),
            liveFallback: L10n.string("player.track.liveStreamActive")
        )
    }

    private var trackArtworkExists: Bool {
        audioPlayer.currentTrackArtworkURL != nil
    }

    private var currentTrackFeedback: TuneAVStationFeedback? {
        libraryStore.feedbackForDiscoveredTrack(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist
        )
    }

    private func queueButton(
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(audioPlayer.canCyclePlaybackQueue ? TuneAVTheme.textSecondary : TuneAVTheme.textSecondary.opacity(0.28))
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial.opacity(audioPlayer.canCyclePlaybackQueue ? 1 : 0.45), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(audioPlayer.canCyclePlaybackQueue ? 0.12 : 0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!audioPlayer.canCyclePlaybackQueue)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct AppShellArtworkZoomOverlay: View {
    @Environment(\.displayScale) private var displayScale

    let station: Station
    let artworkURL: URL?
    let title: String
    let subtitle: String
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.42))
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: 14) {
                artwork
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 18)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 280)
            }
            .padding(20)
        }
        .accessibilityIdentifier("avi.footerPlayer.artworkZoomOverlay")
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL {
            TuneAVRemoteArtworkImage(url: artworkURL, size: 268, scale: displayScale) {
                StationArtworkView(station: station, size: 268)
            }
            .frame(width: 268, height: 268)
            .clipShape(artworkShape)
            .overlay {
                artworkShape
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            StationArtworkView(
                station: station,
                size: 268,
                animationOverlay: .none,
                isAnimationActive: false
            )
        }
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 268), style: .continuous)
    }
}

private struct DetailTopHeader: View {
    let title: String
    var entityName: String? = nil
    let subtitle: String
    var status: String?
    var feedback: TuneAVStationFeedback?
    var showsBackButton = true
    var accessibilityIdentifier: String
    let goBack: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            if showsBackButton {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(TuneAVTheme.elevatedSurface, in: Circle())
                        .overlay {
                            Circle().stroke(TuneAVTheme.borderSubtle.opacity(0.52), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("common.back"))
                .accessibilityIdentifier("\(accessibilityIdentifier).back")
            } else {
                AviStableEmotionImage(emotion: .focused, assetVariant: .head, width: 40)
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                    .overlay {
                        Circle().stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if let status {
                        Text(status)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)
                            .lineLimit(1)
                    }

                    if let feedback {
                        feedbackBadge(feedback)
                    }
                }

                Text(title)
                    .font(.system(size: entityName == nil ? 25 : 15, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(entityName == nil ? 2 : 1)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                if let entityName {
                    Text(entityName)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func feedbackBadge(_ feedback: TuneAVStationFeedback) -> some View {
        Image(systemName: feedback.systemImage)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(feedback == .liked ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse)
            .frame(width: 20, height: 20)
            .background(feedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.86), in: Circle())
            .overlay {
                Circle().stroke(Color.white.opacity(0.74), lineWidth: 1)
            }
    }
}

private struct FullPlayerAviHeader: View {
    let emotion: TuneAVAviEmotion
    let reactionEmotion: TuneAVAviEmotion?
    let reactionStartedAt: Date?
    let label: String
    let title: String
    let summary: String

    private var accessibilityState: String {
        let activeEmotion = reactionEmotion ?? emotion
        let mode = reactionEmotion == nil ? "static" : "reaction"
        return "\(mode):\(activeEmotion.assetName)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            AviReactionEmotionImage(
                emotion: emotion,
                reactionEmotion: reactionEmotion,
                reactionStartedAt: reactionStartedAt,
                width: 82,
                height: 82
            )
                .frame(width: 86, height: 86)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                .overlay {
                    Circle().stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
                }
                .accessibilityLabel(L10n.string("shell.avi.title"))

            VStack(alignment: .leading, spacing: 7) {
                Text(label)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(title)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(summary)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityValue(accessibilityState)
        .accessibilityIdentifier("avi.fullPlayer.header")
    }
}

private struct AviReactionEmotionImage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let emotion: TuneAVAviEmotion
    let reactionEmotion: TuneAVAviEmotion?
    let reactionStartedAt: Date?
    let width: CGFloat
    let height: CGFloat

    @State private var displayedEmotion: TuneAVAviEmotion
    @State private var lastEmotionChange = Date.distantPast

    init(
        emotion: TuneAVAviEmotion,
        reactionEmotion: TuneAVAviEmotion?,
        reactionStartedAt: Date?,
        width: CGFloat,
        height: CGFloat
    ) {
        self.emotion = emotion
        self.reactionEmotion = reactionEmotion
        self.reactionStartedAt = reactionStartedAt
        self.width = width
        self.height = height
        _displayedEmotion = State(initialValue: emotion)
    }

    private var activeEmotion: TuneAVAviEmotion {
        reactionEmotion ?? displayedEmotion
    }

    private var frames: [String] {
        guard reactionEmotion != nil, !reduceMotion else { return [activeEmotion.fullBodyAssetName] }
        return AviReactionFrames.frames(for: activeEmotion)
    }

    private var accessibilityState: String {
        let mode = reactionEmotion == nil ? "static" : "reaction"
        return "\(mode):\(activeEmotion.assetName)"
    }

    var body: some View {
        Group {
            if reactionEmotion != nil, !reduceMotion {
                TimelineView(.periodic(from: .now, by: AviReactionFrames.frameDuration)) { timeline in
                    let elapsed = reactionStartedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                    let frameIndex = AviReactionFrames.frameIndex(
                        elapsed: elapsed,
                        frameCount: frames.count
                    )

                    aviImage(named: frames[frameIndex])
                        .modifier(AviReactionMotion(emotion: activeEmotion, elapsed: elapsed))
                }
            } else {
                aviImage(named: activeEmotion.fullBodyAssetName)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .animation(.snappy(duration: 0.16), value: frames)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("shell.avi.title"))
        .accessibilityValue(accessibilityState)
        .accessibilityIdentifier("avi.fullPlayer.emotion")
        .onAppear {
            displayedEmotion = emotion
            lastEmotionChange = Date()
        }
        .onChange(of: emotion) { _, candidate in
            adopt(candidate)
        }
        .task(id: emotion) {
            await adoptWhenAllowed(emotion)
        }
    }

    private func aviImage(named assetName: String) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
    }

    private func adopt(_ candidate: TuneAVAviEmotion) {
        let now = Date()
        guard TuneAVAviEmotionStability.shouldAdopt(
            displayed: displayedEmotion,
            candidate: candidate,
            elapsedSinceLastChange: now.timeIntervalSince(lastEmotionChange)
        ) else { return }

        displayedEmotion = candidate
        lastEmotionChange = now
    }

    @MainActor
    private func adoptWhenAllowed(_ candidate: TuneAVAviEmotion) async {
        guard displayedEmotion != candidate else { return }
        let minimumInterval = candidate.transitionPriority > displayedEmotion.transitionPriority
            ? TuneAVAviEmotionStability.immediateMinimumDisplayInterval
            : TuneAVAviEmotionStability.defaultMinimumDisplayInterval
        let elapsed = Date().timeIntervalSince(lastEmotionChange)
        let remaining = max(0, minimumInterval - elapsed)
        if remaining > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        adopt(candidate)
    }
}

private enum AviReactionFrames {
    static let frameDuration: TimeInterval = 1.0 / 12.0

    private static let listeningIdleFrames = availableFrames(for: "AviTuneListeningIdle", count: 20)
    private static let happyReactFrames = availableFrames(for: "AviTuneHappyReact", count: 20)
    private static let savedFrames = availableFrames(for: "AviTuneSaved", count: 20)
    private static let curiousFrames = availableFrames(for: "AviTuneCurious", count: 20)
    private static let thinkingFrames = availableFrames(for: "AviTuneThinking", count: 20)
    private static let dislikeFrames = availableFrames(for: "AviTuneDislike", count: 20)
    private static let surprisedFrames = availableFrames(for: "AviTuneSurprised", count: 20)
    private static let calmIdleFrames = availableFrames(for: "AviTuneCalmIdle", count: 20)
    private static let sleepIdleFrames = availableFrames(for: "AviTuneSleepIdle", count: 20)

    static func frameIndex(elapsed: TimeInterval, frameCount: Int) -> Int {
        guard frameCount > 1 else { return 0 }
        let tick = Int((max(0, elapsed) / frameDuration).rounded(.down))
        return tick % frameCount
    }

    static func frames(for emotion: TuneAVAviEmotion) -> [String] {
        switch emotion {
        case .neutral, .listening, .focused:
            return listeningIdleFrames ?? [emotion.fullBodyAssetName]
        case .happy, .liked, .celebrate:
            return happyReactFrames ?? [emotion.fullBodyAssetName]
        case .saved:
            return savedFrames ?? happyReactFrames ?? [emotion.fullBodyAssetName]
        case .curious:
            return curiousFrames ?? [emotion.fullBodyAssetName]
        case .thinking:
            return thinkingFrames ?? [emotion.fullBodyAssetName]
        case .dislike, .warning:
            return dislikeFrames ?? [emotion.fullBodyAssetName]
        case .surprised:
            return surprisedFrames ?? [emotion.fullBodyAssetName]
        case .calm:
            return calmIdleFrames ?? sleepIdleFrames ?? [emotion.fullBodyAssetName]
        case .sleep:
            return sleepIdleFrames ?? [emotion.fullBodyAssetName]
        }
    }

    private static func availableFrames(for prefix: String, count: Int) -> [String]? {
        let names = (0..<count).map { "\(prefix)\(String(format: "%03d", $0))" }
        let existing = names.filter { UIImage(named: $0) != nil }
        return existing.count >= 2 ? existing : nil
    }
}

private struct AviReactionMotion: ViewModifier {
    let emotion: TuneAVAviEmotion
    let elapsed: TimeInterval

    func body(content: Content) -> some View {
        let values = motionValues
        content
            .scaleEffect(values.scale)
            .rotationEffect(.degrees(values.rotation))
            .offset(x: values.x, y: values.y)
    }

    private var motionValues: (scale: CGFloat, rotation: Double, x: CGFloat, y: CGFloat) {
        let progress = min(max(elapsed / 1.45, 0), 1)
        let envelope = CGFloat(max(0.18, 1 - progress))
        let wave = CGFloat(sin(elapsed * .pi * 5.5))

        switch emotion {
        case .celebrate, .happy, .liked, .saved:
            return (
                scale: 1 + (0.075 * envelope * abs(wave)),
                rotation: Double(5.5 * envelope * wave),
                x: 0,
                y: -7 * envelope * abs(wave)
            )
        case .surprised:
            return (
                scale: 1 + (0.09 * envelope * abs(wave)),
                rotation: Double(-3.5 * envelope * wave),
                x: 0,
                y: -6 * envelope * abs(wave)
            )
        case .thinking, .focused, .curious:
            return (
                scale: 1 + (0.025 * envelope * abs(wave)),
                rotation: Double(4 * envelope * CGFloat(sin(elapsed * .pi * 3))),
                x: 4 * envelope * CGFloat(sin(elapsed * .pi * 2)),
                y: 0
            )
        case .dislike, .warning:
            return (
                scale: 1,
                rotation: Double(-4.5 * envelope * abs(wave)),
                x: 5 * envelope * CGFloat(sin(elapsed * .pi * 7)),
                y: 2.5 * envelope * abs(wave)
            )
        case .neutral, .listening, .calm, .sleep:
            return (
                scale: 1 + (0.04 * envelope * abs(wave)),
                rotation: 0,
                x: 0,
                y: -3 * envelope * abs(wave)
            )
        }
    }
}

private let shellScrollCoordinateSpace = "shellScrollCoordinateSpace"
private let shellScreenHorizontalPadding: CGFloat = 20
private let shellScreenTopPadding: CGFloat = 24

private struct ActiveListeningSession {
    let station: Station
    let startedAt: Date
    let source: String
    var trackKeys: Set<String>
}

private extension TuneAVPlaybackQueueSource {
    var analyticsSource: String {
        switch self {
        case .searchResults:
            return "search"
        case .libraryFavorites, .libraryRecents:
            return "library"
        case .homeRecents, .homeFavorites, .homeDiscovery:
            return "home"
        case .singleStation:
            return "player"
        }
    }
}

private enum TuneAVHaptics {
    @MainActor
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

extension View {
    func shellScreenContentPadding(bottom bottomPadding: CGFloat) -> some View {
        padding(.horizontal, shellScreenHorizontalPadding)
            .padding(.top, shellScreenTopPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func shellScreenScrollBehavior() -> some View {
        contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollIndicators(.hidden)
    }
}

private struct ShellScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ShellScrollOffsetReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ShellScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named(shellScrollCoordinateSpace)).minY
            )
        }
        .frame(height: 0)
    }
}

private struct ShellScrollAwareHeader: View {
    let statusTitle: String
    let isVisible: Bool

    var body: some View {
        if isVisible {
            ShellBrandHeader(statusTitle: statusTitle)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct AviScreenHeader: View {
    let emotion: TuneAVAviEmotion
    let title: String
    let summary: String
    var status: String? = nil
    var showsAviImage = true
    var accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsAviImage {
                AviStableEmotionImage(emotion: emotion, assetVariant: .head, width: 54)
                    .accessibilityLabel(L10n.string("shell.avi.title"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 7) {
                    Text(summary)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let status {
                        Text(status)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(TuneAVTheme.highlight.opacity(0.11), in: Capsule(style: .continuous))
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private enum AviScreenReaction: Equatable {
    case newTrack
    case recognizedTrack
    case liked
    case curious
    case saved
    case disliked
    case notForMe
    case warning

    static let automaticCooldown: TimeInterval = 10

    var emotion: TuneAVAviEmotion {
        switch self {
        case .liked, .recognizedTrack:
            return .liked
        case .saved:
            return .saved
        case .newTrack:
            return .surprised
        case .curious:
            return .curious
        case .disliked, .notForMe:
            return .dislike
        case .warning:
            return .warning
        }
    }

    var durationMilliseconds: Int {
        switch self {
        case .newTrack:
            return 2200
        case .curious, .disliked, .notForMe:
            return 2600
        case .liked, .recognizedTrack, .saved:
            return 4200
        case .warning:
            return 2800
        }
    }

    var priority: Int {
        switch self {
        case .warning:
            return 100
        case .liked, .saved, .disliked, .notForMe:
            return 80
        case .recognizedTrack:
            return 70
        case .curious:
            return 60
        case .newTrack:
            return 30
        }
    }

    var usesAutomaticCooldown: Bool {
        switch self {
        case .newTrack:
            return true
        case .recognizedTrack, .liked, .curious, .saved, .disliked, .notForMe, .warning:
            return false
        }
    }
}

private enum AviDiscoveryDecision {
    case saved
    case removed
    case ignored

    var localizedHint: String {
        switch self {
        case .saved:
            return L10n.string("player.avi.feedback.savedHint")
        case .removed:
            return L10n.string("player.discovery.removed")
        case .ignored:
            return L10n.string("player.discovery.noSaveHint")
        }
    }
}

private struct AviStableEmotionImage: View {
    enum AssetVariant {
        case head
        case fullBody
    }

    let emotion: TuneAVAviEmotion
    let assetVariant: AssetVariant
    let width: CGFloat
    var height: CGFloat?

    @State private var displayedEmotion: TuneAVAviEmotion
    @State private var lastEmotionChange = Date.distantPast

    init(
        emotion: TuneAVAviEmotion,
        assetVariant: AssetVariant,
        width: CGFloat,
        height: CGFloat? = nil
    ) {
        self.emotion = emotion
        self.assetVariant = assetVariant
        self.width = width
        self.height = height
        _displayedEmotion = State(initialValue: emotion)
    }

    private var assetName: String {
        switch assetVariant {
        case .head:
            return displayedEmotion.assetName
        case .fullBody:
            return displayedEmotion.fullBodyAssetName
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .animation(.snappy(duration: 0.24), value: assetName)
            .onAppear {
                displayedEmotion = emotion
                lastEmotionChange = Date()
            }
            .onChange(of: emotion) { _, candidate in
                adopt(candidate)
            }
            .task(id: emotion) {
                await adoptWhenAllowed(emotion)
            }
    }

    private func adopt(_ candidate: TuneAVAviEmotion) {
        let now = Date()
        guard TuneAVAviEmotionStability.shouldAdopt(
            displayed: displayedEmotion,
            candidate: candidate,
            elapsedSinceLastChange: now.timeIntervalSince(lastEmotionChange)
        ) else { return }

        displayedEmotion = candidate
        lastEmotionChange = now
    }

    @MainActor
    private func adoptWhenAllowed(_ candidate: TuneAVAviEmotion) async {
        guard displayedEmotion != candidate else { return }
        let minimumInterval = candidate.transitionPriority > displayedEmotion.transitionPriority
            ? TuneAVAviEmotionStability.immediateMinimumDisplayInterval
            : TuneAVAviEmotionStability.defaultMinimumDisplayInterval
        let elapsed = Date().timeIntervalSince(lastEmotionChange)
        let remaining = max(0, minimumInterval - elapsed)
        if remaining > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        adopt(candidate)
    }
}

private func nextShellHeaderVisibility(currentOffset: CGFloat, previousOffset: inout CGFloat, currentVisibility: Bool) -> Bool {
    defer { previousOffset = currentOffset }

    if currentOffset > -18 {
        return true
    }

    let delta = currentOffset - previousOffset
    if delta < -10 {
        return false
    }
    if delta > 8 {
        return true
    }
    return currentVisibility
}

private struct AviScreen: View {
    private static let artistDetailPageSize = 12

    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var libraryStore: LibraryStore

    let currentStation: Station?
    let focusedStation: Station?
    let isFocusedStationActive: Bool
    let currentTrackTitle: String?
    let currentTrackArtist: String?
    let currentTrackArtworkURL: URL?
    let isPlaying: Bool
    let isLoading: Bool
    let canCyclePlaybackQueue: Bool
    let stations: [Station]
    let recentStations: [Station]
    let favoriteStations: [Station]
    let discoveries: [DiscoveredTrack]
    let focusedMusicDetail: SelectedMusicAviDetail?
    let isNowPlayingFullPlayer: Bool
    let stationFeedback: [String: TuneAVStationFeedback]
    let feedContext: HomeFeedContext
    let preferredTag: String
    let preferredCountryCode: String
    let bottomContentPadding: CGFloat
    let openSearch: () -> Void
    let openLibrary: () -> Void
    let openPlayer: () -> Void
    let stopPlayback: () -> Void
    let playPrevious: () -> Void
    let playNext: () -> Void
    let playStation: (Station, [Station]) -> Void
    let toggleFavorite: (Station) -> Void
    let setStationFeedback: (Station, TuneAVStationFeedback?) -> Void
    let showStationDetails: (Station, [Station]) -> Void
    let openDiscoveryInfo: (DiscoveredTrack) -> Void
    let openDiscoveryStation: (DiscoveredTrack) -> Void
    let openAccount: () -> Void
    let startSignIn: () -> Void
    let openProPaywall: () -> Void
    let closeFocusedDetail: () -> Void
    @State private var isShowingAviActions = false
    @State private var isShowingMoreAviActions = false
    @State private var isShowingFeedbackPicker = false
    @State private var aviActionsPage = 0
    @State private var isEditingRadioFeedback = false
    @State private var isShowingArtworkZoom = false
    @State private var browserDestination: BrowserDestination?
    @State private var nestedMusicDetail: SelectedMusicAviDetail?
    @State private var aviReaction: AviScreenReaction?
    @State private var aviReactionStartedAt = Date.distantPast
    @State private var aviReactionToken = UUID()
    @State private var aviDiscoveryDecision: AviDiscoveryDecision?
    @State private var lastAutomaticAviReactionIdentity = ""
    @State private var lastAutomaticAviReactionAt = Date.distantPast
    @State private var visibleArtistSongLimit = artistDetailPageSize
    @State private var visibleArtistStationLimit = artistDetailPageSize
    @State private var visibleFocusedRadioHistoryLimit = artistDetailPageSize
    @State private var openArtistDetailAviActionsID: String?
    @State private var isShowingPlanComparison = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear
                            .frame(height: 0)
                            .id("avi.detail.top")

                        if !accessController.capabilities.canAccessPremiumFeatures && focusedDetailIsEmpty {
                            aviPreviewContent
                        } else {
                            aviContextHeader

                            if focusedDetailIsEmpty {
                                aviLandingContent
                            } else if let activeMusicDetail {
                                focusedMusicExperience(activeMusicDetail)
                            } else {
                                focusedSignalExperience
                            }
                        }
                    }
                    .shellScreenContentPadding(bottom: aviScrollBottomPadding)
                }
                .shellScreenScrollBehavior()
                .onChange(of: activeDetailScrollID) { _, _ in
                    scrollToDetailTop(proxy)
                }
            }
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .sheet(isPresented: $isShowingPlanComparison) {
            AviPlanComparisonSheet(
                accessMode: accessController.accessMode,
                onPrimaryAction: primaryAviPreviewAction,
                onDismiss: { isShowingPlanComparison = false }
            )
        }
        .overlay {
            if isShowingArtworkZoom, let focusedStation {
                artworkZoomOverlay(for: focusedStation)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(30)
            }
        }
        .onChange(of: currentSongIdentity) { _, nextIdentity in
            aviDiscoveryDecision = nil
            resetTransientAviUI()
            showAviReactionForCurrentSongChange(identity: nextIdentity)
        }
        .onChange(of: focusedMusicDetail?.id) { _, _ in
            nestedMusicDetail = nil
            resetArtistDetailLimits()
        }
        .onChange(of: focusedStation?.id) { _, _ in
            visibleFocusedRadioHistoryLimit = Self.artistDetailPageSize
            openArtistDetailAviActionsID = nil
        }
        .accessibilityIdentifier("avi.screen")
    }

    private var aviPreviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            aviPreviewHero
            aviPreviewCurrentContext
            aviPreviewActions
            aviPreviewCapabilities
        }
        .padding(.bottom, 96)
        .accessibilityIdentifier("avi.preview")
    }

    private var aviPreviewHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("shell.avi.preview.eyebrow"))
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                    Text(L10n.string("shell.avi.preview.title"))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                aviHeroImage(width: 62)
                    .padding(7)
                    .background(TuneAVTheme.highlight.opacity(0.09), in: Circle())
            }

            Text(L10n.string("shell.avi.preview.detail"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.12), radius: 14, y: 7)
    }

    private var aviPreviewCurrentContext: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("shell.avi.preview.current"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: currentStation == nil ? "sparkles" : "waveform")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 38, height: 38)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(aviPreviewContextTitle)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(aviPreviewContextDetail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
        }
    }

    private var aviPreviewCapabilities: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L10n.string("shell.avi.preview.capabilities"))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .textCase(.uppercase)

            AviPreviewCapabilityRow(systemImage: "text.quote", title: L10n.string("shell.avi.preview.music.title"), detail: L10n.string("shell.avi.preview.music.detail"))
            Divider().overlay(TuneAVTheme.borderSubtle.opacity(0.45))
            AviPreviewCapabilityRow(systemImage: "dot.radiowaves.left.and.right", title: L10n.string("shell.avi.preview.radio.title"), detail: L10n.string("shell.avi.preview.radio.detail"))
            Divider().overlay(TuneAVTheme.borderSubtle.opacity(0.45))
            AviPreviewCapabilityRow(systemImage: "sparkles", title: L10n.string("shell.avi.preview.recommendations.title"), detail: L10n.string("shell.avi.preview.recommendations.detail"))
        }
        .padding(14)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
    }

    private var aviPreviewActions: some View {
        VStack(spacing: 12) {
            AviPreviewPrimaryButton(
                title: accessController.accessMode == .guest ? L10n.string("shell.avi.preview.primary.guest") : L10n.string("shell.avi.preview.primary.pro"),
                systemImage: accessController.accessMode == .guest ? "person.crop.circle.badge.plus" : "sparkles",
                accessibilityIdentifier: "avi.preview.primary",
                action: primaryAviPreviewAction
            )

            HStack(spacing: 10) {
                AviPreviewSecondaryButton(
                    title: L10n.string("shell.avi.preview.compare"),
                    systemImage: "rectangle.3.group",
                    accessibilityIdentifier: "avi.preview.compare"
                ) {
                    isShowingPlanComparison = true
                }

                AviPreviewSecondaryButton(
                    title: L10n.string("shell.avi.preview.search"),
                    systemImage: "magnifyingglass",
                    accessibilityIdentifier: "avi.preview.search",
                    action: openSearch
                )
            }
        }
    }

    private var aviPreviewContextTitle: String {
        if let currentTrackTitle, let currentTrackArtist {
            return "\(currentTrackTitle) - \(currentTrackArtist)"
        }
        if let currentStation {
            return currentStation.name
        }
        return L10n.string("shell.avi.preview.emptyTitle")
    }

    private var aviPreviewContextDetail: String {
        if currentTrackTitle != nil {
            return L10n.string("shell.avi.preview.songDetail")
        }
        if currentStation != nil {
            return L10n.string("shell.avi.preview.radioDetail")
        }
        return L10n.string("shell.avi.preview.emptyDetail")
    }

    private func primaryAviPreviewAction() {
        if accessController.accessMode == .guest {
            startSignIn()
        } else {
            openProPaywall()
        }
    }

    private func runProAviAction(_ action: () -> Void) {
        guard accessController.capabilities.canAccessPremiumFeatures else {
            openProPaywall()
            return
        }
        action()
    }

    private func runProAviActionOutsideFullPlayer(_ action: () -> Void) {
        guard isNowPlayingFullPlayer || accessController.capabilities.canAccessPremiumFeatures else {
            openProPaywall()
            return
        }
        action()
    }

    private var activeMusicDetail: SelectedMusicAviDetail? {
        nestedMusicDetail ?? focusedMusicDetail
    }

    private var activeDetailScrollID: String {
        if let activeMusicDetail {
            return "music:\(activeMusicDetail.id)"
        }
        if let focusedStation {
            return "radio:\(focusedStation.id)"
        }
        return "landing"
    }

    private func scrollToDetailTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.22)) {
                proxy.scrollTo("avi.detail.top", anchor: .top)
            }
        }
    }

    private func closeActiveDetail() {
        if nestedMusicDetail != nil {
            nestedMusicDetail = nil
        } else {
            closeFocusedDetail()
        }
    }

    private func resetArtistDetailLimits() {
        visibleArtistSongLimit = Self.artistDetailPageSize
        visibleArtistStationLimit = Self.artistDetailPageSize
        openArtistDetailAviActionsID = nil
    }

    private var focusedDetailIsEmpty: Bool {
        focusedStation == nil && activeMusicDetail == nil
    }

    private var aviScrollBottomPadding: CGFloat {
        bottomContentPadding
    }

    @ViewBuilder
    private var aviLandingContent: some View {
        if currentStation != nil {
            aviCommandCenter
            aviCurrentSignalCard
            if topRecommendation != nil {
                recommendationPanel
            }
            aviListeningSignals
        } else {
            aviCommandCenter
            if topRecommendation != nil {
                recommendationPanel
            } else {
                aviCurrentSignalCard
                quickActions
            }
            localSignals
        }
    }

    @ViewBuilder
    private var focusedSignalExperience: some View {
        if let focusedStation {
            if !isNowPlayingFullPlayer {
                VStack(alignment: .leading, spacing: 12) {
                    focusedRadioSummaryCard(for: focusedStation)
                    focusedRadioStats(for: focusedStation)
                    focusedRadioQuickActions(for: focusedStation)
                    focusedAviServices(for: focusedStation)
                    focusedRadioHistoryBlock(for: focusedStation)
                    focusedSignalInfo(for: focusedStation)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    fullPlayerAviOptionsBlock(for: focusedStation)
                    fullPlayerFeedbackBlock(for: focusedStation)
                }
            }
        }
    }

    private var aviCommandCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                aviHeroImage(width: 64)
                    .padding(6)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    Text(aviCommandEyebrow)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                    Text(aviCommandTitle)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text(aviCommandDetail)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 8) {
                if let focusedStation {
                    focusedStationPrimaryCommands(for: focusedStation)
                } else if let activeMusicDetail {
                    focusedMusicPrimaryCommands(for: activeMusicDetail)
                } else if let currentStation {
                    currentSignalPrimaryCommands(for: currentStation)
                } else {
                    defaultAviPrimaryCommands
                }
            }
            .accessibilityIdentifier("avi.commandCenter.actions")
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.22), radius: 14, y: 8)
        .accessibilityIdentifier("avi.commandCenter")
    }

    @ViewBuilder
    private func focusedStationPrimaryCommands(for station: Station) -> some View {
        AviCommandButton(
            title: hasCurrentSongContext ? L10n.string("shell.avi.actions.searchLyrics") : L10n.string("shell.avi.actions.searchPublicInfo"),
            systemImage: hasCurrentSongContext ? "text.quote" : "info.circle",
            accessibilityIdentifier: "avi.command.primary.search"
        ) {
            runProAviActionOutsideFullPlayer {
                if hasCurrentSongContext {
                    openAviSearch(for: station, destination: .web, suffix: "lyrics")
                } else {
                    openAviStationSearch(for: station)
                }
            }
        }

        AviCommandButton(
            title: L10n.string("shell.avi.actions.history"),
            systemImage: "clock.arrow.circlepath",
            accessibilityIdentifier: "avi.command.primary.history"
        ) {
            runProAviActionOutsideFullPlayer {
                showStationDetails(station, [station])
            }
        }
    }

    @ViewBuilder
    private func focusedMusicPrimaryCommands(for detail: SelectedMusicAviDetail) -> some View {
        switch detail {
        case .track(let discovery):
            AviCommandButton(
                title: L10n.string("shell.avi.actions.searchLyrics"),
                systemImage: "text.quote",
                accessibilityIdentifier: "avi.command.primary.music.lyrics"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title) lyrics")
                }
            }
            AviCommandButton(
                title: L10n.string("shell.avi.actions.searchYouTube"),
                systemImage: "play.rectangle",
                accessibilityIdentifier: "avi.command.primary.music.youtube"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .youtube)
                }
            }
            AviCommandButton(
                title: L10n.string("shell.avi.actions.searchArtist"),
                systemImage: "person.crop.circle",
                accessibilityIdentifier: "avi.command.primary.music.artist"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: discovery.artistDisplayText)
                }
            }
        case .artist(let summary):
            AviCommandButton(
                title: L10n.string("shell.avi.actions.searchArtist"),
                systemImage: "person.crop.circle",
                accessibilityIdentifier: "avi.command.primary.artist.search"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: summary.name)
                }
            }
            AviCommandButton(
                title: L10n.string("shell.avi.actions.searchYouTube"),
                systemImage: "play.rectangle",
                accessibilityIdentifier: "avi.command.primary.artist.youtube"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: summary.name, destination: .youtube)
                }
            }
            AviCommandButton(
                title: L10n.string("shell.avi.actions.findRelatedRadios"),
                systemImage: "magnifyingglass",
                accessibilityIdentifier: "avi.command.primary.artist.searchRadio"
            ) {
                runProAviActionOutsideFullPlayer {
                    openSearch()
                }
            }
        }
    }

    @ViewBuilder
    private func currentSignalPrimaryCommands(for station: Station) -> some View {
        AviCommandButton(
            title: hasCurrentSongContext ? L10n.string("shell.avi.actions.searchLyrics") : L10n.string("shell.avi.actions.searchPublicInfo"),
            systemImage: hasCurrentSongContext ? "text.quote" : "info.circle",
            accessibilityIdentifier: hasCurrentSongContext ? "avi.command.primary.searchLyrics" : "avi.command.primary.searchRadio"
        ) {
            runProAviActionOutsideFullPlayer {
                if hasCurrentSongContext {
                    openAviSearch(for: station, destination: .web, suffix: "lyrics")
                } else {
                    openAviStationSearch(for: station)
                }
            }
        }

        AviCommandButton(
            title: L10n.string("shell.avi.actions.history"),
            systemImage: "clock.arrow.circlepath",
            accessibilityIdentifier: "avi.command.primary.history"
        ) {
            runProAviActionOutsideFullPlayer {
                showStationDetails(station, [station])
            }
        }
    }

    @ViewBuilder
    private var defaultAviPrimaryCommands: some View {
        if currentStation != nil {
            AviCommandButton(
                title: L10n.string("shell.avi.action.nowPlaying"),
                systemImage: "waveform",
                accessibilityIdentifier: "avi.command.primary.currentPlayer"
            ) {
                openPlayer()
            }
        }

        AviCommandButton(
            title: L10n.string("shell.avi.action.findStation"),
            systemImage: "sparkles",
            accessibilityIdentifier: "avi.command.primary.findStation"
        ) {
            openSearch()
        }

        AviCommandButton(
            title: L10n.string("shell.avi.action.saved"),
            systemImage: "bookmark.fill",
            accessibilityIdentifier: "avi.command.primary.saved"
        ) {
            openLibrary()
        }

        if let recommendation = topRecommendation {
            AviCommandButton(
                title: L10n.string("shell.avi.recommendation.play"),
                systemImage: "play.fill",
                accessibilityIdentifier: "avi.command.primary.recommendation"
            ) {
                playStation(recommendation.station, recommendationQueue)
            }
        }
    }

    @ViewBuilder
    private var aviCurrentSignalCard: some View {
        if currentStation != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.currentSignal"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(aviCurrentSignalTitle)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)

                Text(aviCurrentSignalDetail)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.currentSignal.live")
        } else if let recommendation = topRecommendation {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("shell.avi.recommendation.title"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(recommendation.station.name)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)

                Text(recommendation.reason)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.currentSignal.recommendation")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.signals.title"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(L10n.string("shell.avi.context.emptyTitle"))
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(L10n.string("shell.avi.detail.ready"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.currentSignal.empty")
        }
    }

    @ViewBuilder
    private var aviSuggestionStack: some View {
        if topRecommendation != nil {
            recommendationPanel
        } else {
            quickActions
        }
    }

    private var aviListeningSignals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("shell.avi.signals.using"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            if hasCurrentSongContext {
                AviSignalRow(
                    title: L10n.string("shell.avi.signals.currentSong.title"),
                    detail: currentTrackArtist.map { L10n.string("shell.avi.signals.currentSong.detailWithArtist", $0) } ?? L10n.string("shell.avi.signals.currentSong.detail"),
                    systemImage: "music.note",
                    accessibilityIdentifier: "avi.signals.currentSong"
                )
            } else if let currentStation {
                AviSignalRow(
                    title: L10n.string("shell.avi.signals.currentRadio.title"),
                    detail: L10n.string("shell.avi.signals.currentRadio.detail", currentStation.name),
                    systemImage: "dot.radiowaves.left.and.right",
                    accessibilityIdentifier: "avi.signals.currentRadio"
                )
            }

            if let recommendation = topRecommendation {
                AviSignalRow(
                    title: L10n.string("shell.avi.signals.next.title"),
                    detail: "\(recommendation.station.name): \(recommendation.reason)",
                    systemImage: "sparkles",
                    accessibilityIdentifier: "avi.signals.nextRecommendation"
                )
            }

            AviSignalRow(
                title: L10n.string("shell.avi.signals.feedback.title"),
                detail: feedbackSignalCount == 0 ? L10n.string("shell.avi.signals.feedback.emptyDetail") : L10n.plural(singular: "shell.avi.signals.feedback.count.one", plural: "shell.avi.signals.feedback.count.other", count: feedbackSignalCount, feedbackSignalCount),
                systemImage: "hand.thumbsup",
                accessibilityIdentifier: "avi.signals.feedback"
            )
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.6), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func focusedMusicExperience(_ detail: SelectedMusicAviDetail) -> some View {
        switch detail {
        case .track(let discovery):
            focusedTrackInfo(discovery)
        case .artist(let summary):
            focusedArtistInfo(summary)
        }
    }

    private func focusedTrackInfo(_ discovery: DiscoveredTrack) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            focusedTrackSummaryCard(discovery)
            focusedTrackQuickActions(discovery)
            focusedTrackStats(discovery)
            focusedMusicAviServices(for: .track(discovery))
            focusedTrackArticle(discovery)
            trackStationsBlock(discovery)
        }
    }

    private func focusedTrackArticle(_ discovery: DiscoveredTrack) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("shell.stationInfo.title"))
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                AviSignalInfoLine(title: L10n.string("shell.avi.music.artist.label"), value: discovery.artistDisplayText)
                AviSignalInfoLine(title: L10n.string("shell.avi.music.station"), value: discovery.stationName)
                AviSignalInfoLine(title: L10n.string("shell.avi.music.lastSeen"), value: discovery.playedAt.formatted(date: .abbreviated, time: .shortened))
                AviSignalInfoLine(
                    title: L10n.string("shell.avi.music.feedback"),
                    value: libraryStore.feedback(for: discovery)?.localizedState ?? L10n.string("shell.avi.music.feedback.empty")
                )
                AviSignalInfoLine(
                    title: L10n.string("shell.stationInfo.summary"),
                    value: L10n.string("shell.avi.music.track.future")
                )
            }
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.2), radius: 12, y: 6)
    }

    private func focusedTrackSummaryCard(_ discovery: DiscoveredTrack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                discoveryArtwork(discovery, size: 62)
                    .overlay(alignment: .topLeading) {
                        if let feedback = libraryStore.feedback(for: discovery) {
                            feedbackStatusBadge(feedback, size: 24)
                                .offset(x: -5, y: -5)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(discovery.title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text("\(discovery.artistDisplayText) · \(discovery.stationName)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)

                    Text("\(L10n.string("shell.avi.music.lastSeen")) · \(discovery.playedAt.formatted(date: .numeric, time: .omitted))")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.16), radius: 10, y: 5)
    }

    private func focusedTrackQuickActions(_ discovery: DiscoveredTrack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    toggleDiscoverySaved(discovery)
                } label: {
                    Label(
                        discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                        systemImage: discovery.isMarkedInteresting ? "bookmark.slash" : "bookmark"
                    )
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(discovery.isMarkedInteresting ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(discovery.isMarkedInteresting ? TuneAVTheme.highlight.opacity(0.34) : TuneAVTheme.borderSubtle, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avi.detail.track.save")

                Button {
                    nestedMusicDetail = .artist(discoveryArtistSummary(for: discovery))
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.actions.searchArtist"))
            }

            StationFeedbackControl(
                selectedFeedback: libraryStore.feedback(for: discovery),
                selectFeedback: { feedback in
                    let nextFeedback = libraryStore.feedback(for: discovery) == feedback ? nil : feedback
                    libraryStore.setFeedbackForDiscoveredTrack(nextFeedback, title: discovery.title, artist: discovery.artist)
                },
                clearFeedback: {
                    libraryStore.setFeedbackForDiscoveredTrack(nil, title: discovery.title, artist: discovery.artist)
                }
            )
        }
        .padding(12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }

    private func discoveryArtistSummary(for discovery: DiscoveredTrack) -> DiscoveryArtistSummary {
        DiscoveryArtistSummary(
            name: discovery.artistDisplayText,
            trackCount: 1,
            artistArtworkURL: discovery.resolvedArtworkURL,
            fallbackArtworkURL: discovery.resolvedStationArtworkURL
        )
    }

    private func focusedTrackStats(_ discovery: DiscoveredTrack) -> some View {
        HStack(spacing: 7) {
            ArtistStatPill(
                title: L10n.string("shell.avi.music.artist.label"),
                value: discovery.artistDisplayText,
                systemImage: "person.fill"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.station"),
                value: discovery.stationName,
                systemImage: "dot.radiowaves.left.and.right"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.feedback"),
                value: libraryStore.feedback(for: discovery)?.localizedState ?? L10n.string("shell.avi.music.feedback.empty"),
                systemImage: "heart.fill"
            )
        }
    }

    private func focusedArtistInfo(_ summary: DiscoveryArtistSummary) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            focusedArtistArticle(summary)
        }
    }

    private func focusedArtistArticle(_ summary: DiscoveryArtistSummary) -> some View {
        let discoveries = artistDiscoveries(for: summary)
        let savedSongs = discoveries.filter(\.isMarkedInteresting)
        let stationCount = artistStationSummaries(for: summary).count

        return VStack(alignment: .leading, spacing: 12) {
            focusedArtistSummaryCard(summary, discoveries: discoveries)
            focusedArtistStats(summary, savedSongsCount: savedSongs.count, stationCount: stationCount)
            focusedMusicAviServices(for: .artist(summary))
            artistSavedSongsBlock(summary, savedSongs: savedSongs)
            artistStationsBlock(summary)
        }
    }

    private func focusedArtistSummaryCard(_ summary: DiscoveryArtistSummary, discoveries: [DiscoveredTrack]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artistArtwork(summary, size: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.name)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(artistSummaryLine(summary))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)

                    if let latestDiscovery = latestDiscovery(for: summary) {
                        Text("\(L10n.string("shell.avi.music.latestSong")) · \(latestDiscovery.title)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.16), radius: 10, y: 5)
    }

    private func focusedArtistStats(_ summary: DiscoveryArtistSummary, savedSongsCount: Int, stationCount: Int) -> some View {
        HStack(spacing: 7) {
            ArtistStatPill(
                title: L10n.string("shell.avi.music.artist.savedSongs"),
                value: "\(savedSongsCount)",
                systemImage: "bookmark.fill"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.artist.radios"),
                value: "\(stationCount)",
                systemImage: "dot.radiowaves.left.and.right"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.lastSeen"),
                value: latestDiscovery(for: summary)?.playedAt.formatted(date: .numeric, time: .omitted) ?? L10n.string("shell.avi.music.feedback.empty"),
                systemImage: "clock.fill"
            )
        }
    }

    private func artistSummaryLine(_ summary: DiscoveryArtistSummary) -> String {
        let songCount = L10n.plural(
            singular: "shell.library.discoveries.artistSongs.one",
            plural: "shell.library.discoveries.artistSongs.other",
            count: summary.trackCount,
            summary.trackCount
        )
        guard let latestDiscovery = latestDiscovery(for: summary) else { return songCount }
        return "\(songCount) · \(latestDiscovery.stationName)"
    }

    private func focusedMusicAviServices(for detail: SelectedMusicAviDetail) -> some View {
        ZStack(alignment: .topLeading) {
            if isShowingAviActions {
                AviRowActionsPanel(close: closeAviActions) {
                    focusedMusicPrimaryCommands(for: detail)
                }
                .transition(.opacity)
            } else {
                detailAskAviCollapsedContent {
                    isShowingAviActions = true
                    isShowingMoreAviActions = false
                    isShowingFeedbackPicker = false
                    isEditingRadioFeedback = false
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isShowingAviActions ? 316 : 168, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 12, y: 6)
    }

    private func focusedAviServices(for station: Station) -> some View {
        ZStack(alignment: .topLeading) {
            if isShowingAviActions {
                aviActionsPanel(for: station)
                    .transition(.opacity)
            } else {
                detailAskAviCollapsedContent {
                    isShowingAviActions = true
                    aviActionsPage = 0
                    isShowingMoreAviActions = false
                    isShowingFeedbackPicker = false
                    isEditingRadioFeedback = false
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isShowingAviActions ? 316 : 168, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 12, y: 6)
    }

    private func detailAskAviCollapsedContent(open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("shell.avi.actions.ask"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(aviPrimaryLine)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    open()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .black))
                    Text(L10n.string("player.avi.moreWithAvi"))
                        .font(.system(size: 15, weight: .black))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .black))
                }
                .foregroundStyle(TuneAVTheme.brandBlack)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("avi.actions.toggle")
        }
    }

    @ViewBuilder
    private func artistSavedSongsBlock(_ summary: DiscoveryArtistSummary, savedSongs: [DiscoveredTrack]) -> some View {
        let visibleSavedSongs = Array(savedSongs.prefix(visibleArtistSongLimit))
        let remainingCount = max(0, savedSongs.count - visibleSavedSongs.count)
        if !savedSongs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.music.artist.savedSongs"))
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                ForEach(visibleSavedSongs) { discovery in
                    DiscoveryTrackCard(
                        discovery: discovery,
                        stationArtworkURL: nil,
                        feedback: libraryStore.feedback(for: discovery),
                        showsSaveButton: false,
                        openAviActionsID: $openArtistDetailAviActionsID,
                        openTrackInfo: { nestedMusicDetail = .track(discovery) },
                        openArtistInfo: { nestedMusicDetail = .artist(discoveryArtistSummary(for: discovery)) },
                        openStationInfo: { openDiscoveryStation(discovery) },
                        toggleSaved: { toggleDiscoverySaved(discovery) },
                        openYouTube: {
                            runProAviAction {
                                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .youtube)
                            }
                        },
                        openLyrics: {
                            runProAviAction {
                                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title) lyrics")
                            }
                        },
                        openAppleMusic: {
                            runProAviAction {
                                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .appleMusic)
                            }
                        },
                        openSpotify: {
                            runProAviAction {
                                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .spotify)
                            }
                        },
                        hideAction: nil,
                        removeAction: nil
                    )
                }

                if remainingCount > 0 {
                    ShowMoreButton(
                        title: L10n.string("shell.avi.music.artist.savedSongs"),
                        remainingCount: remainingCount,
                        action: {
                            visibleArtistSongLimit += Self.artistDetailPageSize
                        }
                    )
                }
            }
            .padding(14)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private func artistStationsBlock(_ summary: DiscoveryArtistSummary) -> some View {
        let stations = artistStationSummaries(for: summary)
        let visibleStations = Array(stations.prefix(visibleArtistStationLimit))
        let resolvedVisibleStations = visibleStations.compactMap { station -> (station: Station, count: Int)? in
            guard let resolvedStation = artistStation(for: station.id) else { return nil }
            return (resolvedStation, station.count)
        }
        let remainingCount = max(0, stations.count - visibleStations.count)
        if !resolvedVisibleStations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.music.artist.radios"))
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                ForEach(resolvedVisibleStations, id: \.station.id) { station in
                    StationListActionRow(
                        station: station.station,
                        isFavorite: favoriteStations.contains { $0.id == station.station.id },
                        nowPlayingTrack: nil,
                        stationFeedback: stationFeedback[station.station.id],
                        toggleFavorite: { toggleFavorite(station.station) },
                        playAction: { playStation(station.station, [station.station]) },
                        openWebsiteAction: {
                            if let url = station.station.resolvedHomepageURL {
                                browserDestination = BrowserDestination(url: url)
                            }
                        },
                        detailsAction: { showStationDetails(station.station, [station.station]) }
                    )
                }

                if remainingCount > 0 {
                    ShowMoreButton(
                        title: L10n.string("shell.avi.music.artist.radios"),
                        remainingCount: remainingCount,
                        action: {
                            visibleArtistStationLimit += Self.artistDetailPageSize
                        }
                    )
                }
            }
            .padding(14)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private func trackStationsBlock(_ discovery: DiscoveredTrack) -> some View {
        let stations = trackStationSummaries(for: discovery)
        let resolvedStations = stations.compactMap { station -> (station: Station, count: Int)? in
            guard let resolvedStation = artistStation(for: station.id) else { return nil }
            return (resolvedStation, station.count)
        }
        if !resolvedStations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.avi.music.artist.radios"))
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                ForEach(resolvedStations, id: \.station.id) { station in
                    StationListActionRow(
                        station: station.station,
                        isFavorite: favoriteStations.contains { $0.id == station.station.id },
                        nowPlayingTrack: nil,
                        stationFeedback: stationFeedback[station.station.id],
                        toggleFavorite: { toggleFavorite(station.station) },
                        playAction: { playStation(station.station, [station.station]) },
                        openWebsiteAction: {
                            if let url = station.station.resolvedHomepageURL {
                                browserDestination = BrowserDestination(url: url)
                            }
                        },
                        detailsAction: { showStationDetails(station.station, [station.station]) }
                    )
                }
            }
            .padding(14)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private func discoveryArtwork(_ discovery: DiscoveredTrack, size: CGFloat) -> some View {
        if let artworkURL = discovery.resolvedArtworkURL ?? discovery.resolvedStationArtworkURL {
            TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                musicArtworkFallback(systemImage: "music.note", size: size)
            }
            .frame(width: size, height: size)
            .clipShape(musicArtworkShape(size: size))
            .overlay {
                musicArtworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            musicArtworkFallback(systemImage: "music.note", size: size)
        }
    }

    @ViewBuilder
    private func artistArtwork(_ summary: DiscoveryArtistSummary, size: CGFloat) -> some View {
        if let artworkURL = summary.displayArtworkURL {
            TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                musicArtworkFallback(systemImage: "person.fill", size: size)
            }
            .frame(width: size, height: size)
            .clipShape(musicArtworkShape(size: size))
            .overlay {
                musicArtworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            musicArtworkFallback(systemImage: "person.fill", size: size)
        }
    }

    private func latestDiscovery(for summary: DiscoveryArtistSummary) -> DiscoveredTrack? {
        artistDiscoveries(for: summary).first
    }

    private func artistDiscoveries(for summary: DiscoveryArtistSummary) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(discoveries)
            .filter { normalizedArtistID($0.artistDisplayText) == summary.id }
            .sorted { $0.playedAt > $1.playedAt }
    }

    private func artistStationSummaries(for summary: DiscoveryArtistSummary) -> [(id: String, name: String, count: Int)] {
        let grouped = Dictionary(grouping: artistDiscoveries(for: summary), by: \.stationID)
        return grouped
            .map { stationID, discoveries in
                (id: stationID, name: discoveries.first?.stationName ?? stationID, count: discoveries.count)
            }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func artistStation(for stationID: String) -> Station? {
        if let station = libraryStore.station(for: stationID) {
            return station
        }
        return stations.first { $0.id == stationID }
            ?? recentStations.first { $0.id == stationID }
            ?? favoriteStations.first { $0.id == stationID }
    }

    private func trackStationSummaries(for discovery: DiscoveredTrack) -> [(id: String, name: String, count: Int)] {
        let key = focusedTrackIdentityKey(discovery)
        let grouped = Dictionary(
            grouping: TuneAVMusicLibraryLogic.visibleDiscoveries(discoveries).filter {
                focusedTrackIdentityKey($0) == key
            },
            by: \.stationID
        )
        return grouped
            .map { stationID, discoveries in
                (id: stationID, name: discoveries.first?.stationName ?? stationID, count: discoveries.count)
            }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func focusedTrackIdentityKey(_ discovery: DiscoveredTrack) -> String {
        let artist = TuneAVText.normalizedValue(discovery.artistDisplayText) ?? discovery.artistDisplayText.lowercased()
        let title = TuneAVText.normalizedValue(discovery.title) ?? discovery.title.lowercased()
        return "\(artist)|\(title)"
    }

    private func normalizedArtistID(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: L10n.locale)
            .lowercased()
    }

    private func musicArtworkFallback(systemImage: String, size: CGFloat) -> some View {
        musicArtworkShape(size: size)
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .overlay {
                musicArtworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }

    private func musicArtworkShape(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous)
    }

    private var aviContextHeader: some View {
        Group {
            if focusedDetailIsEmpty {
                AviScreenHeader(
                    emotion: aviEmotion,
                    title: L10n.string("shell.avi.title"),
                    summary: aviContextMeta,
                    showsAviImage: false,
                    accessibilityIdentifier: "avi.context.header"
                )
            } else if isNowPlayingFullPlayer, activeMusicDetail == nil {
                FullPlayerAviHeader(
                    emotion: aviEmotion,
                    reactionEmotion: aviReaction?.emotion,
                    reactionStartedAt: aviReaction == nil ? nil : aviReactionStartedAt,
                    label: aviEmotionLabel,
                    title: fullPlayerAviHeadline,
                    summary: aviPrimaryLine
                )
            } else {
                if activeMusicDetail != nil {
                    DetailTopHeader(
                        title: focusedDetailTypeTitle,
                        subtitle: aviContextTitle == aviContextMeta ? aviContextTitle : "\(aviContextTitle) · \(aviContextMeta)",
                        status: nil,
                        showsBackButton: true,
                        accessibilityIdentifier: "avi.detail.header",
                        goBack: closeActiveDetail
                    )
                } else {
                    DetailTopHeader(
                        title: focusedDetailTypeTitle,
                        subtitle: aviContextTitle == aviContextMeta ? aviContextTitle : "\(aviContextTitle) · \(aviContextMeta)",
                        status: nil,
                        feedback: focusedStation.flatMap { stationFeedback[$0.id] },
                        showsBackButton: true,
                        accessibilityIdentifier: "avi.detail.header",
                        goBack: closeFocusedDetail
                    )
                }
            }
        }
    }

    private var focusedDetailTypeTitle: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track:
                return L10n.string("shell.avi.music.track.label")
            case .artist:
                return L10n.string("shell.avi.music.artist.label")
            }
        }
        return L10n.string("shell.common.radio")
    }

    private var focusedDetailStatus: String? {
        if activeMusicDetail != nil {
            return L10n.string("tab.music")
        }
        guard focusedStation != nil else { return nil }
        return isFocusedStationActive ? L10n.string("shell.avi.status.playing") : L10n.string("shell.avi.status.info")
    }

    private var aviContextTitle: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track(let discovery):
                return discovery.title
            case .artist(let summary):
                return summary.name
            }
        }
        return focusedStation?.name ?? L10n.string("shell.avi.context.emptyTitle")
    }

    private var fullPlayerAviHeadline: String {
        return L10n.string("shell.avi.mood.vibing")
    }

    private var aviCommandEyebrow: String {
        if activeMusicDetail != nil {
            return L10n.string("tab.music")
        }
        if focusedStation != nil {
            return isFocusedStationActive ? L10n.string("shell.common.playingNow") : L10n.string("shell.common.radio")
        }
        if currentStation != nil {
            return L10n.string("shell.avi.title")
        }
        return L10n.string("shell.avi.state.thinking")
    }

    private var aviCommandTitle: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track(let discovery):
                return discovery.title
            case .artist(let summary):
                return summary.name
            }
        }
        if let focusedStation {
            return isFocusedStationActive
                ? (currentTrackTitle ?? focusedStation.name)
                : focusedStation.name
        }
        if let currentStation {
            if let currentTrackTitle {
                return currentTrackTitle
            }
            return L10n.string("shell.avi.command.tuning", currentStation.name)
        }
        return L10n.string("shell.avi.mood.ready")
    }

    private var aviCommandDetail: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track(let discovery):
                return "\(discovery.artistDisplayText) · \(discovery.stationName)"
            case .artist(let summary):
                return L10n.plural(
                    singular: "shell.library.discoveries.artistSongs.one",
                    plural: "shell.library.discoveries.artistSongs.other",
                    count: summary.trackCount,
                    summary.trackCount
                )
            }
        }
        if let focusedStation {
            if isNowPlayingFullPlayer && hasCurrentSongContext {
                return [currentTrackArtist, focusedStation.name].compactMap { $0 }.joined(separator: " · ")
            }
            return defaultPublicSignalInfo(for: focusedStation)
        }
        if let currentStation {
            if hasCurrentSongContext {
                return [currentTrackArtist, currentStation.name]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            }
            return L10n.string("shell.avi.command.readingSignal", currentStation.name)
        }
        return L10n.string("shell.avi.detail.ready")
    }

    private var aviCurrentSignalTitle: String {
        if let currentTrackTitle {
            return currentTrackTitle
        }
        if let currentStation {
            return currentStation.name
        }
        return L10n.string("shell.avi.context.emptyTitle")
    }

    private var aviCurrentSignalDetail: String {
        guard let currentStation else {
            return L10n.string("shell.avi.detail.ready")
        }

        if let currentTrackArtist {
            return L10n.string("shell.avi.currentSignal.artistDetail", currentTrackArtist, currentStation.name)
        }

        if let currentTrackTitle {
            return L10n.string("shell.avi.currentSignal.titleDetail", currentTrackTitle, currentStation.name)
        }

        return L10n.string("shell.avi.currentSignal.radioDetail", currentStation.name)
    }

    private var aviContextMeta: String {
        if let activeMusicDetail {
            switch activeMusicDetail {
            case .track(let discovery):
                return discovery.artistDisplayText
            case .artist(let summary):
                return L10n.plural(
                    singular: "shell.library.discoveries.artistSongs.one",
                    plural: "shell.library.discoveries.artistSongs.other",
                    count: summary.trackCount,
                    summary.trackCount
                )
            }
        }
        if focusedStation != nil {
            if isNowPlayingFullPlayer {
                return L10n.string("shell.avi.context.currentRadio")
            }
            return focusedStation.map(defaultPublicSignalInfo(for:)) ?? L10n.string("shell.common.radio")
        }
        if currentStation != nil {
            return L10n.string("shell.avi.primary.reacting")
        }
        return L10n.string("shell.avi.context.emptyDetail")
    }

    private func focusedRadioInfoCard(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("shell.common.radio"))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .textCase(.uppercase)

            Text(defaultPublicSignalInfo(for: station))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            listenToFocusedStationButton
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 10, y: 6)
    }

    private func focusedRadioSummaryCard(for station: Station) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StationArtworkView(station: station, size: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(defaultPublicSignalInfo(for: station))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)

                    if let latestDiscovery = stationDiscoveries.first {
                        Text("\(L10n.string("shell.avi.music.latestSong")) · \(latestDiscovery.title)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .lineLimit(1)
                    } else if libraryStore.isFavorite(station) {
                        Text(L10n.string("shell.library.favorites.title"))
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.16), radius: 10, y: 5)
    }

    private func focusedRadioStats(for station: Station) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)
        let latestDate = stationDiscoveries.first?.playedAt.formatted(date: .numeric, time: .omitted)
            ?? L10n.string("shell.avi.music.feedback.empty")

        return HStack(spacing: 7) {
            ArtistStatPill(
                title: L10n.string("shell.library.discoveries.title"),
                value: "\(stationDiscoveries.count)",
                systemImage: "music.note"
            )

            ArtistStatPill(
                title: L10n.string("shell.library.favorites.title"),
                value: libraryStore.isFavorite(station) ? L10n.string("common.yes") : L10n.string("common.no"),
                systemImage: "dot.radiowaves.left.and.right"
            )

            ArtistStatPill(
                title: L10n.string("shell.avi.music.lastSeen"),
                value: latestDate,
                systemImage: "clock.fill"
            )
        }
    }

    @ViewBuilder
    private func focusedRadioHistoryBlock(for station: Station) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)
        let visibleDiscoveries = Array(stationDiscoveries.prefix(visibleFocusedRadioHistoryLimit))
        let remainingCount = max(0, stationDiscoveries.count - visibleDiscoveries.count)
        if !stationDiscoveries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("shell.stationDetail.tab.history"))
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                ForEach(visibleDiscoveries) { discovery in
                    DiscoveryTrackCard(
                        discovery: discovery,
                        stationArtworkURL: nil,
                        feedback: libraryStore.feedback(for: discovery),
                        showsSaveButton: false,
                        openAviActionsID: $openArtistDetailAviActionsID,
                        openTrackInfo: { nestedMusicDetail = .track(discovery) },
                        openArtistInfo: { nestedMusicDetail = .artist(discoveryArtistSummary(for: discovery)) },
                        openStationInfo: { showStationDetails(station, [station]) },
                        toggleSaved: { toggleDiscoverySaved(discovery) },
                        openYouTube: {
                            runProAviAction {
                                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .youtube)
                            }
                        },
                        openLyrics: {
                            runProAviAction {
                                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title) lyrics")
                            }
                        },
                        openAppleMusic: {
                            runProAviAction {
                                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .appleMusic)
                            }
                        },
                        openSpotify: {
                            runProAviAction {
                                openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .spotify)
                            }
                        },
                        hideAction: nil,
                        removeAction: nil
                    )
                }

                if remainingCount > 0 {
                    ShowMoreButton(
                        title: L10n.string("shell.stationDetail.tab.history"),
                        remainingCount: remainingCount,
                        action: {
                            visibleFocusedRadioHistoryLimit += Self.artistDetailPageSize
                        }
                    )
                }
            }
            .padding(14)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func focusedStationDiscoveries(for station: Station) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(discoveries)
            .filter { $0.stationID == station.id }
            .sorted { $0.playedAt > $1.playedAt }
    }

    private func focusedNowPlayingCard(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center) {
                    Text(L10n.string("shell.common.playingNow"))
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                    Spacer()

                    Button {
                        stopPlayback()
                    } label: {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.9))
                            .frame(width: 32, height: 28)
                            .background(TuneAVTheme.cardSurface, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
                            }
                        }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("shell.accessibility.stopListening"))
                    .accessibilityIdentifier("avi.controls.stop")
                }

                Text(station.name)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(currentTrackTitle ?? L10n.string("player.track.liveNow"))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.74)

                Text(currentTrackArtist ?? station.primaryDetailLine)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(hasCurrentSongContext ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if isFocusedStationActive && !hasCurrentSongContext {
                    Text(L10n.string("player.avi.poorInfo"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("player.avi.poorInfo")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 10, y: 6)
    }

    private func focusedListeningDock(for station: Station) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        isShowingArtworkZoom = true
                    }
                } label: {
                    currentArtwork(for: station, size: 72)
                        .overlay(alignment: .topLeading) {
                            if let feedback = currentTrackFeedback {
                                feedbackStatusBadge(feedback, size: 24)
                                    .offset(x: -5, y: -5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.accessibility.zoomArtwork"))
                .accessibilityIdentifier("avi.nowPlaying.artworkZoom")

                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(currentTrackArtist ?? L10n.string("player.track.liveNow"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(hasCurrentSongContext ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(currentTrackTitle ?? station.primaryDetailLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.88))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("player.dock.summary")
            }

            HStack(spacing: 18) {
                Spacer(minLength: 0)

                queueDockButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.controls.previous", action: playPrevious)

                Button(action: openPlayer) {
                    ZStack {
                        Circle()
                            .fill(isPlaying ? TuneAVTheme.brandGraphite : TuneAVTheme.highlight)

                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: primaryFocusedActionIcon)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 62, height: 62)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryFocusedActionTitle)
                .accessibilityIdentifier("avi.controls.playPause")

                queueDockButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.controls.next", action: playNext)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [TuneAVTheme.glassStroke, TuneAVTheme.highlight.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: TuneAVTheme.glassShadow.opacity(0.7), radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: openPlayer)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.dock")
    }

    private func queueDockButton(
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(canCyclePlaybackQueue ? TuneAVTheme.textSecondary : TuneAVTheme.textSecondary.opacity(0.28))
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial.opacity(canCyclePlaybackQueue ? 1 : 0.45), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(canCyclePlaybackQueue ? 0.12 : 0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!canCyclePlaybackQueue)
        .accessibilityLabel(accessibilityLabel(for: systemImage))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func currentArtwork(for station: Station, size: CGFloat) -> some View {
        if let currentTrackArtworkURL {
            TuneAVRemoteArtworkImage(url: currentTrackArtworkURL, size: size, scale: displayScale) {
                StationThumbnailView(station: station, size: size, textMode: .none, animationOverlay: .none, isAnimationActive: false)
            }
            .frame(width: size, height: size)
            .clipShape(artworkShape(size: size))
            .overlay {
                artworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            StationThumbnailView(station: station, size: size, textMode: .none, animationOverlay: .none, isAnimationActive: false)
        }
    }

    private func artworkShape(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous)
    }

    private func artworkZoomOverlay(for station: Station) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.42))
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        isShowingArtworkZoom = false
                    }
            }

            VStack(spacing: 14) {
                currentArtwork(for: station, size: 268)
                    .shadow(color: .black.opacity(0.28), radius: 28, y: 18)

                VStack(spacing: 4) {
                    Text(currentTrackTitle ?? station.name)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(currentTrackArtist ?? station.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 280)
            }
            .padding(20)
        }
        .accessibilityIdentifier("avi.nowPlaying.artworkZoomOverlay")
    }

    private func focusedRadioBlock(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            focusedSignalHeader(for: station)

            if isFocusedStationActive {
                focusedNowBlock(for: station)
            }

            if !isFocusedStationActive {
                listenToFocusedStationButton
            }
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.24), radius: 14, y: 8)
    }

    private func focusedSignalHeader(for station: Station) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(station.name)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)

                    Text(isFocusedStationActive ? L10n.string("shell.avi.status.playing") : L10n.string("shell.avi.status.info"))
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(TuneAVTheme.highlight.opacity(0.11), in: Capsule(style: .continuous))
                }

                if !isFocusedStationActive {
                    Text(defaultPublicSignalInfo(for: station))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func focusedNowBlock(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("shell.common.playingNow"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Spacer()

                Text(isFocusedStationActive ? L10n.string("shell.avi.status.live") : L10n.string("shell.avi.status.info"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
            }

            Text(currentTrackTitle ?? L10n.string("player.track.liveNow"))
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.74)

            Text(focusedSignalDetail(for: station))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineLimit(3)
        }
        .padding(16)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var focusedPlayerControls: some View {
        HStack(alignment: .center, spacing: 12) {
            if isFocusedStationActive {
                listeningControlButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.controls.previous", action: playPrevious)
            }

            if isFocusedStationActive && isPlaying {
                listeningControlButton(systemImage: "stop.fill", accessibilityIdentifier: "avi.controls.stop", action: stopPlayback)
            }

            Button(action: openPlayer) {
                Image(systemName: primaryFocusedActionIcon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            if isFocusedStationActive {
                listeningControlButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.controls.next", action: playNext)
            }
        }
    }

    private var listenToFocusedStationButton: some View {
        Button(action: openPlayer) {
            focusedPlayButtonContent(height: 52, cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.accessibility.listenToRadio"))
        .accessibilityIdentifier("avi.controls.listen")
    }

    private func focusedPlayButtonContent(height: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .tint(TuneAVTheme.brandBlack)
            } else {
                Image(systemName: primaryFocusedActionIcon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func focusedFeedbackBlock(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                aviHeroImage(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isNowPlayingFullPlayer && hasCurrentSongContext ? L10n.string("player.avi.feedback.songQuestion") : L10n.string("player.avi.feedback.radioQuestion"))
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(aviPrimaryLine)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            StationFeedbackControl(
                selectedFeedback: focusedPrimaryFeedback(for: station),
                selectFeedback: { feedback in
                    setFocusedPrimaryFeedback(feedback, for: station)
                },
                clearFeedback: {
                    setFocusedPrimaryFeedback(nil, for: station)
                }
            )
        }
        .padding(14)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.6), lineWidth: 1)
        }
    }

    private func focusedAviBlock(for station: Station) -> some View {
        ZStack(alignment: .topLeading) {
            if isShowingAviActions {
                aviActionsPanel(for: station)
                    .transition(.opacity)
            } else {
                fullPlayerAviControlPanel(for: station)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 306, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.2), radius: 12, y: 6)
        .zIndex(isShowingAviActions ? 10 : 0)
    }

    private func fullPlayerAviControlPanel(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hasCurrentSongContext ? L10n.string("shell.avi.actions.songFeedback") : L10n.string("shell.avi.actions.radioFeedback"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(aviPrimaryLine)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 28, height: 28)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                Text(hasCurrentSongContext ? L10n.string("shell.avi.detail.detecting") : L10n.string("shell.avi.primary.reading"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            StationFeedbackControl(
                selectedFeedback: focusedPrimaryFeedback(for: station),
                selectFeedback: { feedback in
                    let currentFeedback = focusedPrimaryFeedback(for: station)
                    let nextFeedback = currentFeedback == feedback ? nil : feedback
                    setFocusedPrimaryFeedback(nextFeedback, for: station)
                    if let nextFeedback {
                        showAviReaction(for: nextFeedback)
                    }
                },
                clearFeedback: {
                    setFocusedPrimaryFeedback(nil, for: station)
                }
            )

            HStack(spacing: 10) {
                if !hasCurrentSongContext {
                    fullPlayerAviActionButton(
                        title: stationSaveActionTitle(for: station),
                        systemImage: stationSaveActionSystemImage(for: station),
                        accessibilityIdentifier: "avi.fullPlayer.saveRadio"
                    ) {
                        showAviReaction(.liked)
                        toggleFavorite(station)
                    }
                }

                fullPlayerAviActionButton(
                    title: L10n.string("shell.avi.actions.ask"),
                    systemImage: "sparkles",
                    accessibilityIdentifier: "avi.actions.toggle"
                ) {
                    withAnimation(.snappy(duration: 0.22)) {
                        isShowingAviActions = true
                        aviActionsPage = 0
                        isShowingMoreAviActions = false
                        isShowingFeedbackPicker = false
                        isEditingRadioFeedback = false
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func fullPlayerAviOptionsBlock(for station: Station) -> some View {
        ZStack(alignment: .topLeading) {
            if isShowingAviActions {
                aviActionsPanel(for: station)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("shell.avi.actions.ask"))
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)

                        Text(aviPrimaryLine)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            isShowingAviActions = true
                            aviActionsPage = 0
                            isShowingMoreAviActions = false
                            isShowingFeedbackPicker = false
                            isEditingRadioFeedback = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .black))
                            Text(L10n.string("player.avi.moreWithAvi"))
                                .font(.system(size: 15, weight: .black))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .black))
                        }
                        .foregroundStyle(TuneAVTheme.brandBlack)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("avi.actions.toggle")
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isShowingAviActions ? 316 : 168, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 12, y: 6)
    }

    private func fullPlayerFeedbackBlock(for station: Station) -> some View {
        let selectedFeedback = focusedPrimaryFeedback(for: station)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                    Text(hasCurrentSongContext ? L10n.string("shell.avi.actions.songFeedback") : L10n.string("shell.avi.actions.radioFeedback"))
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                    Text(isNowPlayingFullPlayer && hasCurrentSongContext ? L10n.string("player.avi.feedback.songQuestion") : L10n.string("player.avi.feedback.radioQuestion"))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            fullPlayerFeedbackPicker(
                selectedFeedback: selectedFeedback,
                selectFeedback: { feedback in
                    let currentFeedback = focusedPrimaryFeedback(for: station)
                    let nextFeedback = currentFeedback == feedback ? nil : feedback
                    setFocusedPrimaryFeedback(nextFeedback, for: station)
                    if let nextFeedback {
                        showAviReaction(for: nextFeedback)
                    }
                },
                clearFeedback: {
                    setFocusedPrimaryFeedback(nil, for: station)
                }
            )

            fullPlayerFeedbackFollowUp(
                feedback: selectedFeedback,
                station: station
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 172, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.16), radius: 10, y: 5)
    }

    @ViewBuilder
    private func fullPlayerFeedbackPicker(
        selectedFeedback: TuneAVStationFeedback?,
        selectFeedback: @escaping (TuneAVStationFeedback) -> Void,
        clearFeedback: @escaping () -> Void
    ) -> some View {
        if let selectedFeedback {
            HStack(spacing: 8) {
                SelectedStationFeedbackStatus(feedback: selectedFeedback)

                Button(action: clearFeedback) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(TuneAVTheme.shellBackground, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.stationFeedback.clear"))
                .accessibilityIdentifier("stationFeedback.clear")
            }
            .frame(height: 38)
        } else {
            HStack(spacing: 8) {
                StationFeedbackButton(
                    title: L10n.string("shell.stationFeedback.like"),
                    systemImage: "hand.thumbsup.fill",
                    feedback: .liked,
                    isSelected: false,
                    action: { selectFeedback(.liked) }
                )

                StationFeedbackButton(
                    title: L10n.string("shell.stationFeedback.notForMe"),
                    systemImage: "minus.circle.fill",
                    feedback: .notForMe,
                    isSelected: false,
                    action: { selectFeedback(.notForMe) }
                )

                StationFeedbackButton(
                    title: L10n.string("shell.stationFeedback.dislike"),
                    systemImage: "hand.thumbsdown.fill",
                    feedback: .disliked,
                    isSelected: false,
                    action: { selectFeedback(.disliked) }
                )
            }
            .frame(height: 38)
        }
    }

    @ViewBuilder
    private func fullPlayerFeedbackFollowUp(
        feedback: TuneAVStationFeedback?,
        station: Station
    ) -> some View {
        if hasCurrentSongContext {
            fullPlayerFeedbackDecisionRow(station: station)
        } else if feedback != nil {
            fullPlayerFeedbackInfoRow(
                title: L10n.string("player.avi.feedback.tuned"),
                subtitle: L10n.string("player.avi.feedback.tunedHint"),
                systemImage: "sparkles",
                isAction: false
            )
        } else {
            fullPlayerFeedbackInfoRow(
                title: L10n.string("player.avi.feedback.choose"),
                subtitle: L10n.string("player.avi.feedback.chooseHint"),
                systemImage: "slider.horizontal.3",
                isAction: false
            )
        }
    }

    private func fullPlayerFeedbackDecisionRow(station: Station) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if aviDiscoveryDecision == .ignored {
                HStack(spacing: 8) {
                    fullPlayerFeedbackInfoRow(
                        title: L10n.string("player.discovery.noSave"),
                        subtitle: L10n.string("player.discovery.noSaveHint"),
                        systemImage: "xmark",
                        isAction: false
                    )
                    .accessibilityIdentifier("avi.fullPlayer.discoveryNoSave")

                    fullPlayerFeedbackCompactActionButton(
                        title: L10n.string("player.discovery.saveShort"),
                        systemImage: "bookmark",
                        accessibilityIdentifier: "avi.fullPlayer.saveAfterNoSave"
                    ) {
                        let didToggle = saveAviCurrentDiscovery(for: station)
                        if didToggle {
                            aviDiscoveryDecision = .saved
                        }
                    }
                }
            } else if isCurrentTrackSaved(for: station) {
                HStack(spacing: 8) {
                    fullPlayerFeedbackInfoRow(
                        title: L10n.string("player.discovery.savedShort"),
                        subtitle: L10n.string("player.discovery.savedHintShort"),
                        systemImage: "bookmark.fill",
                        isAction: false
                    )

                    fullPlayerFeedbackCompactActionButton(
                        title: L10n.string("player.discovery.unsaveShort"),
                        systemImage: "bookmark.slash",
                        accessibilityIdentifier: "avi.fullPlayer.unsaveSong"
                    ) {
                        let didToggle = saveAviCurrentDiscovery(for: station)
                        if didToggle {
                            aviDiscoveryDecision = .removed
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    fullPlayerFeedbackDecisionButton(
                        title: currentTrackSaveActionTitle(for: station),
                        systemImage: currentTrackSaveActionSystemImage(for: station),
                        isSelected: isCurrentTrackSaved(for: station),
                        accessibilityIdentifier: "avi.fullPlayer.saveSong"
                    ) {
                        let didToggle = saveAviCurrentDiscovery(for: station)
                        if didToggle {
                            aviDiscoveryDecision = isCurrentTrackSaved(for: station) ? .saved : .removed
                        }
                    }

                    fullPlayerFeedbackDecisionButton(
                        title: L10n.string("player.discovery.noSave"),
                        systemImage: "xmark",
                        isSelected: false,
                        accessibilityIdentifier: "avi.fullPlayer.noSaveSong"
                    ) {
                        aviDiscoveryDecision = .ignored
                        showAviReaction(.notForMe)
                    }
                }

                if let aviDiscoveryDecision {
                    Text(aviDiscoveryDecision.localizedHint)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .accessibilityIdentifier("avi.fullPlayer.discoveryDecisionHint")
                }
            }
        }
        .accessibilityIdentifier("avi.fullPlayer.discoveryDecision")
    }

    private func fullPlayerFeedbackCompactActionButton(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .black))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 96, height: 38)
                .background(TuneAVTheme.shellBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func fullPlayerFeedbackDecisionButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .black))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    fullPlayerFeedbackDecisionButtonBackground(isSelected: isSelected)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.44) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func fullPlayerFeedbackDecisionButtonBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TuneAVTheme.highlight)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TuneAVTheme.shellBackground)
        }
    }

    private func fullPlayerFeedbackInfoRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isAction: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(isAction ? TuneAVTheme.brandBlack : TuneAVTheme.highlight)
                .frame(width: 28, height: 28)
                .background((isAction ? TuneAVTheme.brandBlack.opacity(0.12) : TuneAVTheme.highlight.opacity(0.12)), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(TuneAVTheme.highlight.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.16), lineWidth: 1)
        }
    }

    private func compactAviOptionButton(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 25, height: 25)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                Text(title)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.68))
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.6), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func compactAviActionsSheet(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.string("shell.avi.actions.ask"))
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Spacer(minLength: 0)

                Button {
                    closeAviActions()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(TuneAVTheme.cardSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.actions.closeOptions"))
                .accessibilityIdentifier("avi.actions.close")
            }

            HStack(spacing: 8) {
                compactAviOptionButton(title: L10n.string("shell.avi.actions.searchYouTube"), systemImage: "play.rectangle", accessibilityIdentifier: "avi.actions.youtube") {
                    showAviReaction(.curious)
                    openAviSearch(for: station, destination: .youtube)
                }
                compactAviOptionButton(title: L10n.string("shell.avi.actions.searchArtist"), systemImage: "person.crop.circle", accessibilityIdentifier: "avi.actions.artist") {
                    showAviReaction(.curious)
                    openAviArtistSearch()
                }
            }

            HStack(spacing: 8) {
                compactAviOptionButton(title: L10n.string("shell.avi.actions.searchAppleMusic"), systemImage: "music.note", accessibilityIdentifier: "avi.actions.appleMusic") {
                    showAviReaction(.curious)
                    openAviSearch(for: station, destination: .appleMusic)
                }
                compactAviOptionButton(title: L10n.string("shell.avi.actions.radioFeedback"), systemImage: "dot.radiowaves.left.and.right", accessibilityIdentifier: "avi.actions.radioFeedback") {
                    setAviMenuFeedback(.liked, for: station)
                    closeAviActions()
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 184, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(TuneAVTheme.elevatedSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.glassShadow, radius: 24, y: 12)
    }

    private func fullPlayerAviActionButton(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))
                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(TuneAVTheme.brandBlack)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var hasCurrentSongContext: Bool {
        guard let station = focusedStation ?? currentStation else { return false }
        return TuneAVDisplayMetadata.plausibleTitle(currentTrackTitle, stationName: station.name) != nil &&
            TuneAVDisplayMetadata.plausibleArtist(currentTrackArtist, stationName: station.name) != nil
    }

    private var currentSongIdentity: String {
        [
            currentTrackArtist ?? "",
            currentTrackTitle ?? "",
            currentTrackArtworkURL?.absoluteString ?? ""
        ].joined(separator: "|")
    }

    private var currentTrackFeedback: TuneAVStationFeedback? {
        libraryStore.feedbackForDiscoveredTrack(
            title: currentTrackTitle,
            artist: currentTrackArtist
        )
    }

    private func resetTransientAviUI() {
        withAnimation(.snappy(duration: 0.18)) {
            isShowingAviActions = false
            isShowingMoreAviActions = false
            isShowingFeedbackPicker = false
            aviActionsPage = 0
            isEditingRadioFeedback = false
            isShowingArtworkZoom = false
        }
    }

    private func focusedPrimaryFeedback(for station: Station) -> TuneAVStationFeedback? {
        if isNowPlayingFullPlayer && hasCurrentSongContext {
            return currentTrackFeedback
        }
        return stationFeedback[station.id]
    }

    private func setFocusedPrimaryFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        if isNowPlayingFullPlayer && hasCurrentSongContext {
            setCurrentTrackFeedback(feedback)
        } else {
            setStationFeedback(station, feedback)
        }
    }

    private func setCurrentTrackFeedback(_ feedback: TuneAVStationFeedback?) {
        libraryStore.setFeedbackForDiscoveredTrack(
            feedback,
            title: currentTrackTitle,
            artist: currentTrackArtist
        )
    }

    private func focusedSignalInfo(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("shell.stationInfo.title"))
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Spacer()

                Text(L10n.string("shell.stationInfo.summary"))
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule(style: .continuous))
            }

            Text(defaultPublicSignalInfo(for: station))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func focusedRadioQuickActions(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: openPlayer) {
                    Label(
                        isFocusedStationActive ? L10n.string("player.header.nowPlaying") : L10n.string("shell.avi.actions.playRadio"),
                        systemImage: isFocusedStationActive ? "waveform" : "play.fill"
                    )
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avi.detail.radio.play")

                Button {
                    toggleFavorite(station)
                } label: {
                    Image(systemName: stationSaveActionSystemImage(for: station))
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(libraryStore.isFavorite(station) ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(libraryStore.isFavorite(station) ? TuneAVTheme.highlight.opacity(0.34) : TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(stationSaveActionTitle(for: station))
                .accessibilityIdentifier("avi.detail.radio.save")
            }

            StationFeedbackControl(
                selectedFeedback: stationFeedback[station.id],
                selectFeedback: { feedback in
                    let nextFeedback = stationFeedback[station.id] == feedback ? nil : feedback
                    setStationFeedback(station, nextFeedback)
                },
                clearFeedback: {
                    setStationFeedback(station, nil)
                }
            )
        }
        .padding(12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }

    private func fullPlayerRadioDetailLink(for station: Station) -> some View {
        Button {
            showStationDetails(station, [station])
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 38, height: 38)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("shell.avi.recommendation.details"))
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(station.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.75))
            }
            .padding(14)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.66), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avi.fullPlayer.radioDetail")
    }

    private var aviStatusCard: some View {
        HStack(alignment: .center, spacing: 14) {
            aviHeroImage(width: 104)

            VStack(alignment: .leading, spacing: 8) {
                Text(aviEmotionLabel)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(aviMoodLine)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

                Text(aviDetailLine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(TuneAVTheme.elevatedSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.softShadow.opacity(0.38), radius: 18, y: 10)
    }

    private func aviHeroImage(width: CGFloat) -> some View {
        AviStableEmotionImage(emotion: aviEmotion, assetVariant: .head, width: width)
            .accessibilityLabel(L10n.string("shell.avi.title"))
    }

    @ViewBuilder
    private var focusedSignalPanel: some View {
        if let focusedStation {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(signalEyebrow)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                    Text(isFocusedStationActive ? (currentTrackTitle ?? focusedStation.name) : focusedStation.name)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)

                    Text(focusedSignalDetail(for: focusedStation))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    listeningControlButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.controls.previous", action: playPrevious)

                    Button(action: openPlayer) {
                        Label(primaryFocusedActionTitle, systemImage: primaryFocusedActionIcon)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(TuneAVTheme.brandBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    listeningControlButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.controls.next", action: playNext)
                }

                StationFeedbackControl(
                    selectedFeedback: stationFeedback[focusedStation.id],
                    selectFeedback: { feedback in
                        let nextFeedback = stationFeedback[focusedStation.id] == feedback ? nil : feedback
                        setStationFeedback(focusedStation, nextFeedback)
                    },
                    clearFeedback: {
                        setStationFeedback(focusedStation, nil)
                    }
                )

                focusedSignalActions(for: focusedStation)
            }
            .padding(18)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private func focusedSignalDetail(for station: Station) -> String {
        if isFocusedStationActive, let currentTrackArtist {
            return "\(currentTrackArtist) · \(station.name)"
        }
        return station.primaryDetailLine.isEmpty ? L10n.string("shell.avi.radioPublicFallback") : station.primaryDetailLine
    }

    private func signalInfoTitle(for station: Station) -> String {
        let tags = stationTagList(for: station)
        if tags.isEmpty {
            return L10n.string("shell.stationInfo.publicSignal")
        }
        return tags.prefix(2).map { L10n.genreLabel(for: $0) }.joined(separator: " · ")
    }

    private func defaultPublicSignalInfo(for station: Station) -> String {
        var details: [String] = []
        if let countryCode = station.countryCode {
            details.append(L10n.countryName(for: countryCode))
        }
        if !station.language.isEmpty {
            details.append(station.language)
        }
        let tags = stationTagList(for: station)
        if !tags.isEmpty {
            details.append(tags.prefix(4).map { L10n.genreLabel(for: $0) }.joined(separator: ", "))
        }
        return details.isEmpty
            ? L10n.string("shell.stationInfo.publicFallback")
            : details.joined(separator: " · ")
    }

    private func stationTagList(for station: Station) -> [String] {
        station.tags
            .split(separator: ",")
            .compactMap { TuneAVMusicGenreCatalog.canonicalTag(for: String($0)) }
            .reduce(into: [String]()) { result, tag in
                guard !result.contains(tag) else { return }
                result.append(tag)
            }
    }

    private var signalEyebrow: String {
        isFocusedStationActive ? "Encontrado en directo" : "Info de radio"
    }

    private var aviActionsPanelHeight: CGFloat {
        274
    }

    private func aviActionsPanel(for station: Station) -> some View {
        let hasSongStep = hasCurrentSongContext && isNowPlayingFullPlayer
        let pageCount = hasSongStep ? 2 : 1
        let lastPage = pageCount - 1

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(aviActionsPageTitle)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("shell.avi.actions.page", min(aviActionsPage, lastPage) + 1, pageCount))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            aviActionsPage = max(0, aviActionsPage - 1)
                            isEditingRadioFeedback = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .black))
                            .frame(width: 28, height: 28)
                            .background(TuneAVTheme.cardSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(aviActionsPage == 0)
                    .opacity(pageCount == 1 || aviActionsPage == 0 ? 0.34 : 1)
                    .accessibilityLabel(L10n.string("shell.avi.actions.previousOptions"))

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            aviActionsPage = min(lastPage, aviActionsPage + 1)
                            isEditingRadioFeedback = false
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .black))
                            .frame(width: 28, height: 28)
                            .background(TuneAVTheme.cardSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(aviActionsPage >= lastPage)
                    .opacity(pageCount == 1 || aviActionsPage >= lastPage ? 0.34 : 1)
                    .accessibilityLabel(L10n.string("shell.avi.actions.moreOptions"))
                }
                .foregroundStyle(TuneAVTheme.textSecondary)

                Button {
                    closeAviActions()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(TuneAVTheme.cardSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.actions.closeOptions"))
                .accessibilityIdentifier("avi.actions.close")
            }

            VStack(spacing: 6) {
                if hasSongStep && aviActionsPage == 0 {
                    AviCommandButton(title: L10n.string("shell.avi.actions.searchLyrics"), systemImage: "text.quote", accessibilityIdentifier: "avi.actions.lyrics") {
                        showAviReaction(.curious)
                        openAviSearch(for: station, destination: .web, suffix: "lyrics")
                    }
                    AviCommandButton(title: L10n.string("shell.avi.actions.searchYouTube"), systemImage: "play.rectangle", accessibilityIdentifier: "avi.actions.youtube") {
                        showAviReaction(.curious)
                        openAviSearch(for: station, destination: .youtube)
                    }
                    AviCommandButton(title: L10n.string("shell.avi.actions.searchAppleMusic"), systemImage: "music.note", accessibilityIdentifier: "avi.actions.appleMusic") {
                        showAviReaction(.curious)
                        openAviSearch(for: station, destination: .appleMusic)
                    }
                    AviCommandButton(title: L10n.string("shell.avi.actions.searchArtist"), systemImage: "person.crop.circle", accessibilityIdentifier: "avi.actions.artist") {
                        showAviReaction(.curious)
                        openAviArtistSearch()
                    }
                } else {
                    AviCommandButton(title: L10n.string("shell.avi.actions.searchPublicInfo"), systemImage: "info.circle", accessibilityIdentifier: "avi.actions.publicInfo") {
                        runProAviActionOutsideFullPlayer {
                            showAviReaction(.curious)
                            openAviStationSearch(for: station)
                        }
                    }
                    AviCommandButton(title: L10n.string("shell.avi.recommendation.details"), systemImage: "dot.radiowaves.left.and.right", accessibilityIdentifier: "avi.actions.radioDetails") {
                        showStationDetails(station, [station])
                        closeAviActions()
                    }
                    AviCommandButton(title: L10n.string("shell.avi.actions.history"), systemImage: "clock.arrow.circlepath", accessibilityIdentifier: "avi.actions.history") {
                        runProAviActionOutsideFullPlayer {
                            showStationDetails(station, [station])
                            closeAviActions()
                        }
                    }
                    if !isFocusedStationActive {
                        AviCommandButton(title: L10n.string("shell.avi.actions.playRadio"), systemImage: "play.fill", accessibilityIdentifier: "avi.actions.playRadio") {
                            runProAviActionOutsideFullPlayer {
                                openPlayer()
                                closeAviActions()
                            }
                        }
                    } else {
                        AviCommandButton(title: L10n.string("shell.avi.actions.openWebsite"), systemImage: "safari", accessibilityIdentifier: "avi.actions.web") {
                            runProAviActionOutsideFullPlayer {
                                showAviReaction(.curious)
                                if let url = station.resolvedHomepageURL {
                                    browserDestination = BrowserDestination(url: url)
                                } else {
                                    openAviStationSearch(for: station)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: aviActionsPanelHeight, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(TuneAVTheme.elevatedSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.glassShadow, radius: 28, y: 14)
    }

    private var aviActionsPageTitle: String {
        if isNowPlayingFullPlayer && hasCurrentSongContext && aviActionsPage == 0 {
            return L10n.string("shell.avi.actions.songFeedback")
        }
        return L10n.string("shell.common.radio")
    }

    private func setAviMenuFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        if isNowPlayingFullPlayer && hasCurrentSongContext && !isEditingRadioFeedback {
            setCurrentTrackFeedback(feedback)
        } else {
            setStationFeedback(station, feedback)
        }
        if let feedback {
            showAviReaction(for: feedback)
        }
    }

    private func showAviReaction(_ reaction: AviScreenReaction) {
        if let current = aviReaction, current.priority > reaction.priority {
            return
        }

        let token = UUID()
        aviReaction = reaction
        aviReactionStartedAt = Date()
        aviReactionToken = token
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reaction.durationMilliseconds))
            guard aviReactionToken == token else { return }
            aviReaction = nil
        }
    }

    private func showAviReactionForCurrentSongChange(identity: String) {
        guard isNowPlayingFullPlayer, isFocusedStationActive, isPlaying, !identity.isEmpty else {
            aviReaction = nil
            lastAutomaticAviReactionIdentity = ""
            return
        }
        guard identity != lastAutomaticAviReactionIdentity else { return }

        let reaction: AviScreenReaction
        switch currentTrackFeedback {
        case .liked:
            reaction = .recognizedTrack
        case .disliked:
            reaction = .disliked
        case .notForMe:
            reaction = .notForMe
        case nil:
            if let focusedStation,
               libraryStore.isSavedDiscoveredTrack(title: currentTrackTitle, artist: currentTrackArtist, station: focusedStation) {
                reaction = .recognizedTrack
            } else {
                reaction = .newTrack
            }
        }

        let now = Date()
        if reaction.usesAutomaticCooldown,
           now.timeIntervalSince(lastAutomaticAviReactionAt) < AviScreenReaction.automaticCooldown {
            lastAutomaticAviReactionIdentity = identity
            return
        }

        lastAutomaticAviReactionIdentity = identity
        lastAutomaticAviReactionAt = now
        showAviReaction(reaction)
    }

    private func showAviReaction(for feedback: TuneAVStationFeedback) {
        switch feedback {
        case .liked:
            showAviReaction(.liked)
        case .notForMe:
            showAviReaction(.notForMe)
        case .disliked:
            showAviReaction(.disliked)
        }
    }

    private func feedbackStatusBadge(_ feedback: TuneAVStationFeedback, size: CGFloat) -> some View {
        TuneAVFeedbackBadge(feedback: feedback, size: size)
    }

    private func closeAviActions() {
        withAnimation(.snappy(duration: 0.2)) {
            isShowingAviActions = false
            isShowingMoreAviActions = false
            isShowingFeedbackPicker = false
            aviActionsPage = 0
            isEditingRadioFeedback = false
        }
    }

    private func openAviSearch(
        for station: Station,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        let query = TuneAVExternalSearchURL.query(
            parts: [currentTrackArtist, currentTrackTitle, station.name],
            suffix: suffix
        )
        guard !query.isEmpty, let url = TuneAVExternalSearchURL.url(for: destination, query: query) else { return }
        browserDestination = BrowserDestination(url: url)
        closeAviActions()
    }

    private func openAviArtistSearch() {
        guard let currentTrackArtist else { return }
        guard let url = TuneAVExternalSearchURL.url(for: .web, query: currentTrackArtist) else { return }
        browserDestination = BrowserDestination(url: url)
        closeAviActions()
    }

    private func openAviStationSearch(for station: Station) {
        guard let url = TuneAVExternalSearchURL.stationSearch(stationName: station.name) else { return }
        browserDestination = BrowserDestination(url: url)
        closeAviActions()
    }

    private func openExternalSearch(
        query: String,
        destination: TuneAVExternalSearchURL.Destination = .web
    ) {
        guard let url = TuneAVExternalSearchURL.url(for: destination, query: query) else { return }
        browserDestination = BrowserDestination(url: url)
        closeAviActions()
    }

    private func toggleDiscoverySaved(_ discovery: DiscoveredTrack) {
        if discovery.isMarkedInteresting {
            _ = libraryStore.toggleDiscoverySaved(discovery)
            return
        }

        let state = accessController.limitState(
            for: .savedTracks,
            currentUsage: libraryStore.savedDiscoveriesCount
        )
        guard state.isAllowed else {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return
        }

        _ = libraryStore.toggleDiscoverySaved(discovery, savedLimit: state.limit)
    }

    @discardableResult
    private func saveAviCurrentDiscovery(for station: Station) -> Bool {
        guard currentTrackTitle != nil || currentTrackArtist != nil else {
            showAviReaction(.liked)
            toggleFavorite(station)
            return true
        }

        let state = accessController.limitState(
            for: .savedTracks,
            currentUsage: libraryStore.savedDiscoveriesCount
        )

        if !isCurrentTrackSaved(for: station) {
            guard libraryStore.canMarkTrackInteresting(
                title: currentTrackTitle,
                artist: currentTrackArtist,
                station: station,
                limit: state.limit
            ) else {
                accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
                return false
            }
        }

        let didToggle = libraryStore.toggleDiscoveredTrackSaved(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            station: station,
            artworkURL: nil,
            savedLimit: state.limit,
            discoveryLimit: accessController.limits.discoveredTracks
        )
        guard didToggle else {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return false
        }

        showAviReaction(isCurrentTrackSaved(for: station) ? .saved : .curious)
        return true
    }

    private func isCurrentTrackSaved(for station: Station) -> Bool {
        libraryStore.isSavedDiscoveredTrack(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            station: station
        )
    }

    private func currentTrackSaveActionTitle(for station: Station) -> String {
        isCurrentTrackSaved(for: station) ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort")
    }

    private func currentTrackSaveActionSystemImage(for station: Station) -> String {
        isCurrentTrackSaved(for: station) ? "bookmark.slash" : "bookmark"
    }

    private func stationSaveActionTitle(for station: Station) -> String {
        libraryStore.isFavorite(station) ? L10n.string("player.station.unsave") : L10n.string("player.station.save")
    }

    private func stationSaveActionSystemImage(for station: Station) -> String {
        libraryStore.isFavorite(station) ? "bookmark.slash" : "bookmark"
    }

    private func focusedSignalActions(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("shell.avi.can"))
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    AviSignalActionChip(title: isFocusedStationActive ? L10n.string("player.discovery.lyricsShort") : L10n.string("shell.avi.actions.publicInfo"), systemImage: isFocusedStationActive ? "text.quote" : "info.circle") {
                        runProAviActionOutsideFullPlayer {
                            if isFocusedStationActive && hasCurrentSongContext {
                                openAviSearch(for: station, destination: .web, suffix: "lyrics")
                            } else {
                                openAviStationSearch(for: station)
                            }
                        }
                    }
                    AviSignalActionChip(title: L10n.string("shell.avi.actions.historyShort"), systemImage: "clock.arrow.circlepath") {
                        runProAviActionOutsideFullPlayer {
                            showStationDetails(station, [station])
                        }
                    }
                    AviSignalActionChip(title: L10n.string("player.avi.action.web"), systemImage: "safari") {
                        runProAviActionOutsideFullPlayer {
                            if let url = station.resolvedHomepageURL {
                                browserDestination = BrowserDestination(url: url)
                            } else {
                                openAviStationSearch(for: station)
                            }
                        }
                    }
                    if isFocusedStationActive {
                        AviSignalActionChip(title: L10n.string("shell.accessibility.stopListening"), systemImage: "speaker.slash.fill") {
                            stopPlayback()
                        }
                    }
                    AviSignalActionChip(title: L10n.string("common.more"), systemImage: "ellipsis") {
                        withAnimation(.snappy(duration: 0.22)) {
                            isShowingAviActions = true
                            aviActionsPage = 0
                        }
                    }
                }
            }
        }
    }

    private var aviPrimaryLine: String {
        if isFocusedStationActive, currentTrackTitle != nil {
            return L10n.string("shell.avi.primary.reacting")
        }
        return isFocusedStationActive ? L10n.string("shell.avi.primary.reading") : L10n.string("shell.avi.primary.reviewing")
    }

    private var primaryFocusedActionTitle: String {
        guard !isLoading else { return L10n.string("audio.status.loading") }
        guard isFocusedStationActive else { return L10n.string("player.control.play") }
        return isPlaying ? "Pausar" : "Escuchar"
    }

    private var primaryFocusedActionIcon: String {
        guard !isLoading else { return "hourglass" }
        guard isFocusedStationActive else { return "play.fill" }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    private func listeningControlButton(
        systemImage: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 52, height: 52)
                .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: systemImage))
        .accessibilityIdentifier(accessibilityIdentifier ?? systemImage)
    }

    private func accessibilityLabel(for systemImage: String) -> String {
        switch systemImage {
        case "stop.fill": return L10n.string("shell.accessibility.stop")
        case "backward.fill": return L10n.string("player.control.previous")
        case "forward.fill": return L10n.string("player.control.next")
        default: return systemImage
        }
    }

    @ViewBuilder
    private var recommendationPanel: some View {
        if let recommendation = topRecommendation {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        StationThumbnailView(
                            station: recommendation.station,
                            size: 62,
                            animationOverlay: .none,
                            isAnimationActive: false
                        )

                        if let feedback = stationFeedback[recommendation.station.id] {
                            feedbackStatusBadge(feedback, size: 24)
                                .offset(x: -5, y: -5)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("shell.avi.recommendation.title"))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)

                        Text(recommendation.station.name)
                            .font(.system(size: 19, weight: .black))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(1)

                        Text(recommendation.reason)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button {
                        playStation(recommendation.station, recommendationQueue)
                    } label: {
                        Label(L10n.string("shell.avi.recommendation.play"), systemImage: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("avi.recommendation.play")

                    Button {
                        showStationDetails(recommendation.station, recommendationQueue)
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 48, height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TuneAVTheme.highlight)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(L10n.string("shell.avi.recommendation.details"))
                    .accessibilityIdentifier("avi.recommendation.details")
                }

                StationFeedbackControl(
                    selectedFeedback: stationFeedback[recommendation.station.id],
                    selectFeedback: { feedback in
                        let nextFeedback = stationFeedback[recommendation.station.id] == feedback ? nil : feedback
                        setStationFeedback(recommendation.station, nextFeedback)
                    },
                    clearFeedback: {
                        setStationFeedback(recommendation.station, nil)
                    }
                )
                .padding(.top, 2)

                if !secondaryRecommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("shell.avi.recommendation.nextTitle"))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TuneAVTheme.textPrimary)

                        ForEach(secondaryRecommendations, id: \.station.id) { recommendation in
                            AviRecommendationRow(
                                station: recommendation.station,
                                reason: recommendation.reason,
                                selectedFeedback: stationFeedback[recommendation.station.id],
                                playAction: {
                                    playStation(recommendation.station, recommendationQueue)
                                },
                                feedbackAction: { feedback in
                                    let nextFeedback = stationFeedback[recommendation.station.id] == feedback ? nil : feedback
                                    setStationFeedback(recommendation.station, nextFeedback)
                                },
                                clearFeedback: {
                                    setStationFeedback(recommendation.station, nil)
                                },
                                detailsAction: {
                                    showStationDetails(recommendation.station, recommendationQueue)
                                }
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.recommendation.card")
        }
    }

    private var quickActions: some View {
        VStack(spacing: 12) {
            if focusedStation == nil {
                Button(action: openSearch) {
                    Label(L10n.string("shell.avi.action.findStation"), systemImage: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avi.primaryAction")
            }

            HStack(spacing: 12) {
                AviActionButton(title: L10n.string("tab.search"), systemImage: "magnifyingglass", action: openSearch)
                AviActionButton(title: L10n.string("shell.avi.action.saved"), systemImage: "bookmark.fill", action: openLibrary)
            }
        }
    }

    private var localSignals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("shell.avi.signals.title"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            AviSignalRow(
                title: L10n.string("shell.avi.signals.recent.title"),
                detail: recentStations.isEmpty ? L10n.string("shell.avi.signals.recent.empty") : L10n.plural(singular: "shell.avi.signals.recent.count.one", plural: "shell.avi.signals.recent.count.other", count: recentStations.count, recentStations.count),
                systemImage: "clock.arrow.circlepath",
                accessibilityIdentifier: "avi.signals.recent"
            )

            AviSignalRow(
                title: L10n.string("shell.avi.signals.saved.title"),
                detail: favoriteStations.isEmpty ? L10n.string("shell.avi.signals.saved.empty") : L10n.plural(singular: "shell.avi.signals.saved.count.one", plural: "shell.avi.signals.saved.count.other", count: favoriteStations.count, favoriteStations.count),
                systemImage: "dot.radiowaves.left.and.right",
                accessibilityIdentifier: "avi.signals.saved"
            )

            AviSignalRow(
                title: L10n.string("shell.avi.signals.discoveries.title"),
                detail: recentDiscoveryCount == 0 ? L10n.string("shell.avi.signals.discoveries.empty") : L10n.plural(singular: "shell.avi.signals.discoveries.count.one", plural: "shell.avi.signals.discoveries.count.other", count: recentDiscoveryCount, recentDiscoveryCount),
                systemImage: "sparkles",
                accessibilityIdentifier: "avi.signals.discoveries"
            )

            AviSignalRow(
                title: L10n.string("shell.avi.signals.feedback.title"),
                detail: feedbackSignalCount == 0 ? L10n.string("shell.avi.signals.feedback.empty") : L10n.plural(singular: "shell.avi.signals.feedback.count.one", plural: "shell.avi.signals.feedback.count.other", count: feedbackSignalCount, feedbackSignalCount),
                systemImage: "hand.thumbsup",
                accessibilityIdentifier: "avi.signals.feedback"
            )
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.6), lineWidth: 1)
        }
    }

    private var aviStateTitle: String {
        focusedStation == nil ? L10n.string("shell.avi.state.curious") : L10n.string("shell.avi.state.listening")
    }

    private var aviSubtitle: String {
        L10n.string("shell.avi.subtitle")
    }

    private var aviEmotion: TuneAVAviEmotion {
        TuneAVAviEmotionResolver.focusedSignalEmotion(
            focusedStation: focusedStation,
            isFocusedStationActive: isFocusedStationActive,
            isPlaying: isPlaying,
            isLoading: isLoading,
            currentTrackTitle: currentTrackTitle,
            currentTrackArtist: currentTrackArtist,
            feedback: isNowPlayingFullPlayer && hasCurrentSongContext
                ? currentTrackFeedback
                : focusedStation.flatMap { stationFeedback[$0.id] }
        )
    }

    private var aviMoodLine: String {
        if focusedStation != nil {
            return isFocusedStationActive ? L10n.string("shell.avi.mood.vibing") : L10n.string("shell.avi.mood.curiousRadio")
        }
        return recentStations.isEmpty ? L10n.string("shell.avi.mood.ready") : L10n.string("shell.avi.mood.thinking")
    }

    private var aviDetailLine: String {
        if focusedStation != nil {
            return isFocusedStationActive
                ? L10n.string("shell.avi.detail.detecting")
                : L10n.string("shell.avi.detail.scanning")
        }
        return L10n.string("shell.avi.detail.ready")
    }

    private var aviEmotionLabel: String {
        if focusedStation == nil { return L10n.string("shell.avi.state.thinking") }
        return isFocusedStationActive ? L10n.string("shell.avi.state.attentive") : L10n.string("shell.avi.state.exploring")
    }

    private var recommendationScorer: TuneAVLocalRecommendationScorer {
        TuneAVLocalRecommendationScorer(
            currentStation: currentStation,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            discoveries: discoveries,
            stationFeedback: stationFeedback,
            feedContext: feedContext,
            preferredTag: preferredTag,
            currentCountryCode: preferredCountryCode
        )
    }

    private var rankedRecommendationCandidates: [(station: Station, rank: TuneAVLocalRecommendationScorer.Rank)] {
        let excludedIDs = Set(([currentStation?.id].compactMap { $0 }))

        return recommendationScorer
            .rankedStations(stations.filter { !excludedIDs.contains($0.id) })
            .filter { $0.rank.score > 0 }
    }

    private var topRecommendation: (station: Station, reason: String)? {
        guard let top = rankedRecommendationCandidates.first else { return nil }
        return recommendationViewModel(for: top)
    }

    private var secondaryRecommendations: [(station: Station, reason: String)] {
        rankedRecommendationCandidates
            .dropFirst()
            .prefix(2)
            .map(recommendationViewModel(for:))
    }

    private func recommendationViewModel(
        for candidate: (station: Station, rank: TuneAVLocalRecommendationScorer.Rank)
    ) -> (station: Station, reason: String) {
        return (
            station: candidate.station,
            reason: TuneAVLocalRecommendationScorer.localizedSummary(for: candidate.rank.primaryReason) ?? L10n.string("shell.avi.recommendation.reasonFallback")
        )
    }

    private var recommendationQueue: [Station] {
        rankedRecommendationCandidates.map(\.station)
    }

    private var feedbackSignalCount: Int {
        stationFeedback.values.filter { feedback in
            switch feedback {
            case .liked, .disliked, .notForMe:
                return true
            }
        }.count
    }

    private var recentDiscoveryCount: Int {
        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        return discoveries.filter { discovery in
            !discovery.isHidden && discovery.playedAt >= cutoff
        }.count
    }
}

private struct AviRecommendationRow: View {
    let station: Station
    let reason: String
    let selectedFeedback: TuneAVStationFeedback?
    let playAction: () -> Void
    let feedbackAction: (TuneAVStationFeedback) -> Void
    let clearFeedback: () -> Void
    let detailsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: playAction) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TuneAVTheme.brandBlack)
                        .frame(width: 32, height: 32)
                        .background(TuneAVTheme.highlight, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.recommendation.play"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(reason)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .lineLimit(1)

                        if let selectedFeedback {
                            Image(systemName: selectedFeedback.systemImage)
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(selectedFeedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                                .accessibilityLabel(selectedFeedback.localizedState)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: detailsAction) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.recommendation.details"))
            }

            AviCompactFeedbackControl(
                selectedFeedback: selectedFeedback,
                selectFeedback: feedbackAction,
                clearFeedback: clearFeedback
            )
        }
        .padding(10)
        .background(TuneAVTheme.highlight.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("avi.recommendation.secondary")
    }
}

private struct AviCompactFeedbackControl: View {
    let selectedFeedback: TuneAVStationFeedback?
    let selectFeedback: (TuneAVStationFeedback) -> Void
    var clearFeedback: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 7) {
            ForEach(TuneAVStationFeedback.allCases, id: \.self) { feedback in
                Button {
                    selectFeedback(feedback)
                } label: {
                    Image(systemName: feedback.systemImage)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 34, height: 30)
                        .background(
                            TuneAVTheme.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feedback.localizedState)
                .accessibilityIdentifier("avi.recommendation.feedback.\(feedback.rawValue)")
            }
        }
        .frame(height: 30)
        .opacity(selectedFeedback == nil ? 1 : 0)
        .disabled(selectedFeedback != nil)
        .accessibilityHidden(selectedFeedback != nil)
        .accessibilityIdentifier("avi.recommendation.feedback")
    }
}

private struct HomeAviBrief: View {
    let currentStation: Station?
    let recentCount: Int
    let favoriteCount: Int
    let emotion: TuneAVAviEmotion
    let openAvi: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AviStableEmotionImage(emotion: emotion, assetVariant: .head, width: 58, height: 58)
                .padding(6)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("shell.home.aviBrief.title"))
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(briefDetail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: openAvi) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(width: 42, height: 42)
                    .background(TuneAVTheme.highlight, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.home.aviBrief.action"))
            .accessibilityIdentifier("home.aviBrief.open")
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
        }
    }

    private var briefDetail: String {
        if let currentStation {
            return L10n.string("shell.home.aviBrief.listening", currentStation.name)
        }
        if recentCount > 0 || favoriteCount > 0 {
            let recentText = L10n.plural(singular: "shell.count.recent.short.one", plural: "shell.count.recent.short.other", count: recentCount, recentCount)
            let favoriteText = L10n.plural(singular: "shell.count.saved.short.one", plural: "shell.count.saved.short.other", count: favoriteCount, favoriteCount)
            return L10n.string("shell.home.aviBrief.localSignals", recentText, favoriteText)
        }
        return L10n.string("shell.home.aviBrief.empty")
    }
}

private struct AviInlineBrief: View {
    let assetName: String
    let title: String
    let detail: String
    let status: String
    var accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .padding(5)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(status)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(TuneAVTheme.highlight.opacity(0.12), in: Capsule())
                }

                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct SearchAccessRow: View {
    let title: String
    let detail: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }
            .padding(14)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeMoodGenreSuggestion: Hashable {
    let tag: String
    let title: String
}

private struct HomeMoodGenreDesk: View {
    let tags: [HomeMoodGenreSuggestion]
    let selectTag: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("shell.home.moodsGenres.title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(L10n.string("shell.home.moodsGenres.subtitle"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(tags, id: \.self) { suggestion in
                    HomeMoodGenrePill(title: suggestion.title, accessibilityID: "home.moodGenre.\(suggestion.tag)") {
                        selectTag(suggestion.tag)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.section.moodsGenres")
    }
}

private struct HomeMoodGenrePill: View {
    let title: String
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(TuneAVTheme.elevatedSurface, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}

enum HomeAroundYouStationSelector {
    static func select(
        from stations: [Station],
        excluding excludedIDs: Set<String>,
        countryCode: String,
        limit: Int
    ) -> [Station] {
        let remainingStations = stations.filter { !excludedIDs.contains($0.id) }
        let countryStations = remainingStations.filter { station in
            TuneAVCountry.sanitizedCode(station.countryCode) == countryCode
        }

        return Array((countryStations.isEmpty ? remainingStations : countryStations).prefix(limit))
    }
}

private struct AviActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct AviSignalActionChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(TuneAVTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AviPreviewCapabilityRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 30, height: 30)
                .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AviPreviewPrimaryButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 30, height: 30)
                    .background(TuneAVTheme.textInverse.opacity(0.16), in: Circle())

                Text(title)
                    .font(.system(size: 16, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
            }
            .foregroundStyle(TuneAVTheme.textInverse)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .padding(.horizontal, 14)
            .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: TuneAVTheme.highlight.opacity(0.24), radius: 12, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct AviPreviewSecondaryButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 30, height: 30)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .padding(.horizontal, 10)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct AviPlanComparisonSheet: View {
    let accessMode: AccessMode
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("shell.avi.plans.eyebrow"))
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)

                        Text(L10n.string("shell.avi.plans.title"))
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(TuneAVTheme.textPrimary)

                        Text(L10n.string("shell.avi.plans.subtitle"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        planCard(
                            title: L10n.string("shell.avi.plans.guest"),
                            isCurrent: accessMode == .guest,
                            rows: [
                                L10n.string("shell.avi.plans.guest.radios"),
                                L10n.string("shell.avi.plans.guest.songs"),
                                L10n.string("shell.avi.plans.guest.discoveries"),
                                L10n.string("shell.avi.plans.guest.avi"),
                                L10n.string("shell.avi.plans.localOnly")
                            ]
                        )

                        planCard(
                            title: L10n.string("shell.avi.plans.free"),
                            isCurrent: accessMode == .signedInFree,
                            rows: [
                                L10n.string("shell.avi.plans.free.radios"),
                                L10n.string("shell.avi.plans.free.songs"),
                                L10n.string("shell.avi.plans.free.discoveries"),
                                L10n.string("shell.avi.plans.free.avi"),
                                L10n.string("shell.avi.plans.localOnly")
                            ]
                        )

                        planCard(
                            title: L10n.string("shell.avi.plans.pro"),
                            isCurrent: accessMode == .signedInPro,
                            isHighlighted: true,
                            rows: [
                                L10n.string("shell.avi.plans.pro.avi"),
                                L10n.string("shell.avi.plans.pro.radios"),
                                L10n.string("shell.avi.plans.pro.songs"),
                                L10n.string("shell.avi.plans.pro.discoveries"),
                                L10n.string("shell.avi.plans.pro.requests"),
                                L10n.string("shell.avi.plans.pro.sync")
                            ]
                        )
                    }

                    Button {
                        onDismiss()
                        onPrimaryAction()
                    } label: {
                            Text(accessMode == .guest ? L10n.string("shell.avi.preview.primary.guest") : L10n.string("shell.avi.preview.primary.pro"))
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(TuneAVTheme.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityIdentifier("avi.planComparison.primary")
                }
                .padding(22)
            }
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .navigationTitle(L10n.string("shell.avi.plans.eyebrow"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("shell.avi.plans.close"), action: onDismiss)
                }
            }
        }
    }

    private func planCard(title: String, isCurrent: Bool, isHighlighted: Bool = false, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Spacer()

                if isCurrent {
                    Text(L10n.string("shell.avi.plans.current"))
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textInverse)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(TuneAVTheme.highlight, in: Capsule(style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .frame(width: 18)

                        Text(row)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(isHighlighted ? TuneAVTheme.highlight.opacity(0.08) : TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isHighlighted ? TuneAVTheme.highlight.opacity(0.36) : TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
        }
    }
}

private struct AviCommandButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 30, height: 30)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)
            .padding(.horizontal, 10)
            .background(TuneAVTheme.cardSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.46), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .modifier(OptionalAccessibilityIdentifier(accessibilityIdentifier))
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private struct AviSignalRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 28, height: 28)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct AviSignalInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private struct AviMusicMiniRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 30, height: 30)
                .background(TuneAVTheme.highlight.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private struct AviMusicMiniActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let primaryAction: () -> Void
    let secondarySystemImage: String
    let secondaryAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .frame(width: 34, height: 34)
                        .background(TuneAVTheme.highlight.opacity(0.11), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Button(action: secondaryAction) {
                Image(systemName: secondarySystemImage)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(width: 34, height: 34)
                    .background(TuneAVTheme.highlight, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }
}

private struct ArtistStatPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)

            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .frame(height: 68, alignment: .topLeading)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }
}

private struct HomeScreen: View {
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

    private enum FeaturedSource {
        case current
        case lastPlayed
        case recent
        case favorite
        case popular
    }

    private struct DerivedState {
        let displayedRecentStations: [Station]
        let displayedFavoriteStations: [Station]
        let displayedPopularStations: [Station]
        let displayedAviPickStations: [Station]
        let displayedAroundYouStations: [Station]
        let displayedRecentAndFavoriteStations: [Station]
        let moodGenreTags: [HomeMoodGenreSuggestion]
        let recommendationInsights: [String: String]
    }

    var body: some View {
        let derivedState = homeDerivedState

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShellBrandHeader(
                    statusTitle: isLoading ? L10n.string("shell.status.refreshing") : (audioPlayer.currentStation == nil ? L10n.string("shell.status.live") : audioPlayer.status.label)
                )

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
                    currentStation: audioPlayer.currentStation,
                    recentCount: recentStations.count,
                    favoriteCount: favoriteStations.count,
                    emotion: TuneAVAviEmotionResolver.homeEmotion(
                        currentStation: audioPlayer.currentStation,
                        recentCount: recentStations.count,
                        favoriteCount: favoriteStations.count
                    ),
                    openAvi: openAvi
                )

                if shouldShowLiveNowPanel {
                    LiveNowPanel(currentStation: audioPlayer.currentStation, status: audioPlayer.status.label)
                }

                if isLoading && heroStation == nil && derivedState.displayedPopularStations.isEmpty {
                    StationCardSkeletonGroup()
                } else if let errorMessage {
                    EmptyLibraryState(
                        title: L10n.string("shell.home.error.title"),
                        detail: errorMessage
                    )
                } else if let heroStation {
                    HomeTuningDeskHero(
                        station: heroStation,
                        presentation: homePresentation(for: heroStation),
                        isFavorite: favoriteStationIDs.contains(heroStation.id),
                        isCurrentStation: audioPlayer.isCurrent(heroStation),
                        isPlaying: audioPlayer.isCurrent(heroStation) && audioPlayer.isPlaying,
                        isLoading: audioPlayer.isCurrent(heroStation) && audioPlayer.isLoading,
                        stationFeedback: stationFeedback[heroStation.id],
                        playAction: {
                            if audioPlayer.isCurrent(heroStation) {
                                audioPlayer.togglePlayback()
                            } else {
                                playStation(heroStation, featuredQueueSource, featuredQueueStations)
                            }
                        },
                        favoriteAction: { toggleFavorite(heroStation) },
                        feedbackAction: { feedback in
                            let nextFeedback = stationFeedback[heroStation.id] == feedback ? nil : feedback
                            setStationFeedback(heroStation, nextFeedback)
                        },
                        detailsAction: { showStationDetails(heroStation, featuredQueueSource, featuredQueueStations) }
                    )

                } else {
                    EmptyLibraryState(
                        title: L10n.string("shell.home.empty.title"),
                        detail: L10n.string("shell.home.empty.detail")
                    )
                }

                if !derivedState.moodGenreTags.isEmpty {
                    HomeMoodGenreDesk(tags: derivedState.moodGenreTags, selectTag: openSearchTag)
                }

                if !derivedState.displayedAviPickStations.isEmpty {
                    StationSection(
                        title: L10n.string("shell.home.aviPicks.title"),
                        subtitle: L10n.string("shell.home.aviPicks.subtitle"),
                        accessibilityIdentifier: "home.section.aviPicks"
                    ) {
                        StationCompactCarousel(
                            stations: derivedState.displayedAviPickStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            stationInsight: { derivedState.recommendationInsights[$0.id] },
                            stationFeedback: stationFeedback,
                            queueSource: .homeDiscovery,
                            queueStations: derivedState.displayedAviPickStations,
                            playStation: playStation,
                            toggleFavorite: toggleFavorite,
                            showStationDetails: showStationDetails
                        )
                    }
                }

                if !derivedState.displayedAroundYouStations.isEmpty {
                    StationSection(
                        title: L10n.string("shell.home.aroundYou.title"),
                        subtitle: L10n.string("shell.home.aroundYou.subtitle"),
                        accessibilityIdentifier: "home.section.aroundYou"
                    ) {
                        StationCompactCarousel(
                            stations: derivedState.displayedAroundYouStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            stationInsight: { derivedState.recommendationInsights[$0.id] },
                            stationFeedback: stationFeedback,
                            queueSource: .homeDiscovery,
                            queueStations: derivedState.displayedAroundYouStations,
                            playStation: playStation,
                            toggleFavorite: toggleFavorite,
                            showStationDetails: showStationDetails
                        )
                    }
                }

                if !derivedState.displayedRecentStations.isEmpty || !derivedState.displayedFavoriteStations.isEmpty {
                    StationSection(title: L10n.string("shell.home.recentsFavorites.title"), subtitle: L10n.string("shell.home.recentsFavorites.subtitle"), accessibilityIdentifier: "home.section.recentsFavorites") {
                        StationCompactCarousel(
                            stations: derivedState.displayedRecentAndFavoriteStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            stationInsight: { station in stationFeedback[station.id]?.localizedState },
                            stationFeedback: stationFeedback,
                            queueSource: .homeRecents,
                            queueStations: derivedState.displayedRecentAndFavoriteStations,
                            playStation: playStation,
                            toggleFavorite: toggleFavorite,
                            showStationDetails: showStationDetails
                        )
                    }
                }
            }
            .shellScreenContentPadding(bottom: bottomContentPadding)
        }
        .shellScreenScrollBehavior()
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .refreshable {
            await refreshHome()
        }
    }

    private func cleanedFeaturedDetail(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value, excluding: Station.unknownDetailValues, locale: L10n.locale)
    }

    private func localizedCountryName(for station: Station) -> String? {
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            return L10n.countryName(for: countryCode)
        }

        return cleanedFeaturedDetail(station.country)
    }

    private func homePresentation(for station: Station) -> HomeStationPresentation {
        let source = heroSource
        let currentTrack = currentTrackLine(for: station)
        let context = stationContextLine(for: station)
        let label = heroLabel(for: source, station: station)
        let hasReliableProgramData = currentTrack != nil
        let badges = hasReliableProgramData ? [stationCategoryLabel(for: station)].compactMap { $0 }.prefix(2).map { $0 } : []

        return HomeStationPresentation(
            tier: hasReliableProgramData ? .rich : .fallback,
            label: label,
            title: station.name,
            primaryLine: currentTrack ?? context,
            secondaryLine: currentTrack == nil ? nil : context,
            badges: badges
        )
    }

    private func currentTrackLine(for station: Station) -> String? {
        guard audioPlayer.isCurrent(station) else { return nil }
        guard let title = TuneAVDisplayMetadata.normalized(audioPlayer.currentTrackTitle) else { return nil }
        guard !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(title, stationName: station.name) else { return nil }

        if
            let artist = TuneAVDisplayMetadata.normalized(audioPlayer.currentTrackArtist),
            !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(artist, stationName: station.name)
        {
            return "\(artist) · \(title)"
        }

        return title
    }

    private func stationContextLine(for station: Station) -> String? {
        let country = localizedCountryName(for: station).map { country in
            if let flag = station.flagEmoji {
                return "\(flag) \(country)"
            }
            return country
        }
        let language = cleanedFeaturedDetail(station.language)
        let values = [country, language]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
                result.append(value)
            }

        guard !values.isEmpty else { return nil }
        return values.prefix(2).joined(separator: " · ")
    }

    private func stationCategoryLabel(for station: Station) -> String? {
        let tags = station.tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let preferredTags = ["music", "pop", "rock", "jazz", "news", "talk", "sports", "classical", "electronic", "latin", "ambient", "country"]
        if let tag = tags.first(where: { tag in preferredTags.contains { tag.localizedCaseInsensitiveContains($0) } }) {
            return tag.capitalized(with: L10n.locale)
        }

        return nil
    }

    private func heroLabel(for source: FeaturedSource?, station: Station) -> String {
        if audioPlayer.isCurrent(station) {
            return L10n.string("shell.liveNow.title")
        }

        switch source {
        case .favorite:
            return L10n.string("shell.home.favorites.title")
        case .lastPlayed:
            return L10n.string("shell.home.featured.continueListening")
        case .recent:
            return L10n.string("shell.home.recents.title")
        case .current:
            return L10n.string("shell.liveNow.title")
        case .popular, .none:
            return featuredLabel
        }
    }

    private var hasPersonalActivity: Bool {
        !recentStations.isEmpty || !favoriteStations.isEmpty
    }

    private var shouldShowLiveNowPanel: Bool {
        audioPlayer.currentStation == nil && !hasPersonalActivity && heroStation == nil
    }

    private var heroSource: FeaturedSource? {
        if audioPlayer.currentStation != nil {
            return .current
        }
        return featuredSource
    }

    private var heroStation: Station? {
        audioPlayer.currentStation ?? featuredStation
    }

    private var featuredSource: FeaturedSource? {
        if lastPlayedStation != nil {
            return .lastPlayed
        }
        if !favoriteStations.isEmpty {
            return .favorite
        }
        if !stations.isEmpty {
            return .popular
        }
        return nil
    }

    private var featuredStation: Station? {
        switch featuredSource {
        case .current:
            return audioPlayer.currentStation
        case .lastPlayed:
            return lastPlayedStation
        case .recent:
            return nil
        case .favorite:
            return favoriteStations.first
        case .popular:
            return stations.first
        case .none:
            return nil
        }
    }

    private var featuredStationID: String? {
        heroStation?.id
    }

    private var homeDerivedState: DerivedState {
        let displayedRecentStations = displayedRecentStations
        let displayedFavoriteStations = displayedFavoriteStations
        let displayedPopularStations = displayedPopularStations(
            displayedRecentStations: displayedRecentStations,
            displayedFavoriteStations: displayedFavoriteStations
        )
        let displayedAviPickStations = Array(displayedPopularStations.prefix(4))
        let displayedAroundYouStations = displayedAroundYouStations(
            displayedPopularStations: displayedPopularStations,
            displayedAviPickStations: displayedAviPickStations
        )
        let displayedRecentAndFavoriteStations = Array(
            AppShellNowPlayingPreviews.uniqueStations(displayedRecentStations + displayedFavoriteStations).prefix(8)
        )
        let visibleDiscoveryTags = displayedPopularStations
            .prefix(8)
            .flatMap(\.normalizedTags)
            .map { $0.lowercased() }
        let moodGenreTags = moodGenreTags(visibleDiscoveryTags: visibleDiscoveryTags)
        let scorer = recommendationScorer
        let recommendationInsights = Dictionary(
            uniqueKeysWithValues: (displayedAviPickStations + displayedAroundYouStations).map { station in
                (
                    station.id,
                    TuneAVLocalRecommendationScorer.localizedSummary(
                        for: scorer.rank(station).primaryReason
                    ) ?? L10n.string("shell.avi.recommendation.reasonFallback")
                )
            }
        )

        return DerivedState(
            displayedRecentStations: displayedRecentStations,
            displayedFavoriteStations: displayedFavoriteStations,
            displayedPopularStations: displayedPopularStations,
            displayedAviPickStations: displayedAviPickStations,
            displayedAroundYouStations: displayedAroundYouStations,
            displayedRecentAndFavoriteStations: displayedRecentAndFavoriteStations,
            moodGenreTags: moodGenreTags,
            recommendationInsights: recommendationInsights
        )
    }

    private var displayedRecentStations: [Station] {
        Array(filteredStationsExcludingFeatured(from: recentStations).prefix(6))
    }

    private var displayedFavoriteStations: [Station] {
        Array(filteredStationsExcludingFeatured(from: favoriteStations).prefix(6))
    }

    private func displayedPopularStations(displayedRecentStations: [Station], displayedFavoriteStations: [Station]) -> [Station] {
        let excludedIDs = Set(displayedRecentStations.map(\.id) + displayedFavoriteStations.map(\.id))

        let candidates = filteredStationsExcludingFeatured(from: stations)
            .filter { !excludedIDs.contains($0.id) }

        return recommendationScorer.rankedStations(candidates).map(\.station)
    }

    private func displayedAroundYouStations(displayedPopularStations: [Station], displayedAviPickStations: [Station]) -> [Station] {
        let preferredCountry = TuneAVCountry.sanitizedCode(preferredCountryCode)
        let currentCountry = TuneAVCountry.sanitizedCode(audioPlayer.currentStation?.countryCode)
        let country = preferredCountry ?? currentCountry

        guard let country else {
            return Array(displayedPopularStations.dropFirst(4).prefix(6))
        }

        let aviPickIDs = Set(displayedAviPickStations.map(\.id))
        return HomeAroundYouStationSelector.select(
            from: displayedPopularStations,
            excluding: aviPickIDs,
            countryCode: country,
            limit: 6
        )
    }

    private func moodGenreTags(visibleDiscoveryTags: [String]) -> [HomeMoodGenreSuggestion] {
        TuneAVMusicGenreCatalog.visibleTags.map { tag in
            HomeMoodGenreSuggestion(
                tag: tag,
                title: L10n.genreLabel(for: tag).capitalized(with: L10n.locale)
            )
        }
    }

    private var recommendationScorer: TuneAVLocalRecommendationScorer {
        TuneAVLocalRecommendationScorer(
            currentStation: audioPlayer.currentStation,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            discoveries: discoveries,
            stationFeedback: stationFeedback,
            feedContext: feedContext,
            preferredTag: preferredTag,
            currentCountryCode: preferredCountryCode
        )
    }

    private var featuredQueueSource: AudioPlayerService.PlaybackQueue.Source {
        switch heroSource {
        case .current:
            return .singleStation
        case .lastPlayed:
            return .homeRecents
        case .recent:
            return .homeRecents
        case .favorite:
            return .homeFavorites
        case .popular, .none:
            return .homeDiscovery
        }
    }

    private var featuredQueueStations: [Station] {
        switch heroSource {
        case .current:
            return audioPlayer.currentStation.map { [$0] } ?? []
        case .lastPlayed:
            return [lastPlayedStation].compactMap { $0 }
        case .recent:
            return recentStations
        case .favorite:
            return favoriteStations
        case .popular, .none:
            return stations
        }
    }

    private func filteredStationsExcludingFeatured(from stations: [Station]) -> [Station] {
        guard let featuredStationID else { return stations }
        return stations.filter { $0.id != featuredStationID }
    }

    private var featuredLabel: String {
        switch featuredSource {
        case .recent:
            return L10n.string("shell.home.featured.frontPage").uppercased(with: .current)
        case .favorite:
            return L10n.string("shell.home.featured.frontPage").uppercased(with: .current)
        case .current:
            return L10n.string("shell.liveNow.title").uppercased(with: .current)
        case .lastPlayed:
            return L10n.string("shell.home.featured.continueListening").uppercased(with: .current)
        case .popular, .none:
            break
        }

        switch feedContext {
        case .preferredGenre:
            return L10n.string("shell.home.featured.frontPage").uppercased(with: .current)
        case .popularInCountry(let countryCode):
            let countryName = L10n.countryName(for: countryCode)
            return countryName.uppercased(with: .current)
        case .popularWorldwide:
            return L10n.string("shell.home.featured.popular").uppercased(with: .current)
        }
    }

    private var sectionTitle: String {
        if hasPersonalActivity {
            return L10n.string("shell.home.section.freshPicks.title")
        }

        switch feedContext {
        case .preferredGenre(let tag):
            return L10n.string("shell.home.section.topGenre.title", L10n.genreLabel(for: tag))
        case .popularInCountry(let countryCode):
            let countryName = L10n.countryName(for: countryCode)
            return L10n.string("shell.home.section.popularCountry.title", countryName)
        case .popularWorldwide:
            return L10n.string("shell.home.section.popularWorldwide.title")
        }
    }

    private var sectionSubtitle: String {
        if hasPersonalActivity {
            return L10n.string("shell.home.section.freshPicks.subtitle")
        }

        switch feedContext {
        case .preferredGenre:
            return L10n.string("shell.home.section.topGenre.subtitle")
        case .popularInCountry(let countryCode):
            let countryName = L10n.countryName(for: countryCode)
            return L10n.string("shell.home.section.popularCountry.subtitle", countryName)
        case .popularWorldwide:
            return L10n.string("shell.home.section.popularWorldwide.subtitle")
        }
    }
}

private struct SearchScreen: View {
    @Binding var query: String
    @Binding var activeTag: String?
    @Binding var selectedCountryCode: String?
    @Binding var discoveryMode: TuneAVStationDiscoveryMode

    let results: [Station]
    let isLoading: Bool
    let errorMessage: String?
    let tags: [String]
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var isShowingCountryPicker = false
    @State private var browserDestination: BrowserDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: queryText.isEmpty ? 20 : 14) {
                AviScreenHeader(
                    emotion: TuneAVAviEmotionResolver.searchEmotion(
                        isLoading: isLoading,
                        hasResults: !results.isEmpty,
                        query: queryText,
                        discoveryMode: discoveryMode
                    ),
                    title: L10n.string("shell.search.title"),
                    summary: searchAviDetail,
                    showsAviImage: false,
                    accessibilityIdentifier: "search.aviHeader"
                )

                SearchField(query: $query)
                SearchCountryFilterButton(
                    title: selectedCountryTitle,
                    flag: selectedCountryFlag,
                    isActive: selectedCountryCode != nil,
                    clearAction: clearCountryFilter,
                    openAction: { isShowingCountryPicker = true }
                )
                Picker(L10n.string("shell.search.discoveryMode"), selection: $discoveryMode) {
                    Text(L10n.string("shell.search.discoveryMode.music")).tag(TuneAVStationDiscoveryMode.music)
                    Text(L10n.string("shell.search.discoveryMode.allRadio")).tag(TuneAVStationDiscoveryMode.allRadio)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("search.discoveryMode")

                if queryText.isEmpty {
                    GenreTagStrip(tags: visibleTags, activeTag: activeTag, toggleTag: toggleTag)
                }

                StationSection(
                    title: queryText.isEmpty && activeTag == nil && selectedCountryCode != nil
                        ? L10n.string("shell.search.section.country.title", selectedCountryTitle)
                        : queryText.isEmpty && activeTag == nil
                            ? L10n.string("shell.search.section.popularWorldwide.title")
                        : queryText.isEmpty
                            ? L10n.string("shell.search.section.browse.title")
                            : L10n.string("shell.search.section.results.title"),
                    subtitle: queryText.isEmpty
                        ? browseSubtitle
                        : L10n.plural(
                            singular: "shell.search.results.count.one",
                            plural: "shell.search.results.count.other",
                            count: results.count,
                            results.count,
                            queryText
                        ),
                    accessibilityIdentifier: "search.section.results"
                ) {
                    if !results.isEmpty {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, station in
                                StationListActionRow(
                                    station: station,
                                    isFavorite: favoriteStationIDs.contains(station.id),
                                    nowPlayingTrack: nowPlayingTracks[station.id],
                                    stationFeedback: stationFeedback[station.id],
                                    toggleFavorite: { toggleFavorite(station) },
                                    playAction: { playStation(station, .searchResults, results) },
                                    openWebsiteAction: { openStationWebsite(station) },
                                    detailsAction: { showStationDetails(station, .searchResults, results) }
                                )
                                .zIndex(Double(results.count - index))
                            }
                        }
                    } else if isLoading {
                        SearchLoadingCard()
                    } else if let errorMessage {
                        EmptyLibraryState(
                            title: L10n.string("shell.search.error.title"),
                            detail: errorMessage
                        )
                    } else if results.isEmpty {
                        EmptyLibraryState(
                            title: L10n.string("shell.search.empty.title"),
                            detail: queryText.isEmpty && activeTag == nil
                                ? L10n.string("shell.search.empty.detail.initial")
                                : L10n.string("shell.search.empty.detail.retry")
                        )
                    }
                }
            }
            .shellScreenContentPadding(bottom: bottomContentPadding)
        }
        .shellScreenScrollBehavior()
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(isPresented: $isShowingCountryPicker) {
            SearchCountryPickerSheet(selectedCountryCode: $selectedCountryCode)
                .environmentObject(libraryStore)
        }
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .onChange(of: selectedCountryCode) { _, newValue in
            libraryStore.setPreferredCountry(newValue)
        }
    }

    private var queryText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleTag(_ tag: String) {
        activeTag = activeTag == tag ? nil : tag
    }

    private var visibleTags: [String] {
        switch discoveryMode {
        case .music:
            return tags
        case .allRadio:
            return tags + ["news", "sports", "talk", "culture", "local", "public", "religion"]
        }
    }

    private var searchAviDetail: String {
        if discoveryMode == .allRadio {
            return L10n.string("shell.search.avi.detail.allRadio")
        }
        if let activeTag {
            return L10n.string("shell.search.avi.detail.genre", L10n.genreLabel(for: activeTag))
        }
        return L10n.string("shell.search.avi.detail.music")
    }

    private var selectedCountryTitle: String {
        guard let selectedCountryCode else {
            return L10n.string("shell.search.country.all")
        }

        return L10n.countryName(for: selectedCountryCode)
    }

    private var browseSubtitle: String {
        if selectedCountryCode != nil {
            return L10n.string("shell.search.section.country.subtitle", selectedCountryTitle)
        }

        if activeTag == nil {
            return L10n.string("shell.search.section.popularWorldwide.subtitle")
        }

        return L10n.string("shell.search.section.browse.subtitle")
    }

    private func clearCountryFilter() {
        selectedCountryCode = nil
        libraryStore.setPreferredCountry(nil)
    }

    private func openStationWebsite(_ station: Station) {
        guard let url = station.resolvedHomepageURL else { return }
        browserDestination = BrowserDestination(url: url)
    }

    private var selectedCountryFlag: String? {
        guard let selectedCountryCode else { return nil }
        return CountryOption(code: selectedCountryCode, name: selectedCountryTitle).flag
    }
}

private struct LibraryScreen: View {
    private static let pageSize = 40
    private static let overviewLimit = 12

    private struct DerivedState {
        let overviewRecentStations: [Station]
        let overviewFavoriteStations: [Station]
        let overviewTunedStations: [Station]
        let overviewMusicStations: [Station]
        let musicStationCount: Int
        let activeStationSnapshot: RadioStationListSnapshot

        var hasRadioOverviewContent: Bool {
            !overviewFavoriteStations.isEmpty
                || !overviewRecentStations.isEmpty
                || !overviewTunedStations.isEmpty
                || !overviewMusicStations.isEmpty
        }
    }

    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var query = ""
    @State private var isSearchExpanded = false
    @State private var selectedMode: RadioLibraryMode = .saved
    @State private var isShowingOverview = true
    @State private var visibleLimit = pageSize
    @AppStorage("tuneav.radio.savedSort") private var savedSortRawValue = RadioSavedSort.lastListened.rawValue
    @AppStorage("tuneav.radio.recentSort") private var recentSortRawValue = RadioSavedSort.lastListened.rawValue

    let favorites: [Station]
    let recents: [Station]
    let discoveries: [DiscoveredTrack]
    let summary: TuneAVUserSummary?
    @Binding var requestedMode: RadioLibraryMode?
    @Binding var requestedOverview: Bool?
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let openAccountAction: () -> Void
    let startSignInAction: () -> Void
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?, RadioLibraryMode?, Bool?) -> Void
    @State private var browserDestination: BrowserDestination?

    var body: some View {
        let showsOverview = isShowingOverview && trimmedQuery.isEmpty
        let derivedState = radioDerivedState(includeDetail: !showsOverview)

        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if showsOverview {
                        AviScreenHeader(
                            emotion: TuneAVAviEmotionResolver.libraryEmotion(
                                favoriteCount: favorites.count,
                                recentCount: recents.count,
                                isFiltering: false
                            ),
                            title: L10n.string("shell.library.title"),
                            summary: libraryAviDetail,
                            showsAviImage: false,
                            accessibilityIdentifier: "library.aviHeader"
                        )

                        radioOverview(derivedState)
                    } else {
                        Color.clear
                            .frame(height: detailHeaderReservedHeight)

                        radioDetailSection(derivedState)
                    }
                }
                .shellScreenContentPadding(bottom: bottomContentPadding)
                .id(screenIdentity)
            }
            .shellScreenScrollBehavior()

            if !showsOverview {
                stickyDetailHeader
            }
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .onAppear {
            normalizeInitialMode()
            consumeRequestedRadioReturnIfNeeded()
        }
        .onChange(of: requestedMode) { _, _ in
            consumeRequestedRadioReturnIfNeeded()
        }
        .onChange(of: requestedOverview) { _, _ in
            consumeRequestedRadioReturnIfNeeded()
        }
        .onChange(of: query) { _, _ in
            visibleLimit = Self.pageSize
        }
        .onChange(of: selectedMode) { _, _ in
            visibleLimit = Self.pageSize
        }
        .onChange(of: savedSortRawValue) { _, _ in
            visibleLimit = Self.pageSize
        }
        .onChange(of: recentSortRawValue) { _, _ in
            visibleLimit = Self.pageSize
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func consumeRequestedRadioReturnIfNeeded() {
        if let requestedOverview {
            isShowingOverview = requestedOverview
            if requestedOverview {
                query = ""
                isSearchExpanded = false
            }
            self.requestedOverview = nil
        }
        if let requestedMode {
            selectedMode = requestedMode
            isShowingOverview = false
            self.requestedMode = nil
        }
        visibleLimit = Self.pageSize
    }

    private var detailHeaderReservedHeight: CGFloat {
        86
    }

    private var stickyDetailHeader: some View {
        RadioDetailHeader(
            title: selectedMode.title,
            subtitle: selectedMode.subtitle,
            goBack: showOverview
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            TuneAVTheme.shellBackground
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TuneAVTheme.borderSubtle.opacity(0.55))
                .frame(height: 1)
        }
    }

    private var screenIdentity: String {
        if isShowingOverview && trimmedQuery.isEmpty {
            return "library-overview"
        }
        return "library-detail-\(selectedMode.rawValue)"
    }

    private func radioOverview(_ derivedState: DerivedState) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if accessController.capabilities.canAccessPremiumFeatures {
                AccountSummaryStatusCard(
                    kind: .radios,
                    state: libraryStore.userSummaryRefreshState,
                    summary: summary,
                    isSignedIn: accessController.isSignedIn,
                    hasProAccess: true,
                    openAccountAction: openAccountAction,
                    startSignInAction: startSignInAction,
                    refreshAction: {
                        await libraryStore.refreshUserSummary(force: true)
                    }
                )
            }

            if derivedState.hasRadioOverviewContent {
                RadioOverviewMetricGrid {
                    RadioOverviewMetricCard(
                        title: L10n.string("shell.library.overview.saved"),
                        value: summary?.radio.cards.saved.count ?? favorites.count,
                        systemImage: "dot.radiowaves.left.and.right",
                        tint: TuneAVTheme.highlight,
                        action: { openMode(.saved) }
                    )
                    RadioOverviewMetricCard(
                        title: L10n.string("shell.library.overview.recent"),
                        value: summary?.radio.cards.recent.count ?? recents.count,
                        systemImage: "clock.fill",
                        tint: Color(red: 0.17, green: 0.52, blue: 0.96),
                        action: { openMode(.recent) }
                    )
                    RadioOverviewMetricCard(
                        title: L10n.string("shell.library.overview.tuned"),
                        value: summary?.radio.cards.tuned.count ?? stationFeedback.count,
                        systemImage: "slider.horizontal.3",
                        tint: Color(red: 0.95, green: 0.48, blue: 0.18),
                        action: { openMode(.tuned) }
                    )
                    RadioOverviewMetricCard(
                        title: L10n.string("shell.library.overview.musicStationsShort"),
                        value: derivedState.musicStationCount,
                        systemImage: "music.note.list",
                        tint: Color(red: 0.54, green: 0.43, blue: 0.90),
                        action: { openMode(.music) }
                    )
                }

                radioOverviewSectionIfNeeded(
                    stations: derivedState.overviewFavoriteStations,
                    title: L10n.string("shell.library.overview.saved"),
                    subtitle: L10n.string("shell.library.favorites.subtitle"),
                    queueSource: .libraryFavorites,
                    accessibilityIdentifier: "library.section.favorites",
                    action: { openMode(.saved) }
                )

                radioOverviewSectionIfNeeded(
                    stations: derivedState.overviewRecentStations,
                    title: L10n.string("shell.library.overview.latest.title"),
                    subtitle: L10n.string("shell.library.recents.subtitle"),
                    queueSource: .libraryRecents,
                    action: { openMode(.recent) }
                )

                radioOverviewSectionIfNeeded(
                    stations: derivedState.overviewTunedStations,
                    title: L10n.string("shell.library.overview.tuned"),
                    subtitle: L10n.string("shell.avi.signals.feedback.title"),
                    queueSource: .libraryFavorites,
                    action: { openMode(.tuned) }
                )

                radioOverviewSectionIfNeeded(
                    stations: derivedState.overviewMusicStations,
                    title: L10n.string("shell.library.overview.musicStations"),
                    subtitle: L10n.string("shell.library.musicStations.subtitle"),
                    queueSource: .libraryRecents,
                    action: { openMode(.music) }
                )
            } else {
                EmptyLibraryState(
                    title: L10n.string("shell.library.overview.empty"),
                    detail: L10n.string("shell.library.overview.empty.detail")
                )
            }
        }
    }

    @ViewBuilder
    private func radioOverviewSectionIfNeeded(
        stations: [Station],
        title: String,
        subtitle: String,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        if !stations.isEmpty {
            RadioOverviewCarouselSection(
                title: title,
                subtitle: subtitle,
                accessibilityIdentifier: accessibilityIdentifier,
                action: action
            ) {
                radioOverviewCarousel(stations: stations, queueSource: queueSource)
            }
        }
    }

    private func radioOverviewCarousel(stations: [Station], queueSource: AudioPlayerService.PlaybackQueue.Source) -> some View {
        StationCompactCarousel(
            stations: stations,
            favoriteStationIDs: favoriteStationIDs,
            nowPlayingTracks: nowPlayingTracks,
            stationInsight: radioOverviewInsight(for:),
            stationFeedback: stationFeedback,
            queueSource: queueSource,
            queueStations: stations,
            playStation: playStation,
            toggleFavorite: toggleFavorite,
            showStationDetails: { station, source, queue in
                showStationDetails(station, source, queue, nil, true)
            }
        )
    }

    private func radioDetailSection(_ derivedState: DerivedState) -> some View {
        let snapshot = derivedState.activeStationSnapshot
        return VStack(alignment: .leading, spacing: 12) {
            if snapshot.filteredStations.isEmpty {
                EmptyLibraryState(
                    title: snapshot.baseStations.isEmpty ? selectedMode.emptyTitle : L10n.string("shell.library.noMatch.title"),
                    detail: snapshot.baseStations.isEmpty
                        ? selectedMode.emptyDetail
                        : L10n.string("shell.library.favorites.noMatch.detail")
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(snapshot.visibleStations.enumerated()), id: \.element.id) { index, station in
                        StationListActionRow(
                            station: station,
                            isFavorite: favoriteStationIDs.contains(station.id),
                            nowPlayingTrack: nowPlayingTracks[station.id],
                            stationFeedback: stationFeedback[station.id],
                            toggleFavorite: { toggleFavorite(station) },
                            playAction: { playStation(station, queueSource(for: selectedMode), snapshot.filteredStations) },
                            openWebsiteAction: { openStationWebsite(station) },
                            detailsAction: { showStationDetails(station, queueSource(for: selectedMode), snapshot.filteredStations, selectedMode, false) }
                        )
                        .zIndex(Double(snapshot.visibleStations.count - index))
                    }

                    if snapshot.canShowMore {
                        ShowMoreButton(
                            title: L10n.string("common.showMore"),
                            remainingCount: snapshot.filteredStations.count - snapshot.visibleStations.count,
                            action: showMoreStations
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier("library.section.\(selectedMode.rawValue)")
    }

    private func radioDerivedState(includeDetail: Bool) -> DerivedState {
        let tunedStations = (favorites + recents).uniquedByStationID().filter { stationFeedback[$0.id] != nil }
        let musicStations = musicStations
        let activeStationSnapshot = includeDetail
            ? activeStationSnapshot(tunedStations: tunedStations, musicStations: musicStations)
            : RadioStationListSnapshot(baseStations: [], filteredStations: [], visibleStations: [])
        return DerivedState(
            overviewRecentStations: Array(recents.prefix(Self.overviewLimit)),
            overviewFavoriteStations: Array(favorites.prefix(Self.overviewLimit)),
            overviewTunedStations: Array(tunedStations.prefix(Self.overviewLimit)),
            overviewMusicStations: Array(musicStations.prefix(Self.overviewLimit)),
            musicStationCount: musicStations.count,
            activeStationSnapshot: activeStationSnapshot
        )
    }

    private func activeStationSnapshot(tunedStations: [Station], musicStations: [Station]) -> RadioStationListSnapshot {
        let recentRanks = recentRanksByStationID
        let baseStations: [Station]

        switch selectedMode {
        case .saved:
            baseStations = sortedStations(favorites, sort: savedSort, recentRanks: recentRanks)
        case .recent:
            baseStations = sortedStations(recents, sort: recentSort, recentRanks: recentRanks)
        case .tuned:
            baseStations = sortedStations(tunedStations, sort: savedSort, recentRanks: recentRanks)
        case .music:
            baseStations = sortedStations(musicStations, sort: recentSort, recentRanks: recentRanks)
        }

        let filteredStations = filterStations(baseStations)
        return RadioStationListSnapshot(
            baseStations: baseStations,
            filteredStations: filteredStations,
            visibleStations: Array(filteredStations.prefix(visibleLimit))
        )
    }

    private func radioOverviewInsight(for station: Station) -> String? {
        stationFeedback[station.id]?.localizedState
            ?? nowPlayingTracks[station.id]?.title
            ?? station.primaryDetailLine
    }

    private var savedSort: RadioSavedSort {
        RadioSavedSort(rawValue: savedSortRawValue) ?? .recentlyAdded
    }

    private var recentSort: RadioSavedSort {
        RadioSavedSort(rawValue: recentSortRawValue) ?? .lastListened
    }

    private var activeSort: RadioSavedSort {
        switch selectedMode {
        case .saved, .tuned:
            return savedSort
        case .recent, .music:
            return recentSort
        }
    }

    private var musicStations: [Station] {
        discoveries.compactMap { discovery in
            recents.first { $0.id == discovery.stationID } ?? favorites.first { $0.id == discovery.stationID }
        }.uniquedByStationID()
    }

    private func sortedStations(_ stations: [Station], sort: RadioSavedSort, recentRanks: [String: Int]) -> [Station] {
        switch sort {
        case .recentlyAdded:
            return stations
        case .alphabetical:
            return stations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastListened:
            let recentRanks = recentRanksByStationID
            return stations.sorted { first, second in
                lastListenedSort(first, second, recentRanks: recentRanks)
            }
        }
    }

    private var recentRanksByStationID: [String: Int] {
        Dictionary(uniqueKeysWithValues: recents.enumerated().map { index, station in (station.id, index) })
    }

    private func lastListenedSort(_ first: Station, _ second: Station, recentRanks: [String: Int]) -> Bool {
        let firstRank = recentRanks[first.id] ?? Int.max
        let secondRank = recentRanks[second.id] ?? Int.max
        if firstRank == secondRank {
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
        return firstRank < secondRank
    }

    private func filterStations(_ stations: [Station]) -> [Station] {
        TuneAVLibraryStationLogic.filteredStations(stations, query: trimmedQuery)
    }

    private func openMode(_ mode: RadioLibraryMode) {
        TuneAVHaptics.selection()
        selectedMode = mode
        isShowingOverview = false
        visibleLimit = Self.pageSize
    }

    private func showOverview() {
        TuneAVHaptics.selection()
        query = ""
        isSearchExpanded = false
        visibleLimit = Self.pageSize
        withAnimation(.snappy(duration: 0.22)) {
            isShowingOverview = true
        }
    }

    private func setActiveSort(_ sort: RadioSavedSort) {
        guard activeSort != sort else { return }
        TuneAVHaptics.selection()
        switch selectedMode {
        case .saved, .tuned:
            savedSortRawValue = sort.rawValue
        case .recent, .music:
            recentSortRawValue = sort.rawValue
        }
    }

    private func toggleSearch() {
        TuneAVHaptics.selection()
        isShowingOverview = false
        withAnimation(.snappy(duration: 0.22)) {
            isSearchExpanded.toggle()
        }
    }

    private func showMoreStations() {
        TuneAVHaptics.lightImpact()
        visibleLimit += Self.pageSize
    }

    private func normalizeInitialMode() {
        guard favorites.isEmpty else { return }
        if !recents.isEmpty {
            selectedMode = .recent
        }
    }

    private func queueSource(for mode: RadioLibraryMode) -> AudioPlayerService.PlaybackQueue.Source {
        switch mode {
        case .saved, .tuned:
            return .libraryFavorites
        case .recent, .music:
            return .libraryRecents
        }
    }

    private func openStationWebsite(_ station: Station) {
        guard let url = station.resolvedHomepageURL else { return }
        browserDestination = BrowserDestination(url: url)
    }

    private var libraryAviDetail: String {
        if favorites.isEmpty && recents.isEmpty {
            return L10n.string("shell.library.avi.detail.empty")
        }
        let savedText = L10n.plural(singular: "shell.count.savedRadio.one", plural: "shell.count.savedRadio.other", count: favorites.count, favorites.count)
        let recentText = L10n.plural(singular: "shell.count.recentSession.one", plural: "shell.count.recentSession.other", count: recents.count, recents.count)
        return L10n.string("shell.library.avi.detail.signals", savedText, recentText)
    }
}

private enum RadioLibraryMode: String, CaseIterable, Identifiable {
    case saved
    case recent
    case tuned
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved:
            return L10n.string("shell.library.mode.saved")
        case .recent:
            return L10n.string("shell.library.mode.recent")
        case .tuned:
            return L10n.string("shell.library.overview.tuned")
        case .music:
            return L10n.string("shell.library.overview.musicStations")
        }
    }

    var subtitle: String {
        switch self {
        case .saved:
            return L10n.string("shell.library.favorites.subtitle")
        case .recent:
            return L10n.string("shell.library.recents.subtitle")
        case .tuned:
            return L10n.string("shell.avi.signals.feedback.title")
        case .music:
            return L10n.string("shell.library.musicStations.subtitle")
        }
    }

    var emptyTitle: String {
        switch self {
        case .saved:
            return L10n.string("shell.library.favorites.empty")
        case .recent:
            return L10n.string("shell.library.recents.empty")
        case .tuned:
            return L10n.string("shell.library.overview.empty")
        case .music:
            return L10n.string("shell.library.overview.empty")
        }
    }

    var emptyDetail: String {
        switch self {
        case .saved:
            return L10n.string("shell.library.favorites.empty.detail")
        case .recent:
            return L10n.string("shell.library.recents.empty.detail")
        case .tuned, .music:
            return L10n.string("shell.library.overview.empty.detail")
        }
    }
}

private struct RadioStationListSnapshot {
    let baseStations: [Station]
    let filteredStations: [Station]
    let visibleStations: [Station]

    var canShowMore: Bool {
        visibleStations.count < filteredStations.count
    }
}

private enum RadioSavedSort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case alphabetical
    case lastListened

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded:
            return L10n.string("shell.library.sort.recentlyAdded")
        case .alphabetical:
            return L10n.string("shell.library.sort.alphabetical")
        case .lastListened:
            return L10n.string("shell.library.sort.lastListened")
        }
    }
}

private struct RadioDetailHeader: View {
    let title: String
    let subtitle: String
    let goBack: () -> Void

    var body: some View {
        DetailTopHeader(
            title: title,
            subtitle: subtitle,
            status: L10n.string("shell.common.radio"),
            accessibilityIdentifier: "library.detail.header",
            goBack: goBack
        )
    }
}

private struct ShowMoreButton: View {
    let title: String
    let remainingCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 16, weight: .bold))

                Text(L10n.string("common.showMoreCount", title, remainingCount))
                    .font(.system(size: 14, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(TuneAVTheme.highlight)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(TuneAVTheme.highlight.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("list.showMore")
    }
}

private struct RadioOverviewCarouselSection<Content: View>: View {
    let title: String
    let subtitle: String
    var accessibilityIdentifier: String?
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if let accessibilityIdentifier {
            section
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            section
        }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(L10n.string("common.view"))
                            .font(.system(size: 13, weight: .black))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .black))
                    }
                    .foregroundStyle(TuneAVTheme.highlight)
                }
                .buttonStyle(.plain)
            }

            content()
        }
    }
}

private struct RadioOverviewMetricGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            content
        }
    }
}

private enum AccountSummaryStatusKind {
    case radios
    case music

    var title: String {
        switch self {
        case .radios:
            return L10n.string("shell.summary.radios.title")
        case .music:
            return L10n.string("shell.summary.music.title")
        }
    }

    var systemImage: String {
        switch self {
        case .radios:
            return "antenna.radiowaves.left.and.right"
        case .music:
            return "music.note.list"
        }
    }
}

private struct AccountSummaryStatusCard: View {
    let kind: AccountSummaryStatusKind
    let state: TuneAVUserSummaryRefreshState
    let summary: TuneAVUserSummary?
    let isSignedIn: Bool
    let hasProAccess: Bool
    let openAccountAction: () -> Void
    let startSignInAction: () -> Void
    let refreshAction: () async -> Void

    @State private var isRefreshing = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(statusTint)
                .frame(width: 34, height: 34)
                .background(statusTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(kind.title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailingAction
        }
        .padding(14)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusTint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("summary.\(kind == .radios ? "radios" : "music")")
    }

    @ViewBuilder
    private var trailingAction: some View {
        if !isSignedIn {
            Button(action: startSignInAction) {
                Text(L10n.string("profile.account.connect"))
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(TuneAVTheme.highlight, in: Capsule())
            }
            .buttonStyle(.plain)
        } else if !hasProAccess {
            Button(action: openAccountAction) {
                Text(L10n.string("profile.summary.plan.detail.pro"))
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(TuneAVTheme.highlight, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task {
                    isRefreshing = true
                    await refreshAction()
                    isRefreshing = false
                }
            } label: {
                Image(systemName: isRefreshing || state == .loading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.highlight.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing || state == .loading)
            .accessibilityLabel(L10n.string("shell.summary.refresh"))
        }
    }

    private var statusImage: String {
        switch state {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .loaded:
            return kind.systemImage
        case .empty:
            return "tray"
        case .idle, .unavailable:
            return isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle"
        }
    }

    private var statusTint: Color {
        switch state {
        case .failed:
            return Color(red: 1.0, green: 0.17, blue: 0.38)
        case .loaded:
            return TuneAVTheme.highlight
        case .empty:
            return Color(red: 0.95, green: 0.48, blue: 0.18)
        case .loading:
            return Color(red: 0.17, green: 0.52, blue: 0.96)
        case .idle, .unavailable:
            return TuneAVTheme.textSecondary
        }
    }

    private var detail: String {
        guard isSignedIn else {
            return L10n.string("shell.summary.signIn")
        }

        guard hasProAccess else {
            return L10n.string("shell.summary.free")
        }

        switch state {
        case .loading:
            return L10n.string("shell.summary.loading")
        case .failed:
            return L10n.string("shell.summary.failed")
        case .loaded:
            return loadedDetail
        case .empty:
            return L10n.string("shell.summary.empty")
        case .idle, .unavailable:
            return L10n.string("shell.summary.ready")
        }
    }

    private var loadedDetail: String {
        guard let summary else {
            return L10n.string("shell.summary.ready")
        }

        switch kind {
        case .radios:
            let topWeekText = L10n.plural(singular: "shell.count.topWeekStation.one", plural: "shell.count.topWeekStation.other", count: summary.radio.cards.topWeek.count, summary.radio.cards.topWeek.count)
            let tunedText = L10n.plural(singular: "shell.count.tunedSignal.one", plural: "shell.count.tunedSignal.other", count: summary.radio.cards.tuned.count, summary.radio.cards.tuned.count)
            return L10n.string(
                "shell.summary.radios.loaded",
                topWeekText,
                tunedText
            )
        case .music:
            let detectedText = L10n.plural(singular: "shell.count.detectedSong.one", plural: "shell.count.detectedSong.other", count: summary.music.cards.history.count, summary.music.cards.history.count)
            let artistText = L10n.plural(singular: "shell.count.artist.one", plural: "shell.count.artist.other", count: summary.music.cards.artists.count, summary.music.cards.artists.count)
            return L10n.string(
                "shell.summary.music.loaded",
                detectedText,
                artistText
            )
        }
    }
}

private struct RadioOverviewMetricCard: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(
        title: String,
        value: Int,
        systemImage: String,
        tint: Color,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 4)

                Text("\(value)")
                    .font(.system(size: 17, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(TuneAVTheme.textPrimary)
            }
            .padding(10)
            .frame(minHeight: 48)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .modifyIfLet(accessibilityIdentifier) { view, identifier in
            view.accessibilityIdentifier(identifier)
        }
    }
}

private extension View {
    @ViewBuilder
    func modifyIfLet<Value, Modified: View>(
        _ value: Value?,
        transform: (Self, Value) -> Modified
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

private struct OverviewOptionGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            content
        }
    }
}

private struct OverviewOptionCard: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer(minLength: 8)

                    Text("\(value)")
                        .font(.system(size: 24, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 84)
            .padding(12)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(12)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }
}

private enum MusicContentMode: String, CaseIterable, Identifiable {
    case songs
    case artists
    case top
    case history

    var id: String { rawValue }

    init(libraryMode: MusicLibraryMode) {
        switch libraryMode {
        case .songs:
            self = .songs
        case .artists:
            self = .artists
        case .history:
            self = .history
        }
    }

    var libraryMode: MusicLibraryMode {
        switch self {
        case .songs:
            return .songs
        case .artists:
            return .artists
        case .top, .history:
            return .history
        }
    }

    var title: String {
        switch self {
        case .songs:
            return MusicLibraryMode.songs.title
        case .artists:
            return MusicLibraryMode.artists.title
        case .top:
            return L10n.string("shell.music.mode.top")
        case .history:
            return MusicLibraryMode.history.title
        }
    }

    var systemImage: String {
        switch self {
        case .songs:
            return "bookmark.fill"
        case .artists:
            return "person.2.fill"
        case .top:
            return "sparkles"
        case .history:
            return "clock.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .songs:
            return L10n.string("shell.music.detail.songs.subtitle")
        case .artists:
            return L10n.string("shell.music.detail.artists.subtitle")
        case .top:
            return L10n.string("shell.music.detail.top.subtitle")
        case .history:
            return L10n.string("shell.music.detail.history.subtitle")
        }
    }
}

private struct MusicLibraryDerivedState {
    let visibleDiscoveries: [DiscoveredTrack]
    let savedDiscoveries: [DiscoveredTrack]
    let tunedDiscoveries: [DiscoveredTrack]
    let visibleArtistSummaries: [DiscoveryArtistSummary]
    let filteredDiscoveries: [DiscoveredTrack]
    let visibleFilteredDiscoveries: [DiscoveredTrack]
    let filteredArtistSummaries: [DiscoveryArtistSummary]
    let visibleArtistSummariesForMode: [DiscoveryArtistSummary]
    let musicMode: MusicContentMode

    var hasOverviewContent: Bool {
        !savedDiscoveries.isEmpty
            || !visibleDiscoveries.isEmpty
            || !tunedDiscoveries.isEmpty
            || !visibleArtistSummaries.isEmpty
    }

    var isCurrentModeEmpty: Bool {
        switch musicMode {
        case .songs, .top, .history:
            return filteredDiscoveries.isEmpty
        case .artists:
            return filteredArtistSummaries.isEmpty
        }
    }

    var canShowMoreDiscoveries: Bool {
        visibleFilteredDiscoveries.count < filteredDiscoveries.count
    }

    var canShowMoreArtists: Bool {
        visibleArtistSummariesForMode.count < filteredArtistSummaries.count
    }
}

private enum MusicLibrarySort: String, CaseIterable, Identifiable {
    case recent
    case alphabetical
    case strongest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return L10n.string("shell.music.sort.recent")
        case .alphabetical:
            return L10n.string("shell.library.sort.alphabetical")
        case .strongest:
            return L10n.string("shell.music.sort.strongest")
        }
    }
}

private struct MusicLibraryControls: View {
    let savedCount: Int
    let historyCount: Int
    let artistCount: Int
    let stationCount: Int
    let selectedMode: MusicContentMode
    let selectMode: (MusicContentMode) -> Void
    let sort: MusicLibrarySort
    let setSort: (MusicLibrarySort) -> Void
    let isSearchExpanded: Bool
    let showOverview: () -> Void
    let toggleSearch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            overviewButton

            HStack(spacing: 4) {
                modeButton(.songs, value: savedCount)
                modeButton(.artists, value: artistCount)
                modeButton(.top, value: stationCount)
                modeButton(.history, value: historyCount)
            }
            .padding(4)
            .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }

            sortButton
            searchButton
        }
        .accessibilityElement(children: .contain)
    }

    private func modeButton(_ mode: MusicContentMode, value: Int) -> some View {
        Button {
            selectMode(mode)
        } label: {
            Image(systemName: mode.systemImage)
                .font(.system(size: 13, weight: .black))
            .foregroundStyle(selectedMode == mode ? Color.white : TuneAVTheme.textSecondary)
            .frame(width: 44, height: 40)
            .background(selectedMode == mode ? TuneAVTheme.highlight.opacity(0.86) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title), \(value)")
        .accessibilityIdentifier("music.mode.\(mode.rawValue)")
    }

    private var sortButton: some View {
        Menu {
            ForEach(MusicLibrarySort.allCases) { option in
                Button {
                    setSort(option)
                } label: {
                    Label(option.title, systemImage: option == sort ? "checkmark" : "line.3.horizontal.decrease")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(TuneAVTheme.mutedSurface, in: Capsule())
                .overlay {
                    Capsule().stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.music.sort.accessibilityLabel", sort.title))
        .accessibilityIdentifier("music.sort")
    }

    private var overviewButton: some View {
        Button(action: showOverview) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(TuneAVTheme.mutedSurface, in: Capsule())
                .overlay {
                    Capsule().stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.accessibility.showOverview"))
        .accessibilityIdentifier("music.overview")
    }

    private var searchButton: some View {
        Button(action: toggleSearch) {
            Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(isSearchExpanded ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(isSearchExpanded ? TuneAVTheme.highlight : TuneAVTheme.mutedSurface, in: Capsule())
                .overlay {
                    Capsule().stroke(isSearchExpanded ? TuneAVTheme.highlight.opacity(0.5) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.music.searchAccess.title"))
        .accessibilityIdentifier("music.searchToggle")
    }
}

private struct MusicDetailHeader: View {
    let title: String
    let subtitle: String
    let goBack: () -> Void

    var body: some View {
        DetailTopHeader(
            title: title,
            subtitle: subtitle,
            status: L10n.string("tab.music"),
            accessibilityIdentifier: "music.detail.header",
            goBack: goBack
        )
    }
}

private struct MusicScreen: View {
    private static let pageSize = 40
    private static let overviewLimit = 12

    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var query = ""
    @State private var musicMode: MusicContentMode = .songs
    @State private var isShowingOverview = true
    @AppStorage("tuneav.music.sort") private var musicSortRawValue = MusicLibrarySort.recent.rawValue
    @State private var isConfirmingClearDiscoveries = false
    @State private var isShowingDiscoveriesShare = false
    @State private var discoveriesShareTextDraft: String?
    @State private var browserDestination: BrowserDestination?
    @State private var hiddenDiscovery: DiscoveredTrack?
    @State private var selectedArtistName: String?
    @State private var isSearchExpanded = false
    @State private var visibleDiscoveryLimit = pageSize
    @State private var visibleArtistLimit = pageSize
    @State private var openMusicAviActionsID: String?

    let discoveries: [DiscoveredTrack]
    let summary: TuneAVUserSummary?
    @Binding var historyStationFilter: Station?
    @Binding var requestedMusicMode: MusicContentMode?
    @Binding var requestedMusicOverview: Bool?
    let bottomContentPadding: CGFloat
    let openDiscoveryStation: (DiscoveredTrack) -> Void
    let openDiscoveryStationInfo: (DiscoveredTrack) -> Void
    let openDiscoveryInfo: (DiscoveredTrack, MusicContentMode?) -> Void
    let openArtistInfo: (DiscoveryArtistSummary, MusicContentMode?) -> Void
    let stationArtworkURL: (DiscoveredTrack) -> URL?
    let trackFeedback: (DiscoveredTrack) -> TuneAVStationFeedback?
    let openAccountAction: () -> Void
    let startSignInAction: () -> Void
    let toggleDiscoverySaved: (DiscoveredTrack) -> Void
    let hideDiscovery: (DiscoveredTrack) -> Void
    let restoreDiscovery: (DiscoveredTrack) -> Void
    let removeDiscovery: (DiscoveredTrack) -> Void
    let clearDiscoveries: () -> Void

    private func runProAviAction(_ action: () -> Void) {
        guard accessController.capabilities.canAccessPremiumFeatures else {
            accessController.presentUpgradePrompt(for: .aviAction)
            return
        }
        action()
    }

    var body: some View {
        let snapshot = musicDerivedState
        let showsOverview = isShowingOverview && trimmedQuery.isEmpty && historyStationFilter == nil

        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if showsOverview {
                        AviScreenHeader(
                            emotion: TuneAVAviEmotionResolver.musicEmotion(
                                visibleDiscoveryCount: snapshot.visibleDiscoveries.count,
                                savedDiscoveryCount: snapshot.savedDiscoveries.count,
                                artistCount: snapshot.visibleArtistSummaries.count
                            ),
                            title: L10n.string("shell.music.title"),
                            summary: musicAviDetail(snapshot),
                            showsAviImage: false,
                            accessibilityIdentifier: "music.aviHeader"
                        )

                        musicOverview(snapshot)
                    } else {
                        Color.clear
                            .frame(height: musicDetailHeaderReservedHeight)

                        discoveryLibrarySection(snapshot)
                    }
                }
                .shellScreenContentPadding(bottom: bottomContentPadding)
            }
            .shellScreenScrollBehavior()

            if !showsOverview {
                stickyMusicDetailHeader
            }

            VStack {
                Spacer()
                hiddenDiscoveryUndoBanner
            }
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .confirmationDialog(
            L10n.string("shell.library.discoveries.clear.confirmTitle"),
            isPresented: $isConfirmingClearDiscoveries,
            titleVisibility: .visible
        ) {
            Button(L10n.string("shell.library.discoveries.clear.confirmAction"), role: .destructive) {
                clearDiscoveries()
            }
            .accessibilityIdentifier("Borrar descubrimientos")

            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("shell.library.discoveries.clear.confirmMessage"))
        }
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .sheet(
            isPresented: $isShowingDiscoveriesShare,
            onDismiss: { discoveriesShareTextDraft = nil }
        ) {
            ShareSheetView(items: [discoveriesShareTextDraft ?? discoveriesShareText(musicDerivedState)])
        }
        .onAppear {
            normalizeInitialDiscoveryFilter()
            consumeRequestedMusicReturnIfNeeded()
        }
        .onChange(of: query) { _, _ in
            selectedArtistName = nil
            openMusicAviActionsID = nil
            resetVisibleLimits()
        }
        .onChange(of: musicMode) { _, _ in
            openMusicAviActionsID = nil
        }
        .onChange(of: historyStationFilter?.id) { _, stationID in
            guard stationID != nil else { return }
            selectedArtistName = nil
            openMusicAviActionsID = nil
            musicMode = .history
            resetVisibleLimits()
        }
        .onChange(of: requestedMusicMode) { _, _ in
            consumeRequestedMusicReturnIfNeeded()
        }
        .onChange(of: requestedMusicOverview) { _, _ in
            consumeRequestedMusicReturnIfNeeded()
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var musicDetailHeaderReservedHeight: CGFloat {
        126
    }

    private var stickyMusicDetailHeader: some View {
        MusicDetailHeader(
            title: musicMode.title,
            subtitle: musicMode.subtitle,
            goBack: showOverview
        )
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 12)
        .background {
            TuneAVTheme.shellBackground
                .ignoresSafeArea(edges: .top)
        }
    }

    private func musicOverview(_ snapshot: MusicLibraryDerivedState) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if accessController.capabilities.canAccessPremiumFeatures {
                AccountSummaryStatusCard(
                    kind: .music,
                    state: libraryStore.userSummaryRefreshState,
                    summary: summary,
                    isSignedIn: accessController.isSignedIn,
                    hasProAccess: true,
                    openAccountAction: openAccountAction,
                    startSignInAction: startSignInAction,
                    refreshAction: {
                        await libraryStore.refreshUserSummary(force: true)
                    }
                )
            }

            RadioOverviewMetricGrid {
                RadioOverviewMetricCard(
                    title: L10n.string("shell.music.overview.songs"),
                    value: summary?.music.cards.songs.count ?? snapshot.savedDiscoveries.count,
                    systemImage: "bookmark.fill",
                    tint: TuneAVTheme.highlight,
                    accessibilityIdentifier: "music.overview.songs",
                    action: { openMusicMode(.songs) }
                )
                RadioOverviewMetricCard(
                    title: L10n.string("shell.music.overview.artists"),
                    value: summary?.music.cards.artists.count ?? snapshot.visibleArtistSummaries.count,
                    systemImage: "person.2.fill",
                    tint: Color(red: 0.17, green: 0.52, blue: 0.96),
                    accessibilityIdentifier: "music.overview.artists",
                    action: { openMusicMode(.artists) }
                )
                RadioOverviewMetricCard(
                    title: L10n.string("shell.music.overview.top"),
                    value: snapshot.tunedDiscoveries.count,
                    systemImage: "sparkles",
                    tint: Color(red: 0.95, green: 0.48, blue: 0.18),
                    accessibilityIdentifier: "music.overview.top",
                    action: { openMusicMode(.top) }
                )
                RadioOverviewMetricCard(
                    title: L10n.string("shell.music.overview.history"),
                    value: summary?.music.cards.history.count ?? snapshot.visibleDiscoveries.count,
                    systemImage: "clock.fill",
                    tint: Color(red: 0.54, green: 0.43, blue: 0.90),
                    accessibilityIdentifier: "music.overview.history",
                    action: { openMusicMode(.history) }
                )
            }

            if snapshot.hasOverviewContent {
                musicOverviewTrackSectionIfNeeded(
                    discoveries: Array(snapshot.savedDiscoveries.prefix(Self.overviewLimit)),
                    title: L10n.string("shell.music.overview.songs"),
                    subtitle: L10n.string("shell.music.detail.songs.subtitle"),
                    action: { openMusicMode(.songs) }
                )

                musicOverviewArtistSectionIfNeeded(
                    artists: Array(snapshot.visibleArtistSummaries.prefix(Self.overviewLimit)),
                    title: L10n.string("shell.music.overview.artists"),
                    subtitle: L10n.string("shell.music.detail.artists.subtitle"),
                    action: { openMusicMode(.artists) }
                )

                musicOverviewTrackSectionIfNeeded(
                    discoveries: Array(snapshot.tunedDiscoveries.prefix(Self.overviewLimit)),
                    title: L10n.string("shell.music.overview.top"),
                    subtitle: L10n.string("shell.music.detail.top.subtitle"),
                    action: { openMusicMode(.top) }
                )

                musicOverviewTrackSectionIfNeeded(
                    discoveries: Array(snapshot.visibleDiscoveries.prefix(Self.overviewLimit)),
                    title: L10n.string("shell.music.overview.history"),
                    subtitle: L10n.string("shell.music.overview.latest.subtitle"),
                    action: { openMusicMode(.history) }
                )
            } else {
                EmptyLibraryState(
                    title: L10n.string("shell.music.overview.empty"),
                    detail: L10n.string("shell.music.overview.empty.detail")
                )
            }
        }
    }

    private func musicModeControls(_ snapshot: MusicLibraryDerivedState) -> some View {
        MusicLibraryControls(
            savedCount: snapshot.savedDiscoveries.count,
            historyCount: snapshot.visibleDiscoveries.count,
            artistCount: snapshot.visibleArtistSummaries.count,
            stationCount: snapshot.tunedDiscoveries.count,
            selectedMode: musicMode,
            selectMode: selectMusicMode(_:),
            sort: musicSort,
            setSort: setMusicSort(_:),
            isSearchExpanded: isSearchExpanded,
            showOverview: showOverview,
            toggleSearch: toggleMusicSearch
        )
    }

    @ViewBuilder
    private func musicOverviewTrackSectionIfNeeded(
        discoveries: [DiscoveredTrack],
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        if !discoveries.isEmpty {
            RadioOverviewCarouselSection(title: title, subtitle: subtitle, action: action) {
                MusicTrackCompactCarousel(
                    discoveries: discoveries,
                    stationArtworkURL: { discovery in stationArtworkURL(discovery) },
                    trackFeedback: { discovery in trackFeedback(discovery) },
                    openTrackInfo: { discovery in openDiscoveryInfo(discovery, nil) },
                    toggleSaved: { discovery in toggleDiscoverySaved(discovery) },
                    openYouTube: { discovery in runProAviAction { openDiscoverySearch(discovery, suffix: nil, youtube: true) } },
                    openLyrics: { discovery in runProAviAction { openDiscoverySearch(discovery, suffix: "lyrics", youtube: false) } },
                    openAppleMusic: { discovery in runProAviAction { openAppleMusicSearch(discovery) } },
                    openSpotify: { discovery in runProAviAction { openSpotifySearch(discovery) } },
                    hideAction: hideDiscoveryWithUndo(_:),
                    removeAction: { discovery in removeDiscovery(discovery) }
                )
            }
        }
    }

    @ViewBuilder
    private func musicOverviewArtistSectionIfNeeded(
        artists: [DiscoveryArtistSummary],
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        if !artists.isEmpty {
            RadioOverviewCarouselSection(title: title, subtitle: subtitle, action: action) {
                MusicArtistCompactCarousel(
                    artists: artists,
                    openArtistInfo: { artist in openArtistInfo(artist, nil) },
                    openYouTube: { artist in runProAviAction { openArtistSearch(artist, youtube: true) } },
                    openAppleMusic: { artist in runProAviAction { openAppleMusicArtistSearch(artist) } },
                    openSpotify: { artist in runProAviAction { openSpotifyArtistSearch(artist) } }
                )
            }
        }
    }

    private func discoveryLibrarySection(_ snapshot: MusicLibraryDerivedState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.isCurrentModeEmpty {
                EmptyLibraryState(
                    title: emptyDiscoveryTitle(snapshot),
                    detail: emptyDiscoveryDetail(snapshot)
                )
            } else {
                switch musicMode {
                case .songs, .top, .history:
                    discoverySongsHeader(snapshot)
                    discoveryTrackList(snapshot)
                case .artists:
                    discoveryArtistsHeader(snapshot)
                    LazyVStack(spacing: 10) {
                        ForEach(Array(snapshot.visibleArtistSummariesForMode.enumerated()), id: \.element.id) { index, artist in
                            DiscoveryArtistRow(
                                summary: artist,
                                openAviActionsID: $openMusicAviActionsID,
                                openArtist: { openArtistInfo(artist, musicMode) },
                                openArtistSongs: { openArtistSongs(artist.name) },
                                openArtistRadios: { openArtistInfo(artist, musicMode) },
                                openYouTube: { runProAviAction { openArtistSearch(artist.name, youtube: true) } },
                                openAppleMusic: { runProAviAction { openAppleMusicArtistSearch(artist.name) } },
                                openSpotify: { runProAviAction { openSpotifyArtistSearch(artist.name) } }
                            )
                            .zIndex(openMusicAviActionsID == "artist-\(artist.id)" ? 10_000 : Double(snapshot.visibleArtistSummariesForMode.count - index))
                        }

                        if snapshot.canShowMoreArtists {
                            ShowMoreButton(
                                title: L10n.string("common.showMore"),
                                remainingCount: snapshot.filteredArtistSummaries.count - snapshot.visibleArtistSummariesForMode.count,
                                action: showMoreArtists
                            )
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("music.section.discoveries")
    }

    private func discoveryTrackList(_ snapshot: MusicLibraryDerivedState) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(Array(snapshot.visibleFilteredDiscoveries.enumerated()), id: \.element.discoveryID) { index, discovery in
                DiscoveryTrackCard(
                    discovery: discovery,
                    stationArtworkURL: stationArtworkURL(discovery),
                    feedback: trackFeedback(discovery),
                    showsSaveButton: false,
                    openAviActionsID: $openMusicAviActionsID,
                    openTrackInfo: { openDiscoveryInfo(discovery, musicMode) },
                    openArtistInfo: { openArtistInfo(discoveryArtistSummary(for: discovery), musicMode) },
                    openStationInfo: { openDiscoveryStationInfo(discovery) },
                    toggleSaved: { toggleDiscoverySaved(discovery) },
                    openYouTube: { runProAviAction { openDiscoverySearch(discovery, suffix: nil, youtube: true) } },
                    openLyrics: { runProAviAction { openDiscoverySearch(discovery, suffix: "lyrics", youtube: false) } },
                    openAppleMusic: { runProAviAction { openAppleMusicSearch(discovery) } },
                    openSpotify: { runProAviAction { openSpotifySearch(discovery) } },
                    hideAction: { hideDiscoveryWithUndo(discovery) },
                    removeAction: { removeDiscovery(discovery) }
                )
                .zIndex(openMusicAviActionsID == "track-\(discovery.discoveryID)" ? 10_000 : Double(snapshot.visibleFilteredDiscoveries.count - index))
            }

            if snapshot.canShowMoreDiscoveries {
                ShowMoreButton(
                    title: L10n.string("common.showMore"),
                    remainingCount: snapshot.filteredDiscoveries.count - snapshot.visibleFilteredDiscoveries.count,
                    action: showMoreDiscoveries
                )
            }
        }
    }

    private func discoveryArtistSummary(for discovery: DiscoveredTrack) -> DiscoveryArtistSummary {
        DiscoveryArtistSummary(
            name: discovery.artistDisplayText,
            trackCount: 1,
            artistArtworkURL: discovery.resolvedArtworkURL,
            fallbackArtworkURL: discovery.resolvedStationArtworkURL
        )
    }

    private func discoveryArtistsHeader(_ snapshot: MusicLibraryDerivedState) -> some View {
        HStack(spacing: 10) {
            Text(L10n.string("shell.music.artists.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            discoveryActions(snapshot)
        }
    }

    private func openArtistSongs(_ artistName: String) {
        selectedArtistName = artistName
        query = artistName
        musicMode = .songs
    }

    private func openArtistSearch(_ artistName: String, youtube: Bool) {
        let destination: TuneAVExternalSearchURL.Destination = youtube ? .youtube : .web
        let feature: LimitedFeature = youtube ? .youtubeSearch : .webSearch
        guard let search = TuneAVExternalSearchURL.artistSearch(
            artist: artistName,
            destination: destination,
            feature: feature
        ) else { return }
        guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        browserDestination = BrowserDestination(url: search.url)
    }

    private func openAppleMusicArtistSearch(_ artistName: String) {
        guard let search = TuneAVExternalSearchURL.artistSearch(
            artist: artistName,
            destination: .appleMusic,
            feature: .appleMusicSearch
        ) else { return }
        guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        browserDestination = BrowserDestination(url: search.url)
    }

    private func openSpotifyArtistSearch(_ artistName: String) {
        guard let search = TuneAVExternalSearchURL.artistSearch(
            artist: artistName,
            destination: .spotify,
            feature: .spotifySearch
        ) else { return }
        guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        browserDestination = BrowserDestination(url: search.url)
    }

    private func discoverySongsHeader(_ snapshot: MusicLibraryDerivedState) -> some View {
        HStack(spacing: 10) {
            Text(historyStationFilterTitle ?? currentMusicLibraryMode.songsTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if musicMode == .history, historyStationFilter != nil {
                Button {
                    historyStationFilter = nil
                } label: {
                    Text(L10n.string("shell.music.history.all"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(TuneAVTheme.highlight.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("music.history.all")
            }

            discoveryActions(snapshot)
        }
    }

    private var historyStationFilterTitle: String? {
        guard musicMode == .history, let historyStationFilter else { return nil }
        return "\(MusicLibraryMode.history.title) · \(historyStationFilter.name)"
    }

    private func discoveryActions(_ snapshot: MusicLibraryDerivedState) -> some View {
        HStack(spacing: 10) {
            Button {
                let shareText = discoveriesShareText(snapshot)
                guard useDailyFeatureIfAllowed(.discoveryShare, usageKey: shareText) else { return }
                discoveriesShareTextDraft = shareText
                isShowingDiscoveriesShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.mutedSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.library.discoveries.share"))
            .accessibilityIdentifier("discoveries.share")
            .disabled(snapshot.filteredDiscoveries.isEmpty)

            Button {
                isConfirmingClearDiscoveries = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.17, blue: 0.38))
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.mutedSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.library.discoveries.clear"))
            .accessibilityIdentifier("discoveries.clear")
        }
    }

    @ViewBuilder
    private var hiddenDiscoveryUndoBanner: some View {
        if let hiddenDiscovery {
            HStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)

                Text(L10n.string("shell.music.discovery.hidden"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    restoreDiscovery(hiddenDiscovery)
                    withAnimation(.snappy(duration: 0.22)) {
                        self.hiddenDiscovery = nil
                    }
                } label: {
                    Text(L10n.string("common.undo"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.highlight)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("discoveries.undoHide")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(TuneAVTheme.elevatedSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
            .shadow(color: TuneAVTheme.softShadow.opacity(0.22), radius: 12, y: 5)
            .padding(.horizontal, shellScreenHorizontalPadding)
            .padding(.bottom, max(98, bottomContentPadding - 18))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("discoveries.hiddenUndo")
        }
    }

    private func discoverySubsectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(TuneAVTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var musicDerivedState: MusicLibraryDerivedState {
        let visibleDiscoveries = AppShellMusicLibrary.visibleDiscoveries(discoveries)
        let savedDiscoveries = AppShellMusicLibrary.savedDiscoveries(discoveries)
        let tunedDiscoveries = sortTunedDiscoveries(visibleDiscoveries.filter { trackFeedback($0) != nil })
        let visibleArtistSummaries = AppShellMusicLibrary.visibleArtistSummaries(discoveries)
        let filteredDiscoveries = resolvedFilteredDiscoveries()
        let filteredArtistSummaries = resolvedFilteredArtistSummaries()

        return MusicLibraryDerivedState(
            visibleDiscoveries: visibleDiscoveries,
            savedDiscoveries: savedDiscoveries,
            tunedDiscoveries: tunedDiscoveries,
            visibleArtistSummaries: visibleArtistSummaries,
            filteredDiscoveries: filteredDiscoveries,
            visibleFilteredDiscoveries: Array(filteredDiscoveries.prefix(visibleDiscoveryLimit)),
            filteredArtistSummaries: filteredArtistSummaries,
            visibleArtistSummariesForMode: Array(filteredArtistSummaries.prefix(visibleArtistLimit)),
            musicMode: musicMode
        )
    }

    private var visibleDiscoveries: [DiscoveredTrack] {
        AppShellMusicLibrary.visibleDiscoveries(discoveries)
    }

    private func musicAviDetail(_ snapshot: MusicLibraryDerivedState) -> String {
        if snapshot.visibleDiscoveries.isEmpty {
            return L10n.string("shell.music.avi.detail.empty")
        }
        if let strongestStation = strongestDiscoveryStationName(snapshot.visibleDiscoveries) {
            return L10n.plural(singular: "shell.music.avi.detail.strongestStation.one", plural: "shell.music.avi.detail.strongestStation.other", count: snapshot.visibleDiscoveries.count, snapshot.visibleDiscoveries.count, strongestStation)
        }
        let discoveriesText = L10n.plural(singular: "shell.count.discovery.one", plural: "shell.count.discovery.other", count: snapshot.visibleDiscoveries.count, snapshot.visibleDiscoveries.count)
        let savedText = L10n.plural(singular: "shell.count.savedSong.one", plural: "shell.count.savedSong.other", count: snapshot.savedDiscoveries.count, snapshot.savedDiscoveries.count)
        return L10n.string("shell.music.avi.detail.summary", discoveriesText, savedText)
    }

    private func strongestDiscoveryStationName(_ visibleDiscoveries: [DiscoveredTrack]) -> String? {
        let counts = Dictionary(grouping: visibleDiscoveries, by: \.stationName)
            .mapValues(\.count)
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    private func resolvedFilteredDiscoveries() -> [DiscoveredTrack] {
        let filtered = AppShellMusicLibrary.filteredDiscoveries(
            discoveries,
            mode: currentMusicLibraryMode,
            query: query,
            selectedArtistName: selectedArtistName,
            historyStationID: historyStationFilter?.id
        )

        if musicMode == .top {
            return sortTunedDiscoveries(filtered.filter { trackFeedback($0) != nil })
        }

        switch musicSort {
        case .recent:
            return filtered.sorted { $0.playedAt > $1.playedAt }
        case .alphabetical:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .strongest:
            return strongestSortedDiscoveries(filtered)
        }
    }

    private func sortTunedDiscoveries(_ discoveries: [DiscoveredTrack]) -> [DiscoveredTrack] {
        discoveries.sorted { first, second in
            let firstRank = feedbackRank(trackFeedback(first))
            let secondRank = feedbackRank(trackFeedback(second))
            if firstRank == secondRank {
                return first.playedAt > second.playedAt
            }
            return firstRank < secondRank
        }
    }

    private func feedbackRank(_ feedback: TuneAVStationFeedback?) -> Int {
        switch feedback {
        case .liked:
            return 0
        case .notForMe:
            return 1
        case .disliked:
            return 2
        case nil:
            return 3
        }
    }

    private func strongestSortedDiscoveries(_ discoveries: [DiscoveredTrack]) -> [DiscoveredTrack] {
        let songCounts = Dictionary(grouping: discoveries, by: discoveryIdentityKey(_:)).mapValues(\.count)
        return discoveries.sorted { first, second in
            let firstKey = discoveryIdentityKey(first)
            let secondKey = discoveryIdentityKey(second)
            let firstCount = songCounts[firstKey, default: 0]
            let secondCount = songCounts[secondKey, default: 0]
            if firstCount == secondCount {
                return first.playedAt > second.playedAt
            }
            return firstCount > secondCount
        }
    }

    private func discoveryIdentityKey(_ discovery: DiscoveredTrack) -> String {
        "\(TuneAVText.normalizedValue(discovery.artistDisplayText) ?? discovery.artistDisplayText.lowercased())|\(TuneAVText.normalizedValue(discovery.title) ?? discovery.title.lowercased())"
    }

    private func resolvedFilteredArtistSummaries() -> [DiscoveryArtistSummary] {
        let summaries = AppShellMusicLibrary.filteredArtistSummaries(
            discoveries,
            mode: currentMusicLibraryMode,
            query: query
        )

        switch musicSort {
        case .recent, .strongest:
            return summaries
        case .alphabetical:
            return summaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func discoveriesShareText(_ snapshot: MusicLibraryDerivedState) -> String {
        AppShellMusicLibrary.shareText(
            title: L10n.string("shell.library.discoveries.shareTitle"),
            discoveries: snapshot.filteredDiscoveries
        )
    }

    private func resetVisibleLimits() {
        visibleDiscoveryLimit = Self.pageSize
        visibleArtistLimit = Self.pageSize
    }

    private func showMoreDiscoveries() {
        TuneAVHaptics.lightImpact()
        visibleDiscoveryLimit += Self.pageSize
    }

    private func showMoreArtists() {
        TuneAVHaptics.lightImpact()
        visibleArtistLimit += Self.pageSize
    }

    private var musicSort: MusicLibrarySort {
        MusicLibrarySort(rawValue: musicSortRawValue) ?? .recent
    }

    private func emptyDiscoveryTitle(_ snapshot: MusicLibraryDerivedState) -> String {
        if snapshot.visibleDiscoveries.isEmpty {
            return L10n.string("shell.library.discoveries.empty")
        }

        if !trimmedQuery.isEmpty {
            return L10n.string("shell.library.discoveries.noMatch")
        }

        switch musicMode {
        case .songs:
            return L10n.string("shell.library.discoveries.savedEmpty")
        case .artists:
            return L10n.string("shell.music.artists.empty")
        case .top:
            return L10n.string("shell.music.overview.empty")
        case .history:
            return L10n.string("shell.library.discoveries.noMatch")
        }
    }

    private func emptyDiscoveryDetail(_ snapshot: MusicLibraryDerivedState) -> String {
        if snapshot.visibleDiscoveries.isEmpty {
            return L10n.string("shell.library.discoveries.empty.detail")
        }

        if !trimmedQuery.isEmpty {
            return L10n.string("shell.library.discoveries.noMatch.detail")
        }

        switch musicMode {
        case .songs:
            return L10n.string("shell.library.discoveries.savedEmpty.detail")
        case .artists:
            return L10n.string("shell.music.artists.empty.detail")
        case .top:
            return L10n.string("shell.music.overview.empty.detail")
        case .history:
            return L10n.string("shell.library.discoveries.noMatch.detail")
        }
    }

    private func normalizeInitialDiscoveryFilter() {
        let initialMode = AppShellMusicLibrary.normalizedInitialMode(
            currentMusicLibraryMode,
            discoveries: discoveries,
            historyStationID: historyStationFilter?.id
        )
        musicMode = MusicContentMode(libraryMode: initialMode)
        if TuneAVLaunchContext.current.shouldUseLocalUITestDiscovery
            || TuneAVLaunchContext.current.uiTestTrackTitle != nil
            || TuneAVLaunchContext.current.uiTestTrackArtist != nil {
            isShowingOverview = false
        }
    }

    private func consumeRequestedMusicReturnIfNeeded() {
        if let requestedMusicOverview {
            isShowingOverview = requestedMusicOverview
            if requestedMusicOverview {
                query = ""
                selectedArtistName = nil
                historyStationFilter = nil
            }
            self.requestedMusicOverview = nil
        }
        if let requestedMusicMode {
            isShowingOverview = false
            selectedArtistName = nil
            if requestedMusicMode != .history {
                historyStationFilter = nil
            }
            musicMode = requestedMusicMode
            self.requestedMusicMode = nil
        }
        resetVisibleLimits()
    }

    private var currentMusicLibraryMode: MusicLibraryMode {
        musicMode.libraryMode
    }

    private func selectMusicMode(_ mode: MusicContentMode) {
        guard musicMode != mode else { return }
        TuneAVHaptics.selection()
        isShowingOverview = false
        selectedArtistName = nil
        if mode != .history {
            historyStationFilter = nil
        }
        musicMode = mode
        resetVisibleLimits()
    }

    private func openMusicMode(_ mode: MusicContentMode) {
        TuneAVHaptics.selection()
        isShowingOverview = false
        selectedArtistName = nil
        if mode != .history {
            historyStationFilter = nil
        }
        musicMode = mode
        resetVisibleLimits()
    }

    private func showOverview() {
        TuneAVHaptics.selection()
        query = ""
        isSearchExpanded = false
        selectedArtistName = nil
        historyStationFilter = nil
        resetVisibleLimits()
        withAnimation(.snappy(duration: 0.22)) {
            isShowingOverview = true
        }
    }

    private func toggleMusicSearch() {
        TuneAVHaptics.selection()
        isShowingOverview = false
        withAnimation(.snappy(duration: 0.22)) {
            isSearchExpanded.toggle()
        }
    }

    private func setMusicSort(_ sort: MusicLibrarySort) {
        guard musicSort != sort else { return }
        TuneAVHaptics.selection()
        musicSortRawValue = sort.rawValue
        resetVisibleLimits()
    }

    private func hideDiscoveryWithUndo(_ discovery: DiscoveredTrack) {
        withAnimation(.snappy(duration: 0.22)) {
            hiddenDiscovery = discovery
            hideDiscovery(discovery)
        }
    }

    private func openDiscoverySearch(_ discovery: DiscoveredTrack, suffix: String?, youtube: Bool) {
        guard let search = TuneAVExternalSearchURL.discoverySearch(searchQuery: discovery.searchQuery, suffix: suffix, youtube: youtube) else { return }
        guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        browserDestination = BrowserDestination(url: search.url)
    }

    private func openAppleMusicSearch(_ discovery: DiscoveredTrack) {
        guard let search = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: discovery.searchQuery,
            destination: .appleMusic,
            feature: .appleMusicSearch
        ) else { return }
        guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        browserDestination = BrowserDestination(url: search.url)
    }

    private func openSpotifySearch(_ discovery: DiscoveredTrack) {
        guard let search = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: discovery.searchQuery,
            destination: .spotify,
            feature: .spotifySearch
        ) else { return }
        guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        browserDestination = BrowserDestination(url: search.url)
    }

    private func useDailyFeatureIfAllowed(_ feature: LimitedFeature, usageKey: String) -> Bool {
        guard accessController.canUseDailyFeature(feature, usageKey: usageKey) else {
            accessController.presentUpgradePrompt(for: feature)
            return false
        }

        accessController.recordDailyFeatureUse(feature, usageKey: usageKey)
        return true
    }
}

private struct GenreTagStrip: View {
    let tags: [String]
    let activeTag: String?
    let toggleTag: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        toggleTag(tag)
                    } label: {
                        Text(L10n.genreLabel(for: tag))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(activeTag == tag ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(activeTag == tag ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface)
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(activeTag == tag ? TuneAVTheme.highlight.opacity(0.22) : TuneAVTheme.borderSubtle, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct SearchCountryFilterButton: View {
    let title: String
    let flag: String?
    let isActive: Bool
    let clearAction: () -> Void
    let openAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openAction) {
                HStack(spacing: 8) {
                    Image(systemName: "globe.europe.africa")
                        .font(.system(size: 14, weight: .semibold))

                    Text(L10n.string("shell.search.country.label"))
                        .font(.system(size: 14, weight: .semibold))

                    if let flag {
                        Text(flag)
                            .font(.system(size: 16))
                    }

                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(isActive ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isActive ? TuneAVTheme.highlight.opacity(0.08) : TuneAVTheme.cardSurface)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isActive ? TuneAVTheme.highlight.opacity(0.22) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if isActive {
                Button(action: clearAction) {
                    Text(L10n.string("shell.search.country.clear"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(TuneAVTheme.cardSurface)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SearchCountryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryStore: LibraryStore

    @Binding var selectedCountryCode: String?

    @State private var query = ""

    private var countryOptions: [CountryOption] {
        CountryOption.filtered(CountryOption.all, query: query)
    }

    private var suggestedCountries: [CountryOption] {
        let codes =
            [selectedCountryCode, resolvedDeviceCountryCode()] +
            libraryStore.recentStations().compactMap(\.countryCode) +
            libraryStore.favoriteStations().compactMap(\.countryCode) +
            ["ES", "US", "GB", "FR", "DE", "IT", "MX", "AR"]
        let lookup = Dictionary(uniqueKeysWithValues: CountryOption.all.map { ($0.code, $0) })
        var seen = Set<String>()

        return codes
            .compactMap(CountryOption.sanitizedCode)
            .filter { seen.insert($0).inserted }
            .compactMap { lookup[$0] }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SearchField(query: $query, prompt: L10n.string("shell.search.country.searchPrompt"))

                    Button {
                        selectedCountryCode = nil
                        dismiss()
                    } label: {
                        CountryRow(
                            title: L10n.string("shell.search.country.all"),
                            subtitle: L10n.string("shell.search.country.allSubtitle"),
                            flag: nil,
                            isSelected: selectedCountryCode == nil
                        )
                    }
                    .buttonStyle(.plain)

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.string("shell.search.country.suggested"))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)

                            FlowLayout(horizontalSpacing: 10, verticalSpacing: 10) {
                                ForEach(suggestedCountries) { option in
                                    Button {
                                        selectedCountryCode = option.code
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 8) {
                                            if let flag = option.flag {
                                                Text(flag)
                                                    .font(.system(size: 17))
                                            }

                                            Text(option.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .lineLimit(1)

                                            if selectedCountryCode == option.code {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                            }
                                        }
                                        .foregroundStyle(selectedCountryCode == option.code ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(selectedCountryCode == option.code ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface)
                                        )
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .stroke(selectedCountryCode == option.code ? TuneAVTheme.highlight.opacity(0.24) : TuneAVTheme.borderSubtle, lineWidth: 1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }

                    ForEach(countryOptions) { option in
                        Button {
                            selectedCountryCode = option.code
                            dismiss()
                        } label: {
                            CountryRow(
                                title: option.name,
                                subtitle: nil,
                                flag: option.flag,
                                isSelected: selectedCountryCode == option.code
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .navigationTitle(L10n.string("shell.search.country.pickerTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("shell.search.country.done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func resolvedDeviceCountryCode() -> String? {
        CountryOption.sanitizedCode(
            Locale.autoupdatingCurrent.region?.identifier ?? Locale.current.region?.identifier
        )
    }
}

private struct CountryRow: View {
    let title: String
    let subtitle: String?
    let flag: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.mutedSurface)

                if let flag {
                    Text(flag)
                        .font(.system(size: 22))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.highlight)
                }
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.22) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
    }
}

private typealias CountryOption = TuneAVCountry

private extension TuneAVCountry {
    static var all: [TuneAVCountry] {
        all(localizedName: L10n.countryName(for:))
    }
}

private struct HomeStationPresentation {
    enum Tier {
        case rich
        case fallback
    }

    let tier: Tier
    let label: String
    let title: String
    let primaryLine: String?
    let secondaryLine: String?
    let badges: [String]
}

private struct HomeTuningDeskHero: View {
    let station: Station
    let presentation: HomeStationPresentation
    let isFavorite: Bool
    let isCurrentStation: Bool
    let isPlaying: Bool
    let isLoading: Bool
    let stationFeedback: TuneAVStationFeedback?
    let playAction: () -> Void
    let favoriteAction: () -> Void
    let feedbackAction: (TuneAVStationFeedback) -> Void
    let detailsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroHeader

            VStack(alignment: .leading, spacing: 14) {
                stationText
                    .layoutPriority(1)

                deskControls

                AviCompactFeedbackControl(
                    selectedFeedback: stationFeedback,
                    selectFeedback: feedbackAction,
                    clearFeedback: {
                        if let stationFeedback {
                            feedbackAction(stationFeedback)
                        }
                    }
                )
                .accessibilityIdentifier("home.hero.feedback")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture(perform: detailsAction)
        .accessibilityElement(children: .contain)
    }

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            HomeDeskSignalPill(title: presentation.label)

            if isCurrentStation {
                HomeLiveStatePill(isPlaying: isPlaying, isLoading: isLoading)
            }

            Spacer(minLength: 8)

            if presentation.tier == .rich {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .padding(9)
                    .background(Color.white.opacity(0.62), in: Circle())
                    .accessibilityHidden(true)
            }
        }
    }

    private var stationText: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.title)
                    .font(.system(size: 29, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if let stationFeedback {
                    StationFeedbackBadge(feedback: stationFeedback, size: 24, fontSize: 11, borderWidth: 1)
                        .accessibilityLabel(stationFeedback.localizedState)
                }
            }

            if let primaryLine = presentation.primaryLine {
                Text(primaryLine)
                    .font(.system(size: presentation.tier == .rich ? 15 : 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let secondaryLine = presentation.secondaryLine {
                Text(secondaryLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.78))
                    .lineLimit(1)
            }

            if !presentation.badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(presentation.badges, id: \.self) { badge in
                        HomeDeskBadge(title: badge)
                    }
                }
            }
        }
    }

    private var deskControls: some View {
        HStack(spacing: 10) {
            Button(action: playAction) {
                Image(systemName: playIconName)
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(width: 56, height: 56)
                    .background(TuneAVTheme.highlight, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playTitle)

            Button(action: favoriteAction) {
                TuneAVSavedStationIcon(isSaved: isFavorite, size: 18)
                    .frame(width: 50, height: 50)
                    .background(
                        isFavorite ? TuneAVTheme.highlight.opacity(0.18) : Color.white.opacity(0.74),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isFavorite ? TuneAVTheme.highlight.opacity(0.34) : TuneAVTheme.brandGraphite.opacity(0.12), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? L10n.string("player.station.unsave") : L10n.string("player.station.save"))
            .accessibilityIdentifier("home.hero.favorite.\(station.id)")

            Button(action: detailsAction) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.brandGraphite)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(TuneAVTheme.brandGraphite.opacity(0.12), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("common.more"))
        }
    }

    private var heroBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        return ZStack(alignment: .bottomTrailing) {
            StationThumbnailView(
                station: station,
                size: 220,
                animationOverlay: .none,
                isAnimationActive: false
            )
            .scaleEffect(1.18)
            .opacity(0.18)
            .blur(radius: 1.8)
            .offset(x: -84, y: 52)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .clipShape(shape)

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.99, green: 0.97, blue: 0.91),
                            Color(red: 0.96, green: 0.94, blue: 0.87)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.9)

            ZStack(alignment: .bottomTrailing) {
                Image("AviOnboardingHeroStatic")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250)
                    .opacity(0.16)
                    .offset(x: 56, y: 34)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HomeDeskSketchBackdrop()
                    .foregroundStyle(TuneAVTheme.highlight.opacity(0.14))
                    .padding(.bottom, 112)
                    .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
        }
        .overlay {
            shape
                .stroke(TuneAVTheme.brandGraphite.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 18, y: 8)
    }

    private var playIconName: String {
        isPlaying ? "pause.fill" : "play.fill"
    }

    private var playTitle: String {
        if isPlaying {
            return L10n.string("player.control.pause")
        }
        return L10n.string("shell.featured.play")
    }
}

private struct HomeLiveStatePill: View {
    let isPlaying: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(TuneAVTheme.highlight)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(0.7)
                .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(TuneAVTheme.highlight.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
    }

    private var title: String {
        if isLoading {
            return L10n.string("audio.status.loading").uppercased(with: .current)
        }
        if isPlaying {
            return L10n.string("audio.status.playing").uppercased(with: .current)
        }
        return L10n.string("shell.status.live").uppercased(with: .current)
    }
}

private struct HomeDeskBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(TuneAVTheme.brandGraphite.opacity(0.76))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.58), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(TuneAVTheme.brandGraphite.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct HomeDeskSignalPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(TuneAVTheme.highlight)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.system(size: 12, weight: .black))
                .tracking(0.9)
                .foregroundStyle(TuneAVTheme.brandGraphite)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.62), in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.brandGraphite.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct HomeDeskSketchBackdrop: View {
    var body: some View {
        ZStack {
            ForEach([42.0, 72.0, 104.0], id: \.self) { size in
                Circle()
                    .stroke(lineWidth: 1.2)
                    .frame(width: size, height: size)
            }

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .light))
                .offset(x: -36, y: 34)
        }
        .frame(width: 126, height: 126)
        .accessibilityHidden(true)
    }
}

private struct StationSection<Content: View>: View {
    let title: String
    let subtitle: String
    let accessibilityIdentifier: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 12) {
                content()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

private enum StationRowMetrics {
    static let artworkSize: CGFloat = 62
    static let favoriteButtonSize: CGFloat = 34
    static let playButtonSize: CGFloat = 38
}

private enum StationCompactMetrics {
    static let cardWidth: CGFloat = 258
    static let cardHeight: CGFloat = 112
    static let artworkSize: CGFloat = 82
    static let favoriteButtonSize: CGFloat = 30
    static let playBadgeSize: CGFloat = 36
    static let textLineHeight: CGFloat = 13
}

private struct StationFeedbackBadge: View {
    let feedback: TuneAVStationFeedback
    var size: CGFloat = 18
    var fontSize: CGFloat = 8
    var borderWidth: CGFloat = 1

    var body: some View {
        Image(systemName: feedback.systemImage)
            .font(.system(size: fontSize, weight: .black))
            .foregroundStyle(feedback == .liked ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse)
            .frame(width: size, height: size)
            .background(feedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.82), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.82), lineWidth: borderWidth)
            }
            .accessibilityLabel(feedback.localizedState)
    }
}

private struct StationCompactCarousel: View {
    let stations: [Station]
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationInsight: (Station) -> String?
    var stationFeedback: [String: TuneAVStationFeedback] = [:]
    let queueSource: AudioPlayerService.PlaybackQueue.Source
    let queueStations: [Station]
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(stations) { station in
                    StationCompactCard(
                        station: station,
                        isFavorite: favoriteStationIDs.contains(station.id),
                        nowPlayingTrack: nowPlayingTracks[station.id],
                        recommendationInsight: stationInsight(station),
                        stationFeedback: stationFeedback[station.id],
                        toggleFavorite: { toggleFavorite(station) },
                        playAction: { playStation(station, queueSource, queueStations) },
                        detailsAction: { showStationDetails(station, queueSource, queueStations) }
                    )
                    .frame(width: StationCompactMetrics.cardWidth)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

private struct StationCompactCard: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let station: Station
    let isFavorite: Bool
    let nowPlayingTrack: NowPlayingTrack?
    let recommendationInsight: String?
    var stationFeedback: TuneAVStationFeedback? = nil
    let toggleFavorite: () -> Void
    let playAction: () -> Void
    let detailsAction: () -> Void

    private var isPlayingCurrentStation: Bool {
        audioPlayer.isCurrent(station) && audioPlayer.isPlaying
    }

    private var isCurrentStationActive: Bool {
        audioPlayer.isCurrent(station) && (audioPlayer.isPlaying || audioPlayer.isLoading)
    }

    private var compactPrimaryLine: String {
        if let reliableArtist {
            return reliableArtist
        }

        if let reliableTitle {
            return reliableTitle
        }

        return compactStationContext ?? L10n.string("shell.station.row.defaultDetail")
    }

    private var compactSecondaryLine: String {
        if reliableArtist != nil, let reliableTitle {
            return reliableTitle
        }
        if reliableArtist != nil || reliableTitle != nil {
            return compactMetadataContextLine
        }
        return compactContextLine
    }

    private var compactTertiaryLine: String {
        if let stationFeedback {
            return stationFeedback.localizedState
        }
        return L10n.string("shell.station.row.aviCanTune")
    }

    private var compactContextLine: String {
        if reliableArtist != nil || reliableTitle != nil {
            return compactMetadataContextLine
        }
        return compactUniqueLine(
            candidates: [
                stationFeedback == nil ? recommendationInsight : nil,
                compactGenreLine,
                contextFallbackLine,
                L10n.string("shell.stationDetail.suggestedSignal")
            ],
            excluding: [compactPrimaryLine, compactStationContext]
        ) ?? L10n.string("shell.stationDetail.suggestedSignal")
    }

    private var compactMetadataContextLine: String {
        compactUniqueInsight(excluding: [compactPrimaryLine])
            ?? contextFallbackLine
    }

    private func compactUniqueInsight(excluding lines: [String?]) -> String? {
        guard let insight = TuneAVText.normalizedValue(recommendationInsight) else {
            return nil
        }
        return compactUniqueLine(candidates: [insight], excluding: lines)
    }

    private func compactUniqueLine(candidates: [String?], excluding lines: [String?]) -> String? {
        let repeatedLines = lines.compactMap { TuneAVText.normalizedValue($0) }
        return candidates
            .compactMap { TuneAVText.normalizedValue($0) }
            .first { candidate in
                !repeatedLines.contains { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }
            }
    }

    private var contextFallbackLine: String {
        if isFavorite {
            return L10n.string("player.station.savedShort")
        }
        if audioPlayer.isCurrent(station) {
            return isPlayingCurrentStation ? "En directo ahora" : "Pausada"
        }
        return L10n.string("shell.station.row.nearRecents")
    }

    private var compactGenreLine: String? {
        let tags = station.normalizedTags
            .compactMap(TuneAVMusicGenreCatalog.canonicalTag(for:))
            .map { L10n.genreLabel(for: $0) }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
                result.append(value)
            }
        guard !tags.isEmpty else { return nil }
        return tags.prefix(2).joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack(alignment: .topTrailing) {
                Button {
                    if audioPlayer.isCurrent(station) {
                        audioPlayer.togglePlayback()
                    } else {
                        playAction()
                    }
                } label: {
                    StationThumbnailView(
                        station: station,
                        size: StationCompactMetrics.artworkSize,
                        textMode: .none,
                        animationOverlay: .none,
                        isAnimationActive: false
                    )
                        .overlay {
                            artworkShape
                                .fill(isCurrentStationActive ? TuneAVTheme.highlight.opacity(0.16) : .clear)
                        }
                        .overlay {
                            if audioPlayer.isCurrent(station) {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                    Circle()
                                        .stroke(TuneAVTheme.highlight.opacity(0.42), lineWidth: 1)
                                    Image(systemName: isPlayingCurrentStation ? "pause.fill" : "play.fill")
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundStyle(isPlayingCurrentStation ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                                }
                                .frame(width: StationCompactMetrics.playBadgeSize, height: StationCompactMetrics.playBadgeSize)
                            }
                        }
                        .overlay {
                            artworkShape
                                .stroke(isCurrentStationActive ? TuneAVTheme.highlight : TuneAVTheme.borderSubtle, lineWidth: isCurrentStationActive ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationRow.play.\(station.id)")

                favoriteButton
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(compactPrimaryLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(reliableArtist != nil || reliableTitle != nil ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(compactSecondaryLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    feedbackBadgeIfNeeded

                    Text(compactTertiaryLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: StationCompactMetrics.artworkSize, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture(perform: detailsAction)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stationRow.\(station.id)")
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TuneAVTheme.cardSurface.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.66), lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: detailsAction)
    }

    @ViewBuilder
    private var feedbackBadgeIfNeeded: some View {
        if let stationFeedback {
            StationFeedbackBadge(feedback: stationFeedback, size: 22, fontSize: 10)
                .accessibilityLabel(stationFeedback.localizedState)
                .accessibilityIdentifier("stationRow.feedback.\(station.id)")
        }
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            TuneAVSavedStationIcon(isSaved: isFavorite, size: 16)
                .frame(width: StationCompactMetrics.favoriteButtonSize, height: StationCompactMetrics.favoriteButtonSize)
                .background(isFavorite ? TuneAVTheme.highlight.opacity(0.14) : Color.white.opacity(0.72), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isFavorite ? TuneAVTheme.highlight.opacity(0.28) : TuneAVTheme.borderSubtle.opacity(0.65), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? L10n.string("player.station.unsave") : L10n.string("player.station.save"))
        .accessibilityIdentifier("stationRow.favorite.\(station.id)")
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        TuneAVDisplayMetadata.normalized(value)
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: StationCompactMetrics.artworkSize),
            style: .continuous
        )
    }

    private var reliableArtist: String? {
        let candidate = audioPlayer.isCurrent(station) ? audioPlayer.currentTrackArtist : nowPlayingTrack?.artist
        guard let artist = normalizedMetadata(candidate) else { return nil }
        guard !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(artist, stationName: station.name) else { return nil }
        return artist
    }

    private var reliableTitle: String? {
        let candidate = audioPlayer.isCurrent(station) ? audioPlayer.currentTrackTitle : nowPlayingTrack?.title
        guard let title = normalizedMetadata(candidate) else { return nil }
        guard !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(title, stationName: station.name) else { return nil }
        return title
    }

    private var compactStationContext: String? {
        let country = compactCountryName.map { countryName in
            if let flag = station.flagEmoji {
                return "\(flag) \(countryName)"
            }
            return countryName
        }
        let language = TuneAVText.normalizedValue(station.language, excluding: Station.unknownDetailValues, locale: L10n.locale)
        let values = [country, language]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
                result.append(value)
            }

        guard !values.isEmpty else { return nil }
        return values.prefix(2).joined(separator: " · ")
    }

    private var compactCountryName: String? {
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            return L10n.countryName(for: countryCode)
        }

        return TuneAVText.normalizedValue(station.country, excluding: Station.unknownDetailValues, locale: L10n.locale)
    }
}

private struct StationListActionRow: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let station: Station
    let isFavorite: Bool
    let nowPlayingTrack: NowPlayingTrack?
    var stationFeedback: TuneAVStationFeedback? = nil
    let toggleFavorite: () -> Void
    let playAction: () -> Void
    let openWebsiteAction: () -> Void
    let detailsAction: () -> Void
    @State private var isShowingAviActions = false

    private var isPlayingCurrentStation: Bool {
        audioPlayer.isCurrent(station) && audioPlayer.isPlaying
    }

    private var isCurrentStationActive: Bool {
        audioPlayer.isCurrent(station) && (audioPlayer.isPlaying || audioPlayer.isLoading)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if audioPlayer.isCurrent(station) {
                    audioPlayer.togglePlayback()
                } else {
                    playAction()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isCurrentStationActive ? TuneAVTheme.highlight : TuneAVTheme.highlight.opacity(0.14))

                    Image(systemName: isPlayingCurrentStation ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(isCurrentStationActive ? TuneAVTheme.brandBlack : TuneAVTheme.highlight)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlayingCurrentStation ? L10n.string("player.control.pause") : L10n.string("player.control.play"))
            .accessibilityIdentifier("stationRow.play.\(station.id)")

            VStack(alignment: .leading, spacing: 3) {
                Text(station.name)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(primaryDetailLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryDetailIsNowPlaying ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                feedbackBadgeIfNeeded
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .contentShape(Rectangle())
            .onTapGesture(perform: detailsAction)

            aviActionsMenu
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TuneAVTheme.cardSurface.opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isCurrentStationActive ? TuneAVTheme.highlight.opacity(0.3) : TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: detailsAction)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stationRow.\(station.id)")
    }

    @ViewBuilder
    private var feedbackBadgeIfNeeded: some View {
        if let stationFeedback {
            StationFeedbackBadge(feedback: stationFeedback, size: 20, fontSize: 9)
                .accessibilityLabel(stationFeedback.localizedState)
                .accessibilityIdentifier("stationRow.feedback.\(station.id)")
        }
    }

    private var aviActionsMenu: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                isShowingAviActions.toggle()
            }
        } label: {
            Image("AviV2HeadNeutral")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .frame(width: 36, height: 36)
                .background(TuneAVTheme.elevatedSurface, in: Circle())
            .overlay {
                Circle()
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.avi.actions.askShort"))
        .accessibilityIdentifier("stationRow.aviActions.\(station.id)")
        .popover(
            isPresented: Binding(
                get: { isShowingAviActions },
                set: { if !$0 { closeAviActions() } }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            aviActionsPanel
                .frame(width: 278)
                .presentationCompactAdaptation(.none)
        }
    }

    private var aviActionsPanel: some View {
        AviRowActionsPanel(close: closeAviActions) {
            AviRowActionButton(
                title: isFavorite ? L10n.string("player.station.unsave") : L10n.string("player.station.save"),
                systemImage: isFavorite ? "bookmark.slash" : "bookmark"
            ) {
                toggleFavorite()
                closeAviActions()
            }
            AviRowActionButton(title: L10n.string("shell.avi.recommendation.details"), systemImage: "info.circle") {
                detailsAction()
                closeAviActions()
            }
            if station.resolvedHomepageURL != nil {
                AviRowActionButton(title: L10n.string("player.menu.openWebsite"), systemImage: "safari") {
                    openWebsiteAction()
                    closeAviActions()
                }
            }
        }
    }

    private func closeAviActions() {
        withAnimation(.snappy(duration: 0.18)) {
            isShowingAviActions = false
        }
    }

    private var primaryDetailIsNowPlaying: Bool {
        reliableArtist != nil || reliableTitle != nil
    }

    private var primaryDetailLine: String {
        if let reliableArtist, let reliableTitle {
            return "\(reliableArtist) · \(reliableTitle)"
        }

        if let reliableArtist {
            return reliableArtist
        }

        if let reliableTitle {
            return reliableTitle
        }

        return compactStationContext ?? L10n.string("shell.station.row.defaultDetail")
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        TuneAVDisplayMetadata.normalized(value)
    }

    private var reliableArtist: String? {
        let candidate = audioPlayer.isCurrent(station) ? audioPlayer.currentTrackArtist : nowPlayingTrack?.artist
        guard let artist = normalizedMetadata(candidate) else { return nil }
        guard !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(artist, stationName: station.name) else { return nil }
        return artist
    }

    private var reliableTitle: String? {
        let candidate = audioPlayer.isCurrent(station) ? audioPlayer.currentTrackTitle : nowPlayingTrack?.title
        guard let title = normalizedMetadata(candidate) else { return nil }
        guard !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(title, stationName: station.name) else { return nil }
        return title
    }

    private var compactStationContext: String? {
        let country = compactCountryName.map { countryName in
            if let flag = station.flagEmoji {
                return "\(flag) \(countryName)"
            }
            return countryName
        }
        let language = TuneAVText.normalizedValue(station.language, excluding: Station.unknownDetailValues, locale: L10n.locale)
        let values = [country, language]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
                result.append(value)
            }

        guard !values.isEmpty else { return nil }
        return values.prefix(2).joined(separator: " · ")
    }

    private var compactCountryName: String? {
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            return L10n.countryName(for: countryCode)
        }

        return TuneAVText.normalizedValue(station.country, excluding: Station.unknownDetailValues, locale: L10n.locale)
    }
}

private struct AviRowActionsPanel<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("shell.avi.actions.ask"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)

                    Text(L10n.string("shell.avi.actions.page", 1, 1))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                Spacer(minLength: 0)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(TuneAVTheme.cardSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.avi.actions.closeOptions"))
            }

            VStack(spacing: 7) {
                content()
            }
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(TuneAVTheme.elevatedSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.glassShadow, radius: 24, y: 12)
    }
}

private struct AviRowActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(role == .destructive ? Color.red : TuneAVTheme.highlight)
                    .frame(width: 30, height: 30)
                    .background((role == .destructive ? Color.red : TuneAVTheme.highlight).opacity(0.1), in: Circle())

                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .padding(.horizontal, 10)
            .background(TuneAVTheme.cardSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.46), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum StationDetailTab: String, CaseIterable {
    case profile
    case signal
    case history

    var title: String {
        switch self {
        case .profile: return L10n.string("shell.stationDetail.tab.profile")
        case .signal: return L10n.string("shell.stationDetail.tab.signal")
        case .history: return L10n.string("shell.stationDetail.tab.history")
        }
    }

    var icon: String {
        switch self {
        case .profile: return "sparkles"
        case .signal: return "dot.radiowaves.left.and.right"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

private struct StationDetailSheet: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @State private var browserDestination: BrowserDestination?
    @State private var selectedTab: StationDetailTab = .profile

    private static let lastCheckFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let station: Station
    let stationDiscoveries: [DiscoveredTrack]
    let isFavorite: Bool
    let isActive: Bool
    let isPlaying: Bool
    let stationFeedback: TuneAVStationFeedback?
    let playAction: () -> Void
    let toggleFavorite: () -> Void
    let setStationFeedback: (TuneAVStationFeedback?) -> Void
    let openActiveSignal: () -> Void
    let openStationHistory: (Station) -> Void
    let closeAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                signalHeader

                signalConsoleHero

                StationDetailTabBar(selectedTab: $selectedTab)

                switch selectedTab {
                case .profile:
                    profileContent
                case .signal:
                    signalContent
                case .history:
                    historyContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
    }

    private var signalHeader: some View {
        DetailTopHeader(
            title: L10n.string("shell.common.radio"),
            entityName: station.name,
            subtitle: station.primaryDetailLine.isEmpty ? L10n.string("shell.stationInfo.publicSignal") : station.primaryDetailLine,
            status: isActive ? L10n.string("shell.stationDetail.activeSignal") : L10n.string("shell.stationDetail.exploredSignal"),
            feedback: stationFeedback,
            accessibilityIdentifier: "station.detail.header",
            goBack: closeAction
        )
        .overlay(alignment: .topTrailing) {
            if !isActive, audioPlayer.currentStation != nil {
                Button(action: openActiveSignal) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(TuneAVTheme.brandBlack)
                        .frame(width: 36, height: 36)
                        .background(TuneAVTheme.highlight, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.stationDetail.goToActiveSignal"))
            }
        }
    }

    private var signalConsoleHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                StationThumbnailView(
                    station: station,
                    size: 72,
                    animationOverlay: .none,
                    isAnimationActive: false
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(station.primaryDetailLine.isEmpty ? station.name : station.primaryDetailLine)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)

                    Text(isActive ? activeSignalTitle : L10n.string("shell.stationDetail.aviCanAnalyze"))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isActive {
                activeSongPanel
            } else {
                exploredStationPanel
            }

            HStack(spacing: 10) {
                Button {
                    playAction()
                } label: {
                    Label(isPlaying ? L10n.string("player.control.pause") : L10n.string("shell.stationDetail.playRadio"), systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(TuneAVTheme.brandBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationDetail.play")

                signalIconButton(
                    systemImage: isFavorite ? "bookmark.slash" : "bookmark",
                    accessibilityLabel: isFavorite ? L10n.string("player.station.unsave") : L10n.string("player.station.save"),
                    isSelected: isFavorite,
                    action: toggleFavorite
                )

                if let homepageURL {
                    signalIconButton(systemImage: "safari", accessibilityLabel: L10n.string("player.menu.openWebsite")) {
                        browserDestination = BrowserDestination(url: homepageURL)
                    }
                }

                signalIconButton(systemImage: "clock.arrow.circlepath", accessibilityLabel: L10n.string("player.menu.stationHistory")) {
                    openStationHistory(station)
                }
            }

            StationFeedbackControl(
                selectedFeedback: stationFeedback,
                selectFeedback: { feedback in
                    setStationFeedback(stationFeedback == feedback ? nil : feedback)
                },
                clearFeedback: {
                    setStationFeedback(nil)
                }
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(isActive ? TuneAVTheme.highlight.opacity(0.26) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
    }

    private var activeSongPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 36, height: 36)
                .background(TuneAVTheme.elevatedSurface, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("shell.stationDetail.aviListeningNow"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)

                Text(activeSignalSubtitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var exploredStationPanel: some View {
        Text(L10n.string("shell.stationDetail.exploredPanel.detail"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(TuneAVTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func signalIconButton(
        systemImage: String,
        accessibilityLabel: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .symbolRenderingMode(systemImage == "dot.radiowaves.left.and.right" ? .hierarchical : .monochrome)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                .frame(width: 46, height: 46)
                .background(isSelected ? TuneAVTheme.highlight.opacity(0.14) : TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.32) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var activeSignalTitle: String {
        TuneAVText.normalizedValue(audioPlayer.currentTrackTitle) ?? L10n.string("shell.stationDetail.activeSignalFallback")
    }

    private var activeSignalSubtitle: String {
        let artist = TuneAVText.normalizedValue(audioPlayer.currentTrackArtist)
        let title = TuneAVText.normalizedValue(audioPlayer.currentTrackTitle)
        return [artist, title].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var profileContent: some View {
        if let editorial = station.editorial {
            DetailSection(title: L10n.string("shell.stationDetail.section.editorial")) {
                VStack(alignment: .leading, spacing: 16) {
                    WrapTagsRow(tags: editorialBadges(for: editorial), highlighted: true)

                    Text(editorial.summary)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let profile = editorial.discoveryProfile {
                        StationDiscoveryProfileView(profile: profile)
                    }

                    if !editorial.programming.isEmpty {
                        WrapTagsRow(tags: editorial.programming)
                    }

                    Text(L10n.string("shell.stationDetail.editorial.confidence", editorial.confidence.capitalized))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }
            }
        }

        let canonicalTags = station.normalizedTags
            .compactMap(TuneAVMusicGenreCatalog.canonicalTag(for:))
            .map { L10n.genreLabel(for: $0) }
            .reduce(into: [String]()) { result, tag in
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else { return }
                result.append(tag)
            }
        if !canonicalTags.isEmpty {
            DetailSection(title: L10n.string("shell.stationDetail.section.tags")) {
                WrapTagsRow(tags: canonicalTags)
            }
        }
    }

    @ViewBuilder
    private var signalContent: some View {
        if !station.technicalBadges.isEmpty {
            DetailSection(title: L10n.string("shell.stationDetail.section.technical")) {
                WrapTagsRow(tags: station.technicalBadges, highlighted: true)
            }
        }

        if !station.popularityBadges.isEmpty {
            DetailSection(title: L10n.string("shell.stationDetail.section.signals")) {
                WrapTagsRow(tags: station.popularityBadges)
            }
        }

        DetailSection(title: L10n.string("shell.stationDetail.section.about")) {
            VStack(spacing: 12) {
                DetailInfoRow(title: L10n.string("shell.stationDetail.field.country"), value: station.country)
                DetailInfoRow(title: L10n.string("shell.stationDetail.field.language"), value: station.language)
                if let state = station.state, !state.isEmpty {
                    DetailInfoRow(title: L10n.string("shell.stationDetail.field.state"), value: state)
                }
                if let countryCode = station.countryCode, !countryCode.isEmpty {
                    DetailInfoRow(title: L10n.string("shell.stationDetail.field.code"), value: countryCode)
                }
                if let lastCheckOKAt = formattedLastCheck {
                    DetailInfoRow(title: L10n.string("shell.stationDetail.field.lastCheck"), value: lastCheckOKAt)
                }
                if let homepageHost, !homepageHost.isEmpty {
                    DetailInfoRow(title: L10n.string("shell.stationDetail.field.website"), value: homepageHost)
                }
            }
        }
    }

    private var historyContent: some View {
        DetailSection(title: L10n.string("shell.stationDetail.tab.history")) {
            if stationDiscoveries.isEmpty {
                Text(L10n.string("shell.stationDetail.history.empty"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("shell.stationDetail.history.copy"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(stationDiscoveries.prefix(12)) { discovery in
                        StationSheetDiscoveryRow(discovery: discovery)
                    }
                }
            }
        }
    }

    private var homepageURL: URL? {
        station.resolvedHomepageURL
    }

    private var homepageHost: String? {
        homepageURL?.host()
    }

    private var formattedLastCheck: String? {
        guard let lastCheckOKAt = station.lastCheckOKAt, !lastCheckOKAt.isEmpty else { return nil }
        guard let date = Self.lastCheckFormatter.date(from: lastCheckOKAt) else { return lastCheckOKAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func editorialBadges(for editorial: StationEditorial) -> [String] {
        [
            localizedPrimaryFormat(editorial.primaryFormat),
            localizedIntensity("music", value: editorial.musicIntensity),
            localizedIntensity("speech", value: editorial.speechIntensity)
        ]
        .compactMap { $0 }
    }

    private func localizedPrimaryFormat(_ format: String) -> String? {
        switch format {
        case "music": return L10n.string("shell.stationDetail.editorial.format.music")
        case "newsTalk": return L10n.string("shell.stationDetail.editorial.format.newsTalk")
        case "sports": return L10n.string("shell.stationDetail.editorial.format.sports")
        case "mixed": return L10n.string("shell.stationDetail.editorial.format.mixed")
        case "community": return L10n.string("shell.stationDetail.editorial.format.community")
        case "religious": return L10n.string("shell.stationDetail.editorial.format.religious")
        default: return nil
        }
    }

    private func localizedIntensity(_ kind: String, value: String) -> String? {
        switch (kind, value) {
        case ("music", "low"): return L10n.string("shell.stationDetail.editorial.music.low")
        case ("music", "medium"): return L10n.string("shell.stationDetail.editorial.music.medium")
        case ("music", "high"): return L10n.string("shell.stationDetail.editorial.music.high")
        case ("speech", "low"): return L10n.string("shell.stationDetail.editorial.speech.low")
        case ("speech", "medium"): return L10n.string("shell.stationDetail.editorial.speech.medium")
        case ("speech", "high"): return L10n.string("shell.stationDetail.editorial.speech.high")
        default: return nil
        }
    }
}

private struct StationDetailTabBar: View {
    @Binding var selectedTab: StationDetailTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(StationDetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selectedTab == tab ? .white : TuneAVTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            selectedTab == tab ? TuneAVTheme.highlight : TuneAVTheme.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(selectedTab == tab ? TuneAVTheme.highlight.opacity(0.35) : TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct StationFeedbackControl: View {
    let selectedFeedback: TuneAVStationFeedback?
    let selectFeedback: (TuneAVStationFeedback) -> Void
    let clearFeedback: () -> Void

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.string("shell.stationFeedback.title"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)

                Spacer()

                Button(action: clearFeedback) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .opacity(selectedFeedback == nil ? 0 : 1)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(selectedFeedback == nil)
                .accessibilityHidden(selectedFeedback == nil)
                .accessibilityLabel(L10n.string("shell.stationFeedback.clear"))
                .accessibilityIdentifier("stationFeedback.clear")
            }
            .frame(height: 24)

            Group {
                if let selectedFeedback {
                    SelectedStationFeedbackStatus(feedback: selectedFeedback)
                } else {
                    HStack(spacing: 8) {
                        StationFeedbackButton(
                            title: L10n.string("shell.stationFeedback.like"),
                            systemImage: "hand.thumbsup.fill",
                            feedback: .liked,
                            isSelected: false,
                            action: { selectFeedback(.liked) }
                        )

                        StationFeedbackButton(
                            title: L10n.string("shell.stationFeedback.notForMe"),
                            systemImage: "minus.circle.fill",
                            feedback: .notForMe,
                            isSelected: false,
                            action: { selectFeedback(.notForMe) }
                        )

                        StationFeedbackButton(
                            title: L10n.string("shell.stationFeedback.dislike"),
                            systemImage: "hand.thumbsdown.fill",
                            feedback: .disliked,
                            isSelected: false,
                            action: { selectFeedback(.disliked) }
                        )
                    }
                }
            }
            .frame(height: 38)
        }
        .frame(height: 72, alignment: .top)
        .accessibilityIdentifier("stationFeedback.control")
    }
}

private struct SelectedStationFeedbackStatus: View {
    let feedback: TuneAVStationFeedback

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feedback.systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(TuneAVTheme.brandBlack)
                .frame(width: 30, height: 30)
                .background(TuneAVTheme.highlight, in: Circle())

            Text(feedback.localizedState)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(TuneAVTheme.highlight.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
        }
        .accessibilityLabel(feedback.localizedState)
    }
}

private struct StationFeedbackButton: View {
    let title: String
    let systemImage: String
    let feedback: TuneAVStationFeedback
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    isSelected ? TuneAVTheme.highlight : TuneAVTheme.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.62) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? L10n.string("common.selected") : "")
        .accessibilityIdentifier("stationFeedback.\(feedback.rawValue)")
    }
}

private struct StationDiscoveryProfileView: View {
    let profile: StationDiscoveryProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("shell.stationDetail.discovery.score"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                    Text(scoreLabel)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                }

                Spacer()

                Text("\(profile.musicDiscoveryScore)")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .monospacedDigit()
            }

            VStack(spacing: 10) {
                DiscoveryMetricRow(title: L10n.string("shell.stationDetail.discovery.music"), level: profile.musicLevel)
                DiscoveryMetricRow(title: L10n.string("shell.stationDetail.discovery.speech"), level: profile.speechLevel)
                DiscoveryMetricRow(title: L10n.string("shell.stationDetail.discovery.news"), level: profile.newsLevel)
                DiscoveryMetricRow(title: L10n.string("shell.stationDetail.discovery.sports"), level: profile.sportsLevel)
                DiscoveryMetricRow(title: L10n.string("shell.stationDetail.discovery.ads"), level: profile.adLoad)
            }

            if !profile.bestFor.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("shell.stationDetail.discovery.bestFor"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                    WrapTagsRow(tags: profile.bestFor, highlighted: true)
                }
            }

            if !profile.notIdealFor.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("shell.stationDetail.discovery.notIdealFor"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                    WrapTagsRow(tags: profile.notIdealFor)
                }
            }

            if !profile.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profile.reasons.prefix(3), id: \.self) { reason in
                        Label(reason, systemImage: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TuneAVTheme.elevatedSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
    }

    private var scoreLabel: String {
        switch profile.musicDiscoveryScore {
        case 75...100:
            return L10n.string("shell.stationDetail.discovery.scoreHigh")
        case 40..<75:
            return L10n.string("shell.stationDetail.discovery.scoreMedium")
        default:
            return L10n.string("shell.stationDetail.discovery.scoreLow")
        }
    }
}

private struct DiscoveryMetricRow: View {
    let title: String
    let level: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 82, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(TuneAVTheme.borderSubtle.opacity(0.5))
                    Capsule()
                        .fill(level == "unknown" ? TuneAVTheme.textSecondary.opacity(0.35) : TuneAVTheme.highlight.opacity(0.8))
                        .frame(width: proxy.size.width * levelRatio)
                }
            }
            .frame(height: 8)

            Text(localizedLevel)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private var levelRatio: CGFloat {
        switch level {
        case "low": return 0.25
        case "medium": return 0.58
        case "high": return 1
        default: return 0.35
        }
    }

    private var localizedLevel: String {
        switch level {
        case "low": return L10n.string("shell.stationDetail.discovery.level.low")
        case "medium": return L10n.string("shell.stationDetail.discovery.level.medium")
        case "high": return L10n.string("shell.stationDetail.discovery.level.high")
        default: return L10n.string("shell.stationDetail.discovery.level.unknown")
        }
    }
}

private struct StationSheetDiscoveryRow: View {
    let discovery: DiscoveredTrack

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: discovery.isMarkedInteresting ? "bookmark.fill" : "music.note")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(discovery.isMarkedInteresting ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                .frame(width: 36, height: 36)
                .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(discovery.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(discovery.artistDisplayText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(discovery.playedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .multilineTextAlignment(.trailing)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            content()
        }
    }
}

private struct DetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct WrapTagsRow: View {
    let tags: [String]
    var highlighted = false

    var body: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(highlighted ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(highlighted ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(highlighted ? TuneAVTheme.highlight.opacity(0.18) : TuneAVTheme.borderSubtle, lineWidth: 1)
                    }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + horizontalSpacing + size.width > maxWidth {
                totalHeight += lineHeight + verticalSpacing
                maxLineWidth = max(maxLineWidth, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += lineWidth == 0 ? size.width : horizontalSpacing + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        maxLineWidth = max(maxLineWidth, lineWidth)
        totalHeight += lineHeight

        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > bounds.minX, origin.x + size.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += lineHeight + verticalSpacing
                lineHeight = 0
            }

            subview.place(
                at: origin,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            origin.x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct StationCardSkeletonGroup: View {
    var count: Int = 4

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { index in
                StationRowSkeletonCard(accentWidth: index == 0 ? 152 : 124)
            }
        }
    }
}

private struct SearchLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(TuneAVTheme.highlight)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("shell.search.loading.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(L10n.string("shell.search.loading.detail"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
    }
}

private struct StationRowSkeletonCard: View {
    let accentWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SkeletonBlock(cornerRadius: 18)
                .frame(width: StationRowMetrics.artworkSize, height: StationRowMetrics.artworkSize)

            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(cornerRadius: 8)
                    .frame(width: accentWidth, height: 16)

                SkeletonBlock(cornerRadius: 7)
                    .frame(width: 116, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                SkeletonBlock(cornerRadius: 17)
                    .frame(width: StationRowMetrics.favoriteButtonSize, height: StationRowMetrics.favoriteButtonSize)
                    .clipShape(Circle())

                SkeletonBlock(cornerRadius: 19)
                    .frame(width: StationRowMetrics.playButtonSize, height: StationRowMetrics.playButtonSize)
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
        .opacity(0.86)
    }
}

private struct SkeletonBlock: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        TuneAVTheme.mutedSurface.opacity(0.9),
                        TuneAVTheme.skeletonHighlight,
                        TuneAVTheme.mutedSurface.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TuneAVTheme.glassStroke, lineWidth: 0.8)
            }
    }
}

private struct SearchField: View {
    @Binding var query: String
    let prompt: String
    let focusRequest: Int?

    @FocusState private var isFocused: Bool

    init(query: Binding<String>, prompt: String? = nil, focusRequest: Int? = nil) {
        _query = query
        self.prompt = prompt ?? L10n.string("shell.search.field.defaultPrompt")
        self.focusRequest = focusRequest
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)

            TextField(
                text: $query,
                prompt: Text(prompt)
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.68))
            ) {
            }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .tint(TuneAVTheme.highlight)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)

            if !query.isEmpty {
                Button(L10n.string("shell.search.field.clear")) {
                    query = ""
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
        .task(id: focusRequest) {
            guard focusRequest != nil else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isFocused = true
        }
    }
}

struct ShellRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ShellStatusPill: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(TuneAVTheme.highlight)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct EmptyLibraryState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(detail)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
    }
}

#Preview {
    let persistence = PersistenceController(inMemory: true)

    AppShellView()
        .environmentObject(AccessController())
        .environmentObject(AudioPlayerService())
        .environmentObject(LibraryStore(container: persistence.container))
        .modelContainer(persistence.container)
}
