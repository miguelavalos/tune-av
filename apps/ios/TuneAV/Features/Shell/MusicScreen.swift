import AVHaptics
import SwiftUI

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
            openTrackYouTube: { discovery in runProAviAction { musicExternalSearchRouter.openDiscoveryYouTube(discovery) } },
            openLyrics: { discovery in runProAviAction { musicExternalSearchRouter.openDiscoveryLyrics(discovery) } },
            openTrackAppleMusic: { discovery in runProAviAction { musicExternalSearchRouter.openDiscoveryAppleMusic(discovery) } },
            openTrackSpotify: { discovery in runProAviAction { musicExternalSearchRouter.openDiscoverySpotify(discovery) } },
            hideAction: hideDiscoveryWithUndo(_:),
            removeAction: { discovery in removeDiscovery(discovery) },
            openArtistInfo: { artist in openArtistInfo(artist, nil) },
            openArtistYouTube: { artist in runProAviAction { musicExternalSearchRouter.openArtistYouTube(artist) } },
            openArtistAppleMusic: { artist in runProAviAction { musicExternalSearchRouter.openArtistAppleMusic(artist) } },
            openArtistSpotify: { artist in runProAviAction { musicExternalSearchRouter.openArtistSpotify(artist) } }
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
        MusicDiscoveryLibrarySection(
            snapshot: snapshot,
            mode: musicMode,
            emptyTitle: emptyDiscoveryTitle(snapshot),
            emptyDetail: emptyDiscoveryDetail(snapshot),
            header: { discoveryHeader(snapshot) },
            trackList: { discoveryTrackList(snapshot) },
            artistList: { discoveryArtistList(snapshot) }
        )
    }

    private func discoveryTrackList(_ snapshot: MusicLibraryDerivedState) -> some View {
        MusicDiscoveryTrackList(
            snapshot: snapshot,
            openAviActionsID: $openMusicAviActionsID,
            currentMode: musicMode,
            stationArtworkURL: { discovery in stationArtworkURL(discovery) },
            trackFeedback: { discovery in trackFeedback(discovery) },
            actions: discoveryTrackActions,
            showMoreDiscoveries: showMoreDiscoveries
        )
    }

    private var discoveryTrackActions: MusicDiscoveryTrackActions {
        MusicDiscoveryTrackActions(
            openTrackInfo: { discovery, mode in openDiscoveryInfo(discovery, mode) },
            openArtistInfo: { discovery, mode in openArtistInfo(discoveryArtistSummary(for: discovery), mode) },
            openStationInfo: { discovery in openDiscoveryStationInfo(discovery) },
            toggleSaved: { discovery in toggleDiscoverySaved(discovery) },
            openYouTube: { discovery in runProAviAction { musicExternalSearchRouter.openDiscoveryYouTube(discovery) } },
            openLyrics: { discovery in runProAviAction { musicExternalSearchRouter.openDiscoveryLyrics(discovery) } },
            openAppleMusic: { discovery in runProAviAction { musicExternalSearchRouter.openDiscoveryAppleMusic(discovery) } },
            openSpotify: { discovery in runProAviAction { musicExternalSearchRouter.openDiscoverySpotify(discovery) } },
            hideAction: hideDiscoveryWithUndo(_:),
            removeAction: { discovery in removeDiscovery(discovery) }
        )
    }

    private func discoveryArtistList(_ snapshot: MusicLibraryDerivedState) -> some View {
        MusicDiscoveryArtistList(
            snapshot: snapshot,
            openAviActionsID: $openMusicAviActionsID,
            currentMode: musicMode,
            actions: discoveryArtistActions,
            showMoreArtists: showMoreArtists
        )
    }

    private var discoveryArtistActions: MusicDiscoveryArtistActions {
        MusicDiscoveryArtistActions(
            openArtist: { artist, mode in openArtistInfo(artist, mode) },
            openArtistSongs: { artist in openArtistSongs(artist.name) },
            openArtistRadios: { artist, mode in openArtistInfo(artist, mode) },
            openYouTube: { artist in runProAviAction { musicExternalSearchRouter.openArtistYouTube(artist.name) } },
            openAppleMusic: { artist in runProAviAction { musicExternalSearchRouter.openArtistAppleMusic(artist.name) } },
            openSpotify: { artist in runProAviAction { musicExternalSearchRouter.openArtistSpotify(artist.name) } }
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

    private var musicExternalSearchRouter: MusicExternalSearchRouter {
        MusicExternalSearchRouter { search in
            guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
            browserDestination = BrowserDestination(url: search.url)
        }
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
            snapshot: snapshot,
            shareAction: shareDiscoveries(_:),
            clearAction: confirmClearDiscoveries
        )
    }

    private func shareDiscoveries(_ snapshot: MusicLibraryDerivedState) {
        let shareText = discoveriesShareText(snapshot)
        guard useDailyFeatureIfAllowed(.discoveryShare, usageKey: shareText) else { return }
        discoveriesShareTextDraft = shareText
        isShowingDiscoveriesShare = true
    }

    private func confirmClearDiscoveries() {
        isConfirmingClearDiscoveries = true
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
        AVHaptics.perform(.loadMore)
        visibleDiscoveryLimit += Self.pageSize
    }

    private func showMoreArtists() {
        AVHaptics.perform(.loadMore)
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
        AVHaptics.perform(.modeChange)
        isShowingOverview = false
        selectedArtistName = nil
        if mode != .history {
            historyStationFilter = nil
        }
        musicMode = mode
        resetVisibleLimits()
    }

    private func openMusicMode(_ mode: MusicContentMode) {
        AVHaptics.perform(.modeChange)
        isShowingOverview = false
        selectedArtistName = nil
        if mode != .history {
            historyStationFilter = nil
        }
        musicMode = mode
        resetVisibleLimits()
    }

    private func showOverview() {
        AVHaptics.perform(.navigation)
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
        AVHaptics.perform(isSearchExpanded ? .closePanel : .openPanel)
        isShowingOverview = false
        withAnimation(.snappy(duration: 0.22)) {
            isSearchExpanded.toggle()
        }
    }

    private func setMusicSort(_ sort: MusicLibrarySort) {
        guard musicSort != sort else { return }
        AVHaptics.perform(.modeChange)
        musicSortRawValue = sort.rawValue
        resetVisibleLimits()
    }

    private func hideDiscoveryWithUndo(_ discovery: DiscoveredTrack) {
        withAnimation(.snappy(duration: 0.22)) {
            hiddenDiscovery = discovery
            hideDiscovery(discovery)
        }
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
