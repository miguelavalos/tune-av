import SwiftUI

struct AppShellView: View {
    let launchContext: LaunchContext
    let startSignInFlow: (Bool) -> Void

    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var selectedTab: AppShellTab
    @State private var isShowingNowPlaying = false
    @State private var searchQuery: String
    @State private var searchTag: String?
    @State private var searchCountryCode: String?
    @State private var searchFocusRequest = 0
    @State private var searchResults: [Station] = []
    @State private var searchIsLoading = false
    @State private var searchErrorMessage: String?
    @State private var homeStations: [Station] = []
    @State private var homeIsLoading = false
    @State private var homeErrorMessage: String?
    @State private var homeFeedContext: HomeFeedContext = .popularWorldwide
    @State private var homeSnapshot = HomeFeedSnapshot()
    @State private var selectedStationDetail: SelectedStationDetail?
    @State private var musicHistoryStationFilter: Station?
    @State private var stationNowPlayingTracks: [String: NowPlayingTrack] = [:]
    @State private var stationNowPlayingCache: [String: CachedStationNowPlaying] = [:]
    @State private var didBootstrap = false

    private let stationService = StationService()
    private let stationNowPlayingService = NowPlayingService()
    private let genreTags = TuneAVFallbackArtworkCategory.visibleSearchTags

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
            searchAction: {
                selectedTab = .search
                searchFocusRequest += 1
            },
            selectTab: { tab in
                selectedTab = tab
            },
            content: {
                NavigationStack {
                    currentScreen
                }
            },
            footerPlayer: {
                if let station = audioPlayer.currentStation {
                    MiniPlayerView(station: station) {
                        isShowingNowPlaying = true
                    }
                }
            }
        )
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingView(
                startSignInFlow: startSignInFlow,
                stationHistoryAction: { station in
                    openStationHistory(station)
                }
            )
                .environmentObject(accessController)
                .environmentObject(audioPlayer)
                .environmentObject(libraryStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedStationDetail) { detail in
            StationDetailSheet(
                station: detail.station,
                isFavorite: favoriteStationIDs.contains(detail.station.id),
                isPlaying: audioPlayer.isCurrent(detail.station) && audioPlayer.isPlaying,
                playAction: {
                    playStation(
                        detail.station,
                        queueSource: detail.queueSource,
                        queue: detail.queueStations
                    )
                },
                toggleFavorite: { toggleFavorite(detail.station) },
                stationHistoryAction: {
                    openStationHistory(detail.station)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { isShowingNowPlaying ? nil : accessController.upgradePrompt },
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
                    }
                },
                onDismiss: {
                    accessController.upgradePrompt = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .task {
            await bootstrapIfNeeded()
        }
        .task {
            refreshHomePresentation()
        }
        .task {
            await refreshHomeFeed()
        }
        .task(id: libraryStore.settings.preferredTag) {
            await refreshHomeFeed()
        }
        .task(id: searchRequestKey) {
            await loadSearchResults()
        }
        .task(id: stationNowPlayingRequestKey) {
            await loadStationNowPlayingPreviews()
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .home else { return }
            refreshHomePresentation()
        }
        .onChange(of: audioPlayer.currentStation?.id) { _, stationID in
            guard stationID != nil, let station = audioPlayer.currentStation else { return }
            libraryStore.recordPlayback(of: station, recentLimit: accessController.limits.recentStations)
        }
        .onChange(of: currentTrackDiscoveryKey) { _, _ in
            recordCurrentTrackDiscovery()
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selectedTab {
        case .home:
            HomeScreen(
                stations: homeSnapshot.stations,
                isLoading: homeIsLoading,
                errorMessage: homeErrorMessage,
                recentStations: homeSnapshot.recentStations,
                favoriteStations: homeSnapshot.favoriteStations,
                discoveries: libraryStore.discoveries,
                feedContext: homeSnapshot.feedContext,
                bottomContentPadding: shellScrollBottomPadding,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: stationNowPlayingTracks,
                refreshHome: refreshHomePresentationAndFeed,
                playStation: playStation,
                toggleFavorite: toggleFavorite(_:),
                showStationDetails: showStationDetails
            )
        case .search:
            SearchScreen(
                query: $searchQuery,
                activeTag: $searchTag,
                selectedCountryCode: $searchCountryCode,
                results: searchResults,
                isLoading: searchIsLoading,
                errorMessage: searchErrorMessage,
                tags: genreTags,
                focusRequest: searchFocusRequest,
                bottomContentPadding: shellScrollBottomPadding,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: stationNowPlayingTracks,
                playStation: playStation,
                toggleFavorite: toggleFavorite(_:),
                showStationDetails: showStationDetails
            )
        case .library:
            LibraryScreen(
                favorites: favoriteStations,
                recents: recentStations,
                bottomContentPadding: shellScrollBottomPadding,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: stationNowPlayingTracks,
                playStation: playStation,
                toggleFavorite: toggleFavorite(_:),
                showStationDetails: showStationDetails
            )
        case .music:
            MusicScreen(
                discoveries: libraryStore.discoveries,
                historyStationFilter: $musicHistoryStationFilter,
                bottomContentPadding: shellScrollBottomPadding,
                openDiscoveryStation: openDiscoveryStation(_:),
                stationArtworkURL: { _ in nil },
                toggleDiscoverySaved: toggleDiscoverySaved(_:),
                hideDiscovery: libraryStore.hideDiscovery(_:),
                restoreDiscovery: libraryStore.restoreDiscovery(_:),
                removeDiscovery: libraryStore.removeDiscovery(_:),
                clearDiscoveries: libraryStore.clearDiscoveries
            )
        case .profile:
            ProfileScreen(
                startSignInFlow: startSignInFlow,
                bottomContentPadding: shellScrollBottomPadding
            )
        }
    }

    private var favoriteStations: [Station] {
        libraryStore.favoriteStations()
    }

    private var recentStations: [Station] {
        libraryStore.recentStations()
    }

    private var favoriteStationIDs: Set<String> {
        Set(libraryStore.favorites.map(\.stationID))
    }

    private var searchRequestKey: String {
        searchRequest.key
    }

    private var searchRequest: AppShellSearchRequest {
        AppShellSearchRequest(query: searchQuery, tag: searchTag, countryCode: searchCountryCode)
    }

    private var shellScrollBottomPadding: CGFloat {
        // The footer is visually detached and floats above scroll content,
        // so scrollable screens need extra trailing space to bring the last row above it.
        audioPlayer.currentStation == nil ? 96 : 168
    }

    private var stationNowPlayingRequestKey: String {
        let ids = stationNowPlayingCandidates.map(\.id).joined(separator: "|")
        return "\(selectedTab)|\(ids)"
    }

    private var currentTrackDiscoveryKey: String {
        [
            audioPlayer.currentStation?.id ?? "",
            audioPlayer.currentTrackArtist ?? "",
            audioPlayer.currentTrackTitle ?? "",
            audioPlayer.currentTrackArtworkURL?.absoluteString ?? ""
        ].joined(separator: "|")
    }

    private var stationNowPlayingCandidates: [Station] {
        AppShellNowPlayingPreviews.candidateStations(
            selectedTab: selectedTab,
            homeSnapshot: homeSnapshot,
            searchResults: searchResults,
            favoriteStations: favoriteStations,
            recentStations: recentStations,
            isEnabled: isProNowPlayingEnabled
        )
    }

    private func loadStationNowPlayingPreviews() async {
        guard isProNowPlayingEnabled else { return }
        guard !launchContext.isUITesting else { return }

        let supportedStations = stationNowPlayingCandidates
            .filter { stationNowPlayingService.supports($0) }
            .prefix(6)

        guard !supportedStations.isEmpty else { return }

        for station in supportedStations {
            if Task.isCancelled { return }

            if let cached = stationNowPlayingCache[station.id], cached.isFresh {
                stationNowPlayingTracks[station.id] = cached.track
                continue
            }

            guard let track = await stationNowPlayingService.fetchTrack(for: station) else { continue }
            stationNowPlayingTracks[station.id] = track
            stationNowPlayingCache[station.id] = CachedStationNowPlaying(track: track, fetchedAt: Date())
        }
    }

    private var isProNowPlayingEnabled: Bool {
        accessController.capabilities.canAccessPremiumFeatures
    }

    private func recordCurrentTrackDiscovery() {
        guard
            let station = audioPlayer.currentStation,
            normalizedTrackValue(audioPlayer.currentTrackTitle) != nil,
            normalizedTrackValue(audioPlayer.currentTrackArtist) != nil,
            !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(
                audioPlayer.currentTrackTitle,
                stationName: station.name
            ),
            !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(
                audioPlayer.currentTrackArtist,
                stationName: station.name
            )
        else {
            return
        }

        libraryStore.recordDiscoveredTrack(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: station,
            artworkURL: audioPlayer.currentTrackArtworkURL,
            discoveryLimit: accessController.limits.discoveredTracks
        )
    }

    private func applyUITestTrackMetadataIfNeeded() {
        guard launchContext.isUITesting else { return }
        guard launchContext.uiTestTrackTitle != nil || launchContext.uiTestTrackArtist != nil else { return }
        audioPlayer.applyUITestTrackMetadata(
            title: launchContext.uiTestTrackTitle,
            artist: launchContext.uiTestTrackArtist
        )
    }

    private func normalizedTrackValue(_ value: String?) -> String? {
        TuneAVDisplayMetadata.normalized(value)
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
                } else if let demoStation = launchContext.demoStation {
                    playStation(demoStation)
                }
                isShowingNowPlaying = audioPlayer.currentStation != nil
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
        let playbackQueue = AudioPlayerService.PlaybackQueue(
            source: queueSource,
            stations: queue ?? [station]
        )
        audioPlayer.play(station: station, queue: playbackQueue)
        libraryStore.recordPlayback(of: station, recentLimit: accessController.limits.recentStations)
    }

    private func toggleFavorite(_ station: Station) {
        if libraryStore.isFavorite(station) {
            libraryStore.toggleFavorite(for: station)
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

        libraryStore.toggleFavorite(for: station)
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
        queue: [Station]? = nil
    ) {
        let queueStations = queue ?? [station]
        selectedStationDetail = SelectedStationDetail(
            station: station,
            queueSource: queueSource,
            queueStations: queueStations
        )

        if station.editorial == nil {
            Task {
                await refreshSelectedStationDetailEnrichment(
                    station,
                    queueSource: queueSource,
                    queueStations: queueStations
                )
            }
        }
    }

    @MainActor
    private func refreshSelectedStationDetailEnrichment(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queueStations: [Station]
    ) async {
        do {
            let enrichedStations = try await stationService.searchStations(
                filters: .init(query: station.name, limit: 5)
            )
            guard
                selectedStationDetail?.station.id == station.id,
                let enrichedStation = enrichedStations.first(where: { $0.id == station.id }),
                enrichedStation.editorial != nil
            else {
                return
            }

            selectedStationDetail = SelectedStationDetail(
                station: enrichedStation,
                queueSource: queueSource,
                queueStations: queueStations.map { $0.id == station.id ? enrichedStation : $0 }
            )
        } catch {
            return
        }
    }

    private func openStationHistory(_ station: Station) {
        selectedStationDetail = nil
        isShowingNowPlaying = false
        musicHistoryStationFilter = station
        selectedTab = .music
    }

    private func openDiscoveryStation(_ discovery: DiscoveredTrack) {
        guard let station = libraryStore.station(for: discovery.stationID) else { return }

        playStation(station, queueSource: .libraryRecents, queue: recentStations)
    }

    private func refreshHomeFeed() async {
        homeIsLoading = true
        homeErrorMessage = nil

        if launchContext.isUITesting && launchContext.shouldUseLocalUITestDiscovery {
            homeStations = Array(Station.samples.prefix(8))
            homeFeedContext = .popularWorldwide
            refreshHomePresentation()
            homeIsLoading = false
            return
        }

        do {
            let feed = try await homeFeed.load(preferredTag: libraryStore.settings.preferredTag)
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

    private func refreshHomePresentation() {
        homeSnapshot = HomeFeedSnapshot(
            stations: homeStations,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            feedContext: homeFeedContext
        )
    }

    private func refreshHomePresentationAndFeed() async {
        refreshHomePresentation()
        await refreshHomeFeed()
    }

    private func loadSearchResults() async {
        let request = searchRequest
        let requestKey = request.key

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

            searchResults = results
            searchErrorMessage = nil
            searchIsLoading = false
        } catch is CancellationError {
            guard requestKey == searchRequestKey else { return }
            searchIsLoading = false
        } catch {
            guard requestKey == searchRequestKey else { return }
            searchResults = []
            searchErrorMessage = L10n.string("shell.error.search")
            searchIsLoading = false
        }
    }

    private var defaultEditorialStations: [Station] {
        AppShellHomeFeed.defaultEditorialStations(
            currentStation: audioPlayer.currentStation,
            recentStations: recentStations,
            favoriteStations: favoriteStations
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

private struct CachedStationNowPlaying {
    let track: NowPlayingTrack
    let fetchedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 60
    }
}

private struct SelectedStationDetail: Identifiable {
    let station: Station
    let queueSource: AudioPlayerService.PlaybackQueue.Source
    let queueStations: [Station]

    var id: String {
        [station.id, station.editorial?.updatedAt].compactMap { $0 }.joined(separator: "|")
    }
}

private struct AppShellScaffold<Content: View, FooterPlayer: View>: View {
    let selectedTab: AppShellTab
    let hasFooterPlayer: Bool
    let searchAction: () -> Void
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
            .frame(height: hasFooterPlayer ? 210 : 142)
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
                            title: L10n.string("tab.profile"),
                            systemImage: "person.crop.circle.fill",
                            isSelected: selectedTab == .profile,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.profile"
                        ) {
                            selectTab(.profile)
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

                    AppShellFooterSearchButton(isSelected: selectedTab == .search) {
                        searchAction()
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

private struct AppShellFooterSearchButton: View {
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
                }

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
            }
            .frame(width: 62, height: 62)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("tab.search"))
        .accessibilityIdentifier("tab.search")
    }
}

private struct HomeScreen: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let stations: [Station]
    let isLoading: Bool
    let errorMessage: String?
    let recentStations: [Station]
    let favoriteStations: [Station]
    let discoveries: [DiscoveredTrack]
    let feedContext: HomeFeedContext
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let refreshHome: () async -> Void
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    private enum FeaturedSource {
        case current
        case recent
        case favorite
        case popular
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShellBrandHeader(statusTitle: isLoading ? L10n.string("shell.status.refreshing") : (audioPlayer.currentStation == nil ? L10n.string("shell.status.live") : audioPlayer.status.label))

                Text(L10n.string("shell.home.title"))
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                if shouldShowLiveNowPanel {
                    LiveNowPanel(currentStation: audioPlayer.currentStation, status: audioPlayer.status.label)
                }

                if isLoading && heroStation == nil && displayedPopularStations.isEmpty {
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
                        playAction: {
                            if audioPlayer.isCurrent(heroStation) {
                                audioPlayer.togglePlayback()
                            } else {
                                playStation(heroStation, featuredQueueSource, featuredQueueStations)
                            }
                        },
                        favoriteAction: { toggleFavorite(heroStation) },
                        detailsAction: { showStationDetails(heroStation, featuredQueueSource, featuredQueueStations) }
                    )

                } else {
                    EmptyLibraryState(
                        title: L10n.string("shell.home.empty.title"),
                        detail: L10n.string("shell.home.empty.detail")
                    )
                }

                if !displayedRecentStations.isEmpty {
                    StationSection(title: L10n.string("shell.home.recents.title"), subtitle: L10n.string("shell.home.recents.subtitle"), accessibilityIdentifier: "home.section.recents") {
                        StationCompactCarousel(
                            stations: displayedRecentStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            queueSource: .homeRecents,
                            queueStations: recentStations,
                            playStation: playStation,
                            toggleFavorite: toggleFavorite,
                            showStationDetails: showStationDetails
                        )
                    }
                }

                if !displayedFavoriteStations.isEmpty {
                    StationSection(title: L10n.string("shell.home.favorites.title"), subtitle: L10n.string("shell.home.favorites.subtitle"), accessibilityIdentifier: "home.section.favorites") {
                        StationCompactCarousel(
                            stations: displayedFavoriteStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            queueSource: .homeFavorites,
                            queueStations: favoriteStations,
                            playStation: playStation,
                            toggleFavorite: toggleFavorite,
                            showStationDetails: showStationDetails
                        )
                    }
                }

                if !displayedPopularStations.isEmpty {
                    StationSection(
                        title: sectionTitle,
                        subtitle: sectionSubtitle,
                        accessibilityIdentifier: "home.section.discovery"
                    ) {
                        StationCompactCarousel(
                            stations: displayedPopularStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            queueSource: .homeDiscovery,
                            queueStations: displayedPopularStations,
                            playStation: playStation,
                            toggleFavorite: toggleFavorite,
                            showStationDetails: showStationDetails
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, bottomContentPadding)
        }
        .scrollIndicators(.hidden)
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

    private var displayedRecentStations: [Station] {
        Array(filteredStationsExcludingFeatured(from: recentStations).prefix(6))
    }

    private var displayedFavoriteStations: [Station] {
        Array(filteredStationsExcludingFeatured(from: favoriteStations).prefix(6))
    }

    private var displayedPopularStations: [Station] {
        let excludedIDs = Set(displayedRecentStations.map(\.id) + displayedFavoriteStations.map(\.id))
        return filteredStationsExcludingFeatured(from: stations)
            .filter { !excludedIDs.contains($0.id) }
            .sorted { first, second in
                let firstScore = discoverySignalScore(for: first)
                let secondScore = discoverySignalScore(for: second)

                if firstScore == secondScore {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }

                return firstScore > secondScore
            }
    }

    private var featuredQueueSource: AudioPlayerService.PlaybackQueue.Source {
        switch heroSource {
        case .current:
            return .singleStation
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

    private func discoverySignalScore(for station: Station) -> Int {
        discoveries.reduce(0) { score, discovery in
            guard discovery.stationID == station.id else { return score }

            if discovery.isMarkedInteresting {
                return score + 3
            }

            if discovery.isHidden {
                return score - 2
            }

            return score
        }
    }

    private var featuredLabel: String {
        switch featuredSource {
        case .recent:
            return L10n.string("shell.home.featured.frontPage").uppercased(with: .current)
        case .favorite:
            return L10n.string("shell.home.featured.frontPage").uppercased(with: .current)
        case .current:
            return L10n.string("shell.liveNow.title").uppercased(with: .current)
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

    let results: [Station]
    let isLoading: Bool
    let errorMessage: String?
    let tags: [String]
    let focusRequest: Int
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var isShowingCountryPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ShellBrandHeader(statusTitle: isLoading ? L10n.string("shell.search.status.searching") : L10n.string("shell.search.status.search"))

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("shell.search.title"))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("shell.search.subtitle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                SearchField(query: $query, focusRequest: focusRequest)
                SearchCountryFilterButton(
                    title: selectedCountryTitle,
                    flag: selectedCountryFlag,
                    isActive: selectedCountryCode != nil,
                    clearAction: clearCountryFilter,
                    openAction: { isShowingCountryPicker = true }
                )
                GenreTagStrip(tags: tags, activeTag: activeTag, toggleTag: toggleTag)

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
                        if isLoading {
                            SearchLoadingCard()
                        }

                        if usesSearchGrid {
                            LazyVGrid(columns: searchGridColumns, spacing: 12) {
                                ForEach(results) { station in
                                    StationCompactCard(
                                        station: station,
                                        isFavorite: favoriteStationIDs.contains(station.id),
                                        nowPlayingTrack: nowPlayingTracks[station.id],
                                        toggleFavorite: { toggleFavorite(station) },
                                        playAction: { playStation(station, .searchResults, results) },
                                        detailsAction: { showStationDetails(station, .searchResults, results) }
                                    )
                                }
                            }
                        } else {
                            StationCompactCarousel(
                                stations: results,
                                favoriteStationIDs: favoriteStationIDs,
                                nowPlayingTracks: nowPlayingTracks,
                                queueSource: .searchResults,
                                queueStations: results,
                                playStation: playStation,
                                toggleFavorite: toggleFavorite,
                                showStationDetails: showStationDetails
                            )
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
            .padding(24)
            .padding(.bottom, bottomContentPadding)
        }
        .scrollIndicators(.hidden)
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(isPresented: $isShowingCountryPicker) {
            SearchCountryPickerSheet(selectedCountryCode: $selectedCountryCode)
                .environmentObject(libraryStore)
        }
        .onChange(of: selectedCountryCode) { _, newValue in
            libraryStore.setPreferredCountry(newValue)
        }
    }

    private var queryText: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usesSearchGrid: Bool {
        !queryText.isEmpty || activeTag != nil || selectedCountryCode != nil
    }

    private var searchGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 104, maximum: 120), spacing: 12)
        ]
    }

    private func toggleTag(_ tag: String) {
        activeTag = activeTag == tag ? nil : tag
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

    private var selectedCountryFlag: String? {
        guard let selectedCountryCode else { return nil }
        return CountryOption(code: selectedCountryCode, name: selectedCountryTitle).flag
    }
}

private struct LibraryScreen: View {
    @State private var query = ""

    let favorites: [Station]
    let recents: [Station]
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShellBrandHeader(
                    statusTitle: favorites.isEmpty
                        ? L10n.string("shell.library.status.empty")
                        : L10n.plural(
                            singular: "shell.library.status.saved.one",
                            plural: "shell.library.status.saved.other",
                            count: favorites.count,
                            favorites.count
                        )
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("shell.library.title"))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("shell.library.subtitle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                SearchField(query: $query, prompt: L10n.string("shell.library.searchPrompt"))

                StationSection(title: L10n.string("shell.library.favorites.title"), subtitle: L10n.string("shell.library.favorites.subtitle"), accessibilityIdentifier: "library.section.favorites") {
                    if filteredFavorites.isEmpty {
                        EmptyLibraryState(
                            title: favorites.isEmpty ? L10n.string("shell.library.favorites.empty") : L10n.string("shell.library.favorites.noMatch"),
                            detail: favorites.isEmpty
                                ? L10n.string("shell.library.favorites.empty.detail")
                                : L10n.string("shell.library.favorites.noMatch.detail")
                        )
                    } else {
                        LazyVGrid(columns: stationGridColumns, spacing: 12) {
                            ForEach(filteredFavorites) { station in
                                StationCompactCard(
                                    station: station,
                                    isFavorite: favoriteStationIDs.contains(station.id),
                                    nowPlayingTrack: nowPlayingTracks[station.id],
                                    toggleFavorite: { toggleFavorite(station) },
                                    playAction: { playStation(station, .libraryFavorites, favorites) },
                                    detailsAction: { showStationDetails(station, .libraryFavorites, favorites) }
                                )
                            }
                        }
                    }
                }

                if !filteredRecents.isEmpty {
                    StationSection(title: L10n.string("shell.library.recents.title"), subtitle: L10n.string("shell.library.recents.subtitle"), accessibilityIdentifier: "library.section.recents") {
                        LazyVGrid(columns: stationGridColumns, spacing: 12) {
                            ForEach(filteredRecents) { station in
                                StationCompactCard(
                                    station: station,
                                    isFavorite: favoriteStationIDs.contains(station.id),
                                    nowPlayingTrack: nowPlayingTracks[station.id],
                                    toggleFavorite: { toggleFavorite(station) },
                                    playAction: { playStation(station, .libraryRecents, recents) },
                                    detailsAction: { showStationDetails(station, .libraryRecents, recents) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
            .padding(.bottom, bottomContentPadding)
        }
        .scrollIndicators(.hidden)
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var stationGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 104, maximum: 120), spacing: 12)
        ]
    }

    private var filteredFavorites: [Station] {
        filterStations(favorites)
    }

    private var filteredRecents: [Station] {
        filterStations(recents)
    }

    private func filterStations(_ stations: [Station]) -> [Station] {
        TuneAVLibraryStationLogic.filteredStations(stations, query: trimmedQuery)
    }
}

private struct MusicScreen: View {
    @EnvironmentObject private var accessController: AccessController
    @State private var query = ""
    @State private var musicMode: MusicLibraryMode = .songs
    @State private var isConfirmingClearDiscoveries = false
    @State private var isShowingDiscoveriesShare = false
    @State private var browserDestination: BrowserDestination?
    @State private var hiddenDiscovery: DiscoveredTrack?
    @State private var selectedArtistName: String?

    let discoveries: [DiscoveredTrack]
    @Binding var historyStationFilter: Station?
    let bottomContentPadding: CGFloat
    let openDiscoveryStation: (DiscoveredTrack) -> Void
    let stationArtworkURL: (DiscoveredTrack) -> URL?
    let toggleDiscoverySaved: (DiscoveredTrack) -> Void
    let hideDiscovery: (DiscoveredTrack) -> Void
    let restoreDiscovery: (DiscoveredTrack) -> Void
    let removeDiscovery: (DiscoveredTrack) -> Void
    let clearDiscoveries: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ShellBrandHeader(
                        statusTitle: musicStatusTitle
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("shell.music.title"))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)

                        Text(L10n.string("shell.music.subtitle"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                    }

                    SearchField(query: $query, prompt: L10n.string("shell.music.searchPrompt"))
                    MusicSignalSummary(
                        savedCount: savedDiscoveries.count,
                        historyCount: visibleDiscoveries.count,
                        artistCount: visibleArtistSummaries.count,
                        selectedMode: musicMode,
                        selectMode: { mode in
                            selectedArtistName = nil
                            if mode != .history {
                                historyStationFilter = nil
                            }
                            musicMode = mode
                        }
                    )

                    discoveryLibrarySection
                }
                .padding(24)
                .padding(.bottom, bottomContentPadding)
            }
            .scrollIndicators(.hidden)

            hiddenDiscoveryUndoBanner
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

            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("shell.library.discoveries.clear.confirmMessage"))
        }
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .sheet(isPresented: $isShowingDiscoveriesShare) {
            ShareSheetView(items: [discoveriesShareText])
        }
        .onAppear(perform: normalizeInitialDiscoveryFilter)
        .onChange(of: query) { _, _ in
            selectedArtistName = nil
        }
        .onChange(of: historyStationFilter?.id) { _, stationID in
            guard stationID != nil else { return }
            selectedArtistName = nil
            musicMode = .history
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var discoveryLibrarySection: some View {
        StationSection(title: L10n.string("shell.music.discoveries.title"), subtitle: L10n.string("shell.music.discoveries.subtitle"), accessibilityIdentifier: "music.section.discoveries") {
            VStack(alignment: .leading, spacing: 16) {
                if filteredDiscoveries.isEmpty && filteredArtistSummaries.isEmpty {
                    EmptyLibraryState(
                        title: emptyDiscoveryTitle,
                        detail: emptyDiscoveryDetail
                    )
                } else {
                    switch musicMode {
                    case .songs:
                        discoverySongsHeader
                        discoveryTrackList
                    case .artists:
                        discoveryArtistsHeader
                        VStack(spacing: 10) {
                            ForEach(filteredArtistSummaries) { artist in
                                DiscoveryArtistRow(
                                    summary: artist,
                                    openArtist: { openArtistSongs(artist.name) },
                                    openYouTube: { openArtistSearch(artist.name, youtube: true) },
                                    openAppleMusic: { openAppleMusicArtistSearch(artist.name) },
                                    openSpotify: { openSpotifyArtistSearch(artist.name) }
                                )
                            }
                        }
                    case .history:
                        discoverySongsHeader
                        discoveryTrackList
                    }
                }
            }
        }
    }

    private var discoveryTrackList: some View {
        VStack(spacing: 10) {
            ForEach(filteredDiscoveries) { discovery in
                DiscoveryTrackCard(
                    discovery: discovery,
                    stationArtworkURL: stationArtworkURL(discovery),
                    openStation: { openDiscoveryStation(discovery) },
                    toggleSaved: { toggleDiscoverySaved(discovery) },
                    openYouTube: { openDiscoverySearch(discovery, suffix: nil, youtube: true) },
                    openLyrics: { openDiscoverySearch(discovery, suffix: "lyrics", youtube: false) },
                    openAppleMusic: { openAppleMusicSearch(discovery) },
                    openSpotify: { openSpotifySearch(discovery) },
                    hideAction: { hideDiscoveryWithUndo(discovery) },
                    removeAction: { removeDiscovery(discovery) }
                )
            }
        }
    }

    private var discoveryArtistsHeader: some View {
        HStack(spacing: 10) {
            Text(L10n.string("shell.music.artists.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            discoveryActions
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

    private var discoverySongsHeader: some View {
        HStack(spacing: 10) {
            Text(historyStationFilterTitle ?? musicMode.songsTitle)
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

            discoveryActions
        }
    }

    private var historyStationFilterTitle: String? {
        guard musicMode == .history, let historyStationFilter else { return nil }
        return "\(MusicLibraryMode.history.title) · \(historyStationFilter.name)"
    }

    private var discoveryActions: some View {
        HStack(spacing: 10) {
            Button {
                guard useDailyFeatureIfAllowed(.discoveryShare, usageKey: discoveriesShareText) else { return }
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
            .disabled(filteredDiscoveries.isEmpty)

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
            .padding(.horizontal, 24)
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

    private var savedDiscoveries: [DiscoveredTrack] {
        AppShellMusicLibrary.savedDiscoveries(discoveries)
    }

    private var visibleDiscoveries: [DiscoveredTrack] {
        AppShellMusicLibrary.visibleDiscoveries(discoveries)
    }

    private var musicStatusTitle: String {
        if !savedDiscoveries.isEmpty {
            return L10n.plural(
                singular: "shell.music.status.saved.one",
                plural: "shell.music.status.saved.other",
                count: savedDiscoveries.count,
                savedDiscoveries.count
            )
        }

        if !visibleDiscoveries.isEmpty {
            return L10n.plural(
                singular: "shell.music.status.history.one",
                plural: "shell.music.status.history.other",
                count: visibleDiscoveries.count,
                visibleDiscoveries.count
            )
        }

        return L10n.string("shell.music.status.empty")
    }

    private var filteredDiscoveries: [DiscoveredTrack] {
        AppShellMusicLibrary.filteredDiscoveries(
            discoveries,
            mode: musicMode,
            query: query,
            selectedArtistName: selectedArtistName,
            historyStationID: historyStationFilter?.id
        )
    }

    private var filteredArtistSummaries: [DiscoveryArtistSummary] {
        AppShellMusicLibrary.filteredArtistSummaries(
            discoveries,
            mode: musicMode,
            query: query
        )
    }

    private var visibleArtistSummaries: [DiscoveryArtistSummary] {
        AppShellMusicLibrary.visibleArtistSummaries(discoveries)
    }

    private var discoveriesShareText: String {
        AppShellMusicLibrary.shareText(
            title: L10n.string("shell.library.discoveries.shareTitle"),
            discoveries: filteredDiscoveries
        )
    }

    private var emptyDiscoveryTitle: String {
        if visibleDiscoveries.isEmpty {
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
        case .history:
            return L10n.string("shell.library.discoveries.noMatch")
        }
    }

    private var emptyDiscoveryDetail: String {
        if visibleDiscoveries.isEmpty {
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
        case .history:
            return L10n.string("shell.library.discoveries.noMatch.detail")
        }
    }

    private func normalizeInitialDiscoveryFilter() {
        musicMode = AppShellMusicLibrary.normalizedInitialMode(
            musicMode,
            discoveries: discoveries,
            historyStationID: historyStationFilter?.id
        )
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
    let playAction: () -> Void
    let favoriteAction: () -> Void
    let detailsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroHeader

            HStack(alignment: .bottom, spacing: 18) {
                stationArtwork

                VStack(alignment: .leading, spacing: 14) {
                    stationText
                        .layoutPriority(1)
                    deskControls
                }
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

    private var stationArtwork: some View {
        StationThumbnailView(
            station: station,
            size: 128,
            animationOverlay: .none,
            isAnimationActive: false
        )
        .rotationEffect(.degrees(-1.2))
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(isPlaying ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: isPlaying ? "waveform" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(isPlaying ? TuneAVTheme.brandBlack : TuneAVTheme.highlight)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.72), lineWidth: 2)
                }
                .offset(x: 5, y: 6)
        }
    }

    private var stationText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.72)

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
            .accessibilityLabel(isFavorite ? L10n.string("player.discovery.unsave") : L10n.string("player.discovery.saveShort"))

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

            ZStack(alignment: .bottomTrailing) {
                Image("AviOnboardingHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300)
                    .opacity(0.22)
                    .offset(x: 50, y: 32)
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

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
    static let cardWidth: CGFloat = 112
    static let cardHeight: CGFloat = 164
    static let favoriteButtonSize: CGFloat = 30
    static let playBadgeSize: CGFloat = 36
    static let textLineHeight: CGFloat = 13
}

private struct StationCompactCarousel: View {
    let stations: [Station]
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
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
                        toggleFavorite: { toggleFavorite(station) },
                        playAction: { playStation(station, queueSource, queueStations) },
                        detailsAction: { showStationDetails(station, queueSource, queueStations) }
                    )
                    .frame(width: StationCompactMetrics.cardWidth)
                }
            }
            .padding(.horizontal, 1)
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

    private var compactSecondaryLine: String? {
        guard reliableArtist != nil else { return nil }
        return reliableTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                        size: StationCompactMetrics.cardWidth,
                        animationOverlay: .none,
                        isAnimationActive: false
                    )
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(isCurrentStationActive ? TuneAVTheme.highlight : TuneAVTheme.borderSubtle, lineWidth: isCurrentStationActive ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationRow.play.\(station.id)")

                favoriteButton
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(station.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
                    .frame(height: 15, alignment: .leading)

                Text(compactPrimaryLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(reliableArtist != nil || reliableTitle != nil ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.9))
                    .lineLimit(1)
                    .frame(height: 14, alignment: .leading)

                if let compactSecondaryLine {
                    Text(compactSecondaryLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.74))
                        .lineLimit(1)
                        .frame(height: 13, alignment: .leading)
                } else {
                    Color.clear
                        .frame(height: 13)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: detailsAction)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stationRow.\(station.id)")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: StationCompactMetrics.cardHeight, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: detailsAction)
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
        .accessibilityLabel(isFavorite ? L10n.string("player.menu.removeFavorite") : L10n.string("player.menu.addFavorite"))
        .accessibilityIdentifier("stationRow.favorite.\(station.id)")
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
    @Environment(\.dismiss) private var dismiss
    @State private var browserDestination: BrowserDestination?
    @State private var selectedTab: StationDetailTab = .profile

    let station: Station
    let isFavorite: Bool
    let isPlaying: Bool
    let playAction: () -> Void
    let toggleFavorite: () -> Void
    let stationHistoryAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        StationThumbnailView(
                            station: station,
                            size: 104,
                            animationOverlay: .none,
                            isAnimationActive: false
                        )
                            .overlay {
                                RoundedRectangle(cornerRadius: 25, style: .continuous)
                                    .stroke(isPlaying ? TuneAVTheme.highlight : TuneAVTheme.borderSubtle, lineWidth: isPlaying ? 2 : 1)
                            }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(station.name)
                                .font(.system(size: 28, weight: .black))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            if !station.primaryDetailLine.isEmpty {
                                Text(station.primaryDetailLine)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(TuneAVTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        Button {
                            playAction()
                            dismiss()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPlaying ? L10n.string("player.control.pause") : L10n.string("player.control.play"))
                        .accessibilityIdentifier("stationDetail.play")

                        Button(action: toggleFavorite) {
                            TuneAVSavedStationIcon(isSaved: isFavorite, size: 20)
                                .frame(width: 50, height: 50)
                                .background(
                                    isFavorite ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.elevatedSurface,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(isFavorite ? TuneAVTheme.highlight.opacity(0.22) : TuneAVTheme.borderSubtle, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? L10n.string("player.menu.removeFavorite") : L10n.string("player.menu.addFavorite"))

                        if let homepageURL {
                            Button {
                                browserDestination = BrowserDestination(url: homepageURL)
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(TuneAVTheme.textPrimary)
                                    .frame(width: 50, height: 50)
                                    .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.string("player.menu.openWebsite"))
                        }

                        Button {
                            stationHistoryAction()
                            dismiss()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                                .frame(width: 50, height: 50)
                                .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("player.menu.stationHistory"))
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(TuneAVTheme.cardSurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                )
                .shadow(color: TuneAVTheme.softShadow.opacity(0.22), radius: 12, y: 4)

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
            .padding(24)
            .padding(.bottom, 16)
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
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

        if !station.normalizedTags.isEmpty {
            DetailSection(title: L10n.string("shell.stationDetail.section.tags")) {
                WrapTagsRow(tags: station.normalizedTags)
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
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("shell.stationDetail.history.copy"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    stationHistoryAction()
                    dismiss()
                } label: {
                    Label(L10n.string("player.menu.stationHistory"), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
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
        guard let date = ISO8601DateFormatter().date(from: lastCheckOKAt) else { return lastCheckOKAt }
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
