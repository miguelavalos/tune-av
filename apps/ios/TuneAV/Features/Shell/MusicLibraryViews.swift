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
