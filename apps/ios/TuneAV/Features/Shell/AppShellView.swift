import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

private func stationFeedbackHapticEvent(for feedback: TuneAVStationFeedback?) -> AVHapticEvent {
    switch feedback {
    case .liked:
        return .positiveFeedback
    case .notForMe:
        return .dismissiveFeedback
    case .disliked:
        return .negativeFeedback
    case nil:
        return .clear
    }
}

struct AppShellView: View {
    struct PendingPlayback: Identifiable {
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
    let synchronizeLibraryNow: () async -> Void

    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var languageController: AppLanguageController
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.avCommonAppExperience) private var appExperience

    @StateObject private var chromeActions = AppShellChromeActions()
    @StateObject private var searchPresentation: SearchPresentationStore
    @State private var selectedTab: AppShellTab
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
    private let searchLogger = Logger(subsystem: "com.avalsys.tuneav", category: "search")
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
        startSignInFlow: @escaping (Bool) -> Void = { _ in },
        synchronizeLibraryNow: @escaping () async -> Void = {}
    ) {
        self.launchContext = launchContext
        self.startSignInFlow = startSignInFlow
        self.synchronizeLibraryNow = synchronizeLibraryNow
        _selectedTab = State(initialValue: AppShellTab(launchContext.preferredTab, preferredSearchQuery: launchContext.preferredSearchQuery))
        _searchPresentation = StateObject(wrappedValue: SearchPresentationStore(query: launchContext.preferredSearchQuery ?? ""))
    }

    var body: some View {
        adaptiveShell
            .environmentObject(chromeActions)
            .onChange(of: chromeActions.request) { _, request in
                guard let request else { return }
                openChromeRequest(request.item)
            }
            .appShellGlobalPresentations(
                isShowingFooterArtworkZoom: $isShowingFooterArtworkZoom,
                currentStation: audioPlayer.currentStation,
                currentTrackArtworkURL: audioPlayer.currentTrackArtworkURL,
                currentTrackTitle: audioPlayer.currentTrackTitle,
                currentTrackArtist: audioPlayer.currentTrackArtist,
                upgradePrompt: Binding(
                    get: { accessController.upgradePrompt },
                    set: { accessController.upgradePrompt = $0 }
                ),
                isGuest: accessController.accessMode == .guest,
                accountIsAvailable: accessController.accountIsAvailable,
                accessController: accessController,
                showProPaywall: $isShowingProPaywall,
                pendingCellularPlayback: $pendingCellularPlayback,
                isConfirmingStopPlayback: $isConfirmingStopPlayback,
                startSignInFlow: {
                    startSignInFlow(true)
                },
                playPendingCellularPlayback: { pending in
                    playStationAfterCellularCheck(pending.station, queueSource: pending.queueSource, queue: pending.queue)
                },
                stopPlayback: {
                    stopPlaybackAndCloseSignal()
                }
            )
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
                if audioPlayer.status == .playing {
                    recordConfirmedPlaybackIfNeeded(station)
                }
            }
            .onChange(of: audioPlayer.status) { oldStatus, newStatus in
                handlePlaybackStatusChange(from: oldStatus, to: newStatus)
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .task(id: currentTrackDiscoveryKey) {
                recordCurrentTrackDiscovery()
            }
    }

    @ViewBuilder
    private var adaptiveShell: some View {
        TuneAdaptiveLayoutReader { layout in
            if layout.layoutClass.isTabletLike {
                tabletShell
            } else {
                compactShell
            }
        }
    }

    private var compactShell: some View {
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
                compactFooterPlayer
            }
        )
    }

    private var tabletShell: some View {
        NavigationStack {
            HStack(spacing: 0) {
                tabletSidebar

                Divider()

                tabletContentArea
            }
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .accessibilityIdentifier("tune.shell.tablet")
        }
    }

    private var tabletContentArea: some View {
        ZStack {
            currentScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            tabletContentFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabletContentFooter: some View {
        ZStack(alignment: .bottom) {
            if audioPlayer.currentStation != nil {
                LinearGradient(
                    stops: [
                        .init(color: TuneAVTheme.footerBackdrop.opacity(0), location: 0),
                        .init(color: TuneAVTheme.footerBackdrop.opacity(0.94), location: 0.48),
                        .init(color: TuneAVTheme.footerBackdrop, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: shellFooterBackdropHeight)
                .allowsHitTesting(false)
            }

            compactFooterPlayer
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .frame(maxWidth: tabletContentFooterPlayerMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("tune.shell.tablet.footerPlayer")
    }

    private var tabletContentFooterPlayerMaxWidth: CGFloat {
        isAviFullPlayerActive ? 940 : 760
    }

    private var tabletSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabletSidebarBrandHeader
                .padding(.bottom, 12)

            ForEach([AppShellTab.home, .library, .music, .search, .avi], id: \.self) { tab in
                tabletSidebarButton(tab: tab, isSelected: selectedTab == tab)
            }

            Spacer(minLength: 16)

            tabletChromeButton(
                title: L10n.string("profile.settingsScreen.title"),
                systemImage: "gearshape.fill",
                isSelected: selectedTab == .profile && profileMode == .settings,
                accessibilityIdentifier: "tune.sidebar.settings"
            ) {
                openChromeRequest(.settings)
            }

            tabletChromeButton(
                title: L10n.string("profile.accountScreen.title"),
                systemImage: "person.crop.circle.fill",
                isSelected: selectedTab == .profile && profileMode == .account,
                accessibilityIdentifier: "tune.sidebar.account"
            ) {
                openChromeRequest(.account)
            }
        }
        .padding(.horizontal, AVAppShellTabletSidebarMetric.horizontalPadding)
        .padding(.vertical, AVAppShellTabletSidebarMetric.verticalPadding)
        .frame(width: 264, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .accessibilityIdentifier("tune.shell.tablet.sidebar")
    }

    private var tabletSidebarBrandHeader: some View {
        AVAppShellTabletSidebarBrandHeader(
            logoAssetName: appExperience.visualAssets?.headerLogoName ?? "HeaderWordmark",
            accessibilityLabel: appExperience.identity.displayName,
            logoWidth: 138,
            logoHeight: 44,
            logoLeadingCorrection: -16
        )
    }

    private func tabletSidebarButton(tab: AppShellTab, isSelected: Bool) -> some View {
        AVAppShellTabletSidebarButton(
            title: tabletTitle(for: tab),
            systemImage: tabletSystemImage(for: tab),
            isSelected: isSelected
        ) {
            selectTabletTab(tab)
        }
        .accessibilityIdentifier("tune.sidebar.\(tabletAccessibilityID(for: tab))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tabletTitle(for: tab))
    }

    private func tabletChromeButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        AVAppShellTabletSidebarButton(
            title: title,
            systemImage: systemImage,
            isSelected: isSelected,
            fontSize: 15,
            action: action
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var compactFooterPlayer: some View {
        if let station = audioPlayer.currentStation {
            let displayStation = enrichedStation(station)
            if isAviFullPlayerActive && !isAviActionPanelOpen {
                AviExpandedFooterPlayerView(
                    station: displayStation,
                    playbackQueueSource: audioPlayer.playbackQueue.source,
                    playbackQueueStations: enrichedStations(audioPlayer.playbackQueue.stations),
                    stations: enrichedStations(homeStations),
                    recentStations: enrichedRecentStations,
                    favoriteStations: enrichedFavoriteStations
                ) {
                    openNowPlayingFullPlayer(displayStation)
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
                MiniPlayerView(station: displayStation) {
                    openNowPlayingFullPlayer(displayStation)
                }
            }
        }
    }

    private func selectTabletTab(_ tab: AppShellTab) {
        if tab == .avi {
            openContextualAvi()
        } else {
            selectedTab = tab
        }
    }

    private func tabletTitle(for tab: AppShellTab) -> String {
        switch tab {
        case .home:
            return L10n.string("tab.home")
        case .library:
            return L10n.string("tab.library")
        case .music:
            return L10n.string("tab.music")
        case .search:
            return L10n.string("tab.search")
        case .avi:
            return appExperience.identity.assistantName
        case .profile:
            return L10n.string("profile.settingsScreen.title")
        }
    }

    private func tabletSystemImage(for tab: AppShellTab) -> String {
        switch tab {
        case .home:
            return "house.fill"
        case .library:
            return "dot.radiowaves.left.and.right"
        case .music:
            return "music.note.list"
        case .search:
            return "magnifyingglass"
        case .avi:
            return "sparkles"
        case .profile:
            return "gearshape.fill"
        }
    }

    private func tabletAccessibilityID(for tab: AppShellTab) -> String {
        switch tab {
        case .home:
            return "home"
        case .library:
            return "library"
        case .music:
            return "music"
        case .search:
            return "search"
        case .avi:
            return "avi"
        case .profile:
            return "profile"
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
            setStationFeedback: setStationFeedbackWithHaptic(_:feedback:),
            showStationDetails: { station, queueSource, queue in
                showStationDetails(station, queueSource: queueSource, queue: queue)
            }
        )
    }

    private func openHomeSearchTag(_ tag: String) {
        searchPresentation.openTag(tag)
        selectedTab = .search
    }

    private var searchScreen: some View {
        makeSearchScreen(
            query: $searchPresentation.query,
            activeTag: $searchPresentation.activeTag,
            selectedCountryCode: $searchPresentation.selectedCountryCode,
            discoveryMode: $searchPresentation.discoveryMode,
            results: enrichedStations(visibleSearchResults),
            isLoading: searchPresentation.isLoading,
            isLoadingMore: searchPresentation.isLoadingMore,
            totalCount: searchPresentation.totalCount,
            hasMoreResults: searchPresentation.hasMoreResults,
            errorMessage: searchPresentation.errorMessage,
            tags: genreTags,
            bottomContentPadding: shouldHideFooterPlayer ? 176 : shellScrollBottomPadding,
            favoriteStationIDs: favoriteStationIDs,
            nowPlayingTracks: stationNowPlayingTracks,
            stationFeedback: libraryStore.stationFeedback,
            playStation: playStation,
            toggleFavorite: toggleFavorite(_:),
            showStationDetails: showSearchStationDetails(_:queueSource:queue:),
            loadMoreResults: { Task { await loadMoreSearchResults() } }
        )
    }

    private var visibleSearchResults: [Station] {
        searchPresentation.results.isEmpty
            ? searchFallbackStations(for: searchRequest)
            : searchPresentation.results
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
        guard let station = libraryStore.station(for: discovery.stationID) else {
            return discovery.resolvedStationArtworkURL
        }
        return enrichedStation(station).displayArtworkURL ?? discovery.resolvedStationArtworkURL
    }

    private func musicTrackFeedback(_ discovery: DiscoveredTrack) -> TuneAVStationFeedback? {
        libraryStore.feedback(for: discovery)
    }

    private var profileScreen: some View {
        makeProfileScreen(
            mode: profileMode,
            startSignInFlow: startSignInFlow,
            synchronizeLibraryNow: synchronizeLibraryNow,
            bottomContentPadding: shellScrollBottomPadding
        )
    }

    private var aviScreen: some View {
        let focusedStation = selectedStationDetail.map { enrichedStation($0.station) }
        let stations = enrichedStations(homeSnapshot.stations)
        let recentStations = enrichedRecentStations
        let favoriteStations = enrichedFavoriteStations

        return makeAviScreen(
            currentStation: audioPlayer.currentStation.map(enrichedStation),
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
            focusedStationDetailSection: selectedStationDetail?.initialSection ?? .about,
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
            playPrevious: playPreviousInQueueWithHaptic,
            playNext: playNextInQueueWithHaptic,
            playStation: playAviDiscoveryStation(_:queue:),
            playStationFromQueue: playStation(_:queueSource:queue:),
            toggleFavorite: toggleFavorite(_:),
            setStationFeedback: setStationFeedbackWithHaptic(_:feedback:),
            showStationDetails: showAviStationDetails(_:queue:initialSection:),
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
        AVHaptics.perform(.navigation)
        selectedTab = .search
    }

    private func openLibraryTab() {
        AVHaptics.perform(.navigation)
        selectedTab = .library
    }

    private func openAviPlayer() {
        let focusedStation = selectedStationDetail.map { enrichedStation($0.station) }
        let focusedQueueStations = selectedStationDetail.map { enrichedStations($0.queueStations) }
        let focusedQueueSource = selectedStationDetail?.queueSource ?? .singleStation

        if let focusedStation, audioPlayer.isCurrent(focusedStation) {
            togglePlaybackWithHaptic()
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

    private func showAviStationDetails(
        _ station: Station,
        queue: [Station],
        initialSection: StationDetailSection = .about
    ) {
        showStationDetails(
            station,
            queueSource: .homeDiscovery,
            queue: queue,
            initialSection: initialSection
        )
    }

    private func openAccountProfile() {
        AVHaptics.perform(.navigation)
        profileMode = .account
        selectedTab = .profile
    }

    private func openChromeRequest(_ item: ShellBrandHeaderActiveItem) {
        AVHaptics.perform(.navigation)
        switch item {
        case .settings:
            profileMode = .settings
        case .account:
            profileMode = .account
        }
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
        "\(searchPresentation.requestKey)|\(languageController.currentLanguage.id)"
    }

    private var homeFeedRequestKey: String {
        "\(libraryStore.settings.preferredTag)|\(languageController.currentLanguage.id)"
    }

    private var searchRequest: AppShellSearchRequest {
        searchPresentation.request
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
            searchResults: enrichedStations(searchPresentation.results),
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
        ShellListeningSessionCoordinator.rememberTrack(
            session: &listeningSession,
            title: title,
            artist: artist
        )
    }

    private func applyUITestTrackMetadataIfNeeded() {
        guard let metadata = ShellUITestBootstrapOverrides.trackMetadata(from: launchContext) else { return }
        audioPlayer.applyUITestTrackMetadata(
            title: metadata.title,
            artist: metadata.artist
        )
    }

    private func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        seedUITestDataIfNeeded()
        applyLaunchBootstrapActions()

        applyDemoStationBootstrapActions()

        if let feature = ShellUITestBootstrapOverrides.upgradePromptFeature(from: launchContext) {
            accessController.presentUpgradePrompt(for: feature)
        }
    }

    private func applyDemoStationBootstrapActions() {
        guard let demoStation = launchContext.demoStation else { return }

        let actions = ShellDemoStationBootstrapPlanner.actions(
            hasDemoStation: true,
            seedFavorite: launchContext.seedFavorite,
            currentStationID: audioPlayer.currentStation?.id,
            demoStationID: demoStation.id
        )

        for action in actions {
            applyDemoStationBootstrapAction(action, demoStation: demoStation)
        }
        applyUITestTrackMetadataIfNeeded()
    }

    private func applyDemoStationBootstrapAction(
        _ action: ShellDemoStationBootstrapAction,
        demoStation: Station
    ) {
        switch action {
        case let .seed(favorite):
            libraryStore.ensureSeededStation(demoStation, favorite: favorite)
        case .play:
            playStation(demoStation)
        }
    }

    private func applyLaunchBootstrapActions() {
        let lastPlayedStation = libraryStore.station(for: libraryStore.settings.lastPlayedStationID)
        let actions = ShellLaunchBootstrapPlanner.actions(
            preferredTab: launchContext.preferredTab,
            hasPreferredSearchQuery: launchContext.preferredSearchQuery != nil,
            shouldRestoreLastOpenedStation: libraryStore.settings.openLastStationOnLaunch,
            hasLastPlayedStation: lastPlayedStation != nil,
            hasDemoStation: launchContext.demoStation != nil
        )

        let routes = ShellLaunchBootstrapRouter.routes(
            for: actions,
            lastPlayedStation: lastPlayedStation,
            demoStation: launchContext.demoStation
        )

        for route in routes {
            applyLaunchBootstrapRoute(route)
        }
    }

    private func applyLaunchBootstrapRoute(_ route: ShellLaunchBootstrapRoute) {
        switch route {
        case let .selectTab(tab):
            selectedTab = tab
        case let .openPlayer(station):
            playStation(station)
            showStationDetails(station, queueSource: .singleStation, queue: [station])
        case .restoreLastOpenedStation:
            restoreLastOpenedStationOnLaunch()
        }
    }

    private func restoreLastOpenedStationOnLaunch() {
        ShellLaunchRestoreExecutor.restore(
            selection: restoredLaunchSelection(),
            selectStation: { station, queue in
                audioPlayer.select(station: station, queue: queue)
            },
            openPlayer: openNowPlayingFullPlayer(_:)
        )
    }

    private func restoredLaunchSelection() -> ShellRestoredLaunchSelection? {
        ShellPlaybackQueueBuilder.restoredLaunchSelection(
            lastPlayedStationID: libraryStore.settings.lastPlayedStationID,
            lastOpenedStationID: libraryStore.settings.lastOpenedStationID,
            stationForID: libraryStore.station(for:),
            enrichStation: enrichedStation(_:),
            favorites: enrichedFavoriteStations,
            recents: enrichedRecentStations,
            homeStations: enrichedStations(homeSnapshot.stations)
        )
    }

    private func seedUITestDataIfNeeded() {
        ShellUITestBootstrapSeeder.seedLibraryIfNeeded(
            launchContext: launchContext,
            libraryStore: libraryStore,
            recentLimit: accessController.limits.recentStations
        )
    }

    private func playStation(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .singleStation,
        queue: [Station]? = nil
    ) {
        switch cellularPlaybackGateDecision {
        case .playImmediately:
            playStationAfterCellularCheck(station, queueSource: queueSource, queue: queue)
        case .requestConfirmation:
            pendingCellularPlayback = PendingPlayback(station: station, queueSource: queueSource, queue: queue)
        }
    }

    private var cellularPlaybackGateDecision: ShellCellularPlaybackGateDecision {
        ShellCellularPlaybackGate.decision(
            warnBeforeCellularPlayback: libraryStore.settings.warnBeforeCellularPlayback,
            currentNetworkIsExpensive: audioPlayer.currentNetworkIsExpensive
        )
    }

    private func playStationAfterCellularCheck(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .singleStation,
        queue: [Station]? = nil
    ) {
        let selection = ShellPlaybackQueueBuilder.playbackSelection(
            station: station,
            queueSource: queueSource,
            queue: queue,
            enrichStation: enrichedStation(_:),
            enrichStations: enrichedStations(_:)
        )
        AVHaptics.perform(.primaryAction)
        audioPlayer.play(station: selection.station, queue: selection.queue)
        beginListeningSession(for: selection.station, source: selection.queue.source)
    }

    private func requestStopPlaybackConfirmation() {
        guard audioPlayer.currentStation != nil else { return }
        isConfirmingStopPlayback = true
    }

    private func stopPlaybackAndCloseSignal() {
        AVHaptics.perform(.stopAction)
        audioPlayer.stopAndClearCurrentStation()
        closeFocusedAviDetail(fallbackTab: .home)
    }

    private func togglePlaybackWithHaptic() {
        AVHaptics.perform(.primaryAction)
        audioPlayer.togglePlayback()
    }

    private func playPreviousInQueueWithHaptic() {
        AVHaptics.perform(.step)
        audioPlayer.playPreviousInQueue()
    }

    private func playNextInQueueWithHaptic() {
        AVHaptics.perform(.step)
        audioPlayer.playNextInQueue()
    }

    private func beginListeningSession(for station: Station, source: AudioPlayerService.PlaybackQueue.Source) {
        let endedSession = ShellListeningSessionCoordinator.begin(
            session: &listeningSession,
            station: station,
            source: source
        )
        if let endedSession {
            recordListeningSession(endedSession, endedReason: .stationChanged)
        }
    }

    private func handlePlaybackStatusChange(
        from oldStatus: AudioPlayerService.PlaybackStatus,
        to newStatus: AudioPlayerService.PlaybackStatus
    ) {
        switch newStatus {
        case .paused:
            flushListeningSession(endedReason: .paused)
        case .idle:
            flushListeningSession(endedReason: .appClosed)
        case .failed:
            flushListeningSession(endedReason: .streamError)
            autoSkipUnstableStreamIfNeeded()
        case .playing:
            if let station = audioPlayer.currentStation {
                recordConfirmedPlaybackIfNeeded(station)
            }

            if let station = audioPlayer.currentStation {
                ShellListeningSessionCoordinator.resumeIfNeeded(
                    session: &listeningSession,
                    station: station,
                    source: audioPlayer.playbackQueue.source
                )
            }
        case .loading:
            break
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if ShellListeningSessionLifecycle.shouldFlushPendingSessions(scenePhase: phase) {
            flushListeningSession(endedReason: .appBackgrounded)
            libraryStore.flushPendingListeningSessions()
            return
        }

        guard ShellListeningSessionLifecycle.shouldResumeActiveSession(
            scenePhase: phase,
            isPlaying: audioPlayer.status == .playing,
            hasCurrentStation: audioPlayer.currentStation != nil
        ),
            let station = audioPlayer.currentStation
        else {
            return
        }

        ShellListeningSessionCoordinator.resumeIfNeeded(
            session: &listeningSession,
            station: station,
            source: audioPlayer.playbackQueue.source
        )
    }

    private func recordConfirmedPlaybackIfNeeded(_ station: Station) {
        guard lastConfirmedPlaybackStationID != station.id else { return }
        libraryStore.recordPlayback(of: enrichedStation(station), recentLimit: accessController.limits.recentStations)
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

    private func flushListeningSession(endedReason: TuneAVListeningEndedReason) {
        guard let session = ShellListeningSessionCoordinator.flush(session: &listeningSession) else { return }
        recordListeningSession(session, endedReason: endedReason)
    }

    private func recordListeningSession(_ session: ActiveListeningSession, endedReason: TuneAVListeningEndedReason) {
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
            AVHaptics.perform(.undo)
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

        AVHaptics.perform(.affirm)
        libraryStore.toggleFavorite(for: resolvedStation)
    }

    private func setStationFeedbackWithHaptic(_ station: Station, feedback: TuneAVStationFeedback?) {
        guard libraryStore.stationFeedback[station.id] != feedback else { return }
        libraryStore.setFeedback(feedback, for: station)
        AVHaptics.perform(stationFeedbackHapticEvent(for: feedback))
    }

    private func toggleDiscoverySaved(_ discovery: DiscoveredTrack) {
        ShellDiscoverySaveCoordinator.toggleDiscoverySaved(
            discovery,
            savedDiscoveriesCount: libraryStore.savedDiscoveriesCount,
            limitState: { currentUsage in
                accessController.limitState(for: .savedTracks, currentUsage: currentUsage)
            },
            toggleSaved: { discovery, limit in
                let wasSaved = discovery.isMarkedInteresting
                let didToggle = libraryStore.toggleDiscoverySaved(discovery, savedLimit: limit)
                if didToggle {
                    AVHaptics.perform(wasSaved ? .undo : .affirm)
                }
                return didToggle
            },
            presentUpgrade: { currentUsage in
                accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: currentUsage)
            }
        )
    }

    private func showStationDetails(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .singleStation,
        queue: [Station]? = nil,
        returnRadioMode: RadioLibraryMode? = nil,
        returnRadioOverview: Bool? = nil,
        initialSection: StationDetailSection = .about
    ) {
        let plan = ShellStationDetailOpenPlanner.detailPlan(
            station: station,
            queueSource: queueSource,
            queue: queue,
            returnRadioMode: returnRadioMode,
            returnRadioOverview: returnRadioOverview,
            initialSection: initialSection,
            presentation: LastOpenedStationPresentation.detail.rawValue,
            builder: aviStationDetailBuilder
        )
        applyStationDetailOpenPlan(plan)
    }

    private func openNowPlayingFullPlayer(_ station: Station) {
        let plan = ShellStationDetailOpenPlanner.fullPlayerPlan(
            station: station,
            presentation: LastOpenedStationPresentation.player.rawValue,
            builder: aviStationDetailBuilder
        )
        applyStationDetailOpenPlan(plan)
    }

    private func applyStationDetailOpenPlan(_ plan: ShellStationDetailOpenPlan) {
        AVHaptics.perform(.openPanel)
        captureAviReturnContext(
            radioMode: plan.returnRadioMode,
            radioOverview: plan.returnRadioOverview
        )
        if plan.clearsMusicDetail {
            selectedMusicAviDetail = nil
        }
        applyAviStationOpenSelection(plan.selection)
    }

    private func openContextualAvi() {
        let plan = ShellStationDetailOpenPlanner.contextualAviPlan(
            currentStation: audioPlayer.currentStation,
            currentQueueSource: audioPlayer.playbackQueue.source,
            currentQueue: currentPlaybackQueue(fallbackStation:),
            presentation: LastOpenedStationPresentation.player.rawValue,
            builder: aviStationDetailBuilder
        )
        applyContextualAviOpenPlan(plan)
    }

    private func applyContextualAviOpenPlan(_ plan: ShellContextualAviOpenPlan) {
        AVHaptics.perform(.openPanel)
        if plan.capturesReturnContext {
            captureAviReturnContext()
        }
        if plan.clearsStationDetail {
            selectedStationDetail = nil
        }
        if plan.clearsMusicDetail {
            selectedMusicAviDetail = nil
        }
        isAviNowPlayingFullPlayer = plan.isFullPlayer

        if let selection = plan.selection {
            applyAviStationOpenSelection(selection)
        }

        selectedTab = plan.selectedTab
    }

    private func openDiscoveryInfo(_ discovery: DiscoveredTrack, returnMusicMode: MusicContentMode? = nil) {
        openMusicAviDetail(
            AviMusicDetailCoordinator.track(
                discovery,
                returnMusicMode: returnMusicMode
            )
        )
    }

    private func openMusicAviDetail(_ selection: AviMusicDetailSelection) {
        let plan = AviMusicDetailCoordinator.openPlan(for: selection)
        applyMusicAviDetailOpenPlan(plan)
    }

    private func applyMusicAviDetailOpenPlan(_ plan: AviMusicDetailOpenPlan) {
        AVHaptics.perform(.openPanel)
        captureAviReturnContext(
            musicMode: plan.returnMusicMode,
            musicOverview: plan.returnMusicOverview
        )
        if plan.clearsStationDetail {
            selectedStationDetail = nil
        }
        isAviNowPlayingFullPlayer = plan.isNowPlayingFullPlayer
        selectedMusicAviDetail = plan.detail
        selectedTab = plan.selectedTab
    }

    private func openDiscoveryStationInfo(_ discovery: DiscoveredTrack) {
        guard let station = libraryStore.station(for: discovery.stationID) else { return }

        showStationDetails(
            station,
            queueSource: .libraryRecents,
            queue: enrichedRecentStations,
            initialSection: .history
        )
    }

    private func openArtistInfo(_ summary: DiscoveryArtistSummary, returnMusicMode: MusicContentMode? = nil) {
        openMusicAviDetail(
            AviMusicDetailCoordinator.artist(
                summary,
                returnMusicMode: returnMusicMode
            )
        )
    }

    private func closeFocusedAviDetail(fallbackTab: AppShellTab? = nil) {
        let plan = aviReturnCoordinator.closeFocusedDetailPlan(fallbackTab: fallbackTab)
        applyAviCloseFocusedDetailPlan(plan)
    }

    private func applyAviCloseFocusedDetailPlan(_ plan: AviCloseFocusedDetailPlan) {
        AVHaptics.perform(.closePanel)
        if plan.clearsStationDetail {
            selectedStationDetail = nil
        }
        if plan.clearsMusicDetail {
            selectedMusicAviDetail = nil
        }
        isAviNowPlayingFullPlayer = plan.isNowPlayingFullPlayer
        if plan.clearsOpenedStationPresentation {
            libraryStore.clearOpenedStationPresentation()
        }
        restoreAviReturnState(plan)
        if let selectedTab = plan.selectedTab {
            self.selectedTab = selectedTab
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

    private func restoreAviReturnState(_ plan: AviCloseFocusedDetailPlan) {
        if let request = plan.radioReturnRequest {
            applyRadioReturnRequest(request)
        } else if let request = plan.musicReturnRequest {
            applyMusicReturnRequest(request)
        }
    }

    private func applyRadioReturnRequest(_ request: (mode: RadioLibraryMode?, overview: Bool?)) {
        requestedRadioMode = request.mode
        requestedRadioOverview = request.overview
    }

    private func applyMusicReturnRequest(_ request: (mode: MusicContentMode?, overview: Bool?)) {
        requestedMusicMode = request.mode
        requestedMusicOverview = request.overview
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
        let selection = aviStationDetailBuilder.selection(
            station: station,
            queueSource: queueSource,
            queue: queue
        )
        let resolvedStation = selection.resolvedStation
        applySelectedStationDetail(selection.detail, resolvedStation: resolvedStation)
        return resolvedStation
    }

    private func applyAviStationOpenSelection(_ selection: AviStationOpenSelection) {
        applySelectedStationDetail(selection.detail, resolvedStation: selection.resolvedStation)
        libraryStore.rememberOpenedStation(selection.resolvedStation, presentation: selection.presentation)
        isAviNowPlayingFullPlayer = selection.isFullPlayer
        selectedTab = selection.selectedTab
    }

    private func applySelectedStationDetail(_ detail: SelectedStationDetail, resolvedStation: Station) {
        selectedStationDetail = detail
        refreshSelectedStationEnrichmentIfNeeded(resolvedStation)
    }

    private func syncAviActiveSignalIfNeeded(previousStationID: String?, currentStation: Station) {
        guard aviStationDetailBuilder.shouldSyncActiveSignal(
            selectedTab: selectedTab,
            isFullPlayer: isAviNowPlayingFullPlayer,
            previousStationID: previousStationID,
            selectedDetailStationID: selectedStationDetail?.station.id
        ) else { return }

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
        if let isStationNewer = station.metadataFreshnessCompared(to: cachedStation) {
            return isStationNewer ? station : cachedStation
        }
        if station.displayArtworkURL != nil, cachedStation.displayArtworkURL == nil {
            return station
        }
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
                guard station.isPreferredEnrichment(over: current) else { continue }
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
            searchPresentation.finishCancelled()
            return
        }

        seedSearchResultsIfNeeded(for: request)
        searchPresentation.beginLoading()
        searchLogger.debug(
            "Search load started has_query=\(!request.query.isEmpty, privacy: .public) has_tag=\(request.tag != nil, privacy: .public) has_country=\(request.countryCode != nil, privacy: .public) mode=\(request.discoveryMode.rawValue, privacy: .public)"
        )

        if launchContext.isUITesting && launchContext.shouldUseLocalUITestSearch {
            let results = AppShellSearch.localUITestSearchResults(request: request)
            searchPresentation.finishLoading(results: results)
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()

            let page = try await appSearch.load(
                request: request,
                recentStations: recentStations,
                favoriteStations: favoriteStations
            )
            guard requestKey == searchRequestKey else { return }

            let results = page.stations
            rememberBackendStations(results)
            searchPresentation.finishLoading(page: page)
            searchLogger.info(
                "Search load completed result_count=\(results.count, privacy: .public) mode=\(request.discoveryMode.rawValue, privacy: .public)"
            )
        } catch is CancellationError {
            guard requestKey == searchRequestKey else { return }
            searchPresentation.finishCancelled()
            searchLogger.debug("Search load cancelled")
        } catch {
            guard requestKey == searchRequestKey else { return }
            let fallback = searchFallbackStations(for: request)
            searchPresentation.finishWithFallback(fallback, emptyErrorMessage: L10n.string("shell.error.search"))
            searchLogger.error(
                "Search load failed fallback_count=\(fallback.count, privacy: .public) error=\(Self.safeErrorCode(error), privacy: .public)"
            )
        }
    }

    private func loadMoreSearchResults() async {
        let request = searchRequest
        let requestKey = searchRequestKey
        guard !request.usesWorldwideDiscovery, let cursor = searchPresentation.beginLoadingMore() else { return }

        do {
            let page = try await appSearch.loadSearchPage(request: request, cursor: cursor)
            guard requestKey == searchRequestKey else { return }
            rememberBackendStations(page.stations)
            searchPresentation.finishLoadingMore(page: page)
            searchLogger.info(
                "Search next page completed result_count=\(page.stations.count, privacy: .public) mode=\(request.discoveryMode.rawValue, privacy: .public)"
            )
        } catch {
            guard requestKey == searchRequestKey else { return }
            searchPresentation.finishCancelled()
            searchLogger.error("Search next page failed error=\(Self.safeErrorCode(error), privacy: .public)")
        }
    }

    private func seedSearchResultsIfNeeded(for request: AppShellSearchRequest) {
        let fallback = searchFallbackStations(for: request)
        searchPresentation.seedResultsIfEmpty(fallback)
    }

    private func searchFallbackStations(for request: AppShellSearchRequest) -> [Station] {
        if launchContext.isUITesting && launchContext.shouldUseLocalUITestSearch {
            return AppShellSearch.localUITestSearchResults(request: request)
        }
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

    private static func safeErrorCode(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
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
        components.scheme = "stream"
        return components.string?
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

    func isPreferredEnrichment(over current: Station?) -> Bool {
        guard let current else { return true }
        if let isNewer = metadataFreshnessCompared(to: current) {
            return isNewer
        }
        return enrichmentRank >= current.enrichmentRank
    }
}

private struct AviHeaderCopy {
    let label: String
    let title: String
    let summary: String
}

extension Array where Element == Station {
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
            guard
                let candidateStreamKey = candidate.normalizedStreamEnrichmentURLKey,
                let stationStreamKey = station.normalizedStreamEnrichmentURLKey
            else {
                return false
            }
            return candidateStreamKey == stationStreamKey
        }
    }

    func uniquedByStationID() -> [Station] {
        var seenIDs = Set<String>()
        return filter { station in
            seenIDs.insert(station.id).inserted
        }
    }
}

private extension Station {
    var normalizedStreamEnrichmentURLKey: String? {
        enrichmentLookupKeys.first { $0.hasPrefix("stream:") }
    }
}

private struct CachedStationNowPlaying {
    let track: NowPlayingTrack
    let fetchedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 300
    }
}

private let shellScrollCoordinateSpace = "shellScrollCoordinateSpace"

extension TuneAVPlaybackQueueSource {
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

private enum ArtistDetailSection: Equatable {
    case info
    case songs

    var accessibilityID: String {
        switch self {
        case .info:
            return "info"
        case .songs:
            return "songs"
        }
    }
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
    let focusedStationDetailSection: StationDetailSection
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
    let showStationDetails: (Station, [Station], StationDetailSection) -> Void
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
    @State private var selectedStationDetailSection: StationDetailSection = .about
    @State private var selectedArtistDetailSection: ArtistDetailSection = .info
    @State private var openArtistDetailAviActionsID: String?
    @State private var isShowingPlanComparison = false

    private var browserRouter: ShellBrowserRouter {
        ShellBrowserRouter(
            openDestination: { browserDestination = $0 },
            openSystemURL: { UIApplication.shared.open($0) },
            closeAviActions: closeAviActions,
            searchEngine: AVExternalSearchEngine.resolved(from: libraryStore.settings.externalSearchEngine),
            webOpenMode: AVExternalWebOpenMode.resolved(from: libraryStore.settings.externalWebOpenMode)
        )
    }

    var body: some View {
        TuneAdaptiveLayoutReader { layout in
            ZStack(alignment: .bottom) {
                if isNowPlayingFullPlayer {
                    ScrollView {
                        VStack(alignment: .leading, spacing: aviContentSpacing(for: layout)) {
                            if focusedDetailIsEmpty || activeMusicDetail != nil {
                                aviContextHeader
                            }

                            if focusedDetailIsEmpty {
                                aviLandingContent
                            } else if let activeMusicDetail {
                                focusedMusicExperience(activeMusicDetail)
                            } else {
                                focusedSignalExperience
                            }
                        }
                        .shellScreenContentPadding(layout: layout, bottom: aviScrollBottomPadding)
                    }
                    .shellScreenScrollBehavior()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: aviContentSpacing(for: layout)) {
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
                            .shellScreenContentPadding(layout: layout, bottom: aviScrollBottomPadding)
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
                if isFullPlayer {
                    resetNestedMusicNavigation()
                }
            }
            .onChange(of: focusedMusicDetail?.id) { _, _ in
                resetNestedMusicNavigation()
            }
            .onChange(of: focusedStation?.id) { _, _ in
                resetNestedMusicNavigation()
                visibleFocusedRadioHistoryLimit = Self.artistDetailPageSize
                selectedStationDetailSection = focusedStationDetailSection
            }
            .onChange(of: focusedStationDetailSection) { _, section in
                selectedStationDetailSection = section
            }
            .onAppear {
                selectedStationDetailSection = focusedStationDetailSection
            }
            .onDisappear {
                isActionPanelOpen = false
            }
            .accessibilityIdentifier("avi.screen")
        }
    }

    private func aviContentSpacing(for layout: TuneLayoutContext) -> CGFloat {
        layout.isTabletLike ? 20 : 16
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

    private var aviPreviewLandingContent: AVAviLandingContent {
        AVAviLandingContent(
            eyebrow: L10n.string("shell.avi.preview.eyebrow"),
            title: L10n.string("shell.avi.preview.title"),
            detail: L10n.string("shell.avi.preview.detail"),
            chips: [
                AVAviLandingChip(title: L10n.string("shell.avi.preview.chip.listen"), systemImage: "waveform"),
                AVAviLandingChip(title: L10n.string("shell.avi.preview.chip.save"), systemImage: "bookmark"),
                AVAviLandingChip(title: L10n.string("shell.avi.preview.chip.search"), systemImage: "magnifyingglass")
            ],
            accessibilityIdentifier: "avi.preview.hero"
        )
    }

    private var aviPreviewHero: some View {
        AVAviLandingHeroCard(content: aviPreviewLandingContent) {
            aviHeroImage(width: 62)
        }
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
                    AVAviPreviewStep(index: 1, title: L10n.string("shell.avi.preview.step.choose"))
                    AVAviPreviewStep(index: 2, title: L10n.string("shell.avi.preview.step.listen"))
                    AVAviPreviewStep(index: 3, title: L10n.string("shell.avi.preview.step.remember"))
                } else if let currentStation {
                    HStack(spacing: 8) {
                        AVAviPromptButton(
                            title: L10n.string("shell.avi.preview.prompt.saveStation"),
                            systemImage: "bookmark",
                            action: {
                                toggleFavorite(currentStation)
                            }
                        )
                        AVAviPromptButton(
                            title: L10n.string("shell.avi.preview.prompt.history"),
                            systemImage: "clock.arrow.circlepath",
                            action: { showStationDetails(currentStation, [currentStation], .history) }
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

            AVAviPreviewCapabilityRow(systemImage: "text.quote", title: L10n.string("shell.avi.preview.music.title"), detail: L10n.string("shell.avi.preview.music.detail"))
            Divider().overlay(TuneAVTheme.borderSubtle.opacity(0.45))
            AVAviPreviewCapabilityRow(systemImage: "dot.radiowaves.left.and.right", title: L10n.string("shell.avi.preview.radio.title"), detail: L10n.string("shell.avi.preview.radio.detail"))
            Divider().overlay(TuneAVTheme.borderSubtle.opacity(0.45))
            AVAviPreviewCapabilityRow(systemImage: "sparkles", title: L10n.string("shell.avi.preview.recommendations.title"), detail: L10n.string("shell.avi.preview.recommendations.detail"))
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
            AVAviPreviewPrimaryButton(
                title: primaryAviPreviewTitle,
                systemImage: primaryAviPreviewSystemImage,
                accessibilityIdentifier: "avi.preview.primary",
                action: primaryAviPreviewAction
            )

            HStack(spacing: 10) {
                AVAviPreviewSecondaryButton(
                    title: L10n.string("shell.avi.preview.compare"),
                    systemImage: "rectangle.3.group",
                    accessibilityIdentifier: "avi.preview.compare"
                ) {
                    isShowingPlanComparison = true
                }

                if currentStation != nil || currentTrackTitle != nil {
                    AVAviPreviewSecondaryButton(
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
        guard !isNowPlayingFullPlayer else { return nil }
        return nestedMusicDetail ?? focusedMusicDetail
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

    private func resetNestedMusicNavigation() {
        nestedMusicDetail = nil
        resetArtistDetailLimits()
        selectedArtistDetailSection = .info
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
                    focusedRadioSectionPicker(for: focusedStation)

                    switch selectedStationDetailSection {
                    case .about:
                        focusedRadioAboutContent(for: focusedStation)
                    case .history:
                        focusedRadioHistoryBlock(for: focusedStation, showsTitle: false)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    fullPlayerAviFeedbackBlock(for: focusedStation)
                }
            }
        }
    }

    private func focusedRadioAboutContent(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            focusedRadioSummaryCard(for: station)
            focusedRadioStats(for: station)
            focusedRadioQuickActions(for: station)
            focusedAviServices(for: station)
            relatedStationsPanel
            focusedSignalInfo(for: station)
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
        AVAviCommandButton(
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

        AVAviCommandButton(
            title: L10n.string("shell.avi.actions.history"),
            systemImage: "clock.arrow.circlepath",
            accessibilityIdentifier: "avi.command.primary.history"
        ) {
            runProAviActionOutsideFullPlayer {
                showStationDetails(station, [station], .history)
            }
        }

        AVAviCommandButton(
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
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchLyrics"),
                systemImage: "text.quote",
                accessibilityIdentifier: "avi.command.primary.music.lyrics"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title) lyrics")
                }
            }
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchYouTube"),
                systemImage: "play.rectangle",
                accessibilityIdentifier: "avi.command.primary.music.youtube"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: "\(discovery.artistDisplayText) \(discovery.title)", destination: .youtube)
                }
            }
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchArtist"),
                systemImage: "person.crop.circle",
                accessibilityIdentifier: "avi.command.primary.music.artist"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: discovery.artistDisplayText)
                }
            }
        case .artist(let summary):
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchArtist"),
                systemImage: "person.crop.circle",
                accessibilityIdentifier: "avi.command.primary.artist.search"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: summary.name)
                }
            }
            AVAviCommandButton(
                title: L10n.string("shell.avi.actions.searchYouTube"),
                systemImage: "play.rectangle",
                accessibilityIdentifier: "avi.command.primary.artist.youtube"
            ) {
                runProAviActionOutsideFullPlayer {
                    openExternalSearch(query: summary.name, destination: .youtube)
                }
            }
            AVAviCommandButton(
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
        AVAviCommandButton(
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

        AVAviCommandButton(
            title: L10n.string("shell.avi.actions.history"),
            systemImage: "clock.arrow.circlepath",
            accessibilityIdentifier: "avi.command.primary.history"
        ) {
            runProAviActionOutsideFullPlayer {
                showStationDetails(station, [station], .history)
            }
        }
    }

    @ViewBuilder
    private var defaultAviPrimaryCommands: some View {
        if currentStation != nil {
            AVAviCommandButton(
                title: L10n.string("shell.avi.action.nowPlaying"),
                systemImage: "waveform",
                accessibilityIdentifier: "avi.command.primary.currentPlayer"
            ) {
                openPlayer()
            }
        }

        AVAviCommandButton(
            title: L10n.string("shell.avi.action.findStation"),
            systemImage: "sparkles",
            accessibilityIdentifier: "avi.command.primary.findStation"
        ) {
            openSearch()
        }

        AVAviCommandButton(
            title: L10n.string("shell.avi.action.saved"),
            systemImage: "bookmark.fill",
            accessibilityIdentifier: "avi.command.primary.saved"
        ) {
            openLibrary()
        }

        if let recommendation = topRecommendation {
            AVAviCommandButton(
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
                AVAviInfoRow(
                    title: L10n.string("shell.avi.signals.currentSong.title"),
                    detail: currentTrackArtist.map { L10n.string("shell.avi.signals.currentSong.detailWithArtist", $0) } ?? L10n.string("shell.avi.signals.currentSong.detail"),
                    systemImage: "music.note",
                    accessibilityIdentifier: "avi.signals.currentSong"
                )
            } else if let currentStation {
                AVAviInfoRow(
                    title: L10n.string("shell.avi.signals.currentRadio.title"),
                    detail: L10n.string("shell.avi.signals.currentRadio.detail", currentStation.name),
                    systemImage: "dot.radiowaves.left.and.right",
                    accessibilityIdentifier: "avi.signals.currentRadio"
                )
            }

            if let recommendation = topRecommendation {
                AVAviInfoRow(
                    title: L10n.string("shell.avi.signals.next.title"),
                    detail: "\(recommendation.station.name): \(recommendation.reason)",
                    systemImage: "sparkles",
                    accessibilityIdentifier: "avi.signals.nextRecommendation"
                )
            }

            AVAviInfoRow(
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
                libraryStore.setFeedbackForDiscoveredTrack(nextFeedback, title: discovery.title, artist: discovery.artist, stationID: discovery.stationID)
                AVHaptics.perform(stationFeedbackHapticEvent(for: nextFeedback))
            },
            clearFeedback: {
                guard libraryStore.feedback(for: discovery) != nil else { return }
                libraryStore.setFeedbackForDiscoveredTrack(nil, title: discovery.title, artist: discovery.artist, stationID: discovery.stationID)
                AVHaptics.perform(.clear)
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
            focusedArtistSectionPicker(for: summary)

            switch selectedArtistDetailSection {
            case .info:
                focusedArtistInfoContent(summary)
            case .songs:
                artistSongsBlock(summary)
            }
        }
    }

    private func focusedArtistInfoContent(_ summary: DiscoveryArtistSummary) -> some View {
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
            EmptyView()
        } stations: {
            artistStationsBlock(summary)
        }
    }

    private func focusedArtistSectionPicker(for summary: DiscoveryArtistSummary) -> some View {
        let artistDiscoveries = artistDiscoveries(for: summary)

        return HStack(spacing: 6) {
            focusedArtistSectionButton(
                .info,
                title: L10n.string("shell.stationDetail.section.about"),
                systemImage: "info.circle.fill",
                badge: nil
            )
            focusedArtistSectionButton(
                .songs,
                title: L10n.string("shell.music.mode.songs"),
                systemImage: "music.note.list",
                badge: artistDiscoveries.isEmpty ? nil : "\(artistDiscoveries.count)"
            )
        }
        .padding(4)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.82), lineWidth: 1)
        }
        .accessibilityIdentifier("avi.artistDetail.sections")
    }

    private func focusedArtistSectionButton(
        _ section: ArtistDetailSection,
        title: String,
        systemImage: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedArtistDetailSection == section

        return Button {
            AVHaptics.perform(.impactLight)
            selectedArtistDetailSection = section
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            (isSelected ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.cardSurface),
                            in: Capsule(style: .continuous)
                        )
                }
            }
            .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? TuneAVTheme.highlight.opacity(0.38) : TuneAVTheme.borderSubtle.opacity(0.78),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avi.artistDetail.section.\(section.accessibilityID)")
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
                TuneAviPopoverActionsPanel(close: closeAviActions) {
                    focusedMusicPrimaryCommands(for: detail)
                }
                .transition(.opacity)
            } else {
                detailAskAviCollapsedContent {
                    applyAviTransientState(currentAviTransientState.openingActions(resetPage: false))
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
                    applyAviTransientState(currentAviTransientState.openingActions())
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
    private func artistSongsBlock(_ summary: DiscoveryArtistSummary) -> some View {
        let artistDiscoveries = artistDiscoveries(for: summary)
        let visibleSongs = Array(artistDiscoveries.prefix(visibleArtistSongLimit))
        let remainingCount = max(0, artistDiscoveries.count - visibleSongs.count)

        if !artistDiscoveries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleSongs) { discovery in
                    artistDiscoveryTrackCard(discovery)
                }

                if remainingCount > 0 {
                    ShowMoreButton(
                        title: L10n.string("shell.music.mode.songs"),
                        remainingCount: remainingCount,
                        action: {
                            visibleArtistSongLimit += Self.artistDetailPageSize
                        }
                    )
                }
            }
            .padding(14)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Text(L10n.string("shell.library.discoveries.empty"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func artistDiscoveryTrackCard(_ discovery: DiscoveredTrack) -> some View {
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

    @ViewBuilder
    private func artistStationsBlock(_ summary: DiscoveryArtistSummary) -> some View {
        let stations = artistStationSummaries(for: summary)
        let visibleStations = Array(stations.prefix(visibleArtistStationLimit))
        let resolvedVisibleStations = visibleStations.compactMap { station -> (station: Station, count: Int, latestDiscovery: DiscoveredTrack?)? in
            guard let resolvedStation = artistStation(for: station.id) else { return nil }
            return (resolvedStation, station.count, station.latestDiscovery)
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
                        nowPlayingTrack: station.latestDiscovery.map {
                            NowPlayingTrack(title: $0.title, artist: $0.artistDisplayText)
                        },
                        stationFeedback: stationFeedback[station.station.id],
                        toggleFavorite: { toggleFavorite(station.station) },
                        playAction: { playStation(station.station, [station.station]) },
                        openWebsiteAction: {
                            if let url = station.station.resolvedHomepageURL {
                                browserRouter.openURL(url)
                            }
                        },
                        detailsAction: { showStationDetails(station.station, [station.station], .about) }
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
                                browserRouter.openURL(url)
                            }
                        },
                        detailsAction: { showStationDetails(station.station, [station.station], .about) }
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
            AVFramedArtwork(
                size: size,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size)
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                    TuneAVMusicArtworkFallback(systemImage: "music.note", size: size, iconSize: 22)
                }
            }
        } else {
            TuneAVMusicArtworkFallback(systemImage: "music.note", size: size, iconSize: 22)
        }
    }

    @ViewBuilder
    private func artistArtwork(_ summary: DiscoveryArtistSummary, size: CGFloat) -> some View {
        if let artworkURL = summary.displayArtworkURL {
            AVFramedArtwork(
                size: size,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size)
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                    TuneAVMusicArtworkFallback(systemImage: "person.fill", size: size, iconSize: 22)
                }
            }
        } else {
            TuneAVMusicArtworkFallback(systemImage: "person.fill", size: size, iconSize: 22)
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

    private func artistStationSummaries(for summary: DiscoveryArtistSummary) -> [(id: String, name: String, count: Int, latestDiscovery: DiscoveredTrack?)] {
        let grouped = Dictionary(grouping: artistDiscoveries(for: summary), by: \.stationID)
        return grouped
            .map { stationID, discoveries in
                let latestDiscovery = discoveries.sorted { $0.playedAt > $1.playedAt }.first
                return (
                    id: stationID,
                    name: latestDiscovery?.stationName ?? stationID,
                    count: discoveries.count,
                    latestDiscovery: latestDiscovery
                )
            }
            .sorted {
                if let lhsDate = $0.latestDiscovery?.playedAt,
                   let rhsDate = $1.latestDiscovery?.playedAt,
                   lhsDate != rhsDate {
                    return lhsDate > rhsDate
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
                    label: fullPlayerAviCopy.label,
                    title: fullPlayerAviCopy.title,
                    summary: fullPlayerAviCopy.summary
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

    private var fullPlayerAviCopy: AviHeaderCopy {
        guard let station = focusedStation ?? currentStation else {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.ready.label"),
                title: L10n.string("shell.avi.header.ready.title"),
                summary: L10n.string("shell.avi.header.ready.summary")
            )
        }

        if isLoading {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.tuning.label"),
                title: L10n.string("shell.avi.header.tuning.title"),
                summary: L10n.string("shell.avi.header.tuning.summary")
            )
        }

        let feedback = focusedPrimaryFeedback(for: station)
        let hasSong = isFocusedStationActive && hasCurrentSongContext
        let isTrackSaved = hasSong && isCurrentTrackSaved(for: station)

        if isTrackSaved {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.saved.label"),
                title: L10n.string("shell.avi.header.saved.title"),
                summary: L10n.string("shell.avi.header.saved.summary")
            )
        }

        if let feedback {
            switch feedback {
            case .liked:
                return AviHeaderCopy(
                    label: L10n.string("shell.avi.header.learning.label"),
                    title: hasSong ? L10n.string("shell.avi.header.likedSong.title") : L10n.string("shell.avi.header.likedStation.title"),
                    summary: hasSong ? L10n.string("shell.avi.header.likedSong.summary") : L10n.string("shell.avi.header.likedStation.summary")
                )
            case .notForMe:
                return AviHeaderCopy(
                    label: L10n.string("shell.avi.header.adjusting.label"),
                    title: L10n.string("shell.avi.header.notForMe.title"),
                    summary: L10n.string("shell.avi.header.notForMe.summary")
                )
            case .disliked:
                return AviHeaderCopy(
                    label: L10n.string("shell.avi.header.discarding.label"),
                    title: L10n.string("shell.avi.header.disliked.title"),
                    summary: hasSong ? L10n.string("shell.avi.header.dislikedSong.summary") : L10n.string("shell.avi.header.dislikedStation.summary")
                )
            }
        }

        if hasSong {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.listening.label"),
                title: L10n.string("shell.avi.header.track.title"),
                summary: currentTrackArtist.map { L10n.string("shell.avi.header.trackWithArtist.summary", $0) } ?? L10n.string("shell.avi.header.track.summary")
            )
        }

        if libraryStore.isFavorite(station) {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.known.label"),
                title: L10n.string("shell.avi.header.favorite.title"),
                summary: L10n.string("shell.avi.header.favorite.summary")
            )
        }

        if station.displayArtworkURL != nil || station.editorial != nil {
            return AviHeaderCopy(
                label: L10n.string("shell.avi.header.exploring.label"),
                title: L10n.string("shell.avi.header.context.title"),
                summary: station.category.map { L10n.string("shell.avi.header.contextWithCategory.summary", $0) } ?? L10n.string("shell.avi.header.context.summary")
            )
        }

        return AviHeaderCopy(
            label: isFocusedStationActive ? L10n.string("shell.avi.header.reading.label") : L10n.string("shell.avi.header.exploring.label"),
            title: isFocusedStationActive ? L10n.string("shell.avi.header.reading.title") : L10n.string("shell.avi.header.discover.title"),
            summary: isFocusedStationActive ? L10n.string("shell.avi.header.reading.summary") : L10n.string("shell.avi.header.discover.summary")
        )
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

        let metadata: String? = if let latestDiscovery = stationDiscoveries.first {
            "\(L10n.string("shell.avi.music.latestSong")) · \(latestDiscovery.title)"
        } else if libraryStore.isFavorite(station) {
            L10n.string("shell.library.favorites.title")
        } else {
            nil
        }

        return AVAviFocusedSummaryCard(
            title: station.name,
            subtitle: defaultPublicSignalInfo(for: station),
            metadata: metadata
        ) {
            StationArtworkView(station: station, size: 62)
        }
    }

    private func focusedRadioStats(for station: Station) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)
        let latestDate = stationDiscoveries.first?.playedAt.formatted(date: .numeric, time: .omitted)
            ?? L10n.string("shell.avi.music.feedback.empty")

        return HStack(spacing: 7) {
            AVAviStatPill(
                title: L10n.string("shell.library.discoveries.title"),
                value: "\(stationDiscoveries.count)",
                systemImage: "music.note"
            )

            AVAviStatPill(
                title: L10n.string("shell.library.favorites.title"),
                value: libraryStore.isFavorite(station) ? L10n.string("common.yes") : L10n.string("common.no"),
                systemImage: "dot.radiowaves.left.and.right"
            )

            AVAviStatPill(
                title: L10n.string("shell.avi.music.lastSeen"),
                value: latestDate,
                systemImage: "clock.fill"
            )
        }
    }

    private func focusedRadioSectionPicker(for station: Station) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)

        return HStack(spacing: 6) {
            focusedRadioSectionButton(
                .about,
                title: L10n.string("shell.stationDetail.section.about"),
                systemImage: "info.circle.fill",
                badge: nil
            )
            focusedRadioSectionButton(
                .history,
                title: L10n.string("shell.stationDetail.tab.history"),
                systemImage: "clock.arrow.circlepath",
                badge: stationDiscoveries.isEmpty ? nil : "\(stationDiscoveries.count)"
            )
        }
        .padding(4)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.82), lineWidth: 1)
        }
        .accessibilityIdentifier("avi.stationDetail.sections")
    }

    private func focusedRadioSectionButton(
        _ section: StationDetailSection,
        title: String,
        systemImage: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedStationDetailSection == section

        return Button {
            AVHaptics.perform(.impactLight)
            selectedStationDetailSection = section
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            (isSelected ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.cardSurface),
                            in: Capsule(style: .continuous)
                        )
                }
            }
            .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? TuneAVTheme.highlight.opacity(0.38) : TuneAVTheme.borderSubtle.opacity(0.78),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avi.stationDetail.section.\(section.accessibilityID)")
    }

    @ViewBuilder
    private func focusedRadioHistoryBlock(for station: Station, showsTitle: Bool = true) -> some View {
        let stationDiscoveries = focusedStationDiscoveries(for: station)
        let visibleDiscoveries = Array(stationDiscoveries.prefix(visibleFocusedRadioHistoryLimit))
        let remainingCount = max(0, stationDiscoveries.count - visibleDiscoveries.count)
        if !stationDiscoveries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if showsTitle {
                    Text(L10n.string("shell.stationDetail.tab.history"))
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                }

                ForEach(visibleDiscoveries) { discovery in
                    DiscoveryTrackCard(
                        discovery: discovery,
                        stationArtworkURL: nil,
                        feedback: libraryStore.feedback(for: discovery),
                        showsSaveButton: false,
                        openAviActionsID: $openArtistDetailAviActionsID,
                        openTrackInfo: { nestedMusicDetail = .track(discovery) },
                        openArtistInfo: { nestedMusicDetail = .artist(discoveryArtistSummary(for: discovery)) },
                        openStationInfo: { showStationDetails(station, [station], .about) },
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
        } else {
            Text(L10n.string("shell.library.discoveries.empty"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
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
        .buttonStyle(.plain)
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
        .background(Color.clear, in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
        .contentShape(Capsule())
        .buttonStyle(.plain)
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
        AVCircularMaterialIconButton(
            systemImage: systemImage,
            size: 48,
            fontSize: 17,
            isEnabled: canCyclePlaybackQueue,
            accessibilityLabel: accessibilityLabel(for: systemImage),
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }

    private var queueSourceDockButton: some View {
        AVCircularMaterialIconButton(
            systemImage: "list.bullet",
            size: 48,
            fontSize: 17,
            fontWeight: .black,
            accessibilityLabel: L10n.string("shell.queue.current", playbackQueueSource.displayTitle),
            accessibilityIdentifier: "avi.controls.queue"
        ) {
            isShowingQueueSwitcher = true
        }
    }

    private var closeSignalDockButton: some View {
        AVCircularMaterialIconButton(
            systemImage: "power",
            size: 48,
            fontSize: 17,
            fontWeight: .black,
            accessibilityLabel: L10n.string("shell.accessibility.closeSignal"),
            accessibilityIdentifier: "avi.controls.closeSignal",
            action: stopPlayback
        )
    }

    private var queueSwitchOptions: [AviQueueSwitchOption] {
        AviQueueSwitchCoordinator.options(
            currentSource: playbackQueueSource,
            playbackQueueStations: playbackQueueStations,
            stations: stations,
            favoriteStations: favoriteStations,
            recentStations: recentStations
        )
    }

    private func selectQueueOption(_ option: AviQueueSwitchOption) {
        guard let currentStation = currentStation ?? focusedStation else { return }
        let queue = AviQueueSwitchCoordinator.queue(for: currentStation, option: option)
        playStationFromQueue(currentStation, option.source, queue)
        isShowingQueueSwitcher = false
    }

    @ViewBuilder
    private func currentArtwork(for station: Station, size: CGFloat) -> some View {
        if let artworkURL = currentTrackArtworkURL ?? station.displayArtworkURL {
            AVFramedArtwork(
                size: size,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size)
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                    StationThumbnailView(station: station, size: size, textMode: .none, animationOverlay: .none, isAnimationActive: false)
                }
            }
        } else {
            StationThumbnailView(station: station, size: size, textMode: .none, animationOverlay: .none, isAnimationActive: false)
        }
    }

    private func artworkZoomOverlay(for station: Station) -> some View {
        AVArtworkZoomOverlay(
            title: currentTrackTitle ?? station.name,
            subtitle: currentTrackArtist ?? station.name,
            accessibilityIdentifier: "avi.nowPlaying.artworkZoomOverlay",
            dismiss: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isShowingArtworkZoom = false
                }
            }
        ) { artworkSize in
            currentArtwork(for: station, size: artworkSize)
        }
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
        VStack(alignment: .leading, spacing: 8) {
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
                    AVAviPrimaryActionButton(
                        title: stationSaveActionTitle(for: station),
                        systemImage: stationSaveActionSystemImage(for: station),
                        accessibilityIdentifier: "avi.fullPlayer.saveRadio"
                    ) {
                        showAviReaction(.liked)
                        toggleFavorite(station)
                    }
                }

                AVAviPrimaryActionButton(
                    title: L10n.string("shell.avi.actions.ask"),
                    systemImage: "sparkles",
                    accessibilityIdentifier: "avi.actions.toggle"
                ) {
                    withAnimation(.snappy(duration: 0.22)) {
                        applyAviTransientState(currentAviTransientState.openingActions())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func fullPlayerAviFeedbackBlock(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FullPlayerAviHeader(
                emotion: aviEmotion,
                reactionEmotion: aviReaction?.emotion,
                reactionStartedAt: aviReaction == nil ? nil : aviReactionStartedAt,
                label: fullPlayerAviCopy.label,
                title: fullPlayerAviCopy.title,
                summary: fullPlayerAviCopy.summary
            )

            Rectangle()
                .fill(TuneAVTheme.borderSubtle.opacity(0.64))
                .frame(height: 1)

            ZStack(alignment: .topLeading) {
                if isShowingAviActions {
                    aviActionsPanel(for: station)
                        .transition(.opacity)
                } else {
                    fullPlayerAviSignalSummary(for: station)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: isShowingAviActions ? 424 : 156, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isShowingAviActions ? 570 : 300, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            TuneAVTheme.glassStroke.opacity(0.95),
                            TuneAVTheme.highlight.opacity(isShowingAviActions ? 0.14 : 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.2), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("avi.fullPlayer.feedbackBlock")
    }

    private func fullPlayerAviSignalSummary(for station: Station) -> some View {
        let selectedFeedback = focusedPrimaryFeedback(for: station)
        return VStack(alignment: .leading, spacing: 6) {
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
            .frame(height: 42, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func openFullPlayerAviActions() {
        AVHaptics.perform(.openPanel)
        withAnimation(.snappy(duration: 0.22)) {
            applyAviTransientState(currentAviTransientState.openingActions())
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

                AVAviFeedbackClearButton(
                    accessibilityLabel: L10n.string("shell.stationFeedback.clear"),
                    accessibilityIdentifier: "stationFeedback.clear",
                    action: clearFeedback
                )
            }
            .frame(height: 38)
        } else {
            StationFeedbackOptionsRow(selectFeedback: selectFeedback)
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
            AVAviFeedbackInfoRow(
                title: L10n.string("player.avi.feedback.tuned"),
                subtitle: L10n.string("player.avi.feedback.tunedHint"),
                systemImage: "sparkles",
                isAction: false
            )
        } else {
            AVAviFeedbackInfoRow(
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
                    AVAviFeedbackInfoRow(
                        title: L10n.string("player.discovery.noSave"),
                        subtitle: L10n.string("player.discovery.noSaveHint"),
                        systemImage: "xmark",
                        isAction: false
                    )
                    .accessibilityIdentifier("avi.fullPlayer.discoveryNoSave")

                    fullPlayerDiscoveryCompactButton(
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
                .frame(height: 42)
            } else if isCurrentTrackSaved(for: station) {
                HStack(spacing: 8) {
                    AVAviFeedbackInfoRow(
                        title: L10n.string("player.discovery.savedShort"),
                        subtitle: L10n.string("player.discovery.savedHintShort"),
                        systemImage: "bookmark.fill",
                        isAction: false
                    )

                    fullPlayerDiscoveryCompactButton(
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
                .frame(height: 42)
            } else {
                HStack(spacing: 8) {
                    fullPlayerDiscoveryDecisionButton(
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

                    fullPlayerDiscoveryDecisionButton(
                        title: L10n.string("player.discovery.noSave"),
                        systemImage: "xmark",
                        isSelected: false,
                        accessibilityIdentifier: "avi.fullPlayer.noSaveSong"
                    ) {
                        aviDiscoveryDecision = .ignored
                        showAviReaction(.notForMe)
                    }
                }
                .frame(height: 42)

            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("avi.fullPlayer.discoveryDecision")
    }

    private func fullPlayerDiscoveryCompactButton(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            fullPlayerDiscoveryButtonLabel(title: title, systemImage: systemImage)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 126, height: 42)
                .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func fullPlayerDiscoveryDecisionButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            fullPlayerDiscoveryButtonLabel(title: title, systemImage: systemImage)
                .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    isSelected ? TuneAVTheme.highlight : TuneAVTheme.cardSurface,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.44) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func fullPlayerDiscoveryButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))

            Text(title)
                .font(.system(size: 11, weight: .black))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .padding(.horizontal, 8)
    }

    private func compactAviActionsSheet(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.string("shell.avi.actions.ask"))
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Spacer(minLength: 0)

                AVAviPanelCloseButton(
                    accessibilityLabel: L10n.string("shell.avi.actions.closeOptions"),
                    accessibilityIdentifier: "avi.actions.close",
                    action: closeAviActions
                )
            }

            HStack(spacing: 8) {
                AVAviPanelOptionButton(
                    title: L10n.string("shell.avi.actions.searchYouTube"),
                    systemImage: "play.rectangle",
                    style: .compact,
                    accessibilityIdentifier: "avi.actions.youtube"
                ) {
                    showAviReaction(.curious)
                    openAviSearch(for: station, destination: .youtube)
                }
                AVAviPanelOptionButton(
                    title: L10n.string("shell.avi.actions.searchArtist"),
                    systemImage: "person.crop.circle",
                    style: .compact,
                    accessibilityIdentifier: "avi.actions.artist"
                ) {
                    showAviReaction(.curious)
                    openAviArtistSearch()
                }
            }

            HStack(spacing: 8) {
                AVAviPanelOptionButton(
                    title: L10n.string("shell.avi.actions.searchAppleMusic"),
                    systemImage: "music.note",
                    style: .compact,
                    accessibilityIdentifier: "avi.actions.appleMusic"
                ) {
                    showAviReaction(.curious)
                    openAviSearch(for: station, destination: .appleMusic)
                }
                AVAviPanelOptionButton(
                    title: L10n.string("shell.avi.actions.radioFeedback"),
                    systemImage: "dot.radiowaves.left.and.right",
                    style: .compact,
                    accessibilityIdentifier: "avi.actions.radioFeedback"
                ) {
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

    private var currentAviTransientState: ShellAviTransientState {
        ShellAviTransientState(
            isShowingActions: isShowingAviActions,
            isShowingMoreActions: isShowingMoreAviActions,
            isShowingFeedbackPicker: isShowingFeedbackPicker,
            actionsPage: aviActionsPage,
            isEditingRadioFeedback: isEditingRadioFeedback,
            isShowingArtworkZoom: isShowingArtworkZoom
        )
    }

    private func applyAviTransientState(_ state: ShellAviTransientState) {
        isShowingAviActions = state.isShowingActions
        isShowingMoreAviActions = state.isShowingMoreActions
        isShowingFeedbackPicker = state.isShowingFeedbackPicker
        aviActionsPage = state.actionsPage
        isEditingRadioFeedback = state.isEditingRadioFeedback
        isShowingArtworkZoom = state.isShowingArtworkZoom
    }

    private func resetTransientAviUI() {
        withAnimation(.snappy(duration: 0.18)) {
            applyAviTransientState(currentAviTransientState.resettingAll())
        }
    }

    private func focusedPrimaryFeedback(for station: Station) -> TuneAVStationFeedback? {
        if aviFeedbackTarget(for: station).usesTrackFeedback {
            return currentTrackFeedback
        }
        return stationFeedback[station.id]
    }

    private func focusedPrimaryFeedbackIdentity(for station: Station) -> String {
        aviFeedbackTarget(for: station).identity
    }

    private func setFocusedPrimaryFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        if aviFeedbackTarget(for: station).usesTrackFeedback {
            setCurrentTrackFeedback(feedback)
        } else {
            setStationFeedback(station, feedback)
        }
    }

    private func aviFeedbackTarget(for station: Station, isEditingRadioFeedback: Bool = false) -> ShellAviFeedbackTarget {
        ShellAviFeedbackResolver.primaryTarget(
            isNowPlayingFullPlayer: isNowPlayingFullPlayer,
            hasCurrentSongContext: hasCurrentSongContext,
            isEditingRadioFeedback: isEditingRadioFeedback,
            stationID: station.id,
            currentSongIdentity: currentSongIdentity
        )
    }

    private func setCurrentTrackFeedback(_ feedback: TuneAVStationFeedback?) {
        guard currentTrackFeedback != feedback else { return }
        libraryStore.setFeedbackForDiscoveredTrack(
            feedback,
            title: currentTrackTitle,
            artist: currentTrackArtist,
            stationID: currentStation?.id
        )
        AVHaptics.perform(stationFeedbackHapticEvent(for: feedback))
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
                AVAviPrimaryActionButton(
                    title: isFocusedStationActive ? L10n.string("player.header.nowPlaying") : L10n.string("shell.avi.actions.playRadio"),
                    systemImage: isFocusedStationActive ? "waveform" : "play.fill",
                    accessibilityIdentifier: "avi.detail.radio.play",
                    action: openPlayer
                )

                AVAviIconActionButton(
                    systemImage: stationSaveActionSystemImage(for: station),
                    isSelected: libraryStore.isFavorite(station),
                    accessibilityLabel: stationSaveActionTitle(for: station),
                    accessibilityIdentifier: "avi.detail.radio.save"
                ) {
                    toggleFavorite(station)
                }
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
            showStationDetails(station, [station], .about)
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
        isFocusedStationActive ? L10n.string("shell.stationDetail.signal.liveFound") : L10n.string("shell.stationInfo.title")
    }

    private var aviActionsPanelState: ShellAviActionsPanelState {
        ShellAviActionsPanelState(
            hasSongStep: hasCurrentSongContext && isNowPlayingFullPlayer,
            currentPage: aviActionsPage
        )
    }

    private var aviActionsRouter: ShellAviActionsRouter {
        ShellAviActionsRouter(
            changeActionsPage: { page in
                withAnimation(.snappy(duration: 0.2)) {
                    applyAviTransientState(currentAviTransientState.changingActionsPage(to: page))
                }
            },
            closeAviActions: closeAviActions,
            showReaction: showAviReaction,
            openTrackSearch: { station, destination, suffix in
                openAviSearch(for: station, destination: destination, suffix: suffix)
            },
            openArtistSearch: openAviArtistSearch,
            openStationSearch: openAviStationSearch,
            runProActionOutsideFullPlayer: runProAviActionOutsideFullPlayer,
            showStationDetails: { station, queue, initialSection in
                showStationDetails(station, queue, initialSection)
            },
            openStationWebsiteOrSearch: { station in
                browserRouter.openStationWebsiteOrSearch(station, closesAviActions: true)
            },
            showRelatedStations: showRelatedStations,
            stopPlayback: stopPlayback
        )
    }

    private func aviActionsPanel(for station: Station) -> some View {
        aviActionsPanel(for: station, showsStationDetailAction: true)
    }

    private func aviActionsPanel(for station: Station, showsStationDetailAction: Bool) -> some View {
        let panelState = aviActionsPanelState
        let router = aviActionsRouter

        return AviActionsPanelView(
            state: panelState,
            showsStationDetailAction: showsStationDetailAction,
            showsCloseSignalAction: isNowPlayingFullPlayer && isFocusedStationActive,
            previousPage: { router.previousPage(from: panelState) },
            nextPage: { router.nextPage(from: panelState) },
            close: closeAviActions,
            searchLyrics: { router.searchLyrics(for: station) },
            searchYouTube: { router.searchYouTube(for: station) },
            searchAppleMusic: { router.searchAppleMusic(for: station) },
            searchArtist: router.searchArtist,
            searchPublicInfo: { router.searchPublicInfo(for: station) },
            showRadioDetails: { router.showRadioDetails(for: station) },
            showHistory: { router.showHistory(for: station) },
            openWebsite: { router.openWebsite(for: station) },
            findRelatedRadios: { router.findRelatedRadios(for: station) },
            closeSignal: router.closeSignal
        )
    }

    private func setAviMenuFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        if aviFeedbackTarget(for: station, isEditingRadioFeedback: isEditingRadioFeedback).usesTrackFeedback {
            guard currentTrackFeedback != feedback else { return }
            libraryStore.setFeedbackForDiscoveredTrack(
                feedback,
                title: currentTrackTitle,
                artist: currentTrackArtist,
                stationID: station.id
            )
        } else {
            guard stationFeedback[station.id] != feedback else { return }
            setStationFeedback(station, feedback)
        }
        if let feedback {
            showAviReaction(for: feedback)
        } else {
            AVHaptics.perform(.clear)
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
        if let hapticEvent = reaction.hapticEvent {
            AVHaptics.perform(hapticEvent)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reaction.durationMilliseconds))
            guard aviReactionToken == token else { return }
            aviReaction = nil
        }
    }

    private func showAviReactionForCurrentSongChange(identity: String) {
        let isSavedDiscoveredTrack = focusedStation.map {
            libraryStore.isSavedDiscoveredTrack(title: currentTrackTitle, artist: currentTrackArtist, station: $0)
        } ?? false
        let decision = ShellAviAutomaticReactionResolver.decision(
            identity: identity,
            lastIdentity: lastAutomaticAviReactionIdentity,
            lastReactionAt: lastAutomaticAviReactionAt,
            isNowPlayingFullPlayer: isNowPlayingFullPlayer,
            isFocusedStationActive: isFocusedStationActive,
            isPlaying: isPlaying,
            currentTrackFeedback: currentTrackFeedback,
            isSavedDiscoveredTrack: isSavedDiscoveredTrack
        )

        switch decision {
        case .reset:
            aviReaction = nil
            lastAutomaticAviReactionIdentity = ""
        case .none:
            break
        case .suppress(let identity):
            lastAutomaticAviReactionIdentity = identity
        case .show(let reaction, let identity, let at):
            lastAutomaticAviReactionIdentity = identity
            lastAutomaticAviReactionAt = at
            showAviReaction(reaction)
        }
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
        AVHaptics.perform(.closePanel)
        withAnimation(.snappy(duration: 0.2)) {
            applyAviTransientState(currentAviTransientState.closingActions())
        }
    }

    private func openAviSearch(
        for station: Station,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        browserRouter.openTrackSearch(
            for: station,
            currentTrackArtist: currentTrackArtist,
            currentTrackTitle: currentTrackTitle,
            destination: destination,
            suffix: suffix
        )
    }

    private func openAviArtistSearch() {
        browserRouter.openArtistSearch(currentTrackArtist: currentTrackArtist)
    }

    private func openAviStationSearch(for station: Station) {
        browserRouter.openStationSearch(for: station)
    }

    private func openExternalSearch(
        query: String,
        destination: TuneAVExternalSearchURL.Destination = .web
    ) {
        browserRouter.openExternalSearch(query: query, destination: destination)
    }

    private func toggleDiscoverySaved(_ discovery: DiscoveredTrack) {
        ShellDiscoverySaveCoordinator.toggleDiscoverySaved(
            discovery,
            savedDiscoveriesCount: libraryStore.savedDiscoveriesCount,
            limitState: { currentUsage in
                accessController.limitState(for: .savedTracks, currentUsage: currentUsage)
            },
            toggleSaved: { discovery, limit in
                let wasSaved = discovery.isMarkedInteresting
                let didToggle = libraryStore.toggleDiscoverySaved(discovery, savedLimit: limit)
                if didToggle {
                    AVHaptics.perform(wasSaved ? .undo : .affirm)
                }
                return didToggle
            },
            presentUpgrade: { currentUsage in
                accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: currentUsage)
            }
        )
    }

    @discardableResult
    private func saveAviCurrentDiscovery(for station: Station) -> Bool {
        guard !ShellCurrentDiscoveryCoordinator.shouldSaveStationFavorite(
            title: currentTrackTitle,
            artist: currentTrackArtist
        ) else {
            showAviReaction(.liked)
            toggleFavorite(station)
            return true
        }

        let state = accessController.limitState(
            for: .savedTracks,
            currentUsage: libraryStore.savedDiscoveriesCount
        )

        let isAlreadySaved = isCurrentTrackSaved(for: station)
        if !ShellCurrentDiscoveryCoordinator.canToggleTrack(
            isAlreadySaved: isAlreadySaved,
            canMarkInteresting: libraryStore.canMarkTrackInteresting(
                title: currentTrackTitle,
                artist: currentTrackArtist,
                station: station,
                limit: state.limit
            )
        ) {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return false
        }

        let didToggle = libraryStore.toggleDiscoveredTrackSaved(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            station: station,
            artworkURL: currentTrackArtworkURL,
            savedLimit: state.limit,
            discoveryLimit: accessController.limits.discoveredTracks
        )
        guard didToggle else {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return false
        }

        showAviReaction(
            ShellCurrentDiscoveryCoordinator.reactionAfterToggle(
                isSaved: isCurrentTrackSaved(for: station)
            )
        )
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
                    AVAviActionChip(title: isFocusedStationActive ? L10n.string("player.discovery.lyricsShort") : L10n.string("shell.avi.actions.publicInfo"), systemImage: isFocusedStationActive ? "text.quote" : "info.circle") {
                        runProAviActionOutsideFullPlayer {
                            if isFocusedStationActive && hasCurrentSongContext {
                                openAviSearch(for: station, destination: .web, suffix: "lyrics")
                            } else {
                                openAviStationSearch(for: station)
                            }
                        }
                    }
                    AVAviActionChip(title: L10n.string("shell.avi.actions.historyShort"), systemImage: "clock.arrow.circlepath") {
                        runProAviActionOutsideFullPlayer {
                            showStationDetails(station, [station], .history)
                        }
                    }
                    AVAviActionChip(title: L10n.string("player.avi.action.web"), systemImage: "safari") {
                        runProAviActionOutsideFullPlayer {
                            browserRouter.openStationWebsiteOrSearch(station, closesAviActions: true)
                        }
                    }
                    AVAviActionChip(title: L10n.string("shell.avi.actions.findRelatedRadios"), systemImage: "sparkles") {
                        showRelatedStations(for: station)
                    }
                    if isFocusedStationActive {
                        AVAviActionChip(title: L10n.string("shell.accessibility.closeSignal"), systemImage: "power") {
                            stopPlayback()
                        }
                    }
                    AVAviActionChip(title: L10n.string("common.more"), systemImage: "ellipsis") {
                        withAnimation(.snappy(duration: 0.22)) {
                            applyAviTransientState(currentAviTransientState.openingActions())
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
        return isPlaying ? L10n.string("player.control.pause") : L10n.string("player.control.listen")
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
                                    showStationDetails(result.station, relatedStationResults.map(\.station), .about)
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
                        showStationDetails(recommendation.station, recommendationQueue, .about)
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
                                    showStationDetails(recommendation.station, recommendationQueue, .about)
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
                AVAviActionButton(title: L10n.string("tab.search"), systemImage: "magnifyingglass", action: openSearch)
                AVAviActionButton(title: L10n.string("shell.avi.action.saved"), systemImage: "bookmark.fill", action: openLibrary)
            }
        }
    }

    private var localSignals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("shell.avi.signals.title"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            AVAviInfoRow(
                title: L10n.string("shell.avi.signals.recent.title"),
                detail: recentStations.isEmpty ? L10n.string("shell.avi.signals.recent.empty") : L10n.plural(singular: "shell.avi.signals.recent.count.one", plural: "shell.avi.signals.recent.count.other", count: recentStations.count, recentStations.count),
                systemImage: "clock.arrow.circlepath",
                accessibilityIdentifier: "avi.signals.recent"
            )

            AVAviInfoRow(
                title: L10n.string("shell.avi.signals.saved.title"),
                detail: favoriteStations.isEmpty ? L10n.string("shell.avi.signals.saved.empty") : L10n.plural(singular: "shell.avi.signals.saved.count.one", plural: "shell.avi.signals.saved.count.other", count: favoriteStations.count, favoriteStations.count),
                systemImage: "dot.radiowaves.left.and.right",
                accessibilityIdentifier: "avi.signals.saved"
            )

            AVAviInfoRow(
                title: L10n.string("shell.avi.signals.discoveries.title"),
                detail: recentDiscoveryCount == 0 ? L10n.string("shell.avi.signals.discoveries.empty") : L10n.plural(singular: "shell.avi.signals.discoveries.count.one", plural: "shell.avi.signals.discoveries.count.other", count: recentDiscoveryCount, recentDiscoveryCount),
                systemImage: "sparkles",
                accessibilityIdentifier: "avi.signals.discoveries"
            )

            AVAviInfoRow(
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
        let localResults = relatedStationResults(for: station, candidates: relatedCandidateStations)
        relatedStationResults = localResults
        isLoadingRelatedStations = true

        Task {
            let remoteStations = await remoteRelatedStations(for: station)
            let merged = relatedStationResults(
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
        AviRelatedStationsCoordinator.candidateStations(
            stations: stations,
            playbackQueueStations: playbackQueueStations,
            recentStations: recentStations,
            favoriteStations: favoriteStations
        )
    }

    private func relatedStationResults(
        for station: Station,
        candidates: [Station]
    ) -> [(station: Station, reason: String)] {
        AviRelatedStationsCoordinator.results(
            for: station,
            candidates: candidates,
            scorer: recommendationScorer
        )
    }

    private func remoteRelatedStations(for station: Station) async -> [Station] {
        guard let filters = AviRelatedStationsCoordinator.remoteFilters(for: station) else { return [] }
        do {
            return try await TuneAVStationService().searchStations(filters: filters)
        } catch {
            return []
        }
    }

    private var rankedRecommendationCandidates: [(station: Station, rank: TuneAVLocalRecommendationScorer.Rank)] {
        AviRecommendationsCoordinator.rankedCandidates(
            stations: stations,
            currentStation: currentStation,
            scorer: recommendationScorer
        )
    }

    private var topRecommendation: (station: Station, reason: String)? {
        AviRecommendationsCoordinator.topRecommendation(from: rankedRecommendationCandidates)
    }

    private var secondaryRecommendations: [(station: Station, reason: String)] {
        AviRecommendationsCoordinator.secondaryRecommendations(from: rankedRecommendationCandidates)
    }

    private var recommendationQueue: [Station] {
        AviRecommendationsCoordinator.queue(from: rankedRecommendationCandidates)
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

#Preview {
    let persistence = PersistenceController(inMemory: true)

    AppShellView()
        .environmentObject(AccessController())
        .environmentObject(AudioPlayerService())
        .environmentObject(LibraryStore(container: persistence.container))
        .modelContainer(persistence.container)
}
