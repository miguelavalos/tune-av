import SwiftUI

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    @State private var selectedSection: SidebarSection = .home
    @State private var selectedStation: Station?
    @State private var searchQuery = ""
    @State private var searchResults: [Station] = []
    @State private var searchIsLoading = false
    @State private var searchErrorMessage: String?
    @State private var activeSearchTag: String?
    @State private var selectedCountryCode: String?
    @State private var detailStation: Station?
    @AppStorage("tuneav.mac.appearance") private var appearanceMode = "system"
    @AppStorage("tuneav.mac.launchToSearch") private var launchToSearch = false

    private let stationService = StationService()
    private let genreTags = ["ambient", "rock", "pop", "jazz", "news", "electronic"]

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
                canCycleStations: currentStationQueue.count > 1,
                toggleFavorite: libraryStore.toggleFavorite,
                isFavorite: libraryStore.isFavorite
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
                    Label("Search", systemImage: "magnifyingglass")
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
                toggleFavorite: { libraryStore.toggleFavorite(station) }
            )
            .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(item: $libraryStore.upgradePrompt) { context in
            UpgradePromptSheet(
                context: context,
                accountConnectionState: libraryStore.accountConnectionState,
                primaryActionTitle: MacAppConfig.accountManagementURL == nil ? "Open Profile" : "Manage account",
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
        .task {
            selectedStation = libraryStore.recents.first ?? Station.samples.first
            selectedCountryCode = libraryStore.preferredCountryCode
            if launchToSearch {
                selectedSection = .search
                activeSearchTag = libraryStore.preferredTag
            }
            await loadHomeFeedIfNeeded()
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
        List(selection: $selectedSection) {
            Section("Browse") {
                ForEach([SidebarSection.home, .search, .library, .music]) { section in
                    SidebarSectionRow(section: section, detail: sidebarDetail(for: section))
                        .tag(section)
                }
            }

            Section("Account") {
                SidebarSectionRow(section: .profile, detail: libraryStore.accountConnectionState.title)
                    .tag(SidebarSection.profile)
            }

            if let currentStation = audioPlayer.currentStation {
                Section("Now Playing") {
                    Button {
                        selectedStation = currentStation
                    } label: {
                        SidebarNowPlayingRow(station: currentStation)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
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
                feedContext: .popularWorldwide,
                playAction: play,
                toggleFavorite: libraryStore.toggleFavorite,
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
                toggleFavorite: libraryStore.toggleFavorite,
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
                toggleFavorite: libraryStore.toggleFavorite,
                showDetails: showStationDetails
            )
        case .music:
            MusicView(
                discoveries: libraryStore.discoveries,
                limits: libraryStore.limits,
                openStation: openDiscoveryStation,
                toggleSaved: libraryStore.toggleDiscoverySaved,
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
                accountManagementURL: MacAppConfig.accountManagementURL,
                clearAction: libraryStore.clearLocalState,
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

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(audioPlayer.currentStation == nil ? "Ready" : playbackToolbarTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)

            if let station = audioPlayer.currentStation {
                Text(station.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            } else {
                Text("Choose a station to start listening.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private var playbackToolbarTitle: String {
        switch audioPlayer.playbackState {
        case .idle:
            return "Play"
        case .loading:
            return "Connecting"
        case .playing:
            return "Pause"
        case .paused:
            return "Resume"
        case .failed:
            return "Retry"
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
            return audioPlayer.currentStation == nil ? "Live feed" : "Listening"
        case .search:
            return activeSearchTag?.capitalized ?? "Stations"
        case .library:
            return "\(libraryStore.favorites.count) saved"
        case .music:
            return "\(libraryStore.discoveries.count) tracks"
        case .profile:
            return libraryStore.accessMode.title
        }
    }

    private func showStationDetails(_ station: Station) {
        selectedStation = station
        detailStation = station
    }

    private func loadHomeFeedIfNeeded() async {
        guard searchResults.isEmpty else { return }
        await performSearch(initial: true)
    }

    private func play(_ station: Station) {
        selectedStation = station
        libraryStore.recordPlayback(of: station)
        audioPlayer.play(station)
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
        playStationAtOffset(-1)
    }

    private func playNextStation() {
        playStationAtOffset(1)
    }

    private func playStationAtOffset(_ offset: Int) {
        let stations = currentStationQueue
        guard stations.count > 1 else { return }
        let currentID = (audioPlayer.currentStation ?? selectedStation)?.id
        let currentIndex = stations.firstIndex { $0.id == currentID } ?? 0
        let nextIndex = (currentIndex + offset + stations.count) % stations.count
        play(stations[nextIndex])
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
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = activeSearchTag ?? (trimmedQuery.isEmpty ? libraryStore.preferredTag : "")
        let countryCode = selectedCountryCode ?? ""

        if !force, !initial, trimmedQuery.isEmpty, selectedSection != .home, tag.isEmpty, countryCode.isEmpty {
            searchResults = []
            return
        }

        searchIsLoading = true
        searchErrorMessage = nil

        do {
            let results = try await stationService.searchStations(
                filters: .init(
                    query: trimmedQuery,
                    countryCode: countryCode,
                    tag: tag,
                    limit: 32,
                    allowsEmptySearch: initial || !tag.isEmpty || !countryCode.isEmpty
                )
            )
            searchResults = results.isEmpty ? Station.samples : results
        } catch {
            searchResults = Station.samples
            searchErrorMessage = error.localizedDescription
        }

        searchIsLoading = false
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
        switch appearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
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
            StationArtworkView(station: station, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .lineLimit(1)

                Text(audioPlayer.isPlaying ? "Live now" : "Paused")
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

    private var displayStation: Station? {
        audioPlayer.currentStation ?? selectedStation
    }

    var body: some View {
        VStack(spacing: 0) {
            if let station = displayStation {
                stationPanel(station)
            } else {
                EmptyStateCard(title: "No station selected", detail: "Pick a station from Home, Search, or Library.")
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
                .help("Previous station")

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
                .help("Next station")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
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
                .help(isFavorite(station) ? "Remove favorite" : "Favorite station")

                Menu {
                    Button {
                        if let homepageURL = station.resolvedHomepageURL {
                            openURL(homepageURL)
                        }
                    } label: {
                        Label("Website", systemImage: "safari.fill")
                    }
                    .disabled(station.resolvedHomepageURL == nil)

                    Button {
                        openStationSearch(for: station)
                    } label: {
                        Label("Search Station", systemImage: "magnifyingglass")
                    }

                    Button {
                        shareStation(for: station)
                    } label: {
                        Label("Share Station", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        copyStreamURL(for: station)
                    } label: {
                        Label("Copy Stream URL", systemImage: "doc.on.doc")
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
                .help("More")
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
        let title = audioPlayer.currentTrackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title! : station.name
    }

    private func secondaryLine(for station: Station) -> String {
        let artist = audioPlayer.currentTrackArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
        if artist?.isEmpty == false {
            return "\(artist!) · \(station.name)"
        }
        return station.shortMeta
    }

    private func stationMetaLine(for station: Station) -> String {
        if let artist = normalized(audioPlayer.currentTrackArtist) {
            return artist
        }
        if let flag = station.flagEmoji {
            return "\(flag) \(station.country)"
        }
        return station.country
    }

    private var playbackLabel: String {
        switch audioPlayer.playbackState {
        case .idle:
            return "Idle"
        case .loading:
            return "Connecting"
        case .playing:
            return "Live"
        case .paused:
            return "Paused"
        case .failed:
            return "Error"
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
            return "Pause"
        }
        if audioPlayer.isCurrent(station), case .failed = audioPlayer.playbackState {
            return "Retry"
        }
        return "Play"
    }

    private var hasDiscoverableTrack: Bool {
        normalized(audioPlayer.currentTrackTitle) != nil
    }

    private func isCurrentTrackSaved(_ station: Station) -> Bool {
        libraryStore.discoveries.contains {
            $0.discoveryID == DiscoveredTrack.makeID(
                title: normalized(audioPlayer.currentTrackTitle) ?? "",
                artist: normalized(audioPlayer.currentTrackArtist),
                stationID: station.id
            ) && $0.isMarkedInteresting
        }
    }

    private func saveCurrentDiscovery(for station: Station) {
        libraryStore.markTrackInteresting(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: station,
            artworkURL: audioPlayer.currentTrackArtworkURL
        )
    }

    private func shareCurrentDiscovery(for station: Station) {
        let shareText = DiscoveryShareTextFormatter.text(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            stationName: station.name
        )
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
        let query = TuneAVExternalSearchURL.query(
            parts: [audioPlayer.currentTrackArtist, audioPlayer.currentTrackTitle],
            suffix: suffix
        )
        guard !query.isEmpty else { return }

        if let url = TuneAVExternalSearchURL.url(for: destination, query: query) {
            guard libraryStore.useDailyFeatureIfAllowed(feature, usageKey: url.absoluteString) else { return }
            openURL(url)
        }
    }

    private func normalized(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)
    }
}

private struct DesktopPlayerArtwork: View {
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

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isShowingOptions = false
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.12), in: Circle())
                            .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }

                Text(isCurrentTrackSaved ? "SAVED" : (isDiscoverableTrack ? "CURRENT TRACK" : "RADIO STATION"))
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(TuneAVTheme.highlight)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(.white.opacity(0.10), in: Capsule())
                    .overlay { Capsule().stroke(Color.white.opacity(0.13), lineWidth: 1) }

                Spacer(minLength: 8)

                VStack(spacing: 7) {
                    Text(backTitle)
                        .font(.system(size: size < 260 ? 20 : 24, weight: .black))
                        .foregroundStyle(TuneAVTheme.textInverse)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(backSubtitle)
                        .font(.system(size: size < 260 ? 13 : 15, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textInverse.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 14)

                artworkOptionButtons
            }
            .padding(size < 260 ? 18 : 22)
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
                        title: isCurrentTrackSaved ? "Saved" : "Save",
                        isProminent: true,
                        action: onSaveDiscovery
                    )

                    artworkActionButton(systemImage: "square.and.arrow.up", title: "Share", action: onShareDiscovery)
                }

                HStack(spacing: 10) {
                    artworkActionButton(systemImage: "play.rectangle.fill", title: "YouTube", action: onOpenYouTube)
                    artworkActionButton(systemImage: "text.quote", title: "Lyrics", action: onOpenLyrics)
                }
            }
        } else {
            HStack(spacing: 12) {
                artworkIconButton(
                    systemImage: isLoading ? "hourglass" : "play.fill",
                    title: isLoading ? "Loading" : "Play",
                    isProminent: true,
                    action: onTogglePlayback
                )

                artworkIconButton(
                    systemImage: isFavorite ? "heart.fill" : "heart",
                    title: isFavorite ? "Liked" : "Like",
                    action: onToggleFavorite
                )

                if station.homepageURL != nil {
                    artworkIconButton(systemImage: "safari.fill", title: "Website", action: onOpenWebsite)
                }
            }
        }
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
        StationArtworkView(
            station: station,
            size: size,
            surfaceStyle: .light,
            contentInsetRatio: 0.08,
            cornerRadiusRatio: 0.26
        )
        .padding(3)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
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
