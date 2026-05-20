import SwiftUI

enum MusicContentMode: String, CaseIterable, Identifiable {
    case songs
    case artists
    case top
    case history

    var id: String { rawValue }

    init(libraryMode: MusicLibraryMode) {
        switch libraryMode {
        case .songs:
            self = .songs
        case .artists:
            self = .artists
        case .history:
            self = .history
        }
    }

    var libraryMode: MusicLibraryMode {
        switch self {
        case .songs:
            return .songs
        case .artists:
            return .artists
        case .top, .history:
            return .history
        }
    }

    var title: String {
        switch self {
        case .songs:
            return MusicLibraryMode.songs.title
        case .artists:
            return MusicLibraryMode.artists.title
        case .top:
            return L10n.string("shell.music.mode.top")
        case .history:
            return MusicLibraryMode.history.title
        }
    }

    var systemImage: String {
        switch self {
        case .songs:
            return "bookmark.fill"
        case .artists:
            return "person.2.fill"
        case .top:
            return "sparkles"
        case .history:
            return "clock.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .songs:
            return L10n.string("shell.music.detail.songs.subtitle")
        case .artists:
            return L10n.string("shell.music.detail.artists.subtitle")
        case .top:
            return L10n.string("shell.music.detail.top.subtitle")
        case .history:
            return L10n.string("shell.music.detail.history.subtitle")
        }
    }
}

struct MusicLibraryDerivedState {
    let visibleDiscoveries: [DiscoveredTrack]
    let savedDiscoveries: [DiscoveredTrack]
    let tunedDiscoveries: [DiscoveredTrack]
    let visibleArtistSummaries: [DiscoveryArtistSummary]
    let filteredDiscoveries: [DiscoveredTrack]
    let visibleFilteredDiscoveries: [DiscoveredTrack]
    let filteredArtistSummaries: [DiscoveryArtistSummary]
    let visibleArtistSummariesForMode: [DiscoveryArtistSummary]
    let musicMode: MusicContentMode

    var hasOverviewContent: Bool {
        !savedDiscoveries.isEmpty
            || !visibleDiscoveries.isEmpty
            || !tunedDiscoveries.isEmpty
            || !visibleArtistSummaries.isEmpty
    }

    var isCurrentModeEmpty: Bool {
        switch musicMode {
        case .songs, .top, .history:
            return filteredDiscoveries.isEmpty
        case .artists:
            return filteredArtistSummaries.isEmpty
        }
    }

    var canShowMoreDiscoveries: Bool {
        visibleFilteredDiscoveries.count < filteredDiscoveries.count
    }

    var canShowMoreArtists: Bool {
        visibleArtistSummariesForMode.count < filteredArtistSummaries.count
    }
}

enum MusicLibrarySort: String, CaseIterable, Identifiable {
    case recent
    case alphabetical
    case strongest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return L10n.string("shell.music.sort.recent")
        case .alphabetical:
            return L10n.string("shell.library.sort.alphabetical")
        case .strongest:
            return L10n.string("shell.music.sort.strongest")
        }
    }
}

struct MusicLibraryControls: View {
    let savedCount: Int
    let historyCount: Int
    let artistCount: Int
    let stationCount: Int
    let selectedMode: MusicContentMode
    let selectMode: (MusicContentMode) -> Void
    let sort: MusicLibrarySort
    let setSort: (MusicLibrarySort) -> Void
    let isSearchExpanded: Bool
    let showOverview: () -> Void
    let toggleSearch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            overviewButton

