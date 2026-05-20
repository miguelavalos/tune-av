import SwiftUI
import UIKit

struct AppShellView: View {
    private struct PendingPlayback: Identifiable {
        let id = UUID()
        let station: Station
        let queueSource: AudioPlayerService.PlaybackQueue.Source
        let queue: [Station]?
    }

    private enum LastOpenedStationPresentation: String {
        case detail
        case player
    }

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
    @State private var isAviActionPanelOpen = false
    @State private var aviReturnCoordinator = AviReturnCoordinator()
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
    @State private var lastConfirmedPlaybackStationID: String?
    @State private var isShowingProPaywall = false
    @State private var isShowingFooterArtworkZoom = false
    @State private var pendingCellularPlayback: PendingPlayback?
    @State private var isConfirmingStopPlayback = false

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

    private var aviStationDetailBuilder: AviStationDetailBuilder {
        AviStationDetailBuilder(
            enrichStation: enrichedStation,
            enrichStations: enrichedStations
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
            hasAviActiveContext: hasAviActiveContext,
            footerBackdropHeight: shellFooterBackdropHeight,
            footerPlayerTabSpacing: shellFooterPlayerTabSpacing,
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
                    if isAviFullPlayerActive && !isAviActionPanelOpen {
                        AviExpandedFooterPlayerView(
                            station: station,
                            playbackQueueSource: audioPlayer.playbackQueue.source,
                            playbackQueueStations: enrichedStations(audioPlayer.playbackQueue.stations),
                            stations: enrichedStations(homeStations),
                            recentStations: enrichedRecentStations,
                            favoriteStations: enrichedFavoriteStations
                        ) {
                            openNowPlayingFullPlayer(station)
                        } showArtworkZoom: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                isShowingFooterArtworkZoom = true
                            }
                        } stopPlayback: {
                            stopPlaybackAndCloseSignal()
                        } playStationFromQueue: { station, source, queue in
                            playStation(station, queueSource: source, queue: queue)
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
            TuneAVProPaywallView {
                startSignInFlow(true)
            }
                .environmentObject(accessController)
        }
        .alert(L10n.string("settings.cellularPlayback.alert.title"), isPresented: pendingCellularPlaybackIsPresented) {
            Button(L10n.string("common.cancel"), role: .cancel) {
                pendingCellularPlayback = nil
            }
            Button(L10n.string("settings.cellularPlayback.alert.play")) {
                if let pending = pendingCellularPlayback {
                    playStationAfterCellularCheck(pending.station, queueSource: pending.queueSource, queue: pending.queue)
                }
                pendingCellularPlayback = nil
            }
        } message: {
            Text(L10n.string("settings.cellularPlayback.alert.message"))
        }
        .alert(L10n.string("player.stopPlayback.alert.title"), isPresented: $isConfirmingStopPlayback) {
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("player.stopPlayback.alert.stop"), role: .destructive) {
                stopPlaybackAndCloseSignal()
            }
        } message: {
            Text(L10n.string("player.stopPlayback.alert.message"))
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
            if stationID == nil {
                lastConfirmedPlaybackStationID = nil
                return
            }
            guard let station = audioPlayer.currentStation else { return }
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
            homeScreen
        case .search:
            searchScreen
        case .avi:
            aviScreen
        case .library:
            libraryScreen
        case .music:
            musicScreen
        case .profile:
            profileScreen
        }
    }

    private var homeScreen: some View {
        let stations = enrichedStations(homeSnapshot.stations)
        let recentStations = enrichedStations(homeSnapshot.recentStations)
        let favoriteStations = enrichedStations(homeSnapshot.favoriteStations)

        return makeHomeScreen(
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
            openAvi: openContextualAvi,
            openSearchTag: openHomeSearchTag(_:),
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
    }

    private func openHomeSearchTag(_ tag: String) {
        searchQuery = ""
        searchCountryCode = nil
        searchTag = tag
        searchDiscoveryMode = .music
        selectedTab = .search
    }

    private var searchScreen: some View {
        makeSearchScreen(
            query: $searchQuery,
            activeTag: $searchTag,
            selectedCountryCode: $searchCountryCode,
            discoveryMode: $searchDiscoveryMode,
            results: enrichedStations(visibleSearchResults),
            isLoading: searchIsLoading,
            errorMessage: searchErrorMessage,
            tags: genreTags,
            bottomContentPadding: shouldHideFooterPlayer ? 176 : shellScrollBottomPadding,
            favoriteStationIDs: favoriteStationIDs,
            nowPlayingTracks: stationNowPlayingTracks,
            stationFeedback: libraryStore.stationFeedback,
            playStation: playStation,
            toggleFavorite: toggleFavorite(_:),
            showStationDetails: showSearchStationDetails(_:queueSource:queue:)
        )
    }

    private var visibleSearchResults: [Station] {
        searchResults.isEmpty
            ? searchFallbackStations(for: searchRequest)
            : searchResults
    }

    private func showSearchStationDetails(
        _ station: Station,
        queueSource: TuneAVPlaybackQueueSource,
        queue: [Station]?
    ) {
        showStationDetails(station, queueSource: queueSource, queue: queue)
    }

    private var libraryScreen: some View {
        makeLibraryScreen(
            favorites: enrichedFavoriteStations,
            recents: enrichedRecentStations,
            discoveries: libraryStore.discoveries,
            summary: libraryStore.userSummary,
            requestedMode: $requestedRadioMode,
            requestedOverview: $requestedRadioOverview,
            bottomContentPadding: shellScrollBottomPadding,
            favoriteStationIDs: favoriteStationIDs,
            nowPlayingTracks: stationNowPlayingTracks,
            stationFeedback: libraryStore.stationFeedback,
            openAccountAction: openAccountProfile,
            startSignInAction: startAviSignIn,
            openSearchAction: openSearchTab,
            playStation: playStation,
            toggleFavorite: toggleFavorite(_:),
            showStationDetails: showLibraryStationDetails(_:queueSource:queue:returnRadioMode:returnRadioOverview:)
        )
    }

    private func showLibraryStationDetails(
        _ station: Station,
        queueSource: TuneAVPlaybackQueueSource,
        queue: [Station]?,
        returnRadioMode: RadioLibraryMode?,
        returnRadioOverview: Bool?
    ) {
        showStationDetails(
            station,
            queueSource: queueSource,
            queue: queue,
            returnRadioMode: returnRadioMode,
            returnRadioOverview: returnRadioOverview
        )
    }

    private var musicScreen: some View {
        makeMusicScreen(
            discoveries: libraryStore.discoveries,
            summary: libraryStore.userSummary,
            historyStationFilter: $musicHistoryStationFilter,
            requestedMusicMode: $requestedMusicMode,
            requestedMusicOverview: $requestedMusicOverview,
            bottomContentPadding: shellScrollBottomPadding,
            openDiscoveryStation: openDiscoveryStation(_:),
            openDiscoveryStationInfo: openDiscoveryStationInfo(_:),
            openDiscoveryInfo: openMusicDiscoveryInfo(_:returnMusicMode:),
            openArtistInfo: openMusicArtistInfo(_:returnMusicMode:),
            stationArtworkURL: musicStationArtworkURL(_:),
            trackFeedback: musicTrackFeedback(_:),
            openSearchAction: openSearchTab,
            openAccountAction: openAccountProfile,
            startSignInAction: startAviSignIn,
            toggleDiscoverySaved: toggleDiscoverySaved(_:),
            hideDiscovery: libraryStore.hideDiscovery(_:),
            restoreDiscovery: libraryStore.restoreDiscovery(_:),
            removeDiscovery: libraryStore.removeDiscovery(_:),
            clearDiscoveries: libraryStore.clearDiscoveries
        )
    }

    private func openMusicDiscoveryInfo(
        _ discovery: DiscoveredTrack,
        returnMusicMode: MusicContentMode?
    ) {
        openDiscoveryInfo(discovery, returnMusicMode: returnMusicMode)
    }

    private func openMusicArtistInfo(
        _ artist: DiscoveryArtistSummary,
        returnMusicMode: MusicContentMode?
    ) {
        openArtistInfo(artist, returnMusicMode: returnMusicMode)
    }

    private func musicStationArtworkURL(_ discovery: DiscoveredTrack) -> URL? {
        nil
    }

    private func musicTrackFeedback(_ discovery: DiscoveredTrack) -> TuneAVStationFeedback? {
        libraryStore.feedback(for: discovery)
    }

    private var profileScreen: some View {
        makeProfileScreen(
            mode: profileMode,
            startSignInFlow: startSignInFlow,
            bottomContentPadding: shellScrollBottomPadding
        )
    }

    private var aviScreen: some View {
        let focusedStation = selectedStationDetail.map { enrichedStation($0.station) }
        let stations = enrichedStations(homeSnapshot.stations)
        let recentStations = enrichedRecentStations
        let favoriteStations = enrichedFavoriteStations

        return makeAviScreen(
            currentStation: audioPlayer.currentStation,
            focusedStation: focusedStation,
            isFocusedStationActive: focusedStation.map(audioPlayer.isCurrent(_:)) ?? false,
            currentTrackTitle: TuneAVText.normalizedValue(audioPlayer.currentTrackTitle),
            currentTrackArtist: TuneAVText.normalizedValue(audioPlayer.currentTrackArtist),
            currentTrackArtworkURL: audioPlayer.currentTrackArtworkURL,
            isPlaying: audioPlayer.isPlaying,
            isLoading: audioPlayer.isLoading,
            activeSleepTimerMinutes: audioPlayer.activeSleepTimerMinutes,
            activeSleepTimerRemainingMinutes: audioPlayer.activeSleepTimerRemainingMinutes,
            canCyclePlaybackQueue: audioPlayer.canCyclePlaybackQueue,
            playbackQueueSource: audioPlayer.playbackQueue.source,
            playbackQueueStations: enrichedStations(audioPlayer.playbackQueue.stations),
            stations: stations,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            discoveries: libraryStore.discoveries,
            focusedMusicDetail: selectedMusicAviDetail,
            isNowPlayingFullPlayer: isAviNowPlayingFullPlayer,
            isActionPanelOpen: $isAviActionPanelOpen,
            stationFeedback: libraryStore.stationFeedback,
            feedContext: homeSnapshot.feedContext,
            preferredTag: libraryStore.settings.preferredTag,
            preferredCountryCode: libraryStore.settings.preferredCountry,
            bottomContentPadding: shellScrollBottomPadding,
            openSearch: openSearchTab,
            openLibrary: openLibraryTab,
            openPlayer: openAviPlayer,
            stopPlayback: stopPlaybackAndCloseSignal,
            setSleepTimer: audioPlayer.setSleepTimer(minutes:),
            playPrevious: audioPlayer.playPreviousInQueue,
            playNext: audioPlayer.playNextInQueue,
            playStation: playAviDiscoveryStation(_:queue:),
            playStationFromQueue: playStation(_:queueSource:queue:),
            toggleFavorite: toggleFavorite(_:),
            setStationFeedback: { station, feedback in
                libraryStore.setFeedback(feedback, for: station)
            },
            showStationDetails: showAviStationDetails(_:queue:),
            openDiscoveryInfo: { discovery in
                openDiscoveryInfo(discovery)
            },
            openDiscoveryStation: openDiscoveryStation(_:),
            openAccount: openAccountProfile,
            startSignIn: startAviSignIn,
            openProPaywall: openProPaywall,
            closeFocusedDetail: {
                closeFocusedAviDetail()
            }
        )
    }

    private func openSearchTab() {
        selectedTab = .search
    }

    private func openLibraryTab() {
        selectedTab = .library
    }

    private func openAviPlayer() {
        let focusedStation = selectedStationDetail.map { enrichedStation($0.station) }
        let focusedQueueStations = selectedStationDetail.map { enrichedStations($0.queueStations) }
        let focusedQueueSource = selectedStationDetail?.queueSource ?? .singleStation

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
    }

    private func playAviDiscoveryStation(_ station: Station, queue: [Station]) {
        playStation(station, queueSource: .homeDiscovery, queue: queue)
    }

    private func showAviStationDetails(_ station: Station, queue: [Station]) {
        showStationDetails(station, queueSource: .homeDiscovery, queue: queue)
    }

    private func openAccountProfile() {
        profileMode = .account
        selectedTab = .profile
    }

    private func startAviSignIn() {
        startSignInFlow(true)
    }

    private func openProPaywall() {
        isShowingProPaywall = true
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

    private var isAviFullPlayerActive: Bool {
        selectedTab == .avi && isAviNowPlayingFullPlayer && audioPlayer.currentStation != nil
    }

    private var shouldHideFooterPlayer: Bool {
        isAviFullPlayerActive
    }

    private var hasAviActiveContext: Bool {
        audioPlayer.currentStation != nil || selectedStationDetail != nil || selectedMusicAviDetail != nil
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
        if isAviFullPlayerActive && isAviActionPanelOpen {
            return 186
        }
        return isAviFullPlayerActive ? 500 : 224
    }

    private var shellFooterBackdropHeight: CGFloat {
        if audioPlayer.currentStation == nil {
            return 142
        }
        if isAviFullPlayerActive && isAviActionPanelOpen {
            return 156
        }
        return isAviFullPlayerActive ? 500 : 210
    }

    private var shellFooterPlayerTabSpacing: CGFloat {
        10
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

        seedUITestDataIfNeeded()

        if let preferredTab = launchContext.preferredTab {
            switch preferredTab {
            case .home:
                selectedTab = .home
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
        } else if libraryStore.settings.openLastStationOnLaunch {
            restoreLastOpenedStationOnLaunch()
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

    private func restoreLastOpenedStationOnLaunch() {
        if let lastStation = libraryStore.station(for: libraryStore.settings.lastPlayedStationID) {
            selectStationForLaunchAndOpenPlayer(lastStation)
            return
        }

        if let stationID = libraryStore.settings.lastOpenedStationID,
           let station = libraryStore.station(for: stationID) {
            selectStationForLaunchAndOpenPlayer(station)
        }
    }

    private func selectStationForLaunchAndOpenPlayer(_ station: Station) {
        let resolvedStation = enrichedStation(station)
        let queue = restoredPlaybackQueue(for: resolvedStation)
        audioPlayer.select(station: resolvedStation, queue: queue)
        openNowPlayingFullPlayer(resolvedStation)
    }

    private func restoredPlaybackQueue(for station: Station) -> AudioPlayerService.PlaybackQueue {
        let favorites = enrichedFavoriteStations
        if favorites.contains(where: { $0.id == station.id }), favorites.count > 1 {
            return AudioPlayerService.PlaybackQueue(source: .libraryFavorites, stations: favorites)
        }

        let recents = enrichedRecentStations
        if recents.contains(where: { $0.id == station.id }), recents.count > 1 {
            return AudioPlayerService.PlaybackQueue(source: .libraryRecents, stations: recents)
        }

        let fallbackQueue = uniquePlaybackStations([station] + favorites + recents + enrichedStations(homeSnapshot.stations))
        return AudioPlayerService.PlaybackQueue(
            source: fallbackQueue.count > 1 ? .homeRecents : .singleStation,
            stations: fallbackQueue
        )
    }

    private func uniquePlaybackStations(_ stations: [Station]) -> [Station] {
        var seenIDs = Set<String>()
        return stations.filter { station in
            seenIDs.insert(station.id).inserted
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
        guard shouldPlayImmediatelyOnCurrentNetwork else {
            pendingCellularPlayback = PendingPlayback(station: station, queueSource: queueSource, queue: queue)
            return
        }

        playStationAfterCellularCheck(station, queueSource: queueSource, queue: queue)
    }

    private var shouldPlayImmediatelyOnCurrentNetwork: Bool {
        !libraryStore.settings.warnBeforeCellularPlayback || !audioPlayer.currentNetworkIsExpensive
    }

    private var pendingCellularPlaybackIsPresented: Binding<Bool> {
        Binding(
            get: { pendingCellularPlayback != nil },
            set: { if !$0 { pendingCellularPlayback = nil } }
        )
    }

    private func playStationAfterCellularCheck(
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

    private func requestStopPlaybackConfirmation() {
        guard audioPlayer.currentStation != nil else { return }
        isConfirmingStopPlayback = true
    }

    private func stopPlaybackAndCloseSignal() {
        audioPlayer.stopAndClearCurrentStation()
        closeFocusedAviDetail(fallbackTab: .home)
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
            autoSkipUnstableStreamIfNeeded()
        case .playing:
            if let station = audioPlayer.currentStation {
                recordConfirmedPlaybackIfNeeded(station)
            }

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

    private func recordConfirmedPlaybackIfNeeded(_ station: Station) {
        guard lastConfirmedPlaybackStationID != station.id else { return }
        libraryStore.recordPlayback(of: station, recentLimit: accessController.limits.recentStations)
        lastConfirmedPlaybackStationID = station.id
    }

    private func autoSkipUnstableStreamIfNeeded() {
        guard libraryStore.settings.autoSkipUnstableStreams else { return }
        guard audioPlayer.shouldSuggestFailureRecovery, audioPlayer.canCyclePlaybackQueue else { return }
        let skippedStation = audioPlayer.currentStation
        guard audioPlayer.playNextStableInQueue() else {
            audioPlayer.showAutoSkipBlockedNotice()
            return
        }
        if let skippedStation {
            audioPlayer.showAutoSkipNotice(for: skippedStation)
        }
        if let station = audioPlayer.currentStation {
            beginListeningSession(for: station, source: audioPlayer.playbackQueue.source)
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
        captureAviReturnContext(
            radioMode: returnRadioMode,
            radioOverview: returnRadioOverview
        )
        isAviNowPlayingFullPlayer = false
        selectedMusicAviDetail = nil
        let resolvedStation = selectAviStationDetail(
            station,
            queueSource: queueSource,
            queue: { resolvedStation in queue ?? [resolvedStation] }
        )
        libraryStore.rememberOpenedStation(resolvedStation, presentation: LastOpenedStationPresentation.detail.rawValue)
        selectedTab = .avi
    }

    private func openNowPlayingFullPlayer(_ station: Station) {
        captureAviReturnContext()
        selectedMusicAviDetail = nil
        let resolvedStation = selectAviStationDetail(
            station,
            queueSource: .singleStation,
            queue: { [$0] }
        )
        libraryStore.rememberOpenedStation(resolvedStation, presentation: LastOpenedStationPresentation.player.rawValue)
        isAviNowPlayingFullPlayer = true
        selectedTab = .avi
    }

    private func openContextualAvi() {
        captureAviReturnContext()
        selectedStationDetail = nil
        selectedMusicAviDetail = nil
        isAviNowPlayingFullPlayer = false

        if let currentStation = audioPlayer.currentStation {
            let resolvedStation = selectAviStationDetail(
                currentStation,
                queueSource: audioPlayer.playbackQueue.source,
                queue: currentPlaybackQueue(fallbackStation:)
            )
            libraryStore.rememberOpenedStation(resolvedStation, presentation: LastOpenedStationPresentation.player.rawValue)
            isAviNowPlayingFullPlayer = true
        }

        selectedTab = .avi
    }

    private func openDiscoveryInfo(_ discovery: DiscoveredTrack, returnMusicMode: MusicContentMode? = nil) {
        captureAviReturnContext(
            musicMode: returnMusicMode,
            musicOverview: returnMusicMode == nil
        )
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
        captureAviReturnContext(
            musicMode: returnMusicMode,
            musicOverview: returnMusicMode == nil
        )
        selectedStationDetail = nil
        isAviNowPlayingFullPlayer = false
        selectedMusicAviDetail = .artist(summary)
        selectedTab = .avi
    }

    private func closeFocusedAviDetail(fallbackTab: AppShellTab? = nil) {
        selectedStationDetail = nil
        selectedMusicAviDetail = nil
        isAviNowPlayingFullPlayer = false
        libraryStore.clearOpenedStationPresentation()

        if let request = aviReturnCoordinator.consumeRestoreRequest() {
            restoreAviReturnRequest(request)
            selectedTab = request.tab
        } else if let fallbackTab {
            selectedTab = fallbackTab
        }
    }

    private func captureAviReturnContext(
        radioMode: RadioLibraryMode? = nil,
        radioOverview: Bool? = nil,
        musicMode: MusicContentMode? = nil,
        musicOverview: Bool? = nil
    ) {
        aviReturnCoordinator.capture(
            selectedTab: selectedTab,
            radioMode: radioMode,
            radioOverview: radioOverview,
            musicMode: musicMode,
            musicOverview: musicOverview
        )
    }

    private func restoreAviReturnRequest(_ restoreRequest: AviReturnRestoreRequest) {
        if let request = restoreRequest.radioReturnRequest {
            requestedRadioMode = request.mode
            requestedRadioOverview = request.overview
        } else if let request = restoreRequest.musicReturnRequest {
            requestedMusicMode = request.mode
            requestedMusicOverview = request.overview
        }
    }

    private func aviStationDetail(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: [Station]
    ) -> SelectedStationDetail {
        aviStationDetailBuilder.detail(
            station: station,
            queueSource: queueSource,
            queue: queue
        )
    }

    private func currentPlaybackQueue(fallbackStation: Station) -> [Station] {
        aviStationDetailBuilder.playbackQueue(
            stations: audioPlayer.playbackQueue.stations,
            fallbackStation: fallbackStation
        )
    }

    @discardableResult
    private func selectAviStationDetail(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station]
    ) -> Station {
        let resolvedStation = enrichedStation(station)
        selectedStationDetail = aviStationDetail(
            station: resolvedStation,
            queueSource: queueSource,
            queue: queue(resolvedStation)
        )
        refreshSelectedStationEnrichmentIfNeeded(resolvedStation)
        return resolvedStation
    }

    private func syncAviActiveSignalIfNeeded(previousStationID: String?, currentStation: Station) {
        guard selectedTab == .avi else { return }
        if isAviNowPlayingFullPlayer {
            selectAviStationDetail(
                currentStation,
                queueSource: audioPlayer.playbackQueue.source,
                queue: currentPlaybackQueue(fallbackStation:)
            )
            return
        }

        guard let previousStationID else { return }
        guard selectedStationDetail?.station.id == previousStationID else { return }

        selectAviStationDetail(
            currentStation,
            queueSource: audioPlayer.playbackQueue.source,
            queue: currentPlaybackQueue(fallbackStation:)
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
        let cachedStation = station.enrichmentLookupKeys
            .compactMap { enrichedStationsByID[$0] }
            .max { $0.enrichmentRank < $1.enrichmentRank }

        guard let cachedStation else { return station }
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
            for key in station.enrichmentLookupKeys {
                let current = nextEnrichedStationsByID[key]
                guard current == nil || station.enrichmentRank >= current!.enrichmentRank else { continue }
                nextEnrichedStationsByID[key] = station
            }
        }
        if nextEnrichedStationsByID != enrichedStationsByID {
            enrichedStationsByID = nextEnrichedStationsByID
        }

        libraryStore.rememberStationSnapshots(stations)
    }

    private func refreshSelectedStationEnrichmentIfNeeded(_ station: Station) {
        guard !launchContext.isUITesting else { return }
        let resolvedStation = enrichedStation(station)
        guard resolvedStation.enrichmentRank < 12 else { return }

        Task {
            await refreshSelectedStationEnrichment(station)
        }
    }

    private func refreshSelectedStationEnrichment(_ station: Station) async {
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
            guard let enrichedMatch = results.bestBackendMatch(for: station) else { return }
            guard !Task.isCancelled else { return }
            rememberBackendStations([enrichedMatch])
        } catch {
            return
        }
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
        let hadCachedFeed = homeFeed.cachedResult(preferredTag: libraryStore.settings.preferredTag) != nil
        await refreshHomeFeed()
        if hadCachedFeed {
            await refreshHomeFeed(forceRemote: true)
        }
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
    var enrichmentLookupKeys: [String] {
        var keys: [String] = []

        appendEnrichmentIDKeys(id, to: &keys)
        if let canonicalStationId {
            appendEnrichmentIDKeys(canonicalStationId, to: &keys)
        }

        if let streamKey = normalizedEnrichmentURLKey(streamURL) {
            keys.append("stream:\(streamKey)")
        }

        if let homepageURL, let homepageKey = normalizedEnrichmentURLKey(homepageURL) {
            keys.append("homepage:\(homepageKey)")
        }

        return keys
    }

    private func appendEnrichmentIDKeys(_ rawID: String, to keys: inout [String]) {
        let trimmedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        keys.append("id:\(trimmedID)")

        if trimmedID.hasPrefix("st_rb_") {
            let radioBrowserID = String(trimmedID.dropFirst("st_rb_".count)).replacingOccurrences(of: "_", with: "-")
            if radioBrowserID != trimmedID {
                keys.append("id:\(radioBrowserID)")
            }
        } else if trimmedID.contains("-") {
            keys.append("id:st_rb_\(trimmedID.replacingOccurrences(of: "-", with: "_"))")
        }
    }

    private func normalizedEnrichmentURLKey(_ rawURL: String) -> String? {
        guard
            let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

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

private struct AviQueueSwitchOption: Identifiable {
    let source: AudioPlayerService.PlaybackQueue.Source
    let title: String
    let stations: [Station]

    var id: String {
        "\(source.displayTitle)-\(stations.map(\.id).joined(separator: "-"))"
    }
}

private struct RelatedStationContext: Identifiable {
    let baseStation: Station

    var id: String {
        baseStation.id
    }
}

private struct AviQueueSwitcherSheet: View {
    let currentSource: AudioPlayerService.PlaybackQueue.Source
    let options: [AviQueueSwitchOption]
    let selectOption: (AviQueueSwitchOption) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(options) { option in
                Button {
                    selectOption(option)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.source == currentSource ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(option.source == currentSource ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.55))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(TuneAVTheme.textPrimary)

                            Text(L10n.plural(singular: "shell.queue.stationCount.one", plural: "shell.queue.stationCount.other", count: option.stations.count, option.stations.count))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TuneAVTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(L10n.string("shell.queue.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("shell.avi.plans.close"), action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct AppShellScaffold<Content: View, FooterPlayer: View>: View {
    let selectedTab: AppShellTab
    let hasFooterPlayer: Bool
    let hasAviActiveContext: Bool
    let footerBackdropHeight: CGFloat
    let footerPlayerTabSpacing: CGFloat
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

            VStack(spacing: footerPlayerTabSpacing) {
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

                    AppShellFooterAviButton(
                        isSelected: selectedTab == .avi,
                        hasActiveContext: hasAviActiveContext
                    ) {
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
    let hasActiveContext: Bool
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

                if hasActiveContext && !isSelected {
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .frame(width: 20, height: 20)
                        .background(TuneAVTheme.cardSurface, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(TuneAVTheme.highlight.opacity(0.32), lineWidth: 1)
                        }
                        .shadow(color: TuneAVTheme.highlight.opacity(0.18), radius: 4, y: 2)
                        .offset(x: 20, y: -18)
                }
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
    let playbackQueueSource: AudioPlayerService.PlaybackQueue.Source
    let playbackQueueStations: [Station]
    let stations: [Station]
    let recentStations: [Station]
    let favoriteStations: [Station]
    let openPlayer: () -> Void
    let showArtworkZoom: () -> Void
    let stopPlayback: () -> Void
    let playStationFromQueue: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]) -> Void

    @State private var isShowingQueueSwitcher = false

    var body: some View {
        VStack(spacing: 10) {
            Button(action: showArtworkZoom) {
                artwork
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.accessibility.zoomArtwork"))
            .accessibilityIdentifier("avi.footerPlayer.artworkZoom")

            Button(action: showArtworkZoom) {
                metadataText
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.accessibility.zoomArtwork"))
            .accessibilityIdentifier("avi.footerPlayer.textZoom")

            controlsRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(height: 360)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("shell.miniPlayer.accessibility.label", station.name))
        .accessibilityHint(L10n.string("shell.miniPlayer.accessibility.hint"))
        .accessibilityIdentifier("avi.footerPlayer.container")
        .sheet(isPresented: $isShowingQueueSwitcher) {
            AviQueueSwitcherSheet(
                currentSource: playbackQueueSource,
                options: queueSwitchOptions,
                selectOption: selectQueueOption(_:),
                onDismiss: { isShowingQueueSwitcher = false }
            )
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            queueSourceButton

            queueButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.footerPlayer.previous") {
                audioPlayer.playPreviousInQueue()
            }

            playPauseButton

            queueButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.footerPlayer.next") {
                audioPlayer.playNextInQueue()
            }

            sleepTimerMenu
        }
        .frame(height: 72)
        .frame(maxWidth: .infinity)
    }

    private var playPauseButton: some View {
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
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avi.footerPlayer.playPause")
    }

    private var metadataText: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(station.name)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
                .frame(height: 50, alignment: .center)

            Text(artistLine)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(trackArtworkExists ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(titleLine)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .center)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            if let artworkURL = audioPlayer.currentTrackArtworkURL {
                TuneAVRemoteArtworkImage(url: artworkURL, size: 152, scale: displayScale) {
                    StationArtworkView(station: station, size: 152)
                }
                .frame(width: 152, height: 152)
                .clipShape(RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 152), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 152), style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.55), lineWidth: 1)
                }
            } else {
                StationArtworkView(
                    station: station,
                    size: 152,
                    animationOverlay: .none,
                    isAnimationActive: false
                )
            }

            if let feedback = currentTrackFeedback {
                Image(systemName: feedback.systemImage)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(feedback == .liked ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse)
                    .frame(width: 26, height: 26)
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
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(audioPlayer.canCyclePlaybackQueue ? TuneAVTheme.textSecondary : TuneAVTheme.textSecondary.opacity(0.28))
                .frame(width: 54, height: 54)
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

    private var queueSourceButton: some View {
        Button {
            isShowingQueueSwitcher = true
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 18, weight: .black))
            .foregroundStyle(TuneAVTheme.textSecondary)
            .frame(width: 54, height: 54)
            .background(.ultraThinMaterial.opacity(1), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.queue.current", playbackQueueSource.displayTitle))
        .accessibilityIdentifier("avi.footerPlayer.queue")
    }

    private var sleepTimerMenu: some View {
        Menu {
            ForEach(sleepTimerOptions, id: \.self) { minutes in
                Button {
                    audioPlayer.setSleepTimer(minutes: minutes)
                } label: {
                    Label(
                        sleepTimerOptionTitle(for: minutes),
                        systemImage: audioPlayer.activeSleepTimerMinutes == minutes ? "checkmark" : "timer"
                    )
                }
            }
        } label: {
            sleepTimerMenuLabel(remainingMinutes: audioPlayer.activeSleepTimerRemainingMinutes)
        }
        .accessibilityLabel(L10n.string("profile.preferences.sleepTimer.title"))
        .accessibilityValue(sleepTimerOptionTitle(for: audioPlayer.activeSleepTimerMinutes))
        .accessibilityIdentifier("avi.footerPlayer.sleepTimer")
    }

    private func sleepTimerMenuLabel(remainingMinutes: Int?) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial.opacity(1))
            VStack(spacing: 1) {
                Image(systemName: "timer")
                    .font(.system(size: remainingMinutes == nil ? 18 : 15, weight: .black))
            if let remainingMinutes {
                Text("\(remainingMinutes) min")
                    .font(.system(size: 8, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            }
        }
        .foregroundStyle(TuneAVTheme.textSecondary)
        .frame(width: 54, height: 54)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .contentShape(Circle())
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var sleepTimerOptions: [Int?] {
        [nil, 15, 30, 45, 60]
    }

    private func sleepTimerOptionTitle(for minutes: Int?) -> String {
        guard let minutes else {
            return L10n.string("profile.preferences.sleepTimer.off")
        }
        return L10n.string("profile.preferences.sleepTimer.minutes", minutes)
    }

    private var queueSwitchOptions: [AviQueueSwitchOption] {
        var options: [AviQueueSwitchOption] = []

        if !playbackQueueStations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: playbackQueueSource,
                    title: L10n.string("shell.queue.currentOption", playbackQueueSource.displayTitle),
                    stations: playbackQueueStations
                )
            )
        }

        if !stations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: .homeDiscovery,
                    title: L10n.string("shell.queue.popular"),
                    stations: stations
                )
            )
        }

        if !favoriteStations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: .libraryFavorites,
                    title: L10n.string("shell.queue.saved"),
                    stations: favoriteStations
                )
            )
        }

        if !recentStations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: .libraryRecents,
                    title: L10n.string("shell.queue.recent"),
                    stations: recentStations
                )
            )
        }

        var seen = Set<String>()
        return options.filter { option in
            let key = "\(option.source.shortTitle)|\(option.stations.map(\.id).joined(separator: ","))"
            return seen.insert(key).inserted
        }
    }

    private func selectQueueOption(_ option: AviQueueSwitchOption) {
        let queue = option.stations.contains(where: { $0.id == station.id })
            ? option.stations
            : [station] + option.stations
        playStationFromQueue(station, option.source, queue)
        isShowingQueueSwitcher = false
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
                .fill(.black.opacity(0.76))
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            GeometryReader { proxy in
                let artworkSize = min(proxy.size.width - 8, 372)
                let captionWidth = min(artworkSize, 360)

                VStack(spacing: 12) {
                    artwork(size: artworkSize)
                        .shadow(color: .black.opacity(0.46), radius: 32, y: 18)

                    VStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 27, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        Text(subtitle)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.74)
                    }
                    .frame(width: captionWidth - 28)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 15)
                    .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.52), radius: 22, y: 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)
            }
        }
        .accessibilityIdentifier("avi.footerPlayer.artworkZoomOverlay")
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let artworkURL {
            TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                StationArtworkView(station: station, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(artworkShape(size: size))
            .overlay {
                artworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            StationArtworkView(
                station: station,
                size: size,
                animationOverlay: .none,
                isAnimationActive: false
            )
        }
    }

    private func artworkShape(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous)
    }
}

