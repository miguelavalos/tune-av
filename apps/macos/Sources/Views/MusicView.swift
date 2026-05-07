import SwiftUI

struct MusicView: View {
    @Environment(\.openURL) private var openURL

    let discoveries: [DiscoveredTrack]
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
    @State private var hiddenDiscovery: DiscoveredTrack?
    @State private var isConfirmingClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ShellHeader(status: L10n.plural(singular: "shell.library.discoveries.artistSongs.one", plural: "shell.library.discoveries.artistSongs.other", count: visibleDiscoveries.count, visibleDiscoveries.count))

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("tab.music"))
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("shell.library.discoveries.subtitle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                MusicSummaryRow(
                    savedCount: savedDiscoveries.count,
                    historyCount: visibleDiscoveries.count,
                    artistCount: artistSummaries.count,
                    savedLimit: limits.savedTracks
                )

                HStack(spacing: 12) {
                    TextField(L10n.string("shell.library.discoveries.noMatch.detail"), text: $query)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .avCardSurface(cornerRadius: 18)

                    Picker(L10n.string("shell.library.mode.title"), selection: $mode) {
                        ForEach(MusicLibraryMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)

                    Button {
                        shareDiscoveries(filteredDiscoveries)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(filteredDiscoveries.isEmpty)

                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(discoveries.isEmpty)
                }

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

                switch mode {
                case .songs:
                    discoveryList(filteredDiscoveries)
                case .saved:
                    discoveryList(filteredDiscoveries.filter(\.isMarkedInteresting))
                case .artists:
                    artistGrid
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(28)
        }
        .background(TuneAVTheme.shellBackground)
        .confirmationDialog(L10n.string("shell.library.discoveries.clear.confirmTitle"), isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button(L10n.string("shell.library.discoveries.clear.confirmAction"), role: .destructive, action: clearDiscoveries)
            Button(L10n.string("profile.alert.clearData.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("shell.library.discoveries.clear.confirmMessage"))
        }
    }

    private func discoveryList(_ discoveries: [DiscoveredTrack]) -> some View {
        StationSection(title: mode.title, subtitle: L10n.string("shell.library.discoveries.subtitle")) {
            if discoveries.isEmpty {
                EmptyStateCard(title: mode == .saved ? L10n.string("shell.library.discoveries.savedEmpty") : L10n.string("shell.library.discoveries.empty"), detail: mode == .saved ? L10n.string("shell.library.discoveries.savedEmpty.detail") : L10n.string("shell.library.discoveries.empty.detail"))
            } else {
                ForEach(discoveries) { discovery in
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
    }

    private var artistGrid: some View {
        StationSection(title: L10n.string("shell.library.discoveries.artists.title"), subtitle: L10n.string("shell.library.discoveries.subtitle")) {
            if artistSummaries.isEmpty {
                EmptyStateCard(title: L10n.string("shell.library.discoveries.artists.title"), detail: L10n.string("shell.library.discoveries.empty.detail"))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(artistSummaries) { artist in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(artist.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(L10n.plural(singular: "shell.library.discoveries.artistSongs.one", plural: "shell.library.discoveries.artistSongs.other", count: artist.trackCount, artist.trackCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("YouTube") { openArtist(artist.name, youtube: true) }
                                Button("Spotify") { openArtistSpotify(artist.name) }
                            }
                            .font(.caption)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .avCardSurface(cornerRadius: 20)
                    }
                }
            }
        }
    }

    private var visibleDiscoveries: [DiscoveredTrack] {
        discoveries.filter { !$0.isHidden }
    }

    private var savedDiscoveries: [DiscoveredTrack] {
        visibleDiscoveries.filter(\.isMarkedInteresting)
    }

    private var filteredDiscoveries: [DiscoveredTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visibleDiscoveries }
        return visibleDiscoveries.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
                ($0.artist?.localizedCaseInsensitiveContains(trimmed) == true) ||
                $0.stationName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var artistSummaries: [DiscoveryArtistSummary] {
        let grouped = Dictionary(grouping: visibleDiscoveries.compactMap { discovery -> (String, DiscoveredTrack)? in
            guard let artist = discovery.artist, !artist.isEmpty else { return nil }
            return (artist, discovery)
        }, by: \.0)

        return grouped.map { artist, pairs in
            DiscoveryArtistSummary(name: artist, trackCount: pairs.count)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func openSearch(
        _ discovery: DiscoveredTrack,
        feature: LimitedFeature,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        let query = TuneAVExternalSearchURL.query(parts: [discovery.searchQuery], suffix: suffix)

        if let url = TuneAVExternalSearchURL.url(for: destination, query: query) {
            guard useDailyFeature(feature, url.absoluteString) else { return }
            openURL(url)
        }
    }

    private func openArtist(_ artist: String, youtube: Bool) {
        let feature: LimitedFeature = youtube ? .youtubeSearch : .webSearch
        if let url = TuneAVExternalSearchURL.web(query: artist, youtube: youtube) {
            guard useDailyFeature(feature, url.absoluteString) else { return }
            openURL(url)
        }
    }

    private func openArtistSpotify(_ artist: String) {
        guard let url = TuneAVExternalSearchURL.spotify(query: artist),
              useDailyFeature(.spotifySearch, url.absoluteString) else { return }
        openURL(url)
    }
}

private enum MusicLibraryMode: String, CaseIterable, Identifiable {
    case songs
    case saved
    case artists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs:
            return L10n.string("shell.library.mode.music")
        case .saved:
            return L10n.string("shell.library.discoveries.filter.saved")
        case .artists:
            return L10n.string("shell.library.discoveries.artists.title")
        }
    }
}

private struct DiscoveryArtistSummary: Identifiable {
    let name: String
    let trackCount: Int
    var id: String { name }
}

private struct MusicSummaryRow: View {
    let savedCount: Int
    let historyCount: Int
    let artistCount: Int
    let savedLimit: Int?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { cards }
            VStack(spacing: 12) { cards }
        }
    }

    @ViewBuilder
    private var cards: some View {
        LibraryMetricCard(title: L10n.string("shell.library.discoveries.filter.saved"), value: savedLimit.map { "\(savedCount)/\($0)" } ?? "\(savedCount)", detail: L10n.string("shell.library.discoveries.songs.savedTitle"))
        LibraryMetricCard(title: L10n.string("shell.library.discoveries.filter.history"), value: "\(historyCount)", detail: L10n.string("shell.library.discoveries.songs.historyTitle"))
        LibraryMetricCard(title: L10n.string("shell.library.discoveries.artists.title"), value: "\(artistCount)", detail: L10n.string("shell.library.discoveries.artists.title"))
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
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 4) {
                Text(discovery.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(discovery.artistDisplayText) · \(discovery.stationName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: toggleSaved) { Image(systemName: discovery.isMarkedInteresting ? "bookmark.fill" : "bookmark") }
                Button(action: openStation) { Image(systemName: "dot.radiowaves.left.and.right") }
                Button(action: openYouTube) { Image(systemName: "play.rectangle") }
                Button(action: openLyrics) { Image(systemName: "text.quote") }
                Button(action: openAppleMusic) { Image(systemName: "music.note") }
                Button(action: openSpotify) { Image(systemName: "magnifyingglass") }
                Menu {
                    Button(L10n.string("player.discovery.hide"), action: hideAction)
                    Button(L10n.string("player.discovery.remove"), role: .destructive, action: removeAction)
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .avCardSurface(cornerRadius: 22, shadowOpacity: 0.18, shadowRadius: 8, shadowY: 3)
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
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}
