import SwiftUI

struct AppShellView: View {
    let launchContext: LaunchContext
    let startSignInFlow: (Bool) -> Void

    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var languageController: AppLanguageController
    @EnvironmentObject private var libraryStore: LibraryStore

    @StateObject private var chromeActions = AppShellChromeActions()
    @State private var selectedTab: AppShellTab
    @State private var isShowingNowPlaying = false
    @State private var searchQuery: String
    @State private var searchTag: String?
    @State private var searchCountryCode: String?
    @State private var searchDiscoveryMode: TuneAVStationDiscoveryMode = .music
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
    @State private var enrichedStationsByID: [String: Station] = [:]
    @State private var stationNowPlayingTracks: [String: NowPlayingTrack] = [:]
    @State private var stationNowPlayingCache: [String: CachedStationNowPlaying] = [:]
    @State private var didBootstrap = false
    @State private var profileMode: ProfileScreen.Mode = .settings

    private let stationService = StationService()
    private let stationNowPlayingService = NowPlayingService()
    private let genreTags = TuneAVStationMusicClassifier.musicTags

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
            aviAction: {
                selectedTab = .avi
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
        .environmentObject(chromeActions)
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
            let currentDetail = selectedStationDetail ?? detail
            let station = enrichedStation(currentDetail.station)
            let queueStations = enrichedStations(currentDetail.queueStations)
            StationDetailSheet(
                station: station,
                stationDiscoveries: stationDiscoveries(for: station),
                isFavorite: favoriteStationIDs.contains(station.id),
                isPlaying: audioPlayer.isCurrent(station) && audioPlayer.isPlaying,
                stationFeedback: libraryStore.feedback(for: station),
                playAction: {
                    playStation(
                        station,
                        queueSource: currentDetail.queueSource,
                        queue: queueStations
                    )
                },
                toggleFavorite: { toggleFavorite(station) },
                setStationFeedback: { feedback in
                    libraryStore.setFeedback(feedback, for: station)
                }
            )
            .id(station.id)
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
        .task(id: languageController.currentLanguage.id) {
            await refreshHomeFeed()
            await refreshLibraryStationEnrichment()
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
                stations: enrichedStations(homeSnapshot.stations),
                isLoading: homeIsLoading,
                errorMessage: homeErrorMessage,
                recentStations: enrichedStations(homeSnapshot.recentStations),
                favoriteStations: enrichedStations(homeSnapshot.favoriteStations),
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
                    selectedTab = .avi
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
                showStationDetails: showStationDetails
            )
        case .search:
            SearchScreen(
                query: $searchQuery,
                activeTag: $searchTag,
                selectedCountryCode: $searchCountryCode,
                discoveryMode: $searchDiscoveryMode,
                results: enrichedStations(searchResults),
                isLoading: searchIsLoading,
                errorMessage: searchErrorMessage,
                tags: genreTags,
                focusRequest: searchFocusRequest,
                bottomContentPadding: shellScrollBottomPadding,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: stationNowPlayingTracks,
                stationFeedback: libraryStore.stationFeedback,
                playStation: playStation,
                toggleFavorite: toggleFavorite(_:),
                showStationDetails: showStationDetails
            )
        case .avi:
            AviScreen(
                currentStation: audioPlayer.currentStation,
                stations: enrichedStations(homeSnapshot.stations),
                recentStations: enrichedStations(recentStations),
                favoriteStations: enrichedStations(favoriteStations),
                discoveries: libraryStore.discoveries,
                stationFeedback: libraryStore.stationFeedback,
                feedContext: homeSnapshot.feedContext,
                preferredTag: libraryStore.settings.preferredTag,
                preferredCountryCode: libraryStore.settings.preferredCountry,
                bottomContentPadding: shellScrollBottomPadding,
                openSearch: {
                    selectedTab = .search
                    searchFocusRequest += 1
                },
                openLibrary: {
                    selectedTab = .library
                },
                openPlayer: {
                    isShowingNowPlaying = audioPlayer.currentStation != nil
                },
                playStation: { station, queue in
                    playStation(station, queueSource: .homeDiscovery, queue: queue)
                },
                setStationFeedback: { station, feedback in
                    libraryStore.setFeedback(feedback, for: station)
                },
                showStationDetails: { station, queue in
                    showStationDetails(station, queueSource: .homeDiscovery, queue: queue)
                }
            )
        case .library:
            LibraryScreen(
                favorites: enrichedStations(favoriteStations),
                recents: enrichedStations(recentStations),
                bottomContentPadding: shellScrollBottomPadding,
                favoriteStationIDs: favoriteStationIDs,
                nowPlayingTracks: stationNowPlayingTracks,
                stationFeedback: libraryStore.stationFeedback,
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
                mode: profileMode,
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

    private var searchRequest: AppShellSearchRequest {
        AppShellSearchRequest(query: searchQuery, tag: searchTag, countryCode: searchCountryCode, discoveryMode: searchDiscoveryMode)
    }

    private var shellScrollBottomPadding: CGFloat {
        // The footer is visually detached and floats above scroll content,
        // so scrollable screens need extra trailing space to bring the last row above it.
        audioPlayer.currentStation == nil ? 176 : 224
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
            searchResults: enrichedStations(searchResults),
            favoriteStations: enrichedFavoriteStations,
            recentStations: enrichedRecentStations,
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
        let resolvedStation = enrichedStation(station)
        let resolvedQueue = enrichedStations(queue ?? [resolvedStation])
        let playbackQueue = AudioPlayerService.PlaybackQueue(
            source: queueSource,
            stations: resolvedQueue
        )
        audioPlayer.play(station: resolvedStation, queue: playbackQueue)
        libraryStore.recordPlayback(of: resolvedStation, recentLimit: accessController.limits.recentStations)
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
        queue: [Station]? = nil
    ) {
        let resolvedStation = enrichedStation(station)
        let queueStations = enrichedStations(queue ?? [resolvedStation])
        selectedStationDetail = SelectedStationDetail(
            station: resolvedStation,
            queueSource: queueSource,
            queueStations: queueStations
        )
    }

    private func openStationHistory(_ station: Station) {
        selectedStationDetail = nil
        isShowingNowPlaying = false
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

        for station in stations where station.hasBackendEnrichment {
            let current = enrichedStationsByID[station.id]
            guard current == nil || station.enrichmentRank >= current!.enrichmentRank else { continue }
            enrichedStationsByID[station.id] = station
        }

        libraryStore.rememberStationSnapshots(stations)
    }

    private func refreshLibraryStationEnrichment() async {
        guard !launchContext.isUITesting else { return }

        let candidates = libraryEnrichmentCandidates()
        guard !candidates.isEmpty else { return }

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
                rememberBackendStations([enrichedMatch])
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
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

    private func openDiscoveryStation(_ discovery: DiscoveredTrack) {
        guard let station = libraryStore.station(for: discovery.stationID) else { return }

        playStation(station, queueSource: .libraryRecents, queue: enrichedRecentStations)
    }

    private func refreshHomeFeed(forceRemote: Bool = false) async {
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
            let feed = forceRemote
                ? try await homeFeed.refresh(preferredTag: libraryStore.settings.preferredTag)
                : try await homeFeed.load(preferredTag: libraryStore.settings.preferredTag)
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
        await refreshHomeFeed(forceRemote: true)
    }

    private func loadSearchResults() async {
        let request = searchRequest
        let requestKey = searchRequestKey

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
            searchResults = []
            searchErrorMessage = L10n.string("shell.error.search")
            searchIsLoading = false
        }
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
        station.id
    }
}

private struct AppShellScaffold<Content: View, FooterPlayer: View>: View {
    let selectedTab: AppShellTab
    let hasFooterPlayer: Bool
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
                }

                Image("AviV2HeadNeutral")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .shadow(color: TuneAVTheme.highlight.opacity(isSelected ? 0.24 : 0.08), radius: 6, y: 2)
            }
            .frame(width: 62, height: 62)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.avi.title"))
        .accessibilityIdentifier("tab.avi")
    }
}

