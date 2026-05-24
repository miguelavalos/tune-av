import AVAviFoundation
import AVAppShellFoundation
import SwiftUI

struct MacLibraryView: View {
    private static let pageSize = 40
    private static let overviewLimit = 12

    enum Mode: String, CaseIterable, Identifiable {
        case saved
        case recent
        case tuned
        case music

        var id: String { rawValue }

        var title: String {
            switch self {
            case .saved:
                L10n.string("shell.library.mode.saved")
            case .recent:
                L10n.string("shell.library.mode.recent")
            case .tuned:
                L10n.string("shell.library.overview.tuned")
            case .music:
                L10n.string("shell.library.overview.musicStations")
            }
        }

        var subtitle: String {
            switch self {
            case .saved:
                L10n.string("shell.library.favorites.subtitle")
            case .recent:
                L10n.string("shell.library.recents.subtitle")
            case .tuned:
                L10n.string("shell.avi.signals.feedback.title")
            case .music:
                L10n.string("shell.library.musicStations.subtitle")
            }
        }

        var systemImage: String {
            switch self {
            case .saved:
                "bookmark.fill"
            case .recent:
                "clock.fill"
            case .tuned:
                "slider.horizontal.3"
            case .music:
                "music.note.list"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recentlyAdded
        case alphabetical
        case lastListened

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recentlyAdded:
                L10n.string("shell.library.sort.recentlyAdded")
            case .alphabetical:
                L10n.string("shell.library.sort.alphabetical")
            case .lastListened:
                L10n.string("shell.library.sort.lastListened")
            }
        }
    }

    @EnvironmentObject private var model: TuneAVMacModel
    @Environment(\.openURL) private var openURL
    @State private var mode: Mode = .saved
    @State private var isShowingOverview = true
    @State private var isSearchExpanded = false
    @State private var visibleLimit = pageSize
    @State private var query = ""
    @AppStorage("tuneav.radio.savedSort") private var savedSortRawValue = Sort.lastListened.rawValue
    @AppStorage("tuneav.radio.recentSort") private var recentSortRawValue = Sort.lastListened.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if isShowingOverview && trimmedQuery.isEmpty {
                    overview
                } else {
                    controls
                    stationSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .onChange(of: query) { _, _ in visibleLimit = Self.pageSize }
        .onChange(of: mode) { _, _ in visibleLimit = Self.pageSize }
        .onChange(of: savedSortRawValue) { _, _ in visibleLimit = Self.pageSize }
        .onChange(of: recentSortRawValue) { _, _ in visibleLimit = Self.pageSize }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            AVAviAvatarBadge(imageSize: 42, badgeSize: 58, backgroundStyle: .mutedSoft) {
                Image("AviV2HeadNeutral")
                    .resizable()
                    .scaledToFit()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("shell.library.title"))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(libraryDetail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            metrics

            if hasOverviewContent {
                overviewSection(
                    stations: overviewFavoriteStations,
                    title: L10n.string("shell.library.overview.saved"),
                    subtitle: L10n.string("shell.library.favorites.subtitle"),
                    targetMode: .saved
                )

                overviewSection(
                    stations: overviewRecentStations,
                    title: L10n.string("shell.library.overview.latest.title"),
                    subtitle: L10n.string("shell.library.recents.subtitle"),
                    targetMode: .recent
                )

                overviewSection(
                    stations: overviewTunedStations,
                    title: L10n.string("shell.library.overview.tuned"),
                    subtitle: L10n.string("shell.avi.signals.feedback.title"),
                    targetMode: .tuned
                )

                overviewSection(
                    stations: overviewMusicStations,
                    title: L10n.string("shell.library.overview.musicStations"),
                    subtitle: L10n.string("shell.library.musicStations.subtitle"),
                    targetMode: .music
                )
            } else {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        L10n.string("shell.library.overview.empty"),
                        systemImage: "radio",
                        description: Text(L10n.string("shell.library.overview.empty.detail"))
                    )

                    Button {
                        model.selectedSection = .search
                    } label: {
                        Label(L10n.string("shell.music.overview.empty.action"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            MacLibraryMetricCard(
                title: L10n.string("shell.library.overview.saved"),
                value: model.favoriteStations.count,
                systemImage: "dot.radiowaves.left.and.right",
                tint: TuneAVTheme.highlight,
                isSelected: !isShowingOverview && mode == .saved,
                action: { openMode(.saved) }
            )
            MacLibraryMetricCard(
                title: L10n.string("shell.library.overview.recent"),
                value: model.recentStations.count,
                systemImage: "clock.fill",
                tint: Color(red: 0.17, green: 0.52, blue: 0.96),
                isSelected: !isShowingOverview && mode == .recent,
                action: { openMode(.recent) }
            )
            MacLibraryMetricCard(
                title: L10n.string("shell.library.overview.tuned"),
                value: tunedStations.count,
                systemImage: "slider.horizontal.3",
                tint: Color(red: 0.95, green: 0.48, blue: 0.18),
                isSelected: !isShowingOverview && mode == .tuned,
                action: { openMode(.tuned) }
            )
            MacLibraryMetricCard(
                title: L10n.string("shell.library.overview.musicStations"),
                value: musicStations.count,
                systemImage: "music.note.list",
                tint: Color(red: 0.54, green: 0.43, blue: 0.90),
                isSelected: !isShowingOverview && mode == .music,
                action: { openMode(.music) }
            )
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: showOverview) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .libraryToolbarCapsule()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.accessibility.showOverview"))
                .accessibilityIdentifier("library.overview")

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
                        .accessibilityIdentifier("library.mode.\(item.rawValue)")
                    }
                }
                .padding(4)
                .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }

                Spacer(minLength: 12)

                Menu {
                    ForEach(Sort.allCases) { item in
                        Button {
                            activeSortBinding.wrappedValue = item
                        } label: {
                            Label(item.title, systemImage: activeSort == item ? "checkmark" : "arrow.up.arrow.down")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .libraryToolbarCapsule()
                }
                .buttonStyle(.plain)
                .help(L10n.string("shell.library.sort.title"))

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
                        .libraryToolbarCapsule(
                            fill: isSearchExpanded ? TuneAVTheme.highlight : TuneAVTheme.mutedSurface,
                            stroke: isSearchExpanded ? TuneAVTheme.highlight.opacity(0.5) : TuneAVTheme.borderSubtle
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.string("shell.library.searchPrompt"))
                .accessibilityIdentifier("library.searchToggle")
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

    private var stationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(mode.subtitle)
                .font(.subheadline)
                .foregroundStyle(TuneAVTheme.textSecondary)

            if visibleStations.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "radio",
                    description: Text(emptyDetail)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleStations) { station in
                        MacCompactStationCard(station: station)
                    }

                    if canShowMore {
                        AVAppShellShowMoreButton(
                            title: L10n.string("common.showMoreCount", L10n.string("common.showMore"), remainingCount),
                            accessibilityIdentifier: "library.showMore"
                        ) {
                            visibleLimit += Self.pageSize
                        }
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .environment(\.macStationPlaybackQueue, filteredStations)
            }
        }
    }

