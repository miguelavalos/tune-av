import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

func stationFeedbackHapticEvent(for feedback: TuneAVStationFeedback?) -> AVHapticEvent {
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

    /// What Avi said after the last "Surprise me". It stays on Home while the picked radio is the
    /// current one; when nothing could be picked it stays while the current radio is unchanged.
    struct HomeSurpriseBrief: Equatable {
        let stationID: String?
        let currentStationIDAtRequest: String?
        let reason: String

        func reason(forCurrentStationID currentStationID: String?) -> String? {
            let anchor = stationID ?? currentStationIDAtRequest
            return anchor == currentStationID ? reason : nil
        }
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
    @State private var stationPlayLog = TuneAVStationPlayLog.load()
    @State private var homeSurpriseBrief: HomeSurpriseBrief?

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
            returningStation: homeReturningStation(in: recentStations),
            surpriseReason: homeSurpriseBrief?.reason(forCurrentStationID: audioPlayer.currentStation?.id),
            openAvi: openContextualAvi,
            surpriseMe: surpriseMe,
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

    /// The recent radio played most this week, once it reaches three plays on this device.
    private func homeReturningStation(in recentStations: [Station]) -> HomeReturningStation? {
        guard
            let mostPlayed = stationPlayLog.mostPlayedStation(since: Date().addingTimeInterval(-TuneAVStationPlayLog.returningWindow)),
            let station = recentStations.first(where: { $0.id == mostPlayed.stationID })
        else { return nil }
        return HomeReturningStation(name: station.name, count: mostPlayed.count)
    }

    /// One tap: Avi picks a radio it can justify from device-local signals and plays it through the
    /// normal play path, then says why in the Home brief.
    private func surpriseMe() {
        let currentStationID = audioPlayer.currentStation?.id
        let lastPlayedByID = Dictionary(libraryStore.recents.map { ($0.stationID, $0.lastPlayedAt) }, uniquingKeysWith: { max($0, $1) })
        let pick = TuneAVSurpriseStationPicker.pick(
            favorites: enrichedFavoriteStations,
            recentPlays: stationPlayLog.recentPlays(stations: enrichedRecentStations, lastPlayedByID: lastPlayedByID),
            feedback: libraryStore.stationFeedback,
            popular: enrichedStations(homeSnapshot.stations),
            now: .now,
            currentStationID: currentStationID
        )
        guard let pick else {
            AVHaptics.perform(.warning)
            homeSurpriseBrief = HomeSurpriseBrief(
                stationID: nil,
                currentStationIDAtRequest: currentStationID,
                reason: L10n.string("shell.home.surprise.unavailable")
            )
            return
        }
        homeSurpriseBrief = HomeSurpriseBrief(
            stationID: pick.station.id,
            currentStationIDAtRequest: currentStationID,
            reason: pick.localizedReason()
        )
        playStation(pick.station, queueSource: .homeDiscovery, queue: [pick.station])
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
        accessController.noteDiscoveredTrackForUpgradeMoment(key: "\(station.id)|\(trackTitle)|\(trackArtist)")
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
        accessController.noteListeningDayForUpgradeMoment()
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
        stationPlayLog = stationPlayLog.recording(station.id)
        stationPlayLog.save()
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


#Preview {
    let persistence = PersistenceController(inMemory: true)

    AppShellView()
        .environmentObject(AccessController())
        .environmentObject(AudioPlayerService())
        .environmentObject(LibraryStore(container: persistence.container))
        .modelContainer(persistence.container)
}