            HStack(spacing: 4) {
                modeButton(.songs, value: savedCount)
                modeButton(.artists, value: artistCount)
                modeButton(.top, value: stationCount)
                modeButton(.history, value: historyCount)
            }
            .padding(4)
            .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }

            sortButton
            searchButton
        }
        .accessibilityElement(children: .contain)
    }

    private func modeButton(_ mode: MusicContentMode, value: Int) -> some View {
        Button {
            selectMode(mode)
        } label: {
            Image(systemName: mode.systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(selectedMode == mode ? Color.white : TuneAVTheme.textSecondary)
                .frame(width: 44, height: 40)
                .background(selectedMode == mode ? TuneAVTheme.highlight.opacity(0.86) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title), \(value)")
        .accessibilityIdentifier("music.mode.\(mode.rawValue)")
    }

    private var sortButton: some View {
        Menu {
            ForEach(MusicLibrarySort.allCases) { option in
                Button {
                    setSort(option)
                } label: {
                    Label(option.title, systemImage: option == sort ? "checkmark" : "line.3.horizontal.decrease")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(TuneAVTheme.mutedSurface, in: Capsule())
                .overlay {
                    Capsule().stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.music.sort.accessibilityLabel", sort.title))
        .accessibilityIdentifier("music.sort")
    }

    private var overviewButton: some View {
        Button(action: showOverview) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(TuneAVTheme.mutedSurface, in: Capsule())
                .overlay {
                    Capsule().stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.accessibility.showOverview"))
        .accessibilityIdentifier("music.overview")
    }

    private var searchButton: some View {
        Button(action: toggleSearch) {
            Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(isSearchExpanded ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
                .frame(width: 40, height: 40)
                .background(isSearchExpanded ? TuneAVTheme.highlight : TuneAVTheme.mutedSurface, in: Capsule())
                .overlay {
                    Capsule().stroke(isSearchExpanded ? TuneAVTheme.highlight.opacity(0.5) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.music.searchAccess.title"))
        .accessibilityIdentifier("music.searchToggle")
    }
}

struct MusicLibrarySnapshotControls: View {
    let snapshot: MusicLibraryDerivedState
    let selectedMode: MusicContentMode
    let selectMode: (MusicContentMode) -> Void
    let sort: MusicLibrarySort
    let setSort: (MusicLibrarySort) -> Void
    let isSearchExpanded: Bool
    let showOverview: () -> Void
    let toggleSearch: () -> Void

    var body: some View {
        MusicLibraryControls(
            savedCount: snapshot.savedDiscoveries.count,
            historyCount: snapshot.visibleDiscoveries.count,
            artistCount: snapshot.visibleArtistSummaries.count,
            stationCount: snapshot.tunedDiscoveries.count,
            selectedMode: selectedMode,
            selectMode: selectMode,
            sort: sort,
            setSort: setSort,
            isSearchExpanded: isSearchExpanded,
            showOverview: showOverview,
            toggleSearch: toggleSearch
        )
    }
}

struct MusicLibraryOverview: View {
    let snapshot: MusicLibraryDerivedState
    let summary: TuneAVUserSummary?
    let overviewLimit: Int
    let showsAccountSummary: Bool
    let userSummaryRefreshState: TuneAVUserSummaryRefreshState
    let isSignedIn: Bool
    let openAccountAction: () -> Void
    let startSignInAction: () -> Void
    let refreshSummary: () async -> Void
    let openSearchAction: () -> Void
    let openMode: (MusicContentMode) -> Void
    let stationArtworkURL: (DiscoveredTrack) -> URL?
    let trackFeedback: (DiscoveredTrack) -> TuneAVStationFeedback?
    let openTrackInfo: (DiscoveredTrack) -> Void
    let toggleSaved: (DiscoveredTrack) -> Void
    let openTrackYouTube: (DiscoveredTrack) -> Void
    let openLyrics: (DiscoveredTrack) -> Void
    let openTrackAppleMusic: (DiscoveredTrack) -> Void
    let openTrackSpotify: (DiscoveredTrack) -> Void
    let hideAction: (DiscoveredTrack) -> Void
    let removeAction: (DiscoveredTrack) -> Void
    let openArtistInfo: (DiscoveryArtistSummary) -> Void
    let openArtistYouTube: (String) -> Void
    let openArtistAppleMusic: (String) -> Void
    let openArtistSpotify: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showsAccountSummary {
                AccountSummaryStatusCard(
                    kind: .music,
                    state: userSummaryRefreshState,
                    summary: summary,
                    isSignedIn: isSignedIn,
                    hasProAccess: true,
                    openAccountAction: openAccountAction,
                    startSignInAction: startSignInAction,
                    refreshAction: refreshSummary
                )
            }

            MusicOverviewMetricGrid(
                snapshot: snapshot,
                summary: summary,
                openMode: openMode
            )

            if snapshot.hasOverviewContent {
                musicOverviewTrackSectionIfNeeded(
                    discoveries: Array(snapshot.savedDiscoveries.prefix(overviewLimit)),
                    title: L10n.string("shell.music.overview.songs"),
                    subtitle: L10n.string("shell.music.detail.songs.subtitle"),
                    mode: .songs
                )

                musicOverviewArtistSectionIfNeeded(
                    artists: Array(snapshot.visibleArtistSummaries.prefix(overviewLimit)),
                    title: L10n.string("shell.music.overview.artists"),
                    subtitle: L10n.string("shell.music.detail.artists.subtitle"),
                    mode: .artists
                )

                musicOverviewTrackSectionIfNeeded(
                    discoveries: Array(snapshot.tunedDiscoveries.prefix(overviewLimit)),
                    title: L10n.string("shell.music.overview.top"),
                    subtitle: L10n.string("shell.music.detail.top.subtitle"),
                    mode: .top
                )

                musicOverviewTrackSectionIfNeeded(
                    discoveries: Array(snapshot.visibleDiscoveries.prefix(overviewLimit)),
                    title: L10n.string("shell.music.overview.history"),
                    subtitle: L10n.string("shell.music.overview.latest.subtitle"),
                    mode: .history
                )
            } else {
                EmptyLibraryState(
                    title: L10n.string("shell.music.overview.empty"),
                    detail: L10n.string("shell.music.overview.empty.detail"),
                    actionTitle: L10n.string("shell.music.overview.empty.action"),
                    actionSystemImage: "magnifyingglass",
                    action: openSearchAction
                )
            }
        }
    }

    @ViewBuilder
    private func musicOverviewTrackSectionIfNeeded(
        discoveries: [DiscoveredTrack],
        title: String,
        subtitle: String,
        mode: MusicContentMode
    ) -> some View {
        if !discoveries.isEmpty {
            RadioOverviewCarouselSection(title: title, subtitle: subtitle, action: { openMode(mode) }) {
                MusicTrackCompactCarousel(
                    discoveries: discoveries,
                    stationArtworkURL: { discovery in stationArtworkURL(discovery) },
                    trackFeedback: { discovery in trackFeedback(discovery) },
                    openTrackInfo: { discovery in openTrackInfo(discovery) },
                    toggleSaved: { discovery in toggleSaved(discovery) },
                    openYouTube: { discovery in openTrackYouTube(discovery) },
                    openLyrics: { discovery in openLyrics(discovery) },
                    openAppleMusic: { discovery in openTrackAppleMusic(discovery) },
                    openSpotify: { discovery in openTrackSpotify(discovery) },
                    hideAction: { discovery in hideAction(discovery) },
                    removeAction: { discovery in removeAction(discovery) }
                )
            }
        }
    }

    @ViewBuilder
    private func musicOverviewArtistSectionIfNeeded(
        artists: [DiscoveryArtistSummary],
        title: String,
        subtitle: String,
        mode: MusicContentMode
    ) -> some View {
        if !artists.isEmpty {
            RadioOverviewCarouselSection(title: title, subtitle: subtitle, action: { openMode(mode) }) {
                MusicArtistCompactCarousel(
                    artists: artists,
                    openArtistInfo: { artist in openArtistInfo(artist) },
                    openYouTube: { artist in openArtistYouTube(artist) },
                    openAppleMusic: { artist in openArtistAppleMusic(artist) },
                    openSpotify: { artist in openArtistSpotify(artist) }
                )
            }
        }
    }
}

struct MusicOverviewMetricGrid: View {
    let snapshot: MusicLibraryDerivedState
    let summary: TuneAVUserSummary?
    let openMode: (MusicContentMode) -> Void

    var body: some View {
        RadioOverviewMetricGrid {
            RadioOverviewMetricCard(
                title: L10n.string("shell.music.overview.songs"),
                value: summary?.music.cards.songs.count ?? snapshot.savedDiscoveries.count,
                systemImage: "bookmark.fill",
                tint: TuneAVTheme.highlight,
                accessibilityIdentifier: "music.overview.songs",
                action: { openMode(.songs) }
            )
            RadioOverviewMetricCard(
                title: L10n.string("shell.music.overview.artists"),
                value: summary?.music.cards.artists.count ?? snapshot.visibleArtistSummaries.count,
                systemImage: "person.2.fill",
                tint: Color(red: 0.17, green: 0.52, blue: 0.96),
                accessibilityIdentifier: "music.overview.artists",
                action: { openMode(.artists) }
            )
            RadioOverviewMetricCard(
                title: L10n.string("shell.music.overview.top"),
                value: snapshot.tunedDiscoveries.count,
                systemImage: "sparkles",
                tint: Color(red: 0.95, green: 0.48, blue: 0.18),
                accessibilityIdentifier: "music.overview.top",
                action: { openMode(.top) }
            )
            RadioOverviewMetricCard(
                title: L10n.string("shell.music.overview.history"),
                value: summary?.music.cards.history.count ?? snapshot.visibleDiscoveries.count,
                systemImage: "clock.fill",
                tint: Color(red: 0.54, green: 0.43, blue: 0.90),
                accessibilityIdentifier: "music.overview.history",
                action: { openMode(.history) }
            )
        }
    }
}

struct MusicDetailHeader: View {
    let title: String
    let subtitle: String
    let goBack: () -> Void

    var body: some View {
        DetailTopHeader(
            title: title,
            subtitle: subtitle,
            status: L10n.string("tab.music"),
            accessibilityIdentifier: "music.detail.header",
            goBack: goBack
        )
    }
}

struct MusicStickyDetailHeader: View {
    let mode: MusicContentMode
    let goBack: () -> Void

    var body: some View {
        MusicDetailHeader(
            title: mode.title,
            subtitle: mode.subtitle,
            goBack: goBack
        )
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 12)
        .background {
            TuneAVTheme.shellBackground
                .ignoresSafeArea(edges: .top)
        }
    }
}

struct MusicDiscoveryModeHeader: View {
    let mode: MusicContentMode
    let songsTitle: String
    let showsAllHistoryButton: Bool
    let showAllHistory: () -> Void
    let actions: () -> MusicDiscoveryActions

    var body: some View {
        switch mode {
        case .artists:
            MusicDiscoveryArtistsHeader(actions: actions)
        case .songs, .top, .history:
            MusicDiscoverySongsHeader(
                title: songsTitle,
                showsAllHistoryButton: showsAllHistoryButton,
                showAllHistory: showAllHistory,
                actions: actions
            )
        }
    }
}

struct MusicDiscoveryArtistsHeader: View {
    let actions: () -> MusicDiscoveryActions

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.string("shell.music.artists.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            actions()
        }
    }
}

struct MusicDiscoverySongsHeader: View {
    let title: String
    let showsAllHistoryButton: Bool
    let showAllHistory: () -> Void
    let actions: () -> MusicDiscoveryActions

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsAllHistoryButton {
                Button(action: showAllHistory) {
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

            actions()
        }
    }
}

struct MusicDiscoveryActions: View {
    let isShareDisabled: Bool
    let shareAction: () -> Void
    let clearAction: () -> Void

    init(
        isShareDisabled: Bool,
        shareAction: @escaping () -> Void,
        clearAction: @escaping () -> Void
    ) {
        self.isShareDisabled = isShareDisabled
        self.shareAction = shareAction
        self.clearAction = clearAction
    }

    init(
        snapshot: MusicLibraryDerivedState,
        shareAction: @escaping (MusicLibraryDerivedState) -> Void,
        clearAction: @escaping () -> Void
    ) {
        self.init(
            isShareDisabled: snapshot.filteredDiscoveries.isEmpty,
            shareAction: { shareAction(snapshot) },
            clearAction: clearAction
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: shareAction) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(TuneAVTheme.mutedSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.library.discoveries.share"))
            .accessibilityIdentifier("discoveries.share")
            .disabled(isShareDisabled)

            Button(action: clearAction) {
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
}

struct MusicDiscoveryArtistList: View {
    let snapshot: MusicLibraryDerivedState
    @Binding var openAviActionsID: String?
    let currentMode: MusicContentMode
    let openArtist: (DiscoveryArtistSummary, MusicContentMode) -> Void
    let openArtistSongs: (DiscoveryArtistSummary) -> Void
    let openArtistRadios: (DiscoveryArtistSummary, MusicContentMode) -> Void
    let openYouTube: (DiscoveryArtistSummary) -> Void
    let openAppleMusic: (DiscoveryArtistSummary) -> Void
    let openSpotify: (DiscoveryArtistSummary) -> Void
    let showMoreArtists: () -> Void

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(Array(snapshot.visibleArtistSummariesForMode.enumerated()), id: \.element.id) { index, artist in
                DiscoveryArtistRow(
                    summary: artist,
                    openAviActionsID: $openAviActionsID,
                    openArtist: { openArtist(artist, currentMode) },
                    openArtistSongs: { openArtistSongs(artist) },
                    openArtistRadios: { openArtistRadios(artist, currentMode) },
                    openYouTube: { openYouTube(artist) },
                    openAppleMusic: { openAppleMusic(artist) },
                    openSpotify: { openSpotify(artist) }
                )
                .zIndex(openAviActionsID == "artist-\(artist.id)" ? 10_000 : Double(snapshot.visibleArtistSummariesForMode.count - index))
            }

            if snapshot.canShowMoreArtists {
                ShowMoreButton(
                    title: L10n.string("common.showMore"),
                    remainingCount: snapshot.filteredArtistSummaries.count - snapshot.visibleArtistSummariesForMode.count,
                    action: showMoreArtists
                )
            }
        }
    }
}

struct MusicDiscoveryTrackList: View {
    let snapshot: MusicLibraryDerivedState
    @Binding var openAviActionsID: String?
    let currentMode: MusicContentMode
    let stationArtworkURL: (DiscoveredTrack) -> URL?
    let trackFeedback: (DiscoveredTrack) -> TuneAVStationFeedback?
    let openTrackInfo: (DiscoveredTrack, MusicContentMode) -> Void
    let openArtistInfo: (DiscoveredTrack, MusicContentMode) -> Void
    let openStationInfo: (DiscoveredTrack) -> Void
    let toggleSaved: (DiscoveredTrack) -> Void
    let openYouTube: (DiscoveredTrack) -> Void
    let openLyrics: (DiscoveredTrack) -> Void
    let openAppleMusic: (DiscoveredTrack) -> Void
    let openSpotify: (DiscoveredTrack) -> Void
    let hideAction: (DiscoveredTrack) -> Void
    let removeAction: (DiscoveredTrack) -> Void
    let showMoreDiscoveries: () -> Void

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(Array(snapshot.visibleFilteredDiscoveries.enumerated()), id: \.element.discoveryID) { index, discovery in
                DiscoveryTrackCard(
                    discovery: discovery,
                    stationArtworkURL: stationArtworkURL(discovery),
                    feedback: trackFeedback(discovery),
                    showsSaveButton: false,
                    openAviActionsID: $openAviActionsID,
                    openTrackInfo: { openTrackInfo(discovery, currentMode) },
                    openArtistInfo: { openArtistInfo(discovery, currentMode) },
                    openStationInfo: { openStationInfo(discovery) },
                    toggleSaved: { toggleSaved(discovery) },
                    openYouTube: { openYouTube(discovery) },
                    openLyrics: { openLyrics(discovery) },
                    openAppleMusic: { openAppleMusic(discovery) },
                    openSpotify: { openSpotify(discovery) },
                    hideAction: { hideAction(discovery) },
                    removeAction: { removeAction(discovery) }
                )
                .zIndex(openAviActionsID == "track-\(discovery.discoveryID)" ? 10_000 : Double(snapshot.visibleFilteredDiscoveries.count - index))
            }

            if snapshot.canShowMoreDiscoveries {
                ShowMoreButton(
                    title: L10n.string("common.showMore"),
                    remainingCount: snapshot.filteredDiscoveries.count - snapshot.visibleFilteredDiscoveries.count,
                    action: showMoreDiscoveries
                )
            }
        }
    }
}

struct HiddenDiscoveryUndoBanner: View {
    let bottomContentPadding: CGFloat
    let horizontalPadding: CGFloat
    let restoreAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)

            Text(L10n.string("shell.music.discovery.hidden"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: restoreAction) {
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
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, max(98, bottomContentPadding - 18))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discoveries.hiddenUndo")
    }
}

struct MusicHiddenDiscoveryUndoOverlay: View {
    let hiddenDiscovery: DiscoveredTrack?
    let bottomContentPadding: CGFloat
    let horizontalPadding: CGFloat
    let restoreAction: (DiscoveredTrack) -> Void

    var body: some View {
        if let hiddenDiscovery {
            HiddenDiscoveryUndoBanner(
                bottomContentPadding: bottomContentPadding,
                horizontalPadding: horizontalPadding,
                restoreAction: { restoreAction(hiddenDiscovery) }
            )
        }
    }
}