    @ViewBuilder
    private func overviewSection(stations: [Station], title: String, subtitle: String, targetMode: Mode) -> some View {
        if !stations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)

                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Button {
                        openMode(targetMode)
                    } label: {
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

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(stations) { station in
                            MacStationArtworkCard(station: station)
                                .frame(width: 258, height: 112)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
                .environment(\.macStationPlaybackQueue, stations)
            }
        }
    }

    private var libraryDetail: String {
        if model.favoriteStations.isEmpty && model.recentStations.isEmpty {
            return L10n.string("shell.library.avi.detail.empty")
        }

        let saved = L10n.plural(
            singular: "shell.count.savedRadio.one",
            plural: "shell.count.savedRadio.other",
            count: model.favoriteStations.count,
            model.favoriteStations.count
        )
        let recent = L10n.plural(
            singular: "shell.count.recentSession.one",
            plural: "shell.count.recentSession.other",
            count: model.recentStations.count,
            model.recentStations.count
        )
        let discoveries = L10n.plural(
            singular: "shell.count.discovery.one",
            plural: "shell.count.discovery.other",
            count: model.savedDiscoveredTracks.count,
            model.savedDiscoveredTracks.count
        )
        return [L10n.string("shell.library.avi.detail.signals", saved, recent), discoveries].joined(separator: " · ")
    }

    private var baseStations: [Station] {
        switch mode {
        case .saved:
            return model.favoriteStations
        case .recent:
            return model.recentStations
        case .tuned:
            return tunedStations
        case .music:
            return musicStations
        }
    }

    private var visibleStations: [Station] {
        Array(filteredStations.prefix(visibleLimit))
    }

    private var filteredStations: [Station] {
        TuneAVLibraryStationLogic.filteredStations(sortedStations(baseStations), query: trimmedQuery)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canShowMore: Bool {
        visibleStations.count < filteredStations.count
    }

    private var remainingCount: Int {
        max(filteredStations.count - visibleStations.count, 0)
    }

    private var activeSort: Sort {
        switch mode {
        case .saved, .tuned:
            return Sort(rawValue: savedSortRawValue) ?? .lastListened
        case .recent, .music:
            return Sort(rawValue: recentSortRawValue) ?? .lastListened
        }
    }

    private var activeSortBinding: Binding<Sort> {
        Binding {
            activeSort
        } set: { nextSort in
            switch mode {
            case .saved, .tuned:
                savedSortRawValue = nextSort.rawValue
            case .recent, .music:
                recentSortRawValue = nextSort.rawValue
            }
        }
    }

    private var hasOverviewContent: Bool {
        !overviewFavoriteStations.isEmpty ||
            !overviewRecentStations.isEmpty ||
            !overviewTunedStations.isEmpty ||
            !overviewMusicStations.isEmpty
    }

    private var overviewFavoriteStations: [Station] {
        Array(model.favoriteStations.prefix(Self.overviewLimit))
    }

    private var overviewRecentStations: [Station] {
        Array(model.recentStations.prefix(Self.overviewLimit))
    }

    private var overviewTunedStations: [Station] {
        Array(tunedStations.prefix(Self.overviewLimit))
    }

    private var overviewMusicStations: [Station] {
        Array(musicStations.prefix(Self.overviewLimit))
    }

    private var tunedStations: [Station] {
        uniquedStations(model.favoriteStations + model.recentStations).filter { station in
            model.stationFeedback[station.id] != nil
        }
    }

    private var musicStations: [Station] {
        uniquedStations(model.discoveredTracks.compactMap { discovery in
            model.recentStations.first { $0.id == discovery.stationID }
                ?? model.favoriteStations.first { $0.id == discovery.stationID }
        })
    }

    private func sortedStations(_ stations: [Station]) -> [Station] {
        switch activeSort {
        case .recentlyAdded:
            return stations
        case .alphabetical:
            return stations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastListened:
            let ranks = Dictionary(model.recentStations.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: min)
            return stations.sorted { first, second in
                let firstRank = ranks[first.id] ?? Int.max
                let secondRank = ranks[second.id] ?? Int.max
                if firstRank == secondRank {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }
                return firstRank < secondRank
            }
        }
    }

    private func uniquedStations(_ stations: [Station]) -> [Station] {
        var seenIDs = Set<String>()
        return stations.filter { station in
            seenIDs.insert(station.id).inserted
        }
    }

    private func openMode(_ nextMode: Mode) {
        mode = nextMode
        isShowingOverview = false
        visibleLimit = Self.pageSize
    }

    private func showOverview() {
        query = ""
        isSearchExpanded = false
        visibleLimit = Self.pageSize
        isShowingOverview = true
    }

    private var emptyTitle: String {
        if !trimmedQuery.isEmpty {
            return L10n.string("shell.library.noMatch.title")
        }

        switch mode {
        case .saved:
            return L10n.string("shell.library.favorites.empty")
        case .recent:
            return L10n.string("shell.library.recents.empty")
        case .tuned, .music:
            return L10n.string("shell.library.overview.empty")
        }
    }

    private var emptyDetail: String {
        if !trimmedQuery.isEmpty {
            return L10n.string("shell.library.favorites.noMatch.detail")
        }

        switch mode {
        case .saved:
            return L10n.string("shell.library.favorites.empty.detail")
        case .recent:
            return L10n.string("shell.library.recents.empty.detail")
        case .tuned, .music:
            return L10n.string("shell.library.overview.empty.detail")
        }
    }
}

