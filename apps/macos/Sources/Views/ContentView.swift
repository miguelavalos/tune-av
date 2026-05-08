import SwiftUI

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var accountController: MacAccountController
    @EnvironmentObject private var languageController: AppLanguageController

    @State private var selectedSection: SidebarSection = .home
    @State private var musicHistoryStationFilter: Station?
    @State private var selectedStation: Station?
    @State private var searchQuery = ""
    @State private var searchResults: [Station] = []
    @State private var homeFeedContext: HomeFeedContext = .popularWorldwide
    @State private var isClearingLocalData = false
    @State private var isShowingClearLocalDataAlert = false
    @State private var isShowingGuestOnboarding = false
    @State private var searchIsLoading = false
    @State private var searchErrorMessage: String?
    @State private var activeSearchTag: String?
    @State private var selectedCountryCode: String?
    @State private var detailStation: Station?
    @State private var isShowingAccountDeletion = false
    @AppStorage("tuneav.mac.appearance") private var appearanceMode = "system"
    @AppStorage("tuneav.mac.launchToSearch") private var launchToSearch = false

    private let stationService = StationService()
    private let genreTags = ["ambient", "rock", "pop", "jazz", "news", "electronic"]
    private let launchContext = MacLaunchContext.current

    private var appSearch: AppShellSearch {
        AppShellSearch(
            stationService: stationService,
            resolvedDeviceCountryCode: resolvedDeviceCountryCode,
            hasResolvedCountry: hasResolvedCountry(_:)
        )
    }

    private var homeFeed: AppShellHomeFeed {
        AppShellHomeFeed(
            stationService: stationService,
            localizedCountryName: L10n.countryName(for:),
            resolvedDeviceCountryCode: resolvedDeviceCountryCode
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
        } content: {
            currentScreen
                .navigationSplitViewColumnWidth(min: 620, ideal: 760)
                .background(TuneAVTheme.shellBackground)
        } detail: {
            DesktopPlayerInspector(
                selectedStation: selectedStation,
                playAction: play,
                playPreviousAction: playPreviousStation,
                playNextAction: playNextStation,
                canCycleStations: audioPlayer.canCyclePlaybackQueue,
                toggleFavorite: { station in libraryStore.toggleFavorite(station) },
                isFavorite: libraryStore.isFavorite,
                stationHistoryAction: openStationHistory
            )
            .environmentObject(audioPlayer)
            .environmentObject(libraryStore)
            .navigationSplitViewColumnWidth(min: 380, ideal: 400, max: 460)
        }
        .navigationTitle(selectedSection.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    selectedSection = .search
                } label: {
                    Label(L10n.string("tab.search"), systemImage: "magnifyingglass")
                }

                Button {
                    if audioPlayer.currentStation == nil, let station = selectedStation {
                        play(station)
                    } else {
                        audioPlayer.togglePlayback()
                    }
                } label: {
                    Label(playbackToolbarTitle, systemImage: playbackToolbarSymbol)
                }
                .disabled(audioPlayer.currentStation == nil && selectedStation == nil)
            }
        }
        .sheet(item: $detailStation) { station in
            StationDetailSheet(
                station: station,
                isFavorite: libraryStore.isFavorite(station),
                isPlaying: audioPlayer.isCurrent(station) && audioPlayer.isPlaying,
                playAction: { play(station) },
                toggleFavorite: { libraryStore.toggleFavorite(station) },
                stationHistoryAction: { openStationHistory(station) }
            )
            .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(item: $libraryStore.upgradePrompt) { context in
            UpgradePromptSheet(
                context: context,
                accountConnectionState: libraryStore.accountConnectionState,
                primaryActionTitle: MacAppConfig.accountManagementURL == nil ? L10n.string("mac.profile.open") : L10n.string("mac.accountDeletion.openManagement"),
                primaryAction: {
                    libraryStore.upgradePrompt = nil
                    if let accountManagementURL = MacAppConfig.accountManagementURL {
                        openURL(accountManagementURL)
                    } else {
                        selectedSection = .profile
                    }
                },
                dismissAction: {
                    libraryStore.upgradePrompt = nil
                }
            )
        }
        .sheet(isPresented: $isShowingAccountDeletion) {
            MacAccountDeletionSheet(viewModel: accountDeletionViewModel)
        }
        .sheet(isPresented: $isShowingGuestOnboarding) {
            MacAuthOnboardingSheet(
                accountIsAvailable: accountController.isAvailable,
                isAuthenticating: accountController.isAuthenticating,
                errorMessage: accountController.errorMessage,
                onContinueWithApple: {
                    Task { await signInWithAppleFromOnboarding() }
                },
                onContinueWithGoogle: {
                    Task { await signInWithGoogleFromOnboarding() }
                },
                onSkip: {
                    accountController.skipForNow()
                    isShowingGuestOnboarding = false
                }
            )
        }
        .alert(clearLibraryAlertTitle, isPresented: $isShowingClearLocalDataAlert) {
            Button(L10n.string("profile.alert.clearData.cancel"), role: .cancel) {}
            Button(clearLibraryConfirmTitle, role: .destructive) {
                clearLibraryDataFromProfile()
            }
        } message: {
            Text(clearLibraryAlertMessage)
        }
        .task {
            selectedStation = libraryStore.recents.first ?? Station.samples.first
            selectedCountryCode = libraryStore.preferredCountryCode
            audioPlayer.setSleepTimer(minutes: libraryStore.sleepTimerMinutes)
            seedUITestDataIfNeeded()
            if let preferredSearchQuery = launchContext.preferredSearchQuery {
                searchQuery = preferredSearchQuery
                selectedSection = .search
                activeSearchTag = nil
            } else if let preferredTab = launchContext.preferredTab {
                applyPreferredLaunchTab(preferredTab)
            } else if launchToSearch {
                selectedSection = .search
                activeSearchTag = libraryStore.preferredTag
            }
            if let demoStation = launchContext.demoStation {
                libraryStore.ensureSeededStation(demoStation, favorite: launchContext.seedFavorite)
                play(demoStation)
                applyUITestTrackMetadataIfNeeded()
            }
            if launchContext.isUITesting, let feature = launchContext.uiTestUpgradePromptFeature {
                libraryStore.presentUpgradePrompt(for: feature)
            }
            presentAutomaticGuestOnboardingIfNeeded()
            await loadHomeFeedIfNeeded()
        }
        .onChange(of: libraryStore.sleepTimerMinutes) { _, minutes in
            audioPlayer.setSleepTimer(minutes: minutes)
        }
        .onChange(of: libraryStore.preferredTag) { _, _ in
            Task {
                searchResults = []
                await loadHomeFeedIfNeeded()
            }
        }
        .onChange(of: accountController.currentUser) { _, _ in
            Task {
                if accountController.isSignedIn {
                    isShowingGuestOnboarding = false
                }
                await libraryStore.configureBackendClients(
                    tokenProvider: accountController.currentToken,
                    refreshCloudLibrary: true
                )
            }
        }
        .onChange(of: selectedSection) { _, newValue in
            if newValue == .search {
                Task { await performSearch(force: true) }
            }
        }
        .onChange(of: currentTrackDiscoveryKey) { _, _ in
            guard
                let station = audioPlayer.currentStation,
                audioPlayer.currentTrackTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else {
                return
            }

            libraryStore.recordDiscoveredTrack(
                title: audioPlayer.currentTrackTitle,
                artist: audioPlayer.currentTrackArtist,
                station: station,
                artworkURL: audioPlayer.currentTrackArtworkURL
            )
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section(L10n.string("mac.sidebar.browse")) {
                    ForEach([SidebarSection.home, .search, .library, .music]) { section in
                        SidebarSectionRow(section: section, detail: sidebarDetail(for: section))
                            .tag(section)
                    }
                }

                Section(L10n.string("profile.account.title")) {
                    SidebarSectionRow(section: .profile, detail: libraryStore.accountConnectionState.title)
                        .tag(SidebarSection.profile)
                }
            }
            .listStyle(.sidebar)

            sidebarNowPlaying
            sidebarFooter
        }
        .id(languageController.currentLanguage)
    }

    @ViewBuilder
    private var sidebarNowPlaying: some View {
        if let currentStation = audioPlayer.currentStation {
            Divider()

            Button {
                selectedStation = currentStation
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("player.header.nowPlaying"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    SidebarNowPlayingRow(station: currentStation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selectedSection {
        case .home:
            HomeView(
                stations: searchResults.isEmpty ? Station.samples : searchResults,
                isLoading: searchIsLoading && searchResults.isEmpty,
                errorMessage: searchErrorMessage,
                favorites: libraryStore.favorites,
                recents: libraryStore.recents,
                feedContext: homeFeedContext,
                playAction: play,
                toggleFavorite: { station in libraryStore.toggleFavorite(station) },
                showDetails: showStationDetails
            )
        case .search:
            SearchView(
                query: $searchQuery,
                activeTag: $activeSearchTag,
                selectedCountryCode: $selectedCountryCode,
                results: searchResults,
                isLoading: searchIsLoading,
                errorMessage: searchErrorMessage,
                genreTags: genreTags,
                playAction: play,
                toggleFavorite: { station in libraryStore.toggleFavorite(station) },
                isFavorite: libraryStore.isFavorite,
                showDetails: showStationDetails,
                searchAction: { Task { await performSearch(force: true) } }
            )
        case .library:
            LibraryView(
                favorites: libraryStore.favorites,
                recents: libraryStore.recents,
                limits: libraryStore.limits,
                playAction: play,
                toggleFavorite: { station in libraryStore.toggleFavorite(station) },
                showDetails: showStationDetails
            )
        case .music:
            MusicView(
                discoveries: libraryStore.discoveries,
                historyStationFilter: $musicHistoryStationFilter,
                limits: libraryStore.limits,
                openStation: openDiscoveryStation,
                toggleSaved: { discovery in
                    libraryStore.toggleDiscoverySaved(discovery)
                },
                hideDiscovery: libraryStore.hideDiscovery,
                restoreDiscovery: libraryStore.restoreDiscovery,
                removeDiscovery: libraryStore.removeDiscovery,
                shareDiscoveries: { self.shareDiscoveries($0) },
                clearDiscoveries: libraryStore.clearDiscoveries,
                useDailyFeature: libraryStore.useDailyFeatureIfAllowed(_:usageKey:)
            )
        case .profile:
            ProfileView(
                preferredTag: Binding(
                    get: { libraryStore.preferredTag },
                    set: { libraryStore.updatePreferredTag($0) }
                ),
                accessMode: Binding(
                    get: { libraryStore.accessMode },
                    set: { libraryStore.updateAccessMode($0) }
                ),
                capabilities: libraryStore.capabilities,
                planTier: libraryStore.planTier,
                accountConnectionState: libraryStore.accountConnectionState,
                limits: libraryStore.limits,
                favoritesUsage: libraryStore.favoritesUsage,
                recentsUsage: libraryStore.recentsUsage,
                discoveriesUsage: libraryStore.discoveriesUsage,
                savedTracksUsage: libraryStore.savedTracksUsage,
                lyricsUsage: libraryStore.dailyUsage(for: .lyricsSearch),
                webUsage: libraryStore.dailyUsage(for: .webSearch),
                youtubeUsage: libraryStore.dailyUsage(for: .youtubeSearch),
                appleMusicUsage: libraryStore.dailyUsage(for: .appleMusicSearch),
                spotifyUsage: libraryStore.dailyUsage(for: .spotifySearch),
                discoveryShareUsage: libraryStore.dailyUsage(for: .discoveryShare),
                cloudSyncStatus: libraryStore.cloudSyncStatus,
                cloudSyncConflictSummary: libraryStore.cloudSyncConflictSummary,
                cloudSyncFailureTitle: libraryStore.cloudSyncFailureTitle,
                backendConnectionStatus: libraryStore.backendConnectionStatus,
                backendConnectionFailureTitle: libraryStore.backendConnectionFailureTitle,
                cloudSyncReadinessTitle: libraryStore.cloudSyncReadinessTitle,
                cloudSyncBlockerDescription: libraryStore.cloudSyncBlockerDescription,
                accessModeIsBackendManaged: libraryStore.accessModeIsBackendManaged,
                accessModeSourceTitle: libraryStore.accessModeSourceTitle,
                isCloudSyncConfigured: libraryStore.isCloudSyncConfigured,
                canRunCloudSync: libraryStore.canRunCloudSync,
                canRetryBackendConnection: libraryStore.canRetryBackendConnection,
                canClearCloudSyncStatus: libraryStore.canClearCloudSyncStatus,
                canResolveCloudConflict: libraryStore.canResolveCloudConflict,
                accountUserDisplayName: accountController.currentUser?.displayName,
                accountUserEmail: accountController.currentUser?.emailAddress,
                accountIsAvailable: accountController.isAvailable,
                accountIsSignedIn: accountController.isSignedIn,
                accountIsAuthenticating: accountController.isAuthenticating,
                accountErrorMessage: accountController.errorMessage,
                accountManagementURL: MacAppConfig.accountManagementURL,
                isClearingLocalData: isClearingLocalData,
                clearActionTitle: clearLibraryActionTitle,
                clearAction: {
                    isShowingClearLocalDataAlert = true
                },
                signInWithAppleAction: {
                    Task {
                        await signInWithAppleFromOnboarding()
                    }
                },
                signInWithGoogleAction: {
                    Task {
                        await signInWithGoogleFromOnboarding()
                    }
                },
                signOutAction: {
                    Task {
                        if await accountController.signOut() {
                            libraryStore.handleAccountSignedOut()
                        }
                    }
                },
                deleteAccountAction: {
                    isShowingAccountDeletion = true
                },
                retryBackendAction: {
                    Task {
                        await libraryStore.retryBackendConnection()
                    }
                },
                syncAction: {
                    Task {
                        await libraryStore.refreshCloudLibraryIfNeeded()
                    }
                },
                useCloudAction: {
                    Task {
                        await libraryStore.replaceLocalLibraryWithCloudData()
                    }
                },
                overwriteCloudAction: {
                    Task {
                        await libraryStore.overwriteCloudLibraryWithLocalData()
                    }
                },
                clearSyncStatusAction: libraryStore.clearCloudSyncStatus
            )
        }
    }

    private var accountDeletionViewModel: MacAccountDeletionViewModel {
        MacAccountDeletionViewModel(
            api: accountDeletionAPI,
            signOut: {
                let didSignOut = await accountController.signOut()
                if didSignOut {
                    libraryStore.handleAccountSignedOut()
                }
                return didSignOut
            }
        )
    }

    private func presentAutomaticGuestOnboardingIfNeeded() {
        guard !launchContext.shouldDisableOnboarding else { return }
        guard accountController.shouldAutoShowGuestOnboarding else { return }

        isShowingGuestOnboarding = true
        accountController.markGuestOnboardingPromptShown()
    }

    private func signInWithAppleFromOnboarding() async {
        if await accountController.signInWithApple() {
            isShowingGuestOnboarding = false
            await libraryStore.configureBackendClients(
                tokenProvider: accountController.currentToken,
                refreshCloudLibrary: true
            )
        }
    }

    private func signInWithGoogleFromOnboarding() async {
        if await accountController.signInWithGoogle() {
            isShowingGuestOnboarding = false
            await libraryStore.configureBackendClients(
                tokenProvider: accountController.currentToken,
                refreshCloudLibrary: true
            )
        }
    }

    private var shouldClearSyncedLibrary: Bool {
        libraryStore.capabilities.canUseCloudSync
    }

    private var clearLibraryActionTitle: String {
        if isClearingLocalData {
            return shouldClearSyncedLibrary
                ? L10n.string("profile.actions.clearingSyncedLibrary")
                : L10n.string("profile.actions.clearingData")
        }
        return shouldClearSyncedLibrary
            ? L10n.string("profile.actions.clearSyncedLibrary")
            : L10n.string("profile.actions.clearData")
    }

    private var clearLibraryAlertTitle: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.alert.clearSyncedLibrary.title")
            : L10n.string("profile.alert.clearData.title")
    }

    private var clearLibraryAlertMessage: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.alert.clearSyncedLibrary.message")
            : L10n.string("profile.alert.clearData.message")
    }

    private var clearLibraryConfirmTitle: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.alert.clearSyncedLibrary.confirm")
            : L10n.string("profile.alert.clearData.confirm")
    }

    private func clearLibraryDataFromProfile() {
        guard isClearingLocalData == false else { return }
        isClearingLocalData = true
        libraryStore.clearLocalData(propagatesToCloud: shouldClearSyncedLibrary)
        if libraryStore.accessMode == .guest {
            selectedSection = .profile
        }
        isClearingLocalData = false
    }

    private var accountDeletionAPI: MacAccountDeletionAPI {
        if let uiTestAPI = MacUITestAccountDeletionAPI.fromEnvironment() {
            return uiTestAPI
        }
        return MacAccountAPIClient(getToken: accountController.currentToken)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(libraryStore.accountConnectionState.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)

            Text(sidebarLibrarySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private var sidebarLibrarySummary: String {
        let favoritesText = L10n.plural(
            singular: "mac.sidebar.favorite.one",
            plural: "mac.sidebar.favorite.other",
            count: libraryStore.favorites.count,
            libraryStore.favorites.count
        )
        let savedTrackCount = libraryStore.discoveries.filter(\.isMarkedInteresting).count
        let savedText = L10n.plural(
            singular: "mac.sidebar.savedTrack.one",
            plural: "mac.sidebar.savedTrack.other",
            count: savedTrackCount,
            savedTrackCount
        )
        return "\(favoritesText) · \(savedText)"
    }

    private var playbackToolbarTitle: String {
        switch audioPlayer.playbackState {
        case .idle:
            return L10n.string("player.control.play")
        case .loading:
            return L10n.string("mac.player.status.connecting")
        case .playing:
            return L10n.string("player.control.pause")
        case .paused:
            return L10n.string("mac.player.status.resume")
        case .failed:
            return L10n.string("player.retry")
        }
    }

    private var playbackToolbarSymbol: String {
        switch audioPlayer.playbackState {
        case .playing:
            return "pause.fill"
        case .loading:
            return "dot.radiowaves.left.and.right"
        case .idle, .paused, .failed:
            return "play.fill"
        }
    }

    private func sidebarDetail(for section: SidebarSection) -> String {
        switch section {
        case .home:
            return audioPlayer.currentStation == nil ? L10n.string("mac.sidebar.liveFeed") : L10n.string("mac.sidebar.listening")
        case .search:
            return activeSearchTag.map(L10n.genreLabel(for:)) ?? L10n.string("mac.sidebar.stations")
        case .library:
            return L10n.plural(
                singular: "mac.sidebar.saved.one",
                plural: "mac.sidebar.saved.other",
                count: libraryStore.favorites.count,
                libraryStore.favorites.count
            )
        case .music:
            let savedTrackCount = libraryStore.discoveries.filter { discovery in
                discovery.isMarkedInteresting && !discovery.isHidden
            }.count
            return L10n.plural(
                singular: "mac.sidebar.savedTrack.one",
                plural: "mac.sidebar.savedTrack.other",
                count: savedTrackCount,
                savedTrackCount
            )
        case .profile:
            return libraryStore.accessMode.title
        }
    }

    private func showStationDetails(_ station: Station) {
        selectedStation = station
        detailStation = station
    }

    private func openStationHistory(_ station: Station) {
        detailStation = nil
        musicHistoryStationFilter = station
        selectedSection = .music
    }

    private func loadHomeFeedIfNeeded() async {
        guard searchResults.isEmpty else { return }

        searchIsLoading = true
        searchErrorMessage = nil

        if launchContext.isUITesting && launchContext.shouldUseLocalUITestDiscovery {
            searchResults = Array(Station.samples.prefix(8))
            homeFeedContext = .popularWorldwide
            searchIsLoading = false
            return
        }

        do {
            let feed = try await homeFeed.load(preferredTag: libraryStore.preferredTag)
            searchResults = feed.stations
            homeFeedContext = feed.context
            searchIsLoading = false
        } catch is CancellationError {
            searchIsLoading = false
        } catch {
            let editorialStations = AppShellHomeFeed.defaultEditorialStations(
                currentStation: audioPlayer.currentStation,
                recentStations: libraryStore.recentStations(),
                favoriteStations: libraryStore.favoriteStations()
            )
            searchResults = editorialStations
            homeFeedContext = .popularWorldwide
            searchErrorMessage = editorialStations.isEmpty ? L10n.string("shell.error.home") : nil
            searchIsLoading = false
        }
    }

    private func applyPreferredLaunchTab(_ tab: MacLaunchContext.Tab) {
        switch tab {
        case .search:
            selectedSection = .search
        case .library:
            selectedSection = .library
        case .music:
            selectedSection = .music
        case .settings:
            selectedSection = .profile
        case .player:
            if let lastStation = libraryStore.station(for: libraryStore.lastPlayedStationID) ?? selectedStation {
                play(lastStation)
            }
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
            libraryStore.recordPlayback(of: station)
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

    private func applyUITestTrackMetadataIfNeeded() {
        guard launchContext.isUITesting else { return }
        guard launchContext.uiTestTrackTitle != nil || launchContext.uiTestTrackArtist != nil else { return }
        audioPlayer.applyUITestTrackMetadata(
            title: launchContext.uiTestTrackTitle,
            artist: launchContext.uiTestTrackArtist
        )
    }

    private func play(_ station: Station) {
        selectedStation = station
        libraryStore.recordPlayback(of: station)
        audioPlayer.play(
            station: station,
            queue: AudioPlayerService.PlaybackQueue(
                source: searchResults.isEmpty ? .libraryRecents : .searchResults,
                stations: currentStationQueue
            )
        )
    }

    private var currentStationQueue: [Station] {
        let source = searchResults.isEmpty ? (libraryStore.recents.isEmpty ? Station.samples : libraryStore.recents) : searchResults
        var seen: Set<String> = []
        return source.filter { station in
            guard !seen.contains(station.id) else { return false }
            seen.insert(station.id)
            return true
        }
    }

    private func playPreviousStation() {
        guard audioPlayer.canCyclePlaybackQueue else { return }
        audioPlayer.playPreviousInQueue()
        recordCurrentPlayback()
    }

    private func playNextStation() {
        guard audioPlayer.canCyclePlaybackQueue else { return }
        audioPlayer.playNextInQueue()
        recordCurrentPlayback()
    }

    private func recordCurrentPlayback() {
        guard let station = audioPlayer.currentStation else { return }
        selectedStation = station
        libraryStore.recordPlayback(of: station)
    }

    private func openDiscoveryStation(_ discovery: DiscoveredTrack) {
        guard let station = libraryStore.station(for: discovery.stationID) else { return }
        selectedSection = .music
        play(station)
    }

    private func shareDiscoveries(_ discoveries: [DiscoveredTrack]) {
        let shareText = DiscoveryShareTextFormatter.text(for: discoveries)
        guard !shareText.isEmpty,
              libraryStore.useDailyFeatureIfAllowed(.discoveryShare, usageKey: shareText) else { return }
        let picker = NSSharingServicePicker(items: [shareText])
        guard let contentView = NSApp.keyWindow?.contentView else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(shareText, forType: .string)
            return
        }
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }

    private func performSearch(initial: Bool = false, force: Bool = false) async {
        let request = searchRequest()
        let requestKey = request.key

        if !force, !initial, request.query.isEmpty, selectedSection != .home, request.tag == nil, request.countryCode == nil {
            searchResults = []
            return
        }

        searchIsLoading = true
        searchErrorMessage = nil

        if launchContext.isUITesting && launchContext.shouldUseLocalUITestSearch {
            searchResults = AppShellSearch.localUITestSearchResults(request: request)
            searchErrorMessage = nil
            searchIsLoading = false
            return
        }

        do {
            let results = try await appSearch.load(
                request: request,
                recentStations: libraryStore.recentStations(),
                favoriteStations: libraryStore.favoriteStations()
            )
            guard requestKey == searchRequest().key else { return }
            searchResults = results.isEmpty ? Station.samples : results
            if initial, request.query.isEmpty, let tag = request.tag, !tag.isEmpty {
                homeFeedContext = .preferredGenre(tag)
            } else if initial {
                homeFeedContext = request.countryCode.map(HomeFeedContext.popularInCountry) ?? .popularWorldwide
            }
        } catch {
            guard requestKey == searchRequest().key else { return }
            searchResults = Station.samples
            if initial, request.query.isEmpty, let tag = request.tag, !tag.isEmpty {
                homeFeedContext = .preferredGenre(tag)
            } else if initial {
                homeFeedContext = .popularWorldwide
            }
            searchErrorMessage = error.localizedDescription
        }

        searchIsLoading = false
    }

    private func searchRequest() -> AppShellSearchRequest {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = activeSearchTag ?? (trimmedQuery.isEmpty ? libraryStore.preferredTag : nil)
        return AppShellSearchRequest(query: trimmedQuery, tag: tag, countryCode: selectedCountryCode)
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

    private var currentTrackDiscoveryKey: String {
        [
            audioPlayer.currentStation?.id ?? "",
            audioPlayer.currentTrackArtist ?? "",
            audioPlayer.currentTrackTitle ?? "",
            audioPlayer.currentTrackArtworkURL?.absoluteString ?? ""
        ].joined(separator: "|")
    }

    private var preferredColorScheme: ColorScheme? {
        (AppTheme(rawValue: appearanceMode) ?? .system).preferredColorScheme
    }
}

private struct SidebarSectionRow: View {
    let section: SidebarSection
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SidebarNowPlayingRow: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let station: Station

    var body: some View {
        HStack(spacing: 10) {
            StationThumbnailView(station: station, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .lineLimit(1)

                Text(audioPlayer.isPlaying ? L10n.string("player.track.liveNow") : L10n.string("audio.status.paused"))
                    .font(.caption)
                    .foregroundStyle(audioPlayer.isPlaying ? TuneAVTheme.highlight : .secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct DesktopPlayerInspector: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    let selectedStation: Station?
    let playAction: (Station) -> Void
    let playPreviousAction: () -> Void
    let playNextAction: () -> Void
    let canCycleStations: Bool
    let toggleFavorite: (Station) -> Void
    let isFavorite: (Station) -> Bool
    let stationHistoryAction: (Station) -> Void

    private var displayStation: Station? {
        audioPlayer.currentStation ?? selectedStation
    }

    var body: some View {
        VStack(spacing: 0) {
            if let station = displayStation {
                stationPanel(station)
            } else {
                EmptyStateCard(title: L10n.string("player.track.pickStation"), detail: L10n.string("player.empty"))
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    TuneAVTheme.neutral100.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func stationPanel(_ station: Station) -> some View {
        VStack(spacing: 0) {
            if let errorMessage = audioPlayer.lastErrorMessage, audioPlayer.isCurrent(station) {
                PlayerErrorBanner(message: errorMessage)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
            }

            heroPanel(station)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heroPanel(_ station: Station) -> some View {
        VStack(spacing: 18) {
            DesktopPlayerArtwork(
                station: station,
                trackArtworkURL: audioPlayer.currentTrackArtworkURL,
                trackTitle: normalized(audioPlayer.currentTrackTitle),
                trackArtist: normalized(audioPlayer.currentTrackArtist),
                isDiscoverableTrack: hasDiscoverableTrack,
                isCurrentTrackSaved: isCurrentTrackSaved(station),
                isLoading: audioPlayer.isCurrent(station) && audioPlayer.playbackState == .loading,
                isFavorite: isFavorite(station),
                onSaveDiscovery: { saveCurrentDiscovery(for: station) },
                onShareDiscovery: { shareCurrentDiscovery(for: station) },
                onOpenYouTube: {
                    openExternalSearch(.youtubeSearch, destination: .youtube)
                },
                onOpenLyrics: {
                    openExternalSearch(.lyricsSearch, destination: .web, suffix: "lyrics")
                },
                onOpenArtist: {
                    openArtistSearch(destination: .web, feature: .webSearch)
                },
                onOpenArtistYouTube: {
                    openArtistSearch(destination: .youtube, feature: .youtubeSearch)
                },
                onTogglePlayback: {
                    if audioPlayer.isCurrent(station) {
                        audioPlayer.togglePlayback()
                    } else {
                        playAction(station)
                    }
                },
                onToggleFavorite: { toggleFavorite(station) },
                onOpenWebsite: {
                    if let homepageURL = station.resolvedHomepageURL {
                        openURL(homepageURL)
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.16), radius: 18, y: 10)

            playerSummary(for: station)

            HStack(spacing: 18) {
                PlayerCircleButton(systemImage: "backward.fill", size: 52) {
                    playPreviousAction()
                }
                .disabled(!canCycleStations)
                .help(L10n.string("mac.player.previousStation"))

                Button {
                    if audioPlayer.isCurrent(station) {
                        audioPlayer.togglePlayback()
                    } else {
                        playAction(station)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(TuneAVTheme.highlight)

                        if audioPlayer.isCurrent(station), case .loading = audioPlayer.playbackState {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: primaryPlaybackSymbol(for: station))
                                .font(.system(size: 25, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 68, height: 68)
                }
                .buttonStyle(.plain)
                .help(primaryPlaybackHelp(for: station))

                PlayerCircleButton(systemImage: "forward.fill", size: 52) {
                    playNextAction()
                }
                .disabled(!canCycleStations)
                .help(L10n.string("mac.player.nextStation"))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func playerSummary(for station: Station) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(stationMetaLine(for: station))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    toggleFavorite(station)
                } label: {
                    Image(systemName: isFavorite(station) ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isFavorite(station) ? Color.pink : TuneAVTheme.textSecondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .help(isFavorite(station) ? L10n.string("player.menu.removeFavorite") : L10n.string("player.menu.addFavorite"))

                Menu {
                    Button {
                        if let homepageURL = station.resolvedHomepageURL {
                            openURL(homepageURL)
                        }
                    } label: {
                        Label(L10n.string("player.menu.openWebsite"), systemImage: "safari.fill")
                    }
                    .disabled(station.resolvedHomepageURL == nil)

                    Button {
                        openStationSearch(for: station)
                    } label: {
                        Label(L10n.string("player.menu.searchStation"), systemImage: "magnifyingglass")
                    }

                    Button {
                        stationHistoryAction(station)
                    } label: {
                        Label(L10n.string("player.menu.stationHistory"), systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        shareStation(for: station)
                    } label: {
                        Label(L10n.string("player.menu.shareStation"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        copyStreamURL(for: station)
                    } label: {
                        Label(L10n.string("player.menu.copyStreamURL"), systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(width: 34, height: 34)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .rotationEffect(.degrees(90))
                .help(L10n.string("common.more"))
            }

            Text(primaryLine(for: station))
                .font(.system(size: 25, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(secondaryLine(for: station))
                .font(.callout)
                .foregroundStyle(TuneAVTheme.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func primaryLine(for station: Station) -> String {
        nowPlayingDisplayLines(for: station).trackTitleLine
    }

    private func secondaryLine(for station: Station) -> String {
        nowPlayingDisplayLines(for: station).trackSupportingLine
    }

    private func stationMetaLine(for station: Station) -> String {
        nowPlayingDisplayLines(for: station).stationMetaLine
    }

    private var playbackLabel: String {
        switch audioPlayer.playbackState {
        case .idle:
            return L10n.string("mac.player.status.idle")
        case .loading:
            return L10n.string("mac.player.status.connecting")
        case .playing:
            return L10n.string("shell.status.live")
        case .paused:
            return L10n.string("audio.status.paused")
        case .failed:
            return L10n.string("mac.player.status.error")
        }
    }

    private func primaryPlaybackSymbol(for station: Station) -> String {
        if audioPlayer.isCurrent(station), audioPlayer.isPlaying {
            return "pause.fill"
        }
        if audioPlayer.isCurrent(station), case .failed = audioPlayer.playbackState {
            return "arrow.clockwise"
        }
        return "play.fill"
    }

    private func primaryPlaybackHelp(for station: Station) -> String {
        if audioPlayer.isCurrent(station), audioPlayer.isPlaying {
            return L10n.string("player.control.pause")
        }
        if audioPlayer.isCurrent(station), case .failed = audioPlayer.playbackState {
            return L10n.string("player.retry")
        }
        return L10n.string("player.control.play")
    }

    private var hasDiscoverableTrack: Bool {
        guard let station = audioPlayer.currentStation ?? selectedStation else { return false }
        return nowPlayingDisplayLines(for: station).hasDiscoverableTrack
    }

    private func hasPlausibleTrackTitle(for station: Station) -> Bool {
        TuneAVDisplayMetadata.plausibleTitle(audioPlayer.currentTrackTitle, stationName: station.name) != nil
    }

    private func hasPlausibleTrackArtist(for station: Station) -> Bool {
        TuneAVDisplayMetadata.plausibleArtist(audioPlayer.currentTrackArtist, stationName: station.name) != nil
    }

    private func nowPlayingDisplayLines(for station: Station) -> TuneAVNowPlayingDisplayLines {
        TuneAVNowPlayingDisplayLines.resolve(
            station: station,
            currentTitle: audioPlayer.currentTrackTitle,
            currentArtist: audioPlayer.currentTrackArtist,
            currentAlbumTitle: audioPlayer.currentTrackAlbumTitle,
            liveNowFallback: L10n.string("player.track.liveNow"),
            liveStreamFallback: L10n.string("player.track.liveStreamActive")
        )
    }

    private func isCurrentTrackSaved(_ station: Station) -> Bool {
        libraryStore.isSavedDiscoveredTrack(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: station
        )
    }

    private func saveCurrentDiscovery(for station: Station) {
        libraryStore.toggleDiscoveredTrackSaved(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: station,
            artworkURL: audioPlayer.currentTrackArtworkURL
        )
    }

    private func shareCurrentDiscovery(for station: Station) {
        let shareText = currentDiscovery?.localizedShareText ?? station.shareText
        guard libraryStore.useDailyFeatureIfAllowed(.discoveryShare, usageKey: shareText) else { return }
        let picker = NSSharingServicePicker(items: [shareText])
        guard let contentView = NSApp.keyWindow?.contentView else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(shareText, forType: .string)
            return
        }
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }

    private func openStationSearch(for station: Station) {
        if let url = TuneAVExternalSearchURL.stationSearch(stationName: station.name) {
            openURL(url)
        }
    }

    private func openArtistSearch(destination: TuneAVExternalSearchURL.Destination, feature: LimitedFeature) {
        guard
            let discovery = currentDiscovery,
            let search = TuneAVExternalSearchURL.artistSearch(
                artist: discovery.artist,
                destination: destination,
                feature: feature
            )
        else {
            return
        }

        guard libraryStore.useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        openURL(search.url)
    }

    private func shareStation(for station: Station) {
        let shareText = station.shareText

        let picker = NSSharingServicePicker(items: [shareText])
        guard let contentView = NSApp.keyWindow?.contentView else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(shareText, forType: .string)
            return
        }
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }

    private func copyStreamURL(for station: Station) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(station.streamURL, forType: .string)
    }

    private func openExternalSearch(
        _ feature: LimitedFeature,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        if let query = discoverySearchQuery,
           let search = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: query,
            destination: destination,
            feature: feature,
            suffix: suffix
           ) {
            guard libraryStore.useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
            openURL(search.url)
        }
    }

    private var discoverySearchQuery: String? {
        currentDiscovery?.searchQuery
    }

    private var currentDiscovery: TuneAVCurrentDiscovery? {
        TuneAVCurrentDiscovery.resolve(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: audioPlayer.currentStation ?? selectedStation
        )
    }

    private func normalized(_ value: String?) -> String? {
        TuneAVDisplayMetadata.normalized(value)
    }
}

struct DesktopPlayerArtwork: View {
    @EnvironmentObject private var languageController: AppLanguageController

    let station: Station
    let trackArtworkURL: URL?
    let trackTitle: String?
    let trackArtist: String?
    let isDiscoverableTrack: Bool
    let isCurrentTrackSaved: Bool
    let isLoading: Bool
    let isFavorite: Bool
    let onSaveDiscovery: () -> Void
    let onShareDiscovery: () -> Void
    let onOpenYouTube: () -> Void
    let onOpenLyrics: () -> Void
    let onOpenArtist: () -> Void
    let onOpenArtistYouTube: () -> Void
    let onTogglePlayback: () -> Void
    let onToggleFavorite: () -> Void
    let onOpenWebsite: () -> Void

    @State private var isShowingOptions = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let cornerRadius = max(size * 0.105, 24)

            ZStack {
                artworkFront(size: size, cornerRadius: cornerRadius)
                    .opacity(isShowingOptions ? 0 : 1)
                    .rotation3DEffect(.degrees(isShowingOptions ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                    .allowsHitTesting(!isShowingOptions)

                artworkBack(size: size, cornerRadius: cornerRadius)
                    .opacity(isShowingOptions ? 1 : 0)
                    .rotation3DEffect(.degrees(isShowingOptions ? 0 : -180), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
                    .allowsHitTesting(isShowingOptions)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .id(languageController.currentLanguage)
        }
        .onChange(of: station.id) { _, _ in
            isShowingOptions = false
        }
    }

    private func artworkFront(size: CGFloat, cornerRadius: CGFloat) -> some View {
        heroArtwork(size: size, cornerRadius: cornerRadius)
            .overlay {
                if isLoading {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.black.opacity(0.22))

                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                flipButton(size: size)
                    .padding(size * 0.055)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    isShowingOptions = true
                }
            }
    }

    private func artworkBack(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.76),
                    TuneAVTheme.highlight.opacity(0.32),
                    Color.black.opacity(0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            blurredBackdrop(size: size)

            Button {
                flipToFront()
            } label: {
                Color.clear
                    .frame(width: size, height: size)
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(spacing: size < 260 ? 10 : 14) {
                if isDiscoverableTrack {
                    songInfoBlock(size: size)
                    artistInfoBlock(size: size)
                } else {
                    radioInfoBlock(size: size)
                }
            }
            .padding(size < 260 ? 16 : 18)

            Button {
                flipToFront()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(size * 0.055)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isShowingOptions = false
            }
        }
    }

    @ViewBuilder
    private var artworkOptionButtons: some View {
        if isDiscoverableTrack {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    artworkActionButton(
                        systemImage: isCurrentTrackSaved ? "bookmark.fill" : "bookmark",
                        title: isCurrentTrackSaved ? L10n.string("player.discovery.savedShort") : L10n.string("player.discovery.saveShort"),
                        isProminent: true,
                        action: onSaveDiscovery
                    )

                    artworkActionButton(systemImage: "square.and.arrow.up", title: L10n.string("player.discovery.shareShort"), action: onShareDiscovery)
                }

                HStack(spacing: 10) {
                    artworkActionButton(systemImage: "play.rectangle.fill", title: L10n.string("player.discovery.videoShort"), action: onOpenYouTube)
                    artworkActionButton(systemImage: "text.quote", title: L10n.string("player.discovery.lyricsShort"), action: onOpenLyrics)
                }
            }
        } else {
            HStack(spacing: 12) {
                artworkIconButton(
                    systemImage: isLoading ? "hourglass" : "play.fill",
                    title: isLoading ? L10n.string("audio.status.loading") : L10n.string("player.control.play"),
                    isProminent: true,
                    action: onTogglePlayback
                )

                artworkIconButton(
                    systemImage: isFavorite ? "heart.fill" : "heart",
                    title: isFavorite ? L10n.string("mac.player.favorite.saved") : L10n.string("mac.player.favorite.save"),
                    action: onToggleFavorite
                )

                if station.homepageURL != nil {
                    artworkIconButton(systemImage: "safari.fill", title: L10n.string("mac.player.website"), action: onOpenWebsite)
                }
            }
        }
    }

    private func radioInfoBlock(size: CGFloat) -> some View {
        VStack(spacing: size < 260 ? 12 : 16) {
            Button(action: flipToFront) {
                VStack(spacing: size < 260 ? 9 : 12) {
                    stationFallbackArtwork(size: size < 260 ? 76 : 94)

                    VStack(spacing: 4) {
                        Text(station.name)
                            .font(.system(size: size < 260 ? 16 : 18, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textInverse)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text(radioContextLine)
                            .font(.system(size: size < 260 ? 12 : 13, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.66))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                artworkIconOnlyButton(systemImage: isLoading ? "hourglass" : "play.fill", action: onTogglePlayback)
                artworkIconOnlyButton(systemImage: isFavorite ? "heart.fill" : "heart", action: onToggleFavorite)

                if station.resolvedHomepageURL != nil {
                    artworkIconOnlyButton(systemImage: "safari.fill", action: onOpenWebsite)
                }
            }
        }
        .padding(.horizontal, size < 260 ? 12 : 14)
        .padding(.vertical, size < 260 ? 14 : 18)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func songInfoBlock(size: CGFloat) -> some View {
        VStack(spacing: size < 260 ? 8 : 10) {
            Button(action: flipToFront) {
                HStack(spacing: 12) {
                    compactArtwork(size: size < 260 ? 38 : 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(songPrimaryLine)
                            .font(.system(size: size < 260 ? 13 : 15, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textInverse)
                            .lineLimit(1)

                        Text(songSecondaryLine)
                            .font(.system(size: size < 260 ? 11 : 13, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.72))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    artworkActionButton(
                        systemImage: isCurrentTrackSaved ? "bookmark.fill" : "bookmark",
                        title: isCurrentTrackSaved ? L10n.string("player.discovery.savedShort") : L10n.string("player.discovery.saveShort"),
                        isProminent: true,
                        action: onSaveDiscovery
                    )

                    artworkActionButton(systemImage: "square.and.arrow.up", title: L10n.string("player.discovery.shareShort"), action: onShareDiscovery)
                }

                HStack(spacing: 8) {
                    artworkActionButton(systemImage: "text.quote", title: L10n.string("player.discovery.lyricsShort"), action: onOpenLyrics)
                    artworkActionButton(systemImage: "play.rectangle.fill", title: L10n.string("player.discovery.videoShort"), action: onOpenYouTube)
                }
            }
        }
        .padding(.horizontal, size < 260 ? 10 : 12)
        .padding(.vertical, size < 260 ? 9 : 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func artistInfoBlock(size: CGFloat) -> some View {
        VStack(spacing: size < 260 ? 8 : 10) {
            Button(action: flipToFront) {
                HStack(spacing: 12) {
                    stationFallbackArtwork(size: size < 260 ? 40 : 50)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(backSubtitle)
                            .font(.system(size: size < 260 ? 13 : 15, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textInverse)
                            .lineLimit(1)

                        Text(L10n.string("player.artist.stationContext", station.name))
                            .font(.system(size: size < 260 ? 11 : 13, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.66))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                artworkActionButton(systemImage: "music.mic", title: L10n.string("player.artist.searchShort"), action: onOpenArtist)
                artworkActionButton(systemImage: "play.rectangle.fill", title: L10n.string("player.artist.youtubeShort"), action: onOpenArtistYouTube)
            }
        }
        .padding(.horizontal, size < 260 ? 10 : 12)
        .padding(.vertical, size < 260 ? 9 : 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func heroArtwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            if let artworkURL = trackArtworkURL ?? station.displayArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackArtwork(size: size, cornerRadius: cornerRadius)
                    }
                }
            } else {
                fallbackArtwork(size: size, cornerRadius: cornerRadius)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            if trackArtworkURL != nil {
                stationBadge(size: min(64, size * 0.2))
                    .padding(size * 0.06)
            }
        }
    }

    private func fallbackArtwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        StationArtworkView(
            station: station,
            size: size,
            surfaceStyle: .dark,
            contentInsetRatio: 0.04,
            cornerRadiusRatio: cornerRadius / size
        )
    }

    private func stationBadge(size: CGFloat) -> some View {
        StationThumbnailView(
            station: station,
            size: size,
            surfaceStyle: .light
        )
        .padding(3)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }

    private func compactArtwork(size: CGFloat) -> some View {
        Group {
            if let artworkURL = trackArtworkURL ?? station.displayArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        StationThumbnailView(station: station, size: size, surfaceStyle: .dark)
                    }
                }
            } else {
                StationThumbnailView(station: station, size: size, surfaceStyle: .dark)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func stationFallbackArtwork(size: CGFloat) -> some View {
        Group {
            if let artworkURL = station.displayArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        StationThumbnailView(station: station, size: size, surfaceStyle: .dark)
                    }
                }
            } else {
                StationThumbnailView(station: station, size: size, surfaceStyle: .dark)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func blurredBackdrop(size: CGFloat) -> some View {
        Group {
            if let artworkURL = trackArtworkURL ?? station.displayArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .blur(radius: 24)
                            .opacity(0.24)
                            .clipped()
                    }
                }
            }
        }
    }

    private func flipToFront() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isShowingOptions = false
        }
    }

    private func flipButton(size: CGFloat) -> some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 38, height: 38)
            .background(.black.opacity(0.30), in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    private func artworkActionButton(systemImage: String, title: String, isProminent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isProminent ? Color.black : TuneAVTheme.textInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isProminent ? TuneAVTheme.highlight : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isProminent ? 0 : 0.13), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func artworkIconOnlyButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(TuneAVTheme.textInverse)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.13), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func artworkIconButton(systemImage: String, title: String, isProminent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isProminent ? Color.black : TuneAVTheme.textInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(isProminent ? TuneAVTheme.highlight : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isProminent ? 0 : 0.13), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var backTitle: String {
        isDiscoverableTrack ? (trackTitle ?? station.name) : station.name
    }

    private var backSubtitle: String {
        isDiscoverableTrack ? (trackArtist ?? station.name) : station.shortMeta
    }

    private var radioContextLine: String {
        let meta = station.shortMeta.trimmingCharacters(in: .whitespacesAndNewlines)
        return meta.isEmpty ? L10n.string("player.track.liveNow") : meta
    }

    private var songPrimaryLine: String {
        station.name
    }

    private var songSecondaryLine: String {
        backTitle
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .padding(14)
        .avCardSurface(cornerRadius: 18)
    }
}

private struct InspectorStatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TuneAVTheme.highlight)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule())
    }
}

private struct InspectorSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Spacer(minLength: 8)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct PlayerCircleButton: View {
    let systemImage: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: size, height: size)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerActionButton: View {
    let title: String
    let systemImage: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Color.white : TuneAVTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(isActive ? TuneAVTheme.highlight : TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color.clear : TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct FlowTagCloud: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct InspectorMetaRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
    }
}