private let shellScrollCoordinateSpace = "shellScrollCoordinateSpace"

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
    let currentStation: Station?
    let stations: [Station]
    let recentStations: [Station]
    let favoriteStations: [Station]
    let discoveries: [DiscoveredTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let feedContext: HomeFeedContext
    let preferredTag: String
    let preferredCountryCode: String
    let bottomContentPadding: CGFloat
    let openSearch: () -> Void
    let openLibrary: () -> Void
    let openPlayer: () -> Void
    let playStation: (Station, [Station]) -> Void
    let setStationFeedback: (Station, TuneAVStationFeedback?) -> Void
    let showStationDetails: (Station, [Station]) -> Void
    @State private var isHeaderVisible = true
    @State private var previousScrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShellScrollOffsetReader()
                ShellScrollAwareHeader(statusTitle: aviStateTitle, isVisible: isHeaderVisible)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("shell.avi.title"))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(aviSubtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                aviHero
                recommendationPanel
                quickActions
                localSignals
            }
            .padding(24)
            .padding(.bottom, bottomContentPadding)
        }
        .coordinateSpace(name: shellScrollCoordinateSpace)
        .scrollIndicators(.hidden)
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .onPreferenceChange(ShellScrollOffsetPreferenceKey.self) { offset in
            withAnimation(.snappy(duration: 0.22)) {
                isHeaderVisible = nextShellHeaderVisibility(
                    currentOffset: offset,
                    previousOffset: &previousScrollOffset,
                    currentVisibility: isHeaderVisible
                )
            }
        }
        .accessibilityIdentifier("avi.screen")
    }

    private var aviHero: some View {
        VStack(spacing: 18) {
            Image(aviAssetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 230)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityLabel(L10n.string("shell.avi.title"))

            VStack(spacing: 8) {
                Text(aviMoodLine)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(aviDetailLine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
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

    @ViewBuilder
    private var recommendationPanel: some View {
        if let recommendation = topRecommendation {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    StationThumbnailView(
                        station: recommendation.station,
                        size: 62,
                        animationOverlay: .none,
                        isAnimationActive: false
                    )

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
            Button(action: currentStation == nil ? openSearch : openPlayer) {
                Label(currentStation == nil ? L10n.string("shell.avi.action.findStation") : L10n.string("shell.avi.action.openPlayer"), systemImage: currentStation == nil ? "sparkles" : "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("avi.primaryAction")

            HStack(spacing: 12) {
                AviActionButton(title: L10n.string("tab.search"), systemImage: "magnifyingglass", action: openSearch)
                AviActionButton(title: L10n.string("shell.avi.action.saved"), systemImage: "heart.fill", action: openLibrary)
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
                detail: recentStations.isEmpty ? L10n.string("shell.avi.signals.recent.empty") : L10n.string("shell.avi.signals.recent.count", recentStations.count),
                systemImage: "clock.arrow.circlepath",
                accessibilityIdentifier: "avi.signals.recent"
            )

            AviSignalRow(
                title: L10n.string("shell.avi.signals.saved.title"),
                detail: favoriteStations.isEmpty ? L10n.string("shell.avi.signals.saved.empty") : L10n.string("shell.avi.signals.saved.count", favoriteStations.count),
                systemImage: "heart",
                accessibilityIdentifier: "avi.signals.saved"
            )

            AviSignalRow(
                title: L10n.string("shell.avi.signals.discoveries.title"),
                detail: recentDiscoveryCount == 0 ? L10n.string("shell.avi.signals.discoveries.empty") : L10n.string("shell.avi.signals.discoveries.count", recentDiscoveryCount),
                systemImage: "sparkles",
                accessibilityIdentifier: "avi.signals.discoveries"
            )

            AviSignalRow(
                title: L10n.string("shell.avi.signals.feedback.title"),
                detail: feedbackSignalCount == 0 ? L10n.string("shell.avi.signals.feedback.empty") : L10n.string("shell.avi.signals.feedback.count", feedbackSignalCount),
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
        currentStation == nil ? L10n.string("shell.avi.state.curious") : L10n.string("shell.avi.state.listening")
    }

    private var aviSubtitle: String {
        L10n.string("shell.avi.subtitle")
    }

    private var aviAssetName: String {
        currentStation == nil ? "AviV2Thinking" : "AviV2TuneHeadphones"
    }

    private var aviMoodLine: String {
        if let currentStation {
            return L10n.string("shell.avi.mood.listening", currentStation.name)
        }
        return recentStations.isEmpty ? L10n.string("shell.avi.mood.ready") : L10n.string("shell.avi.mood.thinking")
    }

    private var aviDetailLine: String {
        if currentStation != nil {
            return L10n.string("shell.avi.detail.listening")
        }
        return L10n.string("shell.avi.detail.ready")
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
                        .foregroundStyle(selectedFeedback == feedback ? TuneAVTheme.brandBlack : TuneAVTheme.textSecondary)
                        .frame(width: 34, height: 30)
                        .background(
                            selectedFeedback == feedback ? TuneAVTheme.highlight : TuneAVTheme.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(selectedFeedback == feedback ? TuneAVTheme.highlight.opacity(0.5) : TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feedback.localizedState)
                .accessibilityValue(selectedFeedback == feedback ? L10n.string("common.selected") : "")
                .accessibilityIdentifier("avi.recommendation.feedback.\(feedback.rawValue)")
            }

            if selectedFeedback != nil, let clearFeedback {
                Button(action: clearFeedback) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(TuneAVTheme.elevatedSurface, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.stationFeedback.clear"))
                .accessibilityIdentifier("avi.recommendation.feedback.clear")
            }
        }
        .accessibilityIdentifier("avi.recommendation.feedback")
    }
}

private struct HomeAviBrief: View {
    let currentStation: Station?
    let recentCount: Int
    let favoriteCount: Int
    let openAvi: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("AviV2HeadNeutral")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
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
            return L10n.string("shell.home.aviBrief.localSignals", recentCount, favoriteCount)
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
    @State private var isHeaderVisible = true
    @State private var previousScrollOffset: CGFloat = 0

    private enum FeaturedSource {
        case current
        case lastPlayed
        case recent
        case favorite
        case popular
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShellScrollOffsetReader()
                ShellScrollAwareHeader(
                    statusTitle: isLoading ? L10n.string("shell.status.refreshing") : (audioPlayer.currentStation == nil ? L10n.string("shell.status.live") : audioPlayer.status.label),
                    isVisible: isHeaderVisible
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
                    openAvi: openAvi
                )

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

                if !moodGenreTags.isEmpty {
                    HomeMoodGenreDesk(tags: moodGenreTags, selectTag: openSearchTag)
                }

                if !displayedAviPickStations.isEmpty {
                    StationSection(
                        title: L10n.string("shell.home.aviPicks.title"),
                        subtitle: L10n.string("shell.home.aviPicks.subtitle"),
                        accessibilityIdentifier: "home.section.aviPicks"
                    ) {
                        StationCompactCarousel(
                            stations: displayedAviPickStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            stationInsight: recommendationInsight,
                            stationFeedback: stationFeedback,
                            queueSource: .homeDiscovery,
                            queueStations: displayedAviPickStations,
                            playStation: playStation,
                            toggleFavorite: toggleFavorite,
                            showStationDetails: showStationDetails
                        )
                    }
                }

                if !displayedAroundYouStations.isEmpty {
                    StationSection(
                        title: L10n.string("shell.home.aroundYou.title"),
                        subtitle: L10n.string("shell.home.aroundYou.subtitle"),
                        accessibilityIdentifier: "home.section.aroundYou"
                    ) {
                        StationCompactCarousel(
                            stations: displayedAroundYouStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            stationInsight: recommendationInsight,
                            stationFeedback: stationFeedback,
                            queueSource: .homeDiscovery,
                            queueStations: displayedAroundYouStations,
                            playStation: playStation,
                            toggleFavorite: toggleFavorite,
                            showStationDetails: showStationDetails
                        )
                    }
                }

                if !displayedRecentStations.isEmpty || !displayedFavoriteStations.isEmpty {
                    StationSection(title: L10n.string("shell.home.recentsFavorites.title"), subtitle: L10n.string("shell.home.recentsFavorites.subtitle"), accessibilityIdentifier: "home.section.recentsFavorites") {
                        StationCompactCarousel(
                            stations: displayedRecentAndFavoriteStations,
                            favoriteStationIDs: favoriteStationIDs,
                            nowPlayingTracks: nowPlayingTracks,
                            stationInsight: { station in stationFeedback[station.id]?.localizedState },
                            stationFeedback: stationFeedback,
                            queueSource: .homeRecents,
                            queueStations: displayedRecentAndFavoriteStations,
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
        case .lastPlayed:
            return "Continue listening"
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

    private var displayedRecentStations: [Station] {
        Array(filteredStationsExcludingFeatured(from: recentStations).prefix(6))
    }

    private var displayedFavoriteStations: [Station] {
        Array(filteredStationsExcludingFeatured(from: favoriteStations).prefix(6))
    }

    private var displayedPopularStations: [Station] {
        let excludedIDs = Set(displayedRecentStations.map(\.id) + displayedFavoriteStations.map(\.id))

        let candidates = filteredStationsExcludingFeatured(from: stations)
            .filter { !excludedIDs.contains($0.id) }

        return recommendationScorer.rankedStations(candidates).map(\.station)
    }

    private var displayedAviPickStations: [Station] {
        Array(displayedPopularStations.prefix(4))
    }

    private var displayedAroundYouStations: [Station] {
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

    private var displayedRecentAndFavoriteStations: [Station] {
        Array(AppShellNowPlayingPreviews.uniqueStations(displayedRecentStations + displayedFavoriteStations).prefix(8))
    }

    private var moodGenreTags: [HomeMoodGenreSuggestion] {
        let sourceStations = [audioPlayer.currentStation].compactMap { $0 } + recentStations.prefix(8) + favoriteStations.prefix(8)
        let tagCounts = sourceStations
            .flatMap(\.normalizedTags)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { counts, tag in
                counts[tag, default: 0] += 1
            }

        let frequentTags = tagCounts
            .sorted { first, second in
                if first.value == second.value {
                    return first.key.localizedStandardCompare(second.key) == .orderedAscending
                }
                return first.value > second.value
            }
            .map(\.key)

        let preferred = preferredTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let combined = ([preferred] + frequentTags + visibleDiscoveryTags).filter { !$0.isEmpty }
        var seen = Set<String>()

        return combined
            .filter { seen.insert($0).inserted }
            .prefix(8)
            .map { tag in
                HomeMoodGenreSuggestion(
                    tag: tag,
                    title: L10n.genreLabel(for: tag).capitalized(with: L10n.locale)
                )
            }
    }

    private var visibleDiscoveryTags: [String] {
        displayedPopularStations
            .prefix(8)
            .flatMap(\.normalizedTags)
            .map { $0.lowercased() }
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

    private func recommendationInsight(for station: Station) -> String? {
        TuneAVLocalRecommendationScorer.localizedSummary(
            for: recommendationScorer.rank(station).primaryReason
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
            return "CONTINUE LISTENING"
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
    let focusRequest: Int
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var isShowingCountryPicker = false
    @State private var isHeaderVisible = true
    @State private var previousScrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ShellScrollOffsetReader()
                ShellScrollAwareHeader(
                    statusTitle: isLoading ? L10n.string("shell.search.status.searching") : L10n.string("shell.search.status.search"),
                    isVisible: isHeaderVisible
                )

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
                Picker(L10n.string("shell.search.discoveryMode"), selection: $discoveryMode) {
                    Text(L10n.string("shell.search.discoveryMode.music")).tag(TuneAVStationDiscoveryMode.music)
                    Text(L10n.string("shell.search.discoveryMode.allRadio")).tag(TuneAVStationDiscoveryMode.allRadio)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("search.discoveryMode")

                AviInlineBrief(
                    assetName: discoveryMode == .music ? "AviV2Thinking" : "AviV2HeadNeutral",
                    title: L10n.string("shell.search.avi.title"),
                    detail: searchAviDetail,
                    status: discoveryMode == .music ? L10n.string("shell.search.discoveryMode.music") : L10n.string("shell.search.discoveryMode.allRadio"),
                    accessibilityIdentifier: "search.aviBrief"
                )

                GenreTagStrip(tags: visibleTags, activeTag: activeTag, toggleTag: toggleTag)

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
                                        recommendationInsight: nil,
                                        stationFeedback: stationFeedback[station.id],
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
                                stationInsight: { _ in nil },
                                stationFeedback: stationFeedback,
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
        .coordinateSpace(name: shellScrollCoordinateSpace)
        .scrollIndicators(.hidden)
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .onPreferenceChange(ShellScrollOffsetPreferenceKey.self) { offset in
            withAnimation(.snappy(duration: 0.22)) {
                isHeaderVisible = nextShellHeaderVisibility(
                    currentOffset: offset,
                    previousOffset: &previousScrollOffset,
                    currentVisibility: isHeaderVisible
                )
            }
        }
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
            GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 12)
        ]
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

    private var selectedCountryFlag: String? {
        guard let selectedCountryCode else { return nil }
        return CountryOption(code: selectedCountryCode, name: selectedCountryTitle).flag
    }
}

private struct LibraryScreen: View {
    @State private var query = ""
    @State private var isSearchExpanded = false

    let favorites: [Station]
    let recents: [Station]
    let bottomContentPadding: CGFloat
    let favoriteStationIDs: Set<String>
    let nowPlayingTracks: [String: NowPlayingTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let playStation: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    let toggleFavorite: (Station) -> Void
    let showStationDetails: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]?) -> Void
    @State private var isHeaderVisible = true
    @State private var previousScrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShellScrollOffsetReader()
                ShellScrollAwareHeader(
                    statusTitle: favorites.isEmpty
                        ? L10n.string("shell.library.status.empty")
                        : L10n.plural(
                            singular: "shell.library.status.saved.one",
                            plural: "shell.library.status.saved.other",
                            count: favorites.count,
                            favorites.count
                        ),
                    isVisible: isHeaderVisible
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("shell.library.title"))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("shell.library.subtitle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                AviInlineBrief(
                    assetName: favorites.isEmpty ? "AviV2Thinking" : "AviV2HeadNeutral",
                    title: L10n.string("shell.library.avi.title"),
                    detail: libraryAviDetail,
                    status: favorites.isEmpty ? L10n.string("shell.avi.state.curious") : L10n.string("shell.avi.state.focused"),
                    accessibilityIdentifier: "library.aviBrief"
                )

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
                                    recommendationInsight: nil,
                                    stationFeedback: stationFeedback[station.id],
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
                                    recommendationInsight: nil,
                                    stationFeedback: stationFeedback[station.id],
                                    toggleFavorite: { toggleFavorite(station) },
                                    playAction: { playStation(station, .libraryRecents, recents) },
                                    detailsAction: { showStationDetails(station, .libraryRecents, recents) }
                                )
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SearchAccessRow(
                        title: "Find more stations",
                        detail: trimmedQuery.isEmpty ? "Search your saved and recent radios." : "Filtering collection for \(trimmedQuery).",
                        isExpanded: isSearchExpanded || !trimmedQuery.isEmpty,
                        action: {
                            withAnimation(.snappy(duration: 0.22)) {
                                isSearchExpanded.toggle()
                            }
                        }
                    )
                    .accessibilityIdentifier("library.searchAccess")

                    if isSearchExpanded || !trimmedQuery.isEmpty {
                        SearchField(query: $query, prompt: L10n.string("shell.library.searchPrompt"))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(24)
            .padding(.bottom, bottomContentPadding)
        }
        .coordinateSpace(name: shellScrollCoordinateSpace)
        .scrollIndicators(.hidden)
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .onPreferenceChange(ShellScrollOffsetPreferenceKey.self) { offset in
            withAnimation(.snappy(duration: 0.22)) {
                isHeaderVisible = nextShellHeaderVisibility(
                    currentOffset: offset,
                    previousOffset: &previousScrollOffset,
                    currentVisibility: isHeaderVisible
                )
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var stationGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 12)
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

    private var libraryAviDetail: String {
        if favorites.isEmpty && recents.isEmpty {
            return L10n.string("shell.library.avi.detail.empty")
        }
        return L10n.string("shell.library.avi.detail.signals", favorites.count, recents.count)
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
    @State private var isSearchExpanded = false
    @State private var isHeaderVisible = true
    @State private var previousScrollOffset: CGFloat = 0

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
                    ShellScrollOffsetReader()
                    ShellScrollAwareHeader(
                        statusTitle: musicStatusTitle,
                        isVisible: isHeaderVisible
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("shell.music.title"))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)

                        Text(L10n.string("shell.music.subtitle"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                    }

                    AviInlineBrief(
                        assetName: visibleDiscoveries.isEmpty ? "AviV2Thinking" : "AviV2TuneHeadphones",
                        title: L10n.string("shell.music.avi.title"),
                        detail: musicAviDetail,
                        status: visibleDiscoveries.isEmpty ? L10n.string("shell.avi.state.listening") : L10n.string("shell.avi.state.focused"),
                        accessibilityIdentifier: "music.aviBrief"
                    )

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
                    discoveryStationsSection

                    VStack(alignment: .leading, spacing: 12) {
                        SearchAccessRow(
                            title: L10n.string("shell.music.searchAccess.title"),
                            detail: trimmedQuery.isEmpty ? L10n.string("shell.music.searchAccess.detail.empty") : L10n.string("shell.music.searchAccess.detail.filtering", trimmedQuery),
                            isExpanded: isSearchExpanded || !trimmedQuery.isEmpty,
                            action: {
                                withAnimation(.snappy(duration: 0.22)) {
                                    isSearchExpanded.toggle()
                                }
                            }
                        )
                        .accessibilityIdentifier("music.searchAccess")

                        if isSearchExpanded || !trimmedQuery.isEmpty {
                            SearchField(query: $query, prompt: L10n.string("shell.music.searchPrompt"))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, bottomContentPadding)
            }
            .coordinateSpace(name: shellScrollCoordinateSpace)
            .scrollIndicators(.hidden)

            hiddenDiscoveryUndoBanner
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .onPreferenceChange(ShellScrollOffsetPreferenceKey.self) { offset in
            withAnimation(.snappy(duration: 0.22)) {
                isHeaderVisible = nextShellHeaderVisibility(
                    currentOffset: offset,
                    previousOffset: &previousScrollOffset,
                    currentVisibility: isHeaderVisible
                )
            }
        }
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

    @ViewBuilder
    private var discoveryStationsSection: some View {
        let stationSummaries = discoveryStationSummaries
        if !stationSummaries.isEmpty {
            StationSection(
                title: L10n.string("shell.music.discoveryStations.title"),
                subtitle: L10n.string("shell.music.discoveryStations.subtitle"),
                accessibilityIdentifier: "music.section.discoveryStations"
            ) {
                VStack(spacing: 10) {
                    ForEach(stationSummaries) { summary in
                        DiscoveryStationSourceRow(
                            summary: summary,
                            openStation: { openDiscoveryStation(summary.latestDiscovery) }
                        )
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

    private var discoveryStationSummaries: [DiscoveryStationSourceSummary] {
        Dictionary(grouping: visibleDiscoveries, by: \.stationID)
            .compactMap { stationID, discoveries in
                guard let latestDiscovery = discoveries.max(by: { $0.playedAt < $1.playedAt }) else {
                    return nil
                }

                return DiscoveryStationSourceSummary(
                    id: stationID,
                    name: latestDiscovery.stationName,
                    discoveryCount: discoveries.count,
                    latestDiscovery: latestDiscovery,
                    artworkURL: latestDiscovery.resolvedStationArtworkURL ?? latestDiscovery.resolvedArtworkURL
                )
            }
            .sorted { first, second in
                if first.discoveryCount == second.discoveryCount {
                    return first.latestDiscovery.playedAt > second.latestDiscovery.playedAt
                }

                return first.discoveryCount > second.discoveryCount
            }
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

    private var musicAviDetail: String {
        if visibleDiscoveries.isEmpty {
            return L10n.string("shell.music.avi.detail.empty")
        }
        if let strongestStation = strongestDiscoveryStationName {
            return L10n.string("shell.music.avi.detail.strongestStation", visibleDiscoveries.count, strongestStation)
        }
        return L10n.string("shell.music.avi.detail.summary", visibleDiscoveries.count, savedDiscoveries.count)
    }

    private var strongestDiscoveryStationName: String? {
        let counts = Dictionary(grouping: visibleDiscoveries, by: \.stationName)
            .mapValues(\.count)
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key
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
    let stationFeedback: TuneAVStationFeedback?
    let playAction: () -> Void
    let favoriteAction: () -> Void
    let feedbackAction: (TuneAVStationFeedback) -> Void
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
    static let cardWidth: CGFloat = 258
    static let cardHeight: CGFloat = 124
    static let artworkSize: CGFloat = 96
    static let favoriteButtonSize: CGFloat = 30
    static let playBadgeSize: CGFloat = 36
    static let textLineHeight: CGFloat = 13
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

    private var compactSecondaryLine: String? {
        guard reliableArtist != nil else { return recommendationInsight }
        return reliableTitle ?? recommendationInsight
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
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(isCurrentStationActive ? TuneAVTheme.highlight : TuneAVTheme.borderSubtle, lineWidth: isCurrentStationActive ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stationRow.play.\(station.id)")

                feedbackBadge
                    .padding(.leading, 6)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                favoriteButton
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(station.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(compactPrimaryLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(reliableArtist != nil || reliableTitle != nil ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let compactSecondaryLine {
                    Text(compactSecondaryLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.74))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: StationCompactMetrics.artworkSize, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(perform: detailsAction)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stationRow.\(station.id)")
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: StationCompactMetrics.cardHeight, alignment: .top)
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
    private var feedbackBadge: some View {
        if let stationFeedback {
            Image(systemName: stationFeedback.systemImage)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(stationFeedback == .liked ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse)
                .frame(width: 24, height: 24)
                .background(stationFeedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.82), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.76), lineWidth: 1)
                }
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
    let stationDiscoveries: [DiscoveredTrack]
    let isFavorite: Bool
    let isPlaying: Bool
    let stationFeedback: TuneAVStationFeedback?
    let playAction: () -> Void
    let toggleFavorite: () -> Void
    let setStationFeedback: (TuneAVStationFeedback?) -> Void

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
                            withAnimation(.snappy(duration: 0.24)) {
                                selectedTab = .history
                            }
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

private struct StationFeedbackControl: View {
    let selectedFeedback: TuneAVStationFeedback?
    let selectFeedback: (TuneAVStationFeedback) -> Void
    let clearFeedback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.string("shell.stationFeedback.title"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)

                Spacer()

                if selectedFeedback != nil {
                    Button(action: clearFeedback) {
                        Label(L10n.string("shell.stationFeedback.clear"), systemImage: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stationFeedback.clear")
                }
            }

            HStack(spacing: 8) {
                StationFeedbackButton(
                    title: L10n.string("shell.stationFeedback.like"),
                    systemImage: "hand.thumbsup.fill",
                    feedback: .liked,
                    isSelected: selectedFeedback == .liked,
                    action: { selectFeedback(.liked) }
                )

                StationFeedbackButton(
                    title: L10n.string("shell.stationFeedback.notForMe"),
                    systemImage: "minus.circle.fill",
                    feedback: .notForMe,
                    isSelected: selectedFeedback == .notForMe,
                    action: { selectFeedback(.notForMe) }
                )

                StationFeedbackButton(
                    title: L10n.string("shell.stationFeedback.dislike"),
                    systemImage: "hand.thumbsdown.fill",
                    feedback: .disliked,
                    isSelected: selectedFeedback == .disliked,
                    action: { selectFeedback(.disliked) }
                )
            }
        }
        .accessibilityIdentifier("stationFeedback.control")
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
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
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
