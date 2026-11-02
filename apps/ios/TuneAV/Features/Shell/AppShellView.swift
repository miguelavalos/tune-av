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

    enum LastOpenedStationPresentation: String {
        case detail
        case player
    }

    let launchContext: LaunchContext
    let startSignInFlow: (Bool) -> Void
    let synchronizeLibraryNow: () async -> Void

    @EnvironmentObject var accessController: AccessController
    @EnvironmentObject var audioPlayer: AudioPlayerService
    @EnvironmentObject var languageController: AppLanguageController
    @EnvironmentObject var libraryStore: LibraryStore
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.avCommonAppExperience) var appExperience

    @StateObject var chromeActions = AppShellChromeActions()
    @StateObject var searchPresentation: SearchPresentationStore
    @State var selectedTab: AppShellTab
    @State var homeStations: [Station] = []
    @State var homeIsLoading = false
    @State var homeErrorMessage: String?
    @State var homeFeedContext: HomeFeedContext = .popularWorldwide
    @State var homeSnapshot = HomeFeedSnapshot()
    @State var selectedStationDetail: SelectedStationDetail?
    @State var selectedMusicAviDetail: SelectedMusicAviDetail?
    @State var isAviNowPlayingFullPlayer = false
    @State var isAviActionPanelOpen = false
    @State var aviReturnCoordinator = AviReturnCoordinator()
    @State var requestedRadioMode: RadioLibraryMode?
    @State var requestedRadioOverview: Bool?
    @State var requestedMusicMode: MusicContentMode?
    @State var requestedMusicOverview: Bool?
    @State var musicHistoryStationFilter: Station?
    @State var enrichedStationsByID: [String: Station] = [:]
    @State var lastLibraryEnrichmentRequestKey: String?
    @State var lastLibraryEnrichmentRequestAt: Date?
    @State var stationNowPlayingTracks: [String: NowPlayingTrack] = [:]
    @State var stationNowPlayingCache: [String: CachedStationNowPlaying] = [:]
    @State var stationNowPlayingFailureCache: [String: Date] = [:]
    @State var didBootstrap = false
    @State var profileMode: ProfileScreen.Mode = .settings
    @State var listeningSession: ActiveListeningSession?
    @State var lastConfirmedPlaybackStationID: String?
    @State var isShowingProPaywall = false
    @State var isShowingFooterArtworkZoom = false
    @State var pendingCellularPlayback: PendingPlayback?
    @State var isConfirmingStopPlayback = false
    @State var stationPlayLog = TuneAVStationPlayLog.load()
    @State var homeSurpriseBrief: HomeSurpriseBrief?

    let stationService = StationService()
    let stationNowPlayingService = NowPlayingService()
    let searchLogger = Logger(subsystem: "com.avalsys.tuneav", category: "search")
    let genreTags = TuneAVStationMusicClassifier.musicTags
    static let libraryEnrichmentRefreshInterval: TimeInterval = 300

    var homeFeed: AppShellHomeFeed {
        AppShellHomeFeed(
            stationService: stationService,
            localizedCountryName: L10n.countryName(for:),
            resolvedDeviceCountryCode: resolvedDeviceCountryCode
        )
    }

    var appSearch: AppShellSearch {
        AppShellSearch(
            stationService: stationService,
            resolvedDeviceCountryCode: resolvedDeviceCountryCode,
            hasResolvedCountry: hasResolvedCountry(_:)
        )
    }

    var aviStationDetailBuilder: AviStationDetailBuilder {
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
    var adaptiveShell: some View {
        TuneAdaptiveLayoutReader { layout in
            if layout.layoutClass.isTabletLike {
                tabletShell
            } else {
                compactShell
            }
        }
    }

    var compactShell: some View {
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

    @ViewBuilder
    var compactFooterPlayer: some View {
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

    @ViewBuilder
    var currentScreen: some View {
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

    var homeScreen: some View {
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
            showStationDetails: { station, queueSource, queue in
                showStationDetails(station, queueSource: queueSource, queue: queue)
            }
        )
    }

    func openHomeSearchTag(_ tag: String) {
        searchPresentation.openTag(tag)
        selectedTab = .search
    }

    /// The recent radio played most this week, once it reaches three plays on this device.
    func homeReturningStation(in recentStations: [Station]) -> HomeReturningStation? {
        guard
            let mostPlayed = stationPlayLog.mostPlayedStation(since: Date().addingTimeInterval(-TuneAVStationPlayLog.returningWindow)),
            let station = recentStations.first(where: { $0.id == mostPlayed.stationID })
        else { return nil }
        return HomeReturningStation(name: station.name, count: mostPlayed.count)
    }

    /// One tap: Avi picks a radio it can justify from device-local signals and plays it through the
    /// normal play path, then says why in the Home brief.
    func surpriseMe() {
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

    var searchScreen: some View {
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

    var visibleSearchResults: [Station] {
        searchPresentation.results.isEmpty
            ? searchFallbackStations(for: searchRequest)
            : searchPresentation.results
    }

    func showSearchStationDetails(
        _ station: Station,
        queueSource: TuneAVPlaybackQueueSource,
        queue: [Station]?
    ) {
        showStationDetails(station, queueSource: queueSource, queue: queue)
    }

    var libraryScreen: some View {
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

    func showLibraryStationDetails(
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

    var musicScreen: some View {
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

    func openMusicDiscoveryInfo(
        _ discovery: DiscoveredTrack,
        returnMusicMode: MusicContentMode?
    ) {
        openDiscoveryInfo(discovery, returnMusicMode: returnMusicMode)
    }

    func openMusicArtistInfo(
        _ artist: DiscoveryArtistSummary,
        returnMusicMode: MusicContentMode?
    ) {
        openArtistInfo(artist, returnMusicMode: returnMusicMode)
    }

    func musicStationArtworkURL(_ discovery: DiscoveredTrack) -> URL? {
        guard let station = libraryStore.station(for: discovery.stationID) else {
            return discovery.resolvedStationArtworkURL
        }
        return enrichedStation(station).displayArtworkURL ?? discovery.resolvedStationArtworkURL
    }

    func musicTrackFeedback(_ discovery: DiscoveredTrack) -> TuneAVStationFeedback? {
        libraryStore.feedback(for: discovery)
    }

    var profileScreen: some View {
        makeProfileScreen(
            mode: profileMode,
            startSignInFlow: startSignInFlow,
            synchronizeLibraryNow: synchronizeLibraryNow,
            bottomContentPadding: shellScrollBottomPadding
        )
    }

    var aviScreen: some View {
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

    func openSearchTab() {
        AVHaptics.perform(.navigation)
        selectedTab = .search
    }

    func openLibraryTab() {
        AVHaptics.perform(.navigation)
        selectedTab = .library
    }

    func openAviPlayer() {
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

    func playAviDiscoveryStation(_ station: Station, queue: [Station]) {
        playStation(station, queueSource: .homeDiscovery, queue: queue)
    }

    func showAviStationDetails(
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

    func openAccountProfile() {
        AVHaptics.perform(.navigation)
        profileMode = .account
        selectedTab = .profile
    }

    func openChromeRequest(_ item: ShellBrandHeaderActiveItem) {
        AVHaptics.perform(.navigation)
        switch item {
        case .settings:
            profileMode = .settings
        case .account:
            profileMode = .account
        }
        selectedTab = .profile
    }

    func startAviSignIn() {
        startSignInFlow(true)
    }

    func openProPaywall() {
        isShowingProPaywall = true
    }

    var favoriteStations: [Station] {
        libraryStore.favoriteStations()
    }

    var isAviShowingCurrentStation: Bool {
        guard selectedTab == .avi, let currentStation = audioPlayer.currentStation else { return false }
        guard isAviNowPlayingFullPlayer else { return false }
        guard let selectedStation = selectedStationDetail?.station else { return false }
        return selectedStation.id == currentStation.id
    }

    var isAviFullPlayerActive: Bool {
        selectedTab == .avi && isAviNowPlayingFullPlayer && audioPlayer.currentStation != nil
    }

    var shouldHideFooterPlayer: Bool {
        isAviFullPlayerActive
    }

    var hasAviActiveContext: Bool {
        audioPlayer.currentStation != nil || selectedStationDetail != nil || selectedMusicAviDetail != nil
    }

    var recentStations: [Station] {
        libraryStore.recentStations()
    }

    var favoriteStationIDs: Set<String> {
        Set(libraryStore.favorites.map(\.stationID))
    }

    var enrichedFavoriteStations: [Station] {
        enrichedStations(favoriteStations)
    }

    var enrichedRecentStations: [Station] {
        enrichedStations(recentStations)
    }

    var lastPlayedStation: Station? {
        libraryStore.station(for: libraryStore.settings.lastPlayedStationID)
    }

    var searchRequestKey: String {
        "\(searchPresentation.requestKey)|\(languageController.currentLanguage.id)"
    }

    var homeFeedRequestKey: String {
        "\(libraryStore.settings.preferredTag)|\(languageController.currentLanguage.id)"
    }

    var searchRequest: AppShellSearchRequest {
        searchPresentation.request
    }

    var shellScrollBottomPadding: CGFloat {
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

    var shellFooterBackdropHeight: CGFloat {
        if audioPlayer.currentStation == nil {
            return 142
        }
        if isAviFullPlayerActive && isAviActionPanelOpen {
            return 156
        }
        return isAviFullPlayerActive ? 500 : 210
    }

    var shellFooterPlayerTabSpacing: CGFloat {
        10
    }
}

extension Station {
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

extension Station {
    var normalizedStreamEnrichmentURLKey: String? {
        enrichmentLookupKeys.first { $0.hasPrefix("stream:") }
    }
}

struct CachedStationNowPlaying {
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
