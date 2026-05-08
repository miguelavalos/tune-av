import SwiftUI

struct MusicView: View {
    @Environment(\.openURL) private var openURL

    let discoveries: [DiscoveredTrack]
    @Binding var historyStationFilter: Station?
    let limits: AccessLimits
    let openStation: (DiscoveredTrack) -> Void
    let toggleSaved: (DiscoveredTrack) -> Void
    let hideDiscovery: (DiscoveredTrack) -> Void
    let restoreDiscovery: (DiscoveredTrack) -> Void
    let removeDiscovery: (DiscoveredTrack) -> Void
    let shareDiscoveries: ([DiscoveredTrack]) -> Void
    let clearDiscoveries: () -> Void
    let useDailyFeature: (LimitedFeature, String) -> Bool

    @State private var query = ""
    @State private var mode: MusicLibraryMode = .songs
    @State private var selectedArtistName: String?
    @State private var hiddenDiscovery: DiscoveredTrack?
    @State private var isConfirmingClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ShellHeader(status: L10n.plural(singular: "shell.library.discoveries.artistSongs.one", plural: "shell.library.discoveries.artistSongs.other", count: visibleDiscoveries.count, visibleDiscoveries.count))

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("shell.music.title"))
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("shell.music.subtitle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                MacSearchField(prompt: L10n.string("shell.music.searchPrompt"), text: $query)

                MusicSignalSummary(
                    savedCount: savedDiscoveries.count,
                    historyCount: visibleDiscoveries.count,
                    artistCount: visibleArtistSummaries.count,
                    selectedMode: mode,
                    selectMode: { mode in
                        selectedArtistName = nil
                        if mode != .history {
                            historyStationFilter = nil
                        }
                        self.mode = mode
                    }
                )

                if let hiddenDiscovery {
                    HStack {
                        Text(L10n.string("mac.music.hidden", hiddenDiscovery.title))
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Button(L10n.string("mac.music.undo")) {
                            restoreDiscovery(hiddenDiscovery)
                            self.hiddenDiscovery = nil
                        }
                    }
                    .padding(12)
                    .background(TuneAVTheme.highlight.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                discoveryLibrarySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .background(TuneAVTheme.shellBackground)
        .confirmationDialog(L10n.string("shell.library.discoveries.clear.confirmTitle"), isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button(L10n.string("shell.library.discoveries.clear.confirmAction"), role: .destructive, action: clearDiscoveries)
            Button(L10n.string("profile.alert.clearData.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("shell.library.discoveries.clear.confirmMessage"))
        }
        .onAppear(perform: normalizeInitialDiscoveryFilter)
        .onChange(of: query) {
            selectedArtistName = nil
        }
        .onChange(of: historyStationFilter?.id) { _, stationID in
            guard stationID != nil else { return }
            selectedArtistName = nil
            mode = .history
        }
    }

    private var discoveryLibrarySection: some View {
        StationSection(title: L10n.string("shell.music.discoveries.title"), subtitle: L10n.string("shell.music.discoveries.subtitle")) {
            VStack(alignment: .leading, spacing: 16) {
                if filteredDiscoveries.isEmpty && filteredArtistSummaries.isEmpty {
                    EmptyStateCard(title: emptyDiscoveryTitle, detail: emptyDiscoveryDetail)
                } else {
                    switch mode {
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
                                    openYouTube: { openArtist(artist.name, youtube: true) },
                                    openAppleMusic: { openArtistAppleMusic(artist.name) },
                                    openSpotify: { openArtistSpotify(artist.name) }
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
                DiscoveryTrackRow(
                    discovery: discovery,
                    openStation: { openStation(discovery) },
                    toggleSaved: { toggleSaved(discovery) },
                    openYouTube: { openSearch(discovery, feature: .youtubeSearch, destination: .youtube) },
                    openLyrics: { openSearch(discovery, feature: .lyricsSearch, destination: .web, suffix: "lyrics") },
                    openAppleMusic: { openSearch(discovery, feature: .appleMusicSearch, destination: .appleMusic) },
                    openSpotify: { openSearch(discovery, feature: .spotifySearch, destination: .spotify) },
                    hideAction: {
                        hiddenDiscovery = discovery
                        hideDiscovery(discovery)
                    },
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

    private var discoverySongsHeader: some View {
        HStack(spacing: 10) {
            Text(historyStationFilterTitle ?? mode.songsTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if mode == .history, historyStationFilter != nil {
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
            }

            discoveryActions
        }
    }

    private var historyStationFilterTitle: String? {
        guard mode == .history, let historyStationFilter else { return nil }
        return "\(MusicLibraryMode.history.title) · \(historyStationFilter.name)"
    }

    private var discoveryActions: some View {
        HStack(spacing: 10) {
            MacIconButton(systemImage: "square.and.arrow.up") {
                shareDiscoveries(filteredDiscoveries)
            }
            .disabled(filteredDiscoveries.isEmpty)

            MacIconButton(systemImage: "trash", role: .destructive) {
                isConfirmingClear = true
            }
            .disabled(discoveries.isEmpty)
        }
    }

    private func openArtistSongs(_ artistName: String) {
        selectedArtistName = artistName
        query = artistName
        mode = .songs
    }

    private var visibleDiscoveries: [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(discoveries)
    }

    private var savedDiscoveries: [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.savedDiscoveries(discoveries)
    }

    private var filteredDiscoveries: [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.filteredDiscoveries(
            discoveries,
            mode: mode,
            query: query,
            selectedArtistName: selectedArtistName,
            historyStationID: historyStationFilter?.id
        )
    }

    private var filteredArtistSummaries: [DiscoveryArtistSummary] {
        TuneAVMusicLibraryLogic.filteredArtistSummaries(discoveries, mode: mode, query: query, locale: L10n.locale)
    }

    private var visibleArtistSummaries: [DiscoveryArtistSummary] {
        TuneAVMusicLibraryLogic.visibleArtistSummaries(discoveries, locale: L10n.locale)
    }

    private var emptyDiscoveryTitle: String {
        if visibleDiscoveries.isEmpty {
            return L10n.string("shell.library.discoveries.empty")
        }

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("shell.library.discoveries.noMatch")
        }

        switch mode {
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

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("shell.library.discoveries.noMatch.detail")
        }

        switch mode {
        case .songs:
            return L10n.string("shell.library.discoveries.savedEmpty.detail")
        case .artists:
            return L10n.string("shell.music.artists.empty.detail")
        case .history:
            return L10n.string("shell.library.discoveries.noMatch.detail")
        }
    }

    private func normalizeInitialDiscoveryFilter() {
        mode = TuneAVMusicLibraryLogic.normalizedInitialMode(
            mode,
            discoveries: discoveries,
            historyStationID: historyStationFilter?.id
        )
    }

    private func openSearch(
        _ discovery: DiscoveredTrack,
        feature: LimitedFeature,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        guard let search = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: discovery.searchQuery,
            destination: destination,
            feature: feature,
            suffix: suffix
        ) else { return }
        guard useDailyFeature(search.feature, search.url.absoluteString) else { return }
        openURL(search.url)
    }

    private func openArtist(_ artist: String, youtube: Bool) {
        let feature: LimitedFeature = youtube ? .youtubeSearch : .webSearch
        let destination: TuneAVExternalSearchURL.Destination = youtube ? .youtube : .web
        guard let search = TuneAVExternalSearchURL.artistSearch(artist: artist, destination: destination, feature: feature) else { return }
        guard useDailyFeature(search.feature, search.url.absoluteString) else { return }
        openURL(search.url)
    }

    private func openArtistSpotify(_ artist: String) {
        guard let search = TuneAVExternalSearchURL.artistSearch(artist: artist, destination: .spotify, feature: .spotifySearch) else { return }
        guard useDailyFeature(search.feature, search.url.absoluteString) else { return }
        openURL(search.url)
    }

    private func openArtistAppleMusic(_ artist: String) {
        guard let search = TuneAVExternalSearchURL.artistSearch(artist: artist, destination: .appleMusic, feature: .appleMusicSearch) else { return }
        guard useDailyFeature(search.feature, search.url.absoluteString) else { return }
        openURL(search.url)
    }
}

private typealias MusicLibraryMode = TuneAVMusicLibraryMode
private typealias DiscoveryArtistSummary = TuneAVDiscoveryArtistSummary

private struct MusicSignalSummary: View {
    let savedCount: Int
    let historyCount: Int
    let artistCount: Int
    let selectedMode: MusicLibraryMode
    let selectMode: (MusicLibraryMode) -> Void

    var body: some View {
        HStack(spacing: 10) {
            MusicSignalButton(
                title: MusicLibraryMode.songs.title,
                value: savedCount,
                systemImage: "bookmark.fill",
                isSelected: selectedMode == .songs,
                action: { selectMode(.songs) }
            )

            MusicSignalButton(
                title: MusicLibraryMode.artists.title,
                value: artistCount,
                systemImage: "person.2.fill",
                isSelected: selectedMode == .artists,
                action: { selectMode(.artists) }
            )

            MusicSignalButton(
                title: MusicLibraryMode.history.title,
                value: historyCount,
                systemImage: "clock.fill",
                isSelected: selectedMode == .history,
                action: { selectMode(.history) }
            )
        }
    }
}

private struct MusicSignalButton: View {
    let title: String
    let value: Int
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))

                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .foregroundStyle(isSelected ? Color.white : TuneAVTheme.textSecondary)

                Text("\(value)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : TuneAVTheme.textPrimary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.82) : TuneAVTheme.mutedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.95) : TuneAVTheme.borderSubtle, lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DiscoveryTrackRow: View {
    let discovery: DiscoveredTrack
    let openStation: () -> Void
    let toggleSaved: () -> Void
    let openYouTube: () -> Void
    let openLyrics: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void
    let hideAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: openStation) {
                HStack(spacing: 14) {
                    artwork

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

            HStack(spacing: 8) {
                discoverySaveButton
                Menu {
                    Button(L10n.string("player.discovery.youtube"), action: openYouTube)
                    Button(L10n.string("player.discovery.lyrics"), action: openLyrics)
                    Button(L10n.string("player.discovery.appleMusic"), action: openAppleMusic)
                    Button(L10n.string("player.discovery.spotify"), action: openSpotify)
                    Divider()
                    Button(L10n.string("player.discovery.hide"), action: hideAction)
                    Button(L10n.string("player.discovery.remove"), role: .destructive, action: removeAction)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .rotationEffect(.degrees(90))
                        .frame(width: 34, height: 34)
                        .background(TuneAVTheme.mutedSurface, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .avCardSurface(cornerRadius: 22, shadowOpacity: 0.08, shadowRadius: 8, shadowY: 3)
    }

    private var discoverySaveButton: some View {
        Button(action: toggleSaved) {
            Image(systemName: discovery.isMarkedInteresting ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(discovery.isMarkedInteresting ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(discovery.isMarkedInteresting ? TuneAVTheme.highlight.opacity(0.14) : TuneAVTheme.mutedSurface)
                )
                .overlay {
                    Circle()
                        .stroke(discovery.isMarkedInteresting ? TuneAVTheme.highlight.opacity(0.28) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = discovery.resolvedArtworkURL ?? discovery.resolvedStationArtworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallbackArtwork
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.75), lineWidth: 1)
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: 58, height: 58)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
    }
}

private struct DiscoveryArtistRow: View {
    let summary: DiscoveryArtistSummary
    let openArtist: () -> Void
    let openYouTube: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openArtist) {
                HStack(spacing: 10) {
                    artwork

                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(1)

                        Text(L10n.plural(singular: "shell.library.discoveries.artistSongs.one", plural: "shell.library.discoveries.artistSongs.other", count: summary.trackCount, summary.trackCount))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(L10n.string("shell.music.artist.viewSongs"), action: openArtist)
                Button(L10n.string("player.discovery.youtube"), action: openYouTube)
                Button(L10n.string("player.discovery.appleMusic"), action: openAppleMusic)
                Button(L10n.string("player.discovery.spotify"), action: openSpotify)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 32, height: 32)
                    .background(TuneAVTheme.mutedSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.string("common.more"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TuneAVTheme.mutedSurface.opacity(0.64))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(TuneAVTheme.highlight)
                        .frame(width: 3)
                        .padding(.vertical, 12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        )
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = summary.displayArtworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackArtwork
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        Circle()
            .fill(TuneAVTheme.cardSurface)
            .frame(width: 46, height: 46)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
    }
}