struct DetailTopHeader: View {
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
                    .lineLimit(1)
                    .frame(height: 13)

                Text(title)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)
                    .frame(height: 30)

                Text(summary)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)
                    .frame(height: 34, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .frame(height: 96)
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
    var displayTitle: String {
        switch self {
        case .homeRecents:
            return L10n.string("shell.queue.homeRecents")
        case .homeFavorites:
            return L10n.string("shell.queue.homeFavorites")
        case .homeDiscovery:
            return L10n.string("shell.queue.popular")
        case .searchResults:
            return L10n.string("shell.queue.search")
        case .libraryRecents:
            return L10n.string("shell.queue.recent")
        case .libraryFavorites:
            return L10n.string("shell.queue.saved")
        case .singleStation:
            return L10n.string("shell.queue.single")
        }
    }

    var shortTitle: String {
        switch self {
        case .homeRecents:
            return L10n.string("shell.queue.short.home")
        case .homeFavorites, .libraryFavorites:
            return L10n.string("shell.queue.short.saved")
        case .homeDiscovery:
            return L10n.string("shell.queue.short.popular")
        case .searchResults:
            return L10n.string("shell.queue.short.search")
        case .libraryRecents:
            return L10n.string("shell.queue.short.recent")
        case .singleStation:
            return L10n.string("shell.queue.short.radio")
        }
    }

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

struct AviStableEmotionImage: View {
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

struct AviScreen: View {
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
    let activeSleepTimerMinutes: Int?
    let activeSleepTimerRemainingMinutes: Int?
    let canCyclePlaybackQueue: Bool
    let playbackQueueSource: AudioPlayerService.PlaybackQueue.Source
    let playbackQueueStations: [Station]
    let stations: [Station]
    let recentStations: [Station]
    let favoriteStations: [Station]
    let discoveries: [DiscoveredTrack]
    let focusedMusicDetail: SelectedMusicAviDetail?
    let isNowPlayingFullPlayer: Bool
    @Binding var isActionPanelOpen: Bool
    let stationFeedback: [String: TuneAVStationFeedback]
    let feedContext: HomeFeedContext
    let preferredTag: String
    let preferredCountryCode: String
    let bottomContentPadding: CGFloat
    let openSearch: () -> Void
    let openLibrary: () -> Void
    let openPlayer: () -> Void
    let stopPlayback: () -> Void
    let setSleepTimer: (Int?) -> Void
    let playPrevious: () -> Void
    let playNext: () -> Void
    let playStation: (Station, [Station]) -> Void
    let playStationFromQueue: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]) -> Void
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
    @State private var isShowingQueueSwitcher = false
    @State private var browserDestination: BrowserDestination?
    @State private var nestedMusicDetail: SelectedMusicAviDetail?
    @State private var aviReaction: AviScreenReaction?
    @State private var relatedStationContext: RelatedStationContext?
    @State private var relatedStationResults: [(station: Station, reason: String)] = []
    @State private var isLoadingRelatedStations = false
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
            if isNowPlayingFullPlayer {
                VStack(alignment: .leading, spacing: 16) {
                    aviContextHeader

                    if focusedDetailIsEmpty {
                        aviLandingContent
                    } else if let activeMusicDetail {
                        focusedMusicExperience(activeMusicDetail)
                    } else {
                            focusedSignalExperience
                    }
                }
                .padding(.horizontal, shellScreenHorizontalPadding)
                .padding(.top, shellScreenTopPadding + 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear
                                .frame(height: 0)
                                .id("avi.detail.top")

                            aviContextHeader

                            if focusedDetailIsEmpty {
                                aviLandingContent
                            } else if let activeMusicDetail {
                                focusedMusicExperience(activeMusicDetail)
                            } else {
                                focusedSignalExperience
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
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .sheet(isPresented: $isShowingQueueSwitcher) {
            AviQueueSwitcherSheet(
                currentSource: playbackQueueSource,
                options: queueSwitchOptions,
                selectOption: selectQueueOption(_:),
                onDismiss: { isShowingQueueSwitcher = false }
            )
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
        .onChange(of: isShowingAviActions) { _, isShowing in
            isActionPanelOpen = isShowing && isNowPlayingFullPlayer
        }
        .onChange(of: isNowPlayingFullPlayer) { _, isFullPlayer in
            isActionPanelOpen = isFullPlayer && isShowingAviActions
        }
        .onChange(of: focusedMusicDetail?.id) { _, _ in
            nestedMusicDetail = nil
            resetArtistDetailLimits()
        }
        .onChange(of: focusedStation?.id) { _, _ in
            visibleFocusedRadioHistoryLimit = Self.artistDetailPageSize
            openArtistDetailAviActionsID = nil
        }
        .onDisappear {
            isActionPanelOpen = false
        }
        .accessibilityIdentifier("avi.screen")
    }

    private var aviPreviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            aviPreviewHero
            aviPreviewCurrentContext
            aviPromptSuggestions
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

            HStack(spacing: 8) {
                AviSignalChip(title: L10n.string("shell.avi.preview.chip.listen"), systemImage: "waveform")
                AviSignalChip(title: L10n.string("shell.avi.preview.chip.save"), systemImage: "bookmark")
                AviSignalChip(title: L10n.string("shell.avi.preview.chip.search"), systemImage: "magnifyingglass")
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

    private var aviPromptSuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(currentStation == nil ? "shell.avi.preview.steps" : "shell.avi.preview.prompts"))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                if currentStation == nil {
                    AviSignalStep(index: 1, title: L10n.string("shell.avi.preview.step.choose"))
                    AviSignalStep(index: 2, title: L10n.string("shell.avi.preview.step.listen"))
                    AviSignalStep(index: 3, title: L10n.string("shell.avi.preview.step.remember"))
                } else if let currentStation {
                    HStack(spacing: 8) {
                        AviPromptButton(
                            title: L10n.string("shell.avi.preview.prompt.saveStation"),
                            systemImage: "bookmark",
                            action: {
                                toggleFavorite(currentStation)
                            }
                        )
                        AviPromptButton(
                            title: L10n.string("shell.avi.preview.prompt.history"),
                            systemImage: "clock.arrow.circlepath",
                            action: { showStationDetails(currentStation, [currentStation]) }
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.5), lineWidth: 1)
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
                title: primaryAviPreviewTitle,
                systemImage: primaryAviPreviewSystemImage,
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

                if currentStation != nil || currentTrackTitle != nil {
                    AviPreviewSecondaryButton(
                        title: L10n.string("shell.avi.preview.search"),
                        systemImage: "magnifyingglass",
                        accessibilityIdentifier: "avi.preview.search",
                        action: openSearch
                    )
                }
            }
        }
    }

    private var primaryAviPreviewTitle: String {
        if currentStation != nil || currentTrackTitle != nil {
            return L10n.string("shell.avi.preview.primary.nowPlaying")
        }
        return L10n.string("shell.avi.preview.primary.search")
    }

    private var primaryAviPreviewSystemImage: String {
        if currentStation != nil || currentTrackTitle != nil {
            return "waveform"
        }
        return "magnifyingglass"
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
        if currentStation != nil || currentTrackTitle != nil {
            openPlayer()
        } else {
            openSearch()
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
            aviFreeAccessSupport
        } else {
            aviCommandCenter
            if topRecommendation != nil {
                recommendationPanel
            } else {
                aviCurrentSignalCard
                quickActions
            }
            localSignals
            aviFreeAccessSupport
        }
    }

    @ViewBuilder
    private var aviFreeAccessSupport: some View {
        if !accessController.capabilities.canAccessPremiumFeatures {
            VStack(alignment: .leading, spacing: 12) {
                aviPreviewActions
                aviPreviewCapabilities
            }
            .accessibilityIdentifier("avi.freeAccess.support")
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
                    relatedStationsPanel
                    focusedRadioHistoryBlock(for: focusedStation)
                    focusedSignalInfo(for: focusedStation)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    fullPlayerAviSignalBlock(for: focusedStation)
                    relatedStationsPanel
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

        AviCommandButton(
            title: L10n.string("shell.avi.actions.findRelatedRadios"),
            systemImage: "sparkles",
            accessibilityIdentifier: "avi.command.primary.relatedRadios"
        ) {
            showRelatedStations(for: station)
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
                if let stationID = latestDiscovery(for: summary)?.stationID,
                   let station = artistStation(for: stationID) {
                    showRelatedStations(for: station)
                } else {
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
            AviFocusedTrackStats(
                artistName: discovery.artistDisplayText,
                stationName: discovery.stationName,
                feedbackLabel: libraryStore.feedback(for: discovery)?.localizedState ?? L10n.string("shell.avi.music.feedback.empty")
            )
            focusedMusicAviServices(for: .track(discovery))
            AviFocusedTrackArticle(
                artistName: discovery.artistDisplayText,
                stationName: discovery.stationName,
                lastSeenLabel: discovery.playedAt.formatted(date: .abbreviated, time: .shortened),
                feedbackLabel: libraryStore.feedback(for: discovery)?.localizedState ?? L10n.string("shell.avi.music.feedback.empty")
            )
            trackStationsBlock(discovery)
        }
    }

    private func focusedTrackSummaryCard(_ discovery: DiscoveredTrack) -> some View {
        AviFocusedTrackSummaryCard(
            discovery: discovery,
            feedback: libraryStore.feedback(for: discovery)
        )
    }

    private func focusedTrackQuickActions(_ discovery: DiscoveredTrack) -> some View {
        AviFocusedTrackQuickActions(
            discovery: discovery,
            selectedFeedback: libraryStore.feedback(for: discovery),
            toggleSaved: {
                toggleDiscoverySaved(discovery)
            },
            openArtist: {
                nestedMusicDetail = .artist(discoveryArtistSummary(for: discovery))
            },
            selectFeedback: { feedback in
                let nextFeedback = libraryStore.feedback(for: discovery) == feedback ? nil : feedback
                libraryStore.setFeedbackForDiscoveredTrack(nextFeedback, title: discovery.title, artist: discovery.artist)
            },
            clearFeedback: {
                libraryStore.setFeedbackForDiscoveredTrack(nil, title: discovery.title, artist: discovery.artist)
            }
        )
    }

    private func discoveryArtistSummary(for discovery: DiscoveredTrack) -> DiscoveryArtistSummary {
        DiscoveryArtistSummary(
            name: discovery.artistDisplayText,
            trackCount: 1,
            artistArtworkURL: discovery.resolvedArtworkURL,
            fallbackArtworkURL: discovery.resolvedStationArtworkURL
        )
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

        return AviFocusedArtistArticle {
            focusedArtistSummaryCard(summary, discoveries: discoveries)
        } stats: {
            AviFocusedArtistStats(
                savedSongsCount: savedSongs.count,
                stationCount: stationCount,
                latestSeenLabel: latestDiscovery(for: summary)?.playedAt.formatted(date: .numeric, time: .omitted) ?? L10n.string("shell.avi.music.feedback.empty")
            )
        } services: {
            focusedMusicAviServices(for: .artist(summary))
        } savedSongs: {
            artistSavedSongsBlock(summary, savedSongs: savedSongs)
        } stations: {
            artistStationsBlock(summary)
        }
    }

    private func focusedArtistSummaryCard(_ summary: DiscoveryArtistSummary, discoveries: [DiscoveredTrack]) -> some View {
        AviFocusedArtistSummaryCard(
            summary: summary,
            summaryLine: artistSummaryLine(summary),
            latestDiscoveryTitle: latestDiscovery(for: summary)?.title
        )
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
                aviActionsPanel(for: station, showsStationDetailAction: false)
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
        .frame(height: isNowPlayingFullPlayer ? 96 : nil, alignment: .center)
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
        guard isFocusedStationActive else {
            return L10n.string("shell.avi.mood.ready")
        }
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
            HStack {
                Text(L10n.string("shell.common.playingNow"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Spacer()

                aviSleepTimerMenu
            }

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

                queueSourceDockButton

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

                closeSignalDockButton

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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.dock")
    }

    private var aviSleepTimerMenu: some View {
        Menu {
            ForEach(sleepTimerOptions, id: \.self) { minutes in
                Button {
                    setSleepTimer(minutes)
                } label: {
                    Label(
                        sleepTimerOptionTitle(for: minutes),
                        systemImage: activeSleepTimerMinutes == minutes ? "checkmark" : "timer"
                    )
                }
            }
        } label: {
            sleepTimerMenuLabel(remainingMinutes: activeSleepTimerRemainingMinutes)
        }
        .accessibilityLabel(L10n.string("profile.preferences.sleepTimer.title"))
        .accessibilityValue(sleepTimerOptionTitle(for: activeSleepTimerMinutes))
        .accessibilityIdentifier("avi.controls.sleepTimer")
    }

    private func sleepTimerMenuLabel(remainingMinutes: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .black))

            if let remainingMinutes {
                Text("\(remainingMinutes) min")
                    .font(.system(size: 12, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .foregroundStyle(TuneAVTheme.textPrimary)
        .frame(width: 70, height: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
        .contentShape(Capsule())
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var sleepTimerOptions: [Int?] {
        [nil, 15, 30, 45, 60]
    }

    private func sleepTimerOptionTitle(for minutes: Int?) -> String {
        guard let minutes else {
            return L10n.string("profile.preferences.sleepTimer.off")
        }
        return L10n.string("profile.preferences.sleepTimer.minutes", minutes)
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

    private var queueSourceDockButton: some View {
        Button {
            isShowingQueueSwitcher = true
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 17, weight: .black))
            .foregroundStyle(TuneAVTheme.textSecondary)
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial.opacity(1), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.queue.current", playbackQueueSource.displayTitle))
        .accessibilityIdentifier("avi.controls.queue")
    }

    private var closeSignalDockButton: some View {
        Button(action: stopPlayback) {
            Image(systemName: "power")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial.opacity(1), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.accessibility.closeSignal"))
        .accessibilityIdentifier("avi.controls.closeSignal")
    }

    private var queueSwitchOptions: [AviQueueSwitchOption] {
        var options: [AviQueueSwitchOption] = []

        if !playbackQueueStations.isEmpty {
            options.append(
                AviQueueSwitchOption(
                    source: playbackQueueSource,
                    title: L10n.string("shell.queue.currentOption", playbackQueueSource.displayTitle),
                    stations: playbackQueueStations
                )
            )
        }

        if !stations.isEmpty {
            options.append(AviQueueSwitchOption(source: .homeDiscovery, title: L10n.string("shell.queue.popular"), stations: stations))
        }
        if !favoriteStations.isEmpty {
            options.append(AviQueueSwitchOption(source: .libraryFavorites, title: L10n.string("shell.queue.saved"), stations: favoriteStations))
        }
        if !recentStations.isEmpty {
            options.append(AviQueueSwitchOption(source: .libraryRecents, title: L10n.string("shell.queue.recent"), stations: recentStations))
        }

        var seen = Set<String>()
        return options.filter { option in
            let key = "\(option.source.shortTitle)|\(option.stations.map(\.id).joined(separator: ","))"
            return seen.insert(key).inserted
        }
    }

    private func selectQueueOption(_ option: AviQueueSwitchOption) {
        guard let currentStation = currentStation ?? focusedStation else { return }
        let queue = option.stations.contains(where: { $0.id == currentStation.id })
            ? option.stations
            : [currentStation] + option.stations
        playStationFromQueue(currentStation, option.source, queue)
        isShowingQueueSwitcher = false
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
                .fill(.black.opacity(0.76))
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        isShowingArtworkZoom = false
                    }
            }

            GeometryReader { proxy in
                let artworkSize = min(proxy.size.width - 8, 372)
                let captionWidth = min(artworkSize, 360)

                VStack(spacing: 12) {
                    currentArtwork(for: station, size: artworkSize)
                        .shadow(color: .black.opacity(0.46), radius: 32, y: 18)

                    VStack(spacing: 7) {
                        Text(currentTrackTitle ?? station.name)
                            .font(.system(size: 27, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        Text(currentTrackArtist ?? station.name)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.74)
                    }
                    .frame(width: captionWidth - 28)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 15)
                    .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.52), radius: 22, y: 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)
            }
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
                listeningControlButton(systemImage: "power", accessibilityIdentifier: "avi.controls.closeSignal", action: stopPlayback)
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
                feedbackIdentity: focusedPrimaryFeedbackIdentity(for: station),
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
                feedbackIdentity: focusedPrimaryFeedbackIdentity(for: station),
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

    private func fullPlayerAviSignalBlock(for station: Station) -> some View {
        ZStack(alignment: .topLeading) {
            if isShowingAviActions {
                aviActionsPanel(for: station)
                    .transition(.opacity)
            } else {
                fullPlayerAviSignalSummary(for: station)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isShowingAviActions ? 438 : 172, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(isShowingAviActions ? 0.22 : 0.38), lineWidth: isShowingAviActions ? 1 : 1.5)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.2), radius: 12, y: 6)
    }

    private func fullPlayerAviSignalSummary(for station: Station) -> some View {
        let selectedFeedback = focusedPrimaryFeedback(for: station)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(hasCurrentSongContext ? L10n.string("shell.avi.actions.songFeedback") : L10n.string("shell.avi.actions.radioFeedback"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    openFullPlayerAviActions()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .black))
                        Text(L10n.string("player.avi.moreWithAvi"))
                            .font(.system(size: 12, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .black))
                    }
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(TuneAVTheme.highlight, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(TuneAVTheme.brandBlack.opacity(0.08), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avi.actions.toggle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)

            Text(isNowPlayingFullPlayer && hasCurrentSongContext ? L10n.string("player.avi.feedback.songQuestion") : L10n.string("player.avi.feedback.radioQuestion"))
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22)

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
            .frame(height: 38)

            fullPlayerFeedbackFollowUp(
                feedback: selectedFeedback,
                station: station
            )
            .frame(height: 38)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func openFullPlayerAviActions() {
        withAnimation(.snappy(duration: 0.22)) {
            isShowingAviActions = true
            aviActionsPage = 0
            isShowingMoreAviActions = false
            isShowingFeedbackPicker = false
            isEditingRadioFeedback = false
        }
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

    private func focusedPrimaryFeedbackIdentity(for station: Station) -> String {
        if isNowPlayingFullPlayer && hasCurrentSongContext {
            return "track:\(currentSongIdentity)"
        }
        return "station:\(station.id)"
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

                Text(stationInfoBadgeTitle(for: station))
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule(style: .continuous))
            }

            stationInfoContent(for: station)
        }
        .padding(16)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private func stationInfoContent(for station: Station) -> some View {
        if let editorial = station.editorial, let summary = stationInfoSummary(for: editorial) {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                let badges = stationInfoBadges(for: editorial)
                if !badges.isEmpty {
                    WrapTagsRow(tags: badges, highlighted: true)
                }

                if let profile = editorial.discoveryProfile {
                    StationInfoDiscoverySnapshot(profile: profile)
                }

                let contextTags = stationInfoContextTags(for: editorial)
                if !contextTags.isEmpty {
                    WrapTagsRow(tags: contextTags)
                }
            }
        } else {
            Text(L10n.string("shell.stationInfo.notProcessed"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                feedbackIdentity: "station:\(station.id)",
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
                    feedbackIdentity: "station:\(focusedStation.id)",
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

    private func stationInfoBadgeTitle(for station: Station) -> String {
        station.editorial.flatMap(stationInfoSummary(for:)) != nil
            ? L10n.string("shell.stationInfo.summary")
            : L10n.string("shell.stationInfo.pending")
    }

    private func stationInfoSummary(for editorial: StationEditorial) -> String? {
        let summary = editorial.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private func stationInfoBadges(for editorial: StationEditorial) -> [String] {
        var badges = [
            stationInfoLocalizedPrimaryFormat(editorial.primaryFormat),
            stationInfoLocalizedIntensity("music", value: editorial.musicIntensity),
            stationInfoLocalizedIntensity("speech", value: editorial.speechIntensity)
        ].compactMap { $0 }

        for format in editorial.secondaryFormats.prefix(2) {
            let label = L10n.genreLabel(for: format)
            guard !label.isEmpty, !badges.contains(where: { $0.localizedCaseInsensitiveCompare(label) == .orderedSame }) else {
                continue
            }
            badges.append(label)
        }

        return badges
    }

    private func stationInfoContextTags(for editorial: StationEditorial) -> [String] {
        let profileTags = editorial.discoveryProfile.map { $0.genres + $0.moods } ?? []
        return (profileTags + editorial.programming + editorial.languages)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, tag in
                guard result.count < 6 else { return }
                guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else { return }
                result.append(L10n.genreLabel(for: tag))
            }
    }

    private func stationInfoLocalizedPrimaryFormat(_ format: String) -> String? {
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

    private func stationInfoLocalizedIntensity(_ kind: String, value: String) -> String? {
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
        356
    }

    private func aviActionsPanel(for station: Station) -> some View {
        aviActionsPanel(for: station, showsStationDetailAction: true)
    }

    private func aviActionsPanel(for station: Station, showsStationDetailAction: Bool) -> some View {
        let hasSongStep = hasCurrentSongContext && isNowPlayingFullPlayer
        let pageCount = hasSongStep ? 2 : 1
        let lastPage = pageCount - 1

        return VStack(alignment: .leading, spacing: 9) {
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

            VStack(spacing: 5) {
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
                    if showsStationDetailAction {
                        AviCommandButton(title: L10n.string("shell.avi.recommendation.details"), systemImage: "dot.radiowaves.left.and.right", accessibilityIdentifier: "avi.actions.radioDetails") {
                            showStationDetails(station, [station])
                            closeAviActions()
                        }
                    }
                    AviCommandButton(title: L10n.string("shell.avi.actions.history"), systemImage: "clock.arrow.circlepath", accessibilityIdentifier: "avi.actions.history") {
                        runProAviActionOutsideFullPlayer {
                            showStationDetails(station, [station])
                            closeAviActions()
                        }
                    }
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
                    AviCommandButton(title: L10n.string("shell.avi.actions.findRelatedRadios"), systemImage: "sparkles", accessibilityIdentifier: "avi.actions.relatedRadios") {
                        showAviReaction(.curious)
                        showRelatedStations(for: station)
                        closeAviActions()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            if isNowPlayingFullPlayer && isFocusedStationActive {
                AviCloseSignalPanelButton {
                    closeAviActions()
                    stopPlayback()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: aviActionsPanelHeight, alignment: .top)
        .background(TuneAVTheme.elevatedSurface.opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var aviActionsPageTitle: String {
        if isNowPlayingFullPlayer && hasCurrentSongContext && aviActionsPage == 0 {
            return L10n.string("shell.avi.actions.aboutSong")
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
                    AviSignalActionChip(title: L10n.string("shell.avi.actions.findRelatedRadios"), systemImage: "sparkles") {
                        showRelatedStations(for: station)
                    }
                    if isFocusedStationActive {
                        AviSignalActionChip(title: L10n.string("shell.accessibility.closeSignal"), systemImage: "power") {
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
        guard focusedStation != nil || currentStation != nil else {
            return L10n.string("shell.avi.detail.ready")
        }
        if isFocusedStationActive, currentTrackTitle != nil {
            return L10n.string("shell.avi.primary.reacting")
        }
        return isFocusedStationActive ? L10n.string("shell.avi.primary.reading") : L10n.string("player.avi.detail.neutral")
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
        case "power": return L10n.string("shell.accessibility.closeSignal")
        case "backward.fill": return L10n.string("player.control.previous")
        case "forward.fill": return L10n.string("player.control.next")
        default: return systemImage
        }
    }

    @ViewBuilder
    private var relatedStationsPanel: some View {
        if let relatedStationContext {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("shell.avi.related.title"))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)

                        Text(L10n.string("shell.avi.related.subtitle", relatedStationContext.baseStation.name))
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isLoadingRelatedStations {
                        ProgressView()
                            .tint(TuneAVTheme.highlight)
                    }
                }

                if relatedStationResults.isEmpty && !isLoadingRelatedStations {
                    Text(L10n.string("shell.avi.related.empty"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        ForEach(relatedStationResults.prefix(5), id: \.station.id) { result in
                            AviRelatedStationRow(
                                station: result.station,
                                reason: result.reason,
                                playAction: {
                                    playStation(result.station, relatedStationResults.map(\.station))
                                },
                                detailsAction: {
                                    showStationDetails(result.station, relatedStationResults.map(\.station))
                                }
                            )
                        }
                    }
                }
            }
            .padding(18)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.related.card")
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
                    feedbackIdentity: "station:\(recommendation.station.id)",
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

    private func showRelatedStations(for station: Station) {
        relatedStationContext = RelatedStationContext(baseStation: station)
        let localResults = relatedStationViewModels(for: station, candidates: relatedCandidateStations)
        relatedStationResults = localResults
        isLoadingRelatedStations = true

        Task {
            let remoteStations = await remoteRelatedStations(for: station)
            let merged = relatedStationViewModels(
                for: station,
                candidates: relatedCandidateStations + remoteStations
            )
            await MainActor.run {
                guard relatedStationContext?.baseStation.id == station.id else { return }
                relatedStationResults = merged
                isLoadingRelatedStations = false
            }
        }
    }

    private var relatedCandidateStations: [Station] {
        uniqueStations(stations + playbackQueueStations + recentStations + favoriteStations)
    }

    private func relatedStationViewModels(
        for station: Station,
        candidates: [Station]
    ) -> [(station: Station, reason: String)] {
        recommendationScorer
            .relatedStations(to: station, candidates: uniqueStations(candidates))
            .prefix(8)
            .map { candidate in
                (
                    station: candidate.station,
                    reason: TuneAVLocalRecommendationScorer.localizedSummary(for: candidate.rank.primaryReason) ?? L10n.string("shell.avi.recommendation.reasonFallback")
                )
            }
    }

    private func remoteRelatedStations(for station: Station) async -> [Station] {
        guard let tag = primaryRelatedTag(for: station) else { return [] }
        do {
            return try await TuneAVStationService().searchStations(
                filters: TuneAVStationSearchFilters(
                    query: "",
                    countryCode: station.countryCode ?? "",
                    language: station.language,
                    tag: tag,
                    locale: Locale.current.identifier,
                    limit: 24,
                    allowsEmptySearch: true
                )
            )
        } catch {
            return []
        }
    }

    private func primaryRelatedTag(for station: Station) -> String? {
        station.tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func uniqueStations(_ stations: [Station]) -> [Station] {
        var seen = Set<String>()
        return stations.filter { station in
            seen.insert(station.id).inserted
        }
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
                feedbackIdentity: "station:\(station.id)",
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

private struct AviRelatedStationRow: View {
    let station: Station
    let reason: String
    let playAction: () -> Void
    let detailsAction: () -> Void

    var body: some View {
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

                Text(reason)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
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
        .padding(10)
        .background(TuneAVTheme.highlight.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("avi.related.row")
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

private struct AviPromptButton: View {
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
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)
            }
            .foregroundStyle(TuneAVTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AviSignalStep: View {
    let index: Int
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 24, height: 24)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
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

private struct AviSignalChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(TuneAVTheme.highlight)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
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

                    planSummaryStrip

                    VStack(spacing: 12) {
                        planCard(
                            title: L10n.string("shell.avi.plans.guest"),
                            subtitle: L10n.string("shell.avi.plans.guest.subtitle"),
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
                            subtitle: L10n.string("shell.avi.plans.free.subtitle"),
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
                            subtitle: L10n.string("shell.avi.plans.pro.subtitle"),
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
                            Text(accessMode == .guest ? L10n.string("shell.avi.preview.primary.search") : L10n.string("shell.avi.preview.primary.pro"))
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

    private var planSummaryStrip: some View {
        HStack(spacing: 10) {
            PlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.start"),
                detail: L10n.string("shell.avi.plans.summary.start.detail")
            )
            PlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.save"),
                detail: L10n.string("shell.avi.plans.summary.save.detail")
            )
            PlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.pro"),
                detail: L10n.string("shell.avi.plans.summary.pro.detail")
            )
        }
    }

    private func planCard(title: String, subtitle: String, isCurrent: Bool, isHighlighted: Bool = false, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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

private struct PlanSummaryPill: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(detail)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 66, alignment: .topLeading)
        .padding(10)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.55), lineWidth: 1)
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
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 28, height: 28)
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
            .frame(height: 36)
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

private struct AviCloseSignalPanelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(TuneAVTheme.textSecondary.opacity(0.1), in: Circle())

                Text(L10n.string("shell.accessibility.closeSignal"))
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38)
            .background(TuneAVTheme.cardSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.38), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.accessibility.closeSignal"))
        .accessibilityIdentifier("avi.actions.closeSignal")
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

private struct HomeHeaderContent: View {
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

private struct HomeHeroContent: View {
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

private struct HomeRecommendationSections: View {
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

struct SearchScreen: View {
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

struct LibraryScreen: View {
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
    let openSearchAction: () -> Void
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

            if derivedState.hasRadioOverviewContent {
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
                    detail: L10n.string("shell.library.overview.empty.detail"),
                    actionTitle: L10n.string("shell.music.overview.empty.action"),
                    actionSystemImage: "magnifyingglass",
                    action: openSearchAction
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
        Dictionary(recents.enumerated().map { index, station in (station.id, index) }, uniquingKeysWith: min)
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

enum RadioLibraryMode: String, CaseIterable, Identifiable {
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

struct MusicScreen: View {
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
    let openSearchAction: () -> Void
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
        MusicStickyDetailHeader(
            mode: musicMode,
            goBack: showOverview
        )
    }

    private func musicOverview(_ snapshot: MusicLibraryDerivedState) -> some View {
        MusicLibraryOverview(
            snapshot: snapshot,
            summary: summary,
            overviewLimit: Self.overviewLimit,
            showsAccountSummary: accessController.capabilities.canAccessPremiumFeatures,
            userSummaryRefreshState: libraryStore.userSummaryRefreshState,
            isSignedIn: accessController.isSignedIn,
            openAccountAction: openAccountAction,
            startSignInAction: startSignInAction,
            refreshSummary: { await libraryStore.refreshUserSummary(force: true) },
            openSearchAction: openSearchAction,
            openMode: openMusicMode(_:),
            stationArtworkURL: { discovery in stationArtworkURL(discovery) },
            trackFeedback: { discovery in trackFeedback(discovery) },
            openTrackInfo: { discovery in openDiscoveryInfo(discovery, nil) },
            toggleSaved: { discovery in toggleDiscoverySaved(discovery) },
            openTrackYouTube: { discovery in runProAviAction { openDiscoverySearch(discovery, suffix: nil, youtube: true) } },
            openLyrics: { discovery in runProAviAction { openDiscoverySearch(discovery, suffix: "lyrics", youtube: false) } },
            openTrackAppleMusic: { discovery in runProAviAction { openAppleMusicSearch(discovery) } },
            openTrackSpotify: { discovery in runProAviAction { openSpotifySearch(discovery) } },
            hideAction: hideDiscoveryWithUndo(_:),
            removeAction: { discovery in removeDiscovery(discovery) },
            openArtistInfo: { artist in openArtistInfo(artist, nil) },
            openArtistYouTube: { artist in runProAviAction { openArtistSearch(artist, youtube: true) } },
            openArtistAppleMusic: { artist in runProAviAction { openAppleMusicArtistSearch(artist) } },
            openArtistSpotify: { artist in runProAviAction { openSpotifyArtistSearch(artist) } }
        )
    }

    private func musicModeControls(_ snapshot: MusicLibraryDerivedState) -> some View {
        MusicLibrarySnapshotControls(
            snapshot: snapshot,
            selectedMode: musicMode,
            selectMode: selectMusicMode(_:),
            sort: musicSort,
            setSort: setMusicSort(_:),
            isSearchExpanded: isSearchExpanded,
            showOverview: showOverview,
            toggleSearch: toggleMusicSearch
        )
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
                    discoveryHeader(snapshot)
                    discoveryTrackList(snapshot)
                case .artists:
                    discoveryHeader(snapshot)
                    MusicDiscoveryArtistList(
                        snapshot: snapshot,
                        openAviActionsID: $openMusicAviActionsID,
                        currentMode: musicMode,
                        openArtist: { artist, mode in openArtistInfo(artist, mode) },
                        openArtistSongs: { artist in openArtistSongs(artist.name) },
                        openArtistRadios: { artist, mode in openArtistInfo(artist, mode) },
                        openYouTube: { artist in runProAviAction { openArtistSearch(artist.name, youtube: true) } },
                        openAppleMusic: { artist in runProAviAction { openAppleMusicArtistSearch(artist.name) } },
                        openSpotify: { artist in runProAviAction { openSpotifyArtistSearch(artist.name) } },
                        showMoreArtists: showMoreArtists
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("music.section.discoveries")
    }

    private func discoveryTrackList(_ snapshot: MusicLibraryDerivedState) -> some View {
        MusicDiscoveryTrackList(
            snapshot: snapshot,
            openAviActionsID: $openMusicAviActionsID,
            currentMode: musicMode,
            stationArtworkURL: { discovery in stationArtworkURL(discovery) },
            trackFeedback: { discovery in trackFeedback(discovery) },
            openTrackInfo: { discovery, mode in openDiscoveryInfo(discovery, mode) },
            openArtistInfo: { discovery, mode in openArtistInfo(discoveryArtistSummary(for: discovery), mode) },
            openStationInfo: { discovery in openDiscoveryStationInfo(discovery) },
            toggleSaved: { discovery in toggleDiscoverySaved(discovery) },
            openYouTube: { discovery in runProAviAction { openDiscoverySearch(discovery, suffix: nil, youtube: true) } },
            openLyrics: { discovery in runProAviAction { openDiscoverySearch(discovery, suffix: "lyrics", youtube: false) } },
            openAppleMusic: { discovery in runProAviAction { openAppleMusicSearch(discovery) } },
            openSpotify: { discovery in runProAviAction { openSpotifySearch(discovery) } },
            hideAction: hideDiscoveryWithUndo(_:),
            removeAction: { discovery in removeDiscovery(discovery) },
            showMoreDiscoveries: showMoreDiscoveries
        )
    }

    private func discoveryArtistSummary(for discovery: DiscoveredTrack) -> DiscoveryArtistSummary {
        DiscoveryArtistSummary(
            name: discovery.artistDisplayText,
            trackCount: 1,
            artistArtworkURL: discovery.resolvedArtworkURL,
            fallbackArtworkURL: discovery.resolvedStationArtworkURL
        )
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

    private func discoveryHeader(_ snapshot: MusicLibraryDerivedState) -> some View {
        MusicDiscoveryModeHeader(
            mode: musicMode,
            songsTitle: historyStationFilterTitle ?? currentMusicLibraryMode.songsTitle,
            showsAllHistoryButton: musicMode == .history && historyStationFilter != nil,
            showAllHistory: { historyStationFilter = nil },
            actions: { discoveryActions(snapshot) }
        )
    }

    private var historyStationFilterTitle: String? {
        guard musicMode == .history, let historyStationFilter else { return nil }
        return "\(MusicLibraryMode.history.title) · \(historyStationFilter.name)"
    }

    private func discoveryActions(_ snapshot: MusicLibraryDerivedState) -> MusicDiscoveryActions {
        MusicDiscoveryActions(
            isShareDisabled: snapshot.filteredDiscoveries.isEmpty,
            shareAction: {
                let shareText = discoveriesShareText(snapshot)
                guard useDailyFeatureIfAllowed(.discoveryShare, usageKey: shareText) else { return }
                discoveriesShareTextDraft = shareText
                isShowingDiscoveriesShare = true
            },
            clearAction: {
                isConfirmingClearDiscoveries = true
            }
        )
    }

    @ViewBuilder
    private var hiddenDiscoveryUndoBanner: some View {
        MusicHiddenDiscoveryUndoOverlay(
            hiddenDiscovery: hiddenDiscovery,
            bottomContentPadding: bottomContentPadding,
            horizontalPadding: shellScreenHorizontalPadding,
            restoreAction: { discovery in
                restoreDiscovery(discovery)
                withAnimation(.snappy(duration: 0.22)) {
                    hiddenDiscovery = nil
                }
            }
        )
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

#Preview {
    let persistence = PersistenceController(inMemory: true)

    AppShellView()
        .environmentObject(AccessController())
        .environmentObject(AudioPlayerService())
        .environmentObject(LibraryStore(container: persistence.container))
        .modelContainer(persistence.container)
}
