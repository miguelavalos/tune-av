import SwiftUI

struct LibraryScreen: View {
    private static let pageSize = 40
    private static let overviewLimit = 12

    private struct DerivedState {
        let overviewRecentStations: [Station]
        let overviewFavoriteStations: [Station]
        let overviewTunedStations: [Station]
        let overviewMusicStations: [Station]
        let tunedStationCount: Int
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
                    localRadioTunedCount: derivedState.tunedStationCount,
                    localMusicDetectedCount: nil,
                    localMusicArtistCount: nil,
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
                    value: favorites.count,
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: TuneAVTheme.highlight,
                    action: { openMode(.saved) }
                )
                RadioOverviewMetricCard(
                    title: L10n.string("shell.library.overview.recent"),
                    value: recents.count,
                    systemImage: "clock.fill",
                    tint: Color(red: 0.17, green: 0.52, blue: 0.96),
                    action: { openMode(.recent) }
                )
                RadioOverviewMetricCard(
                    title: L10n.string("shell.library.overview.tuned"),
                    value: derivedState.tunedStationCount,
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
            tunedStationCount: tunedStations.count,
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