private struct MacLibraryPillButton: View {
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
    func libraryToolbarCapsule(
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

struct MacDiscoveryCard: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: TuneAVMacModel
    @State private var isShowingAviActions = false
    @State private var aviActionsPage = 0
    let discovery: MacDiscoveredTrack
    var showsSaveButton = true
    var openTrackInfo: (() -> Void)?
    var openArtistInfo: (() -> Void)?
    var openStationInfo: (() -> Void)?
    var hideAction: (() -> Void)?
    var removeAction: (() -> Void)?
    var openYouTube: (() -> Void)?
    var openLyrics: (() -> Void)?
    var openAppleMusic: (() -> Void)?
    var openSpotify: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { openTrackInfo?() }) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 3) {
                        Text(discovery.title)
                            .font(.system(size: 15, weight: .black))
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
            .disabled(openTrackInfo == nil)

            if showsSaveButton {
                Button {
                    model.toggleDiscoverySaved(discovery)
                } label: {
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
                .help(discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.save"))
            }

            aviActionsButton
        }
        .padding(12)
        .frame(height: 78)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.12), radius: 8, y: 3)
    }

    private var aviActionsButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                if isShowingAviActions {
                    closeAviActions()
                } else {
                    aviActionsPage = 0
                    isShowingAviActions = true
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
        .frame(width: 36, height: 36)
        .fixedSize()
        .help(L10n.string("shell.avi.actions.askShort"))
        .accessibilityLabel(L10n.string("shell.avi.actions.askShort"))
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
                if let openTrackInfo {
                    AVAviPanelOptionButton(title: L10n.string("shell.music.discovery.openTrackInfo.action"), systemImage: "info.circle") {
                        openTrackInfo()
                        closeAviActions()
                    }
                }
                if let openArtistInfo {
                    AVAviPanelOptionButton(title: L10n.string("player.artist.view"), systemImage: "person.crop.circle") {
                        openArtistInfo()
                        closeAviActions()
                    }
                }
                if let openStationInfo {
                    AVAviPanelOptionButton(title: L10n.string("shell.music.discovery.openStation.action"), systemImage: "dot.radiowaves.left.and.right") {
                        openStationInfo()
                        closeAviActions()
                    }
                }
                if showsSaveButton {
                    AVAviPanelOptionButton(
                        title: discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                        systemImage: discovery.isMarkedInteresting ? "bookmark.slash" : "bookmark"
                    ) {
                        model.toggleDiscoverySaved(discovery)
                        closeAviActions()
                    }
                }
            } else {
                AVAviPanelOptionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle") {
                    (openYouTube ?? { openSearch(destination: .youtube) })()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("player.discovery.lyrics"), systemImage: "text.quote") {
                    (openLyrics ?? { openSearch(destination: .web, suffix: "lyrics") })()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note") {
                    (openAppleMusic ?? { openSearch(destination: .appleMusic) })()
                    closeAviActions()
                }
                AVAviPanelOptionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3") {
                    (openSpotify ?? { openSearch(destination: .spotify) })()
                    closeAviActions()
                }
                if let hideAction {
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.hide"), systemImage: "eye.slash") {
                        hideAction()
                        closeAviActions()
                    }
                }
                if let removeAction {
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.remove"), systemImage: "trash") {
                        removeAction()
                        closeAviActions()
                    }
                }
            }
        }
    }

    private func closeAviActions() {
        withAnimation(.snappy(duration: 0.18)) {
            isShowingAviActions = false
            aviActionsPage = 0
        }
    }

    private var artwork: some View {
        Group {
            if let url = discovery.resolvedArtworkURL ?? discovery.resolvedStationArtworkURL {
                TuneAVRemoteArtworkImage(url: url, size: 54, scale: NSScreen.main?.backingScaleFactor ?? 2) {
                    fallbackArtwork
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 54), style: .continuous))
        .background(Color.white, in: RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 54), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 54), style: .continuous)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }

    private var fallbackArtwork: some View {
        Image(systemName: "music.note")
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(TuneAVTheme.highlight)
            .frame(width: 54, height: 54)
            .background(TuneAVTheme.highlight.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func openSearch(destination: TuneAVExternalSearchURL.Destination, suffix: String? = nil) {
        let query = [discovery.searchQuery, suffix].compactMap { $0 }.joined(separator: " ")
        guard let url = TuneAVExternalSearchURL.url(for: destination, query: query) else { return }
        openURL(url)
    }
}

private struct MacLibraryMetricCard: View {
    let title: String
    let value: Int
    let systemImage: String
    var tint: Color = TuneAVTheme.highlight
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : tint)
                    .frame(width: 34, height: 34)
                    .background((isSelected ? TuneAVTheme.highlight : tint.opacity(0.14)), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text("\(value)")
                        .font(.system(size: 24, weight: .bold))
                }

                Spacer()
            }
            .padding(14)
            .frame(minHeight: 82)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.45) : TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(TuneAVTheme.textPrimary)
    }
}
