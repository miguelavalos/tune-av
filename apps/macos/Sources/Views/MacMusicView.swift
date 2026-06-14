import AppKit
import AVAppShellFoundation
import AVAviFoundation
import SwiftUI

struct MacMusicView: View {
    private static let pageSize = 40
    private static let overviewLimit = 12

    enum Mode: String, CaseIterable, Identifiable {
        case songs
        case artists
        case top
        case history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .songs:
                L10n.string("shell.music.mode.songs")
            case .artists:
                L10n.string("shell.music.mode.artists")
            case .top:
                L10n.string("shell.music.mode.top")
            case .history:
                L10n.string("shell.music.mode.history")
            }
        }

        var systemImage: String {
            switch self {
            case .songs:
                "bookmark.fill"
            case .artists:
                "person.2.fill"
            case .top:
                "sparkles"
            case .history:
                "clock.fill"
            }
        }

        var libraryMode: TuneAVMusicLibraryMode {
            switch self {
            case .songs:
                return .songs
            case .artists:
                return .artists
            case .top, .history:
                return .history
            }
        }

        var subtitle: String {
            switch self {
            case .songs:
                L10n.string("shell.music.detail.songs.subtitle")
            case .artists:
                L10n.string("shell.music.detail.artists.subtitle")
            case .top:
                L10n.string("shell.music.detail.top.subtitle")
            case .history:
                L10n.string("shell.music.detail.history.subtitle")
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent
        case alphabetical
        case strongest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent:
                L10n.string("shell.music.sort.recent")
            case .alphabetical:
                L10n.string("shell.library.sort.alphabetical")
            case .strongest:
                L10n.string("shell.music.sort.strongest")
            }
        }
    }

    @EnvironmentObject private var model: TuneAVMacModel
    @Environment(\.openURL) private var openURL
    @State private var mode: Mode = .songs
    @State private var isShowingOverview = true
    @State private var isSearchExpanded = false
    @State private var selectedArtistName: String?
    @State private var visibleDiscoveryLimit = pageSize
    @State private var visibleArtistLimit = pageSize
    @State private var query = ""
    @State private var hiddenDiscovery: MacDiscoveredTrack?
    @State private var isConfirmingClear = false
    @State private var copiedShareText = false
    @State private var openAviActionsID: String?
    @State private var cachedVisibleDiscoveries: [MacDiscoveredTrack] = []
    @State private var cachedSavedDiscoveries: [MacDiscoveredTrack] = []
    @State private var cachedTopDiscoveries: [MacDiscoveredTrack] = []
    @State private var cachedArtistSummaries: [TuneAVDiscoveryArtistSummary] = []
    @AppStorage("tuneav.music.sort") private var sortRawValue = Sort.recent.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MacMusicAviHeader(detail: musicAviDetail)

                if isShowingOverview && trimmedQuery.isEmpty {
                    overview
                } else {
                    controls
                    content
                }

                if let hiddenDiscovery {
                    undoHiddenDiscoveryBanner(hiddenDiscovery)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .onChange(of: query) { _, _ in
            selectedArtistName = nil
            resetVisibleLimits()
        }
        .onChange(of: mode) { _, _ in resetVisibleLimits() }
        .onChange(of: sortRawValue) { _, _ in resetVisibleLimits() }
        .task {
            refreshCachedLibraryViews()
        }
        .onChange(of: model.discoveredTracks) { _, _ in
            refreshCachedLibraryViews()
        }
        .onChange(of: model.tunedTrackDiscoveries) { _, _ in
            refreshCachedTopDiscoveries()
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            RadioOverviewMetricGrid {
                MacMusicOverviewCard(title: L10n.string("shell.music.overview.songs"), value: savedDiscoveries.count, systemImage: "music.note.list", isSelected: !isShowingOverview && mode == .songs) {
                    openMode(.songs)
                }
                MacMusicOverviewCard(title: L10n.string("shell.music.overview.artists"), value: artistSummaries.count, systemImage: "person.2.fill", isSelected: !isShowingOverview && mode == .artists) {
                    openMode(.artists)
                }
                MacMusicOverviewCard(title: L10n.string("shell.music.overview.top"), value: topDiscoveries.count, systemImage: "sparkles", isSelected: !isShowingOverview && mode == .top) {
                    openMode(.top)
                }
                MacMusicOverviewCard(title: L10n.string("shell.music.overview.history"), value: visibleDiscoveries.count, systemImage: "clock.fill", isSelected: !isShowingOverview && mode == .history) {
                    openMode(.history)
                }
            }
            .frame(maxWidth: 860, alignment: .leading)

            VStack(alignment: .leading, spacing: 24) {
                if hasOverviewContent {
                    overviewSection(
                        title: L10n.string("shell.music.overview.songs"),
                        subtitle: L10n.string("shell.music.detail.songs.subtitle"),
                        mode: .songs,
                        discoveries: Array(savedDiscoveries.prefix(Self.overviewLimit))
                    )

                    overviewArtistsSection

                    overviewSection(
                        title: L10n.string("shell.music.overview.top"),
                        subtitle: L10n.string("shell.music.detail.top.subtitle"),
                        mode: .top,
                        discoveries: Array(topDiscoveries.prefix(Self.overviewLimit))
                    )

                    overviewSection(
                        title: L10n.string("shell.music.overview.history"),
                        subtitle: L10n.string("shell.music.detail.history.subtitle"),
                        mode: .history,
                        discoveries: Array(visibleDiscoveries.prefix(Self.overviewLimit))
                    )
                } else {
                    ContentUnavailableView(
                        L10n.string("shell.music.overview.empty"),
                        systemImage: "music.note",
                        description: Text(L10n.string("shell.music.overview.empty.detail"))
                    )
                .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: showOverview) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .musicToolbarCapsule()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.accessibility.showOverview"))
                .accessibilityIdentifier("music.overview")

                HStack(spacing: 4) {
                    ForEach(Mode.allCases) { item in
                        Button {
                            mode = item
                        } label: {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(mode == item ? Color.white : TuneAVTheme.textSecondary)
                                .frame(width: 44, height: 40)
                                .background(mode == item ? TuneAVTheme.highlight.opacity(0.86) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                        .accessibilityIdentifier("music.mode.\(item.rawValue)")
                    }
                }
                .padding(4)
                .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }

                Spacer()

                Button {
                    shareDiscoveries()
                } label: {
                    Image(systemName: copiedShareText ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(TuneAVTheme.mutedSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(filteredDiscoveries.isEmpty)
                .help(copiedShareText ? L10n.string("common.done") : L10n.string("common.share"))
                .accessibilityLabel(L10n.string("shell.library.discoveries.share"))
                .accessibilityIdentifier("discoveries.share")

                if isConfirmingClear {
                    Button(role: .destructive) {
                        model.clearDiscoveredTracks()
                        isConfirmingClear = false
                    } label: {
                        Label(L10n.string("shell.library.discoveries.clear.confirmAction"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.string("common.cancel")) {
                        isConfirmingClear = false
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.17, blue: 0.38))
                            .frame(width: 36, height: 36)
                            .background(TuneAVTheme.mutedSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(visibleDiscoveries.isEmpty)
                    .help(L10n.string("shell.library.discoveries.clear"))
                    .accessibilityLabel(L10n.string("shell.library.discoveries.clear"))
                    .accessibilityIdentifier("discoveries.clear")
                }

                Menu {
                    ForEach(Sort.allCases) { item in
                        Button {
                            sortBinding.wrappedValue = item
                        } label: {
                            Label(item.title, systemImage: currentSort == item ? "checkmark" : "arrow.up.arrow.down")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .musicToolbarCapsule()
                }
                .buttonStyle(.plain)
                .help(L10n.string("shell.library.sort.title"))
                .accessibilityLabel(L10n.string("shell.music.sort.accessibilityLabel", currentSort.title))
                .accessibilityIdentifier("music.sort")

                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        isSearchExpanded.toggle()
                        if !isSearchExpanded {
                            query = ""
                        }
                    }
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(isSearchExpanded ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
                        .musicToolbarCapsule(
                            fill: isSearchExpanded ? TuneAVTheme.highlight : TuneAVTheme.mutedSurface,
                            stroke: isSearchExpanded ? TuneAVTheme.highlight.opacity(0.5) : TuneAVTheme.borderSubtle
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.string("shell.library.searchPrompt"))
                .accessibilityLabel(L10n.string("shell.music.searchAccess.title"))
                .accessibilityIdentifier("music.searchToggle")
            }
            .frame(maxWidth: 860, alignment: .leading)

            if isSearchExpanded {
                AVAppShellSearchField(
                    query: $query,
                    prompt: L10n.string("shell.library.searchPrompt"),
                    clearTitle: L10n.string("common.clear")
                )
                    .frame(maxWidth: 520)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .artists:
            artistGrid
        case .songs, .top, .history:
            discoverySection(discoveriesForCurrentMode)
        }
    }

    private func discoverySection(_ discoveries: [MacDiscoveredTrack]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MacMusicSectionHeader(title: mode.title, subtitle: mode.subtitle)

            if discoveries.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "music.note",
                    description: Text(emptyDetail)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(discoveries) { discovery in
                        MacMusicDiscoveryTrackCard(
                            discovery: discovery,
                            feedback: model.feedback(for: discovery),
                            showsSaveButton: false,
                            openAviActionsID: $openAviActionsID,
                            openTrackInfo: { model.openMusicTrackDetail(discovery) },
                            openArtistInfo: { model.openMusicArtistDetail(discovery.artistDisplayText) },
                            openStationInfo: { openDiscoveryStation(discovery) },
                            toggleSaved: { model.toggleDiscoverySaved(discovery) },
                            hideAction: {
                                hiddenDiscovery = discovery
                                model.hideDiscovery(discovery)
                            },
                            removeAction: { model.removeDiscovery(discovery) },
                            openYouTube: { openDiscoverySearch(discovery, destination: .youtube) },
                            openLyrics: { openDiscoverySearch(discovery, destination: .web, suffix: "lyrics") },
                            openAppleMusic: { openDiscoverySearch(discovery, destination: .appleMusic) },
                            openSpotify: { openDiscoverySearch(discovery, destination: .spotify) }
                        )
                    }

                    if canShowMoreDiscoveries {
                        showMoreButton(remaining: filteredDiscoveries.count - visibleFilteredDiscoveries.count) {
                            visibleDiscoveryLimit += Self.pageSize
                        }
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
            }
        }
    }

    private var artistGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            MacMusicSectionHeader(title: L10n.string("shell.music.artists.title"), subtitle: L10n.string("shell.music.detail.artists.subtitle"))

            if artistNames.isEmpty {
                ContentUnavailableView(
                    L10n.string("shell.music.artists.empty"),
                    systemImage: "person.2",
                    description: Text(L10n.string("shell.music.artists.empty.detail"))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleArtistSummaries) { artist in
                        MacMusicDiscoveryArtistRow(
                            summary: artist,
                            openAviActionsID: $openAviActionsID,
                            openArtist: { model.openMusicArtistDetail(artist.name) },
                            openArtistSongs: { openArtistSongs(artist.name) },
                            openArtistRadios: { query = artist.name },
                            openYouTube: { openArtistSearch(artist.name, destination: .youtube) },
                            openAppleMusic: { openArtistSearch(artist.name, destination: .appleMusic) },
                            openSpotify: { openArtistSearch(artist.name, destination: .spotify) }
                        )
                    }

                    if canShowMoreArtists {
                        showMoreButton(remaining: filteredArtistSummaries.count - visibleArtistSummaries.count) {
                            visibleArtistLimit += Self.pageSize
                        }
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
            }
        }
    }

    private var discoveriesForCurrentMode: [MacDiscoveredTrack] {
        switch mode {
        case .top:
            return visibleFilteredDiscoveries
        case .history:
            return visibleFilteredDiscoveries
        case .songs, .artists:
            return visibleFilteredDiscoveries
        }
    }

    private var visibleDiscoveries: [MacDiscoveredTrack] {
        cachedVisibleDiscoveries
    }

    private var savedDiscoveries: [MacDiscoveredTrack] {
        cachedSavedDiscoveries
    }

    private var filteredDiscoveries: [MacDiscoveredTrack] {
        let baseDiscoveries: [MacDiscoveredTrack]
        switch mode {
        case .songs, .artists:
            baseDiscoveries = savedDiscoveries
        case .top, .history:
            baseDiscoveries = topDiscoveries
        }

        let artistFilteredDiscoveries: [MacDiscoveredTrack]
        if let selectedArtistName {
            artistFilteredDiscoveries = baseDiscoveries.filter {
                $0.artistDisplayText.compare(
                    selectedArtistName,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
        } else {
            artistFilteredDiscoveries = baseDiscoveries
        }

        let filtered: [MacDiscoveredTrack]
        if let trimmedQuery = TuneAVText.normalizedValue(query) {
            filtered = artistFilteredDiscoveries.filter { discovery in
                discovery.title.localizedCaseInsensitiveContains(trimmedQuery)
                    || discovery.artist?.localizedCaseInsensitiveContains(trimmedQuery) == true
                    || discovery.stationName.localizedCaseInsensitiveContains(trimmedQuery)
            }
        } else {
            filtered = artistFilteredDiscoveries
        }

        if mode == .top {
            return sortTunedDiscoveries(filtered)
        }

        switch currentSort {
        case .recent:
            return filtered.sorted { $0.playedAt > $1.playedAt }
        case .alphabetical:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .strongest:
            return strongestSortedDiscoveries(filtered)
        }
    }

    private var visibleFilteredDiscoveries: [MacDiscoveredTrack] {
        Array(filteredDiscoveries.prefix(visibleDiscoveryLimit))
    }

    private var topDiscoveries: [MacDiscoveredTrack] {
        cachedTopDiscoveries
    }

    private var artistNames: [String] {
        artistSummaries.map(\.name)
    }

    private var artistSummaries: [TuneAVDiscoveryArtistSummary] {
        cachedArtistSummaries
    }

    private var filteredArtistSummaries: [TuneAVDiscoveryArtistSummary] {
        let summaries: [TuneAVDiscoveryArtistSummary]
        if let trimmedQuery = TuneAVText.normalizedValue(query) {
            summaries = TuneAVMusicLibraryLogic.artistSummariesForSavedDiscoveries(
                savedDiscoveries.filter { discovery in
                    discovery.artist?.localizedCaseInsensitiveContains(trimmedQuery) == true
                        || discovery.title.localizedCaseInsensitiveContains(trimmedQuery)
                },
                locale: L10n.locale
            )
        } else {
            summaries = artistSummaries
        }

        switch currentSort {
        case .recent, .strongest:
            return summaries
        case .alphabetical:
            return summaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var visibleArtistSummaries: [TuneAVDiscoveryArtistSummary] {
        Array(filteredArtistSummaries.prefix(visibleArtistLimit))
    }

    private var hasOverviewContent: Bool {
        !savedDiscoveries.isEmpty || !visibleDiscoveries.isEmpty || !topDiscoveries.isEmpty || !artistSummaries.isEmpty
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentSort: Sort {
        Sort(rawValue: sortRawValue) ?? .recent
    }

    private var sortBinding: Binding<Sort> {
        Binding {
            currentSort
        } set: { sortRawValue = $0.rawValue }
    }

    private var canShowMoreDiscoveries: Bool {
        visibleFilteredDiscoveries.count < filteredDiscoveries.count
    }

    private var canShowMoreArtists: Bool {
        visibleArtistSummaries.count < filteredArtistSummaries.count
    }

    private var emptyTitle: String {
        if visibleDiscoveries.isEmpty {
            return L10n.string("shell.library.discoveries.empty")
        }
        if !trimmedQuery.isEmpty {
            return L10n.string("shell.library.discoveries.noMatch")
        }
        switch mode {
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

    private var emptyDetail: String {
        if visibleDiscoveries.isEmpty {
            return L10n.string("shell.library.discoveries.empty.detail")
        }
        if !trimmedQuery.isEmpty {
            return L10n.string("shell.library.discoveries.noMatch.detail")
        }
        switch mode {
        case .songs:
            return L10n.string("shell.library.discoveries.savedEmpty.detail")
        case .artists:
            return L10n.string("shell.music.artists.empty.detail")
        case .top:
            return L10n.string("shell.music.detail.top.subtitle")
        case .history:
            return L10n.string("shell.library.discoveries.noMatch.detail")
        }
    }

    private var musicAviDetail: String {
        if visibleDiscoveries.isEmpty {
            return L10n.string("shell.music.avi.detail.empty")
        }
        let discoveriesText = L10n.plural(singular: "shell.count.discovery.one", plural: "shell.count.discovery.other", count: visibleDiscoveries.count, visibleDiscoveries.count)
        let savedText = L10n.plural(singular: "shell.count.savedSong.one", plural: "shell.count.savedSong.other", count: savedDiscoveries.count, savedDiscoveries.count)
        return L10n.string("shell.music.avi.detail.summary", discoveriesText, savedText)
    }

    @ViewBuilder
    private func overviewSection(title: String, subtitle: String, mode: Mode, discoveries: [MacDiscoveredTrack]) -> some View {
        if !discoveries.isEmpty {
            RadioOverviewCarouselSection(title: title, subtitle: subtitle, action: { openMode(mode) }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(discoveries) { discovery in
                            MacMusicDiscoveryTrackCard(
                                discovery: discovery,
                                feedback: model.feedback(for: discovery),
                                showsSaveButton: false,
                                openAviActionsID: $openAviActionsID,
                                openTrackInfo: { model.openMusicTrackDetail(discovery) },
                                openArtistInfo: { model.openMusicArtistDetail(discovery.artistDisplayText) },
                                openStationInfo: { openDiscoveryStation(discovery) },
                                toggleSaved: { model.toggleDiscoverySaved(discovery) },
                                hideAction: {
                                    hiddenDiscovery = discovery
                                    model.hideDiscovery(discovery)
                                },
                                removeAction: { model.removeDiscovery(discovery) },
                                openYouTube: { openDiscoverySearch(discovery, destination: .youtube) },
                                openLyrics: { openDiscoverySearch(discovery, destination: .web, suffix: "lyrics") },
                                openAppleMusic: { openDiscoverySearch(discovery, destination: .appleMusic) },
                                openSpotify: { openDiscoverySearch(discovery, destination: .spotify) }
                            )
                            .frame(width: 252)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private var overviewArtistsSection: some View {
        let artists = Array(artistSummaries.prefix(Self.overviewLimit))
        if !artists.isEmpty {
            RadioOverviewCarouselSection(
                title: L10n.string("shell.music.overview.artists"),
                subtitle: L10n.string("shell.music.detail.artists.subtitle"),
                action: { openMode(.artists) }
            ) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(artists) { artist in
                            MacMusicDiscoveryArtistRow(
                                summary: artist,
                                openAviActionsID: $openAviActionsID,
                                openArtist: { model.openMusicArtistDetail(artist.name) },
                                openArtistSongs: { openArtistSongs(artist.name) },
                                openArtistRadios: { query = artist.name },
                                openYouTube: { openArtistSearch(artist.name, destination: .youtube) },
                                openAppleMusic: { openArtistSearch(artist.name, destination: .appleMusic) },
                                openSpotify: { openArtistSearch(artist.name, destination: .spotify) }
                            )
                            .frame(width: 252)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func openMode(_ nextMode: Mode) {
        mode = nextMode
        isShowingOverview = false
        selectedArtistName = nil
        resetVisibleLimits()
    }

    private func showOverview() {
        query = ""
        isSearchExpanded = false
        selectedArtistName = nil
        isConfirmingClear = false
        openAviActionsID = nil
        resetVisibleLimits()
        isShowingOverview = true
    }

    private func openArtistSongs(_ artistName: String) {
        selectedArtistName = artistName
        query = artistName
        mode = .songs
        isShowingOverview = false
        resetVisibleLimits()
    }

    private func resetVisibleLimits() {
        visibleDiscoveryLimit = Self.pageSize
        visibleArtistLimit = Self.pageSize
    }

    private func refreshCachedLibraryViews() {
        cachedVisibleDiscoveries = TuneAVMusicLibraryLogic.visibleDiscoveries(model.discoveredTracks)
        cachedSavedDiscoveries = cachedVisibleDiscoveries.filter(\.isMarkedInteresting)
        cachedArtistSummaries = TuneAVMusicLibraryLogic.artistSummariesForSavedDiscoveries(cachedSavedDiscoveries, locale: L10n.locale)
        refreshCachedTopDiscoveries()
    }

    private func refreshCachedTopDiscoveries() {
        cachedTopDiscoveries = sortTunedDiscoveries(model.tunedTrackDiscoveries)
    }

    private func sortTunedDiscoveries(_ discoveries: [MacDiscoveredTrack]) -> [MacDiscoveredTrack] {
        discoveries.sorted { first, second in
            let firstRank = feedbackRank(model.feedback(for: first))
            let secondRank = feedbackRank(model.feedback(for: second))
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

    private func strongestSortedDiscoveries(_ discoveries: [MacDiscoveredTrack]) -> [MacDiscoveredTrack] {
        let counts = Dictionary(grouping: discoveries, by: discoveryIdentityKey(_:)).mapValues(\.count)
        return discoveries.sorted { first, second in
            let firstCount = counts[discoveryIdentityKey(first), default: 0]
            let secondCount = counts[discoveryIdentityKey(second), default: 0]
            if firstCount == secondCount {
                return first.playedAt > second.playedAt
            }
            return firstCount > secondCount
        }
    }

    private func discoveryIdentityKey(_ discovery: MacDiscoveredTrack) -> String {
        "\(TuneAVText.normalizedValue(discovery.artistDisplayText) ?? discovery.artistDisplayText.lowercased())|\(TuneAVText.normalizedValue(discovery.title) ?? discovery.title.lowercased())"
    }

    private func showMoreButton(remaining: Int, action: @escaping () -> Void) -> some View {
        AVAppShellShowMoreButton(
            title: L10n.string("common.showMoreCount", L10n.string("common.showMore"), remaining),
            accessibilityIdentifier: "music.showMore",
            action: action
        )
    }

    private func shareDiscoveries() {
        guard model.canPerformPremiumAviAction(feature: .discoveryShare, usageKey: "music.discoveries") else { return }
        let text = TuneAVDiscoveryShareTextFormatter.listText(
            title: L10n.string("shell.library.discoveries.shareTitle"),
            discoveries: filteredDiscoveries
        )
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedShareText = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedShareText = false
        }
    }

    private func openDiscoverySearch(_ discovery: MacDiscoveredTrack, destination: TuneAVExternalSearchURL.Destination, suffix: String? = nil) {
        let query = [discovery.searchQuery, suffix].compactMap { $0 }.joined(separator: " ")
        guard model.canPerformPremiumAviSearch(destination: destination, suffix: suffix, usageKey: query) else { return }
        guard let url = TuneAVExternalSearchURL.url(for: destination, query: query) else { return }
        openURL(url)
    }

    private func openArtistSearch(_ artist: String, destination: TuneAVExternalSearchURL.Destination) {
        guard model.canPerformPremiumAviSearch(destination: destination, usageKey: artist) else { return }
        guard let url = TuneAVExternalSearchURL.url(for: destination, query: artist) else { return }
        openURL(url)
    }

    private func openDiscoveryStation(_ discovery: MacDiscoveredTrack) {
        guard let station = (model.recentStations + model.favoriteStations + model.featuredStations).first(where: { $0.id == discovery.stationID }) else { return }
        model.openStationDetail(station, queue: [station])
    }

    private func undoHiddenDiscoveryBanner(_ discovery: MacDiscoveredTrack) -> some View {
        HStack(spacing: 12) {
            Text(L10n.string("player.discovery.hide"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Spacer()

            Button(L10n.string("common.undo")) {
                model.restoreDiscovery(discovery)
                hiddenDiscovery = nil
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
        .frame(maxWidth: 860)
    }
}

private struct MacMusicAviHeader: View {
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("shell.music.title"))
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Spacer()
        }
    }
}

private struct MacMusicOverviewSection<Content: View>: View {
    let title: String
    let subtitle: String
    let open: () -> Void
    let content: Content

    init(title: String, subtitle: String, open: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.open = open
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                MacMusicSectionHeader(title: title, subtitle: subtitle)

                Spacer(minLength: 8)

                Button(action: open) {
                    HStack(spacing: 4) {
                        Text(L10n.string("common.view"))
                            .font(.system(size: 13, weight: .black))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .black))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(TuneAVTheme.highlight)
            }

            content
        }
    }
}

private struct MacMusicPillButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .black))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(isSelected ? TuneAVTheme.highlight.opacity(0.18) : TuneAVTheme.cardSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.52) : TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func musicToolbarCapsule(
        fill: Color = TuneAVTheme.mutedSurface,
        stroke: Color = TuneAVTheme.borderSubtle
    ) -> some View {
        frame(width: 40, height: 40)
            .background(fill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(stroke, lineWidth: 1)
            }
    }
}

private struct MacMusicSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(subtitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
        }
    }
}

private struct MacMusicOverviewCard: View {
    let title: String
    let value: Int
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(value)")
                        .font(.system(size: 24, weight: .bold))
                }

                Spacer()
            }
            .padding(14)
            .frame(minHeight: 82)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.45) : TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(TuneAVTheme.textPrimary)
    }
}

struct MacMusicDiscoveryTrackCard: View {
    let discovery: MacDiscoveredTrack
    let feedback: TuneAVStationFeedback?
    var showsSaveButton = true
    @Binding var openAviActionsID: String?
    let openTrackInfo: () -> Void
    let openArtistInfo: () -> Void
    let openStationInfo: () -> Void
    let toggleSaved: () -> Void
    let hideAction: () -> Void
    let removeAction: () -> Void
    let openYouTube: () -> Void
    let openLyrics: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void
    @State private var aviActionsPage = 0

    private var aviActionsID: String {
        "track-\(discovery.discoveryID)"
    }

    private var isShowingAviActions: Bool {
        openAviActionsID == aviActionsID
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openTrackInfo) {
                HStack(spacing: 12) {
                    feedbackArtwork(size: 54, badgeSize: 22, badgeFontSize: 9, badgeOffset: -5)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(discovery.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(1)

                        Text(discovery.artistDisplayText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .lineLimit(1)

                        Text(discovery.stationName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.82))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(discovery.title), \(discovery.artistDisplayText), \(discovery.stationName)")
            .accessibilityHint(L10n.string("shell.music.discovery.openTrackInfo.hint"))
            .accessibilityIdentifier("discoveryTrack.openInfo.\(discovery.discoveryID)")

            if showsSaveButton {
                saveButton
            }
            aviActionsMenu
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discoveryTrack.\(discovery.discoveryID)")
    }

    private func feedbackArtwork(size: CGFloat, badgeSize: CGFloat, badgeFontSize: CGFloat, badgeOffset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            artwork

            if let feedback {
                TuneAVFeedbackBadge(feedback: feedback, size: badgeSize, fontSize: badgeFontSize)
                    .offset(x: badgeOffset, y: badgeOffset)
            }
        }
        .frame(width: size, height: size)
    }

    private var saveButton: some View {
        Button(action: toggleSaved) {
            Image(systemName: discovery.isMarkedInteresting ? "bookmark.fill" : "bookmark")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(discovery.isMarkedInteresting ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                .frame(width: 36, height: 36)
                .background(TuneAVTheme.mutedSurface, in: Circle())
                .overlay {
                    Circle()
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.save"))
        .accessibilityIdentifier("discoveryTrack.save.\(discovery.discoveryID)")
    }

    private var aviActionsMenu: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                if isShowingAviActions {
                    openAviActionsID = nil
                } else {
                    aviActionsPage = 0
                    openAviActionsID = aviActionsID
                }
            }
        } label: {
            AVAviAvatarBadge(backgroundStyle: .muted) {
                Image("AviV2HeadNeutral")
                    .resizable()
                    .scaledToFit()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.avi.actions.askShort"))
        .accessibilityIdentifier("discoveryTrack.menu.\(discovery.discoveryID)")
        .popover(
            isPresented: Binding(
                get: { isShowingAviActions },
                set: { if !$0 { closeAviActions() } }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            aviActionsPanel
                .frame(width: 278)
                .presentationCompactAdaptation(.none)
        }
    }

    private var aviActionsPanel: some View {
        TuneAviPopoverActionsPanel(
            page: aviActionsPage,
            pageCount: 2,
            previous: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = max(0, aviActionsPage - 1) } },
            next: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = min(1, aviActionsPage + 1) } },
            close: closeAviActions
        ) {
            if aviActionsPage == 0 {
                AVAviPanelOptionButton(
                    title: discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                    systemImage: discovery.isMarkedInteresting ? "bookmark.slash" : "bookmark",
                    accessibilityIdentifier: "discoveryTrack.save.\(discovery.discoveryID)"
                ) {
                    toggleSaved()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("shell.music.discovery.openTrackInfo.action"), systemImage: "info.circle") {
                    openTrackInfo()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("player.artist.view"), systemImage: "person.crop.circle") {
                    openArtistInfo()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("shell.music.discovery.openStation.action"), systemImage: "dot.radiowaves.left.and.right") {
                    openStationInfo()
                    closeAviActions()
                }
            } else {
                AVAviPanelOptionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle", action: runAndClose(openYouTube))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.lyrics"), systemImage: "text.quote", action: runAndClose(openLyrics))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note", action: runAndClose(openAppleMusic))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3", action: runAndClose(openSpotify))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.hide"), systemImage: "eye.slash", action: runAndClose(hideAction))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.remove"), systemImage: "trash", action: runAndClose(removeAction))
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = discovery.resolvedArtworkURL ?? discovery.resolvedStationArtworkURL {
            AVFramedArtwork(size: 54, cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 54)) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: 54, scale: NSScreen.main?.backingScaleFactor ?? 2) {
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        MacMusicCompactArtworkFallback(systemImage: "music.note", size: 54)
    }

    private func closeAviActions() {
        withAnimation(.snappy(duration: 0.18)) {
            openAviActionsID = nil
            aviActionsPage = 0
        }
    }

    private func runAndClose(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            closeAviActions()
        }
    }
}

struct MacMusicDiscoveryArtistRow: View {
    private let artworkSize: CGFloat = 54

    let summary: TuneAVDiscoveryArtistSummary
    @Binding var openAviActionsID: String?
    let openArtist: () -> Void
    let openArtistSongs: () -> Void
    let openArtistRadios: () -> Void
    let openYouTube: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void
    @State private var aviActionsPage = 0

    private var aviActionsID: String {
        "artist-\(summary.id)"
    }

    private var isShowingAviActions: Bool {
        openAviActionsID == aviActionsID
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openArtist) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(1)

                        Text(L10n.plural(
                            singular: "shell.library.discoveries.artistSongs.one",
                            plural: "shell.library.discoveries.artistSongs.other",
                            count: summary.trackCount,
                            summary.trackCount
                        ))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    if isShowingAviActions {
                        openAviActionsID = nil
                    } else {
                        aviActionsPage = 0
                        openAviActionsID = aviActionsID
                    }
                }
            } label: {
                AVAviAvatarBadge(backgroundStyle: .mutedSoft) {
                    Image("AviV2HeadNeutral")
                        .resizable()
                        .scaledToFit()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.avi.actions.askShort"))
            .accessibilityIdentifier("discoveryArtistRow.aviActions.\(summary.id)")
            .popover(
                isPresented: Binding(
                    get: { isShowingAviActions },
                    set: { if !$0 { closeAviActions() } }
                ),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                aviActionsPanel
                    .frame(width: 278)
                    .presentationCompactAdaptation(.none)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("discoveryArtistRow.\(summary.id)")
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = summary.displayArtworkURL {
            AVFramedArtwork(size: artworkSize, cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: artworkSize)) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: artworkSize, scale: NSScreen.main?.backingScaleFactor ?? 2) {
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        MacMusicCompactArtworkFallback(systemImage: "person.fill", size: artworkSize)
    }

    private var aviActionsPanel: some View {
        TuneAviPopoverActionsPanel(
            page: aviActionsPage,
            pageCount: 2,
            previous: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = max(0, aviActionsPage - 1) } },
            next: { withAnimation(.snappy(duration: 0.18)) { aviActionsPage = min(1, aviActionsPage + 1) } },
            close: closeAviActions
        ) {
            if aviActionsPage == 0 {
                AVAviPanelOptionButton(title: L10n.string("shell.music.artist.openDetails"), systemImage: "info.circle") {
                    openArtist()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("shell.music.artist.viewSavedSongs"), systemImage: "music.note.list") {
                    openArtistSongs()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("shell.avi.music.artist.radios"), systemImage: "dot.radiowaves.left.and.right") {
                    openArtistRadios()
                    closeAviActions()
                }
            } else {
                AVAviPanelOptionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle", action: runAndClose(openYouTube))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note", action: runAndClose(openAppleMusic))
                AVAviPanelOptionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3", action: runAndClose(openSpotify))
            }
        }
    }

    private func closeAviActions() {
        withAnimation(.snappy(duration: 0.18)) {
            openAviActionsID = nil
            aviActionsPage = 0
        }
    }

    private func runAndClose(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            closeAviActions()
        }
    }
}

struct MacMusicCompactArtworkFallback: View {
    let systemImage: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(size * 0.32, 16), weight: .black))
            .foregroundStyle(TuneAVTheme.highlight)
            .frame(width: size, height: size)
            .background(TuneAVTheme.highlight.opacity(0.12), in: RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous))
    }
}
