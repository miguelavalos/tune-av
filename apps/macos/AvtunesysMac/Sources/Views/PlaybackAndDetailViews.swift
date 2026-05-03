import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let station: Station
    let openPlayer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlayerArtworkTile(station: station, artworkURL: audioPlayer.currentTrackArtworkURL, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(nowPlayingTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AvtunesysTheme.textPrimary)
                    .lineLimit(1)

                Text(nowPlayingSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            PlayerIconButton(systemImage: "stop.fill", action: audioPlayer.stop)
            PlayerIconButton(systemImage: playbackSymbol, highlighted: true, action: audioPlayer.togglePlayback)
            PlayerIconButton(systemImage: "arrow.up.left.and.arrow.down.right", action: openPlayer)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AvtunesysTheme.borderSubtle.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: AvtunesysTheme.softShadow.opacity(0.16), radius: 10, y: 3)
    }

    private var nowPlayingTitle: String {
        audioPlayer.currentTrackTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? audioPlayer.currentTrackTitle!
            : station.name
    }

    private var nowPlayingSubtitle: String {
        if let artist = audioPlayer.currentTrackArtist, !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(artist) · \(station.name)"
        }
        return statusLine
    }

    private var statusLine: String {
        switch audioPlayer.playbackState {
        case .idle:
            return station.shortMeta
        case .loading:
            return "Connecting · \(station.shortMeta)"
        case .playing:
            return "Live · \(station.shortMeta)"
        case .paused:
            return "Paused · \(station.shortMeta)"
        case .failed(let message):
            return "Error · \(message)"
        }
    }

    private var playbackSymbol: String {
        switch audioPlayer.playbackState {
        case .playing:
            return "pause.fill"
        case .failed:
            return "arrow.clockwise"
        case .idle, .loading, .paused:
            return "play.fill"
        }
    }
}

struct MacNowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        GeometryReader { proxy in
            if let station = audioPlayer.currentStation {
                let compact = proxy.size.width < 900

                VStack(spacing: 0) {
                    playerHeader(for: station)

                    Divider()

                    if compact {
                        ScrollView {
                            VStack(spacing: 20) {
                                primaryPanel(for: station, compact: true)
                                detailPanel(for: station)
                            }
                            .padding(20)
                        }
                    } else {
                        HStack(spacing: 0) {
                            primaryPanel(for: station, compact: false)
                                .frame(minWidth: 430, idealWidth: 470, maxWidth: 520)
                                .padding(24)

                            Divider()

                            ScrollView {
                                detailPanel(for: station)
                                    .padding(24)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                EmptyStateCard(title: "Nothing playing", detail: "Start a station from Home, Search, or Library.")
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    private func playerHeader(for station: Station) -> some View {
        HStack(spacing: 12) {
            PlayerArtworkTile(station: station, artworkURL: audioPlayer.currentTrackArtworkURL, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Now Playing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(station.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                if let homepageURL = station.resolvedHomepageURL {
                    openURL(homepageURL)
                }
            } label: {
                Label("Website", systemImage: "safari")
            }
            .disabled(station.resolvedHomepageURL == nil)

            Button("Done", action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func primaryPanel(for station: Station, compact: Bool) -> some View {
        VStack(spacing: 18) {
            PlayerArtworkTile(station: station, artworkURL: audioPlayer.currentTrackArtworkURL, size: compact ? 220 : 300)

            VStack(spacing: 6) {
                Text(trackTitleFallback(station))
                    .font(.system(size: compact ? 26 : 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                Text(trackSubtitleFallback(station))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                PlayerIconButton(systemImage: "stop.fill", size: 42, action: audioPlayer.stop)

                Button(action: audioPlayer.togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(AvtunesysTheme.highlight)
                        if audioPlayer.playbackState == .loading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: playbackSymbol)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)

                PlayerIconButton(systemImage: libraryStore.isFavorite(station) ? "heart.fill" : "heart", size: 42) {
                    libraryStore.toggleFavorite(station)
                }
            }

            if let errorMessage = audioPlayer.lastErrorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func detailPanel(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PlayerSection(title: "Live Track") {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(title: "Title", value: trackTitleFallback(station))
                    InfoRow(title: "Artist", value: normalized(audioPlayer.currentTrackArtist) ?? "Not available")
                    InfoRow(title: "Station", value: station.name)

                    if hasDiscoverableTrack {
                        HStack(spacing: 8) {
                            Button {
                                saveCurrentDiscovery(for: station)
                            } label: {
                                Label(isCurrentTrackSaved ? "Saved" : "Save", systemImage: isCurrentTrackSaved ? "bookmark.fill" : "bookmark")
                            }

                            Button {
                                openExternalSearch(.youtubeSearch, destination: .youtube)
                            } label: {
                                Label("YouTube", systemImage: "play.rectangle")
                            }

                            Button {
                                openExternalSearch(.lyricsSearch, destination: .web, suffix: "lyrics")
                            } label: {
                                Label("Lyrics", systemImage: "text.quote")
                            }
                        }
                    }
                }
            }

            PlayerSection(title: "Playback") {
                VStack(alignment: .leading, spacing: 12) {
                    StatusBadge(text: playbackLabel)
                }
            }

            PlayerSection(title: "Station") {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(title: "Country", value: station.country)
                    InfoRow(title: "Language", value: station.language)
                    if let codec = station.codec {
                        InfoRow(title: "Codec", value: codec)
                    }
                    if let bitrate = station.bitrate {
                        InfoRow(title: "Bitrate", value: "\(bitrate) kbps")
                    }
                    if !station.tagsList.isEmpty {
                        Text(station.tagsList.prefix(8).joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: 520, alignment: .topLeading)
    }

    private var playbackSymbol: String {
        switch audioPlayer.playbackState {
        case .playing:
            return "pause.fill"
        case .failed:
            return "arrow.clockwise"
        case .idle, .loading, .paused:
            return "play.fill"
        }
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

    private var hasDiscoverableTrack: Bool {
        normalized(audioPlayer.currentTrackTitle) != nil
    }

    private var isCurrentTrackSaved: Bool {
        guard let station = audioPlayer.currentStation else { return false }
        return libraryStore.discoveries.contains {
            $0.discoveryID == DiscoveredTrack.makeID(
                title: normalized(audioPlayer.currentTrackTitle) ?? "",
                artist: normalized(audioPlayer.currentTrackArtist),
                stationID: station.id
            ) && $0.isMarkedInteresting
        }
    }

    private func trackTitleFallback(_ station: Station) -> String {
        normalized(audioPlayer.currentTrackTitle) ?? station.name
    }

    private func trackSubtitleFallback(_ station: Station) -> String {
        if let artist = normalized(audioPlayer.currentTrackArtist) {
            return artist
        }
        return station.shortMeta
    }

    private func saveCurrentDiscovery(for station: Station) {
        libraryStore.markTrackInteresting(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: station,
            artworkURL: audioPlayer.currentTrackArtworkURL
        )
    }

    private func openExternalSearch(
        _ feature: LimitedFeature,
        destination: AVTunesysExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        let query = AVTunesysExternalSearchURL.query(
            parts: [audioPlayer.currentTrackArtist, audioPlayer.currentTrackTitle],
            suffix: suffix
        )
        guard !query.isEmpty else { return }

        if let url = AVTunesysExternalSearchURL.url(for: destination, query: query) {
            guard libraryStore.useDailyFeatureIfAllowed(feature, usageKey: url.absoluteString) else { return }
            openURL(url)
        }
    }

    private func normalized(_ value: String?) -> String? {
        AVTunesysText.normalizedValue(value)
    }
}

struct StationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let station: Station
    let isFavorite: Bool
    let isPlaying: Bool
    let playAction: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    StationArtworkView(station: station, size: 92)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(station.name)
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(AvtunesysTheme.textPrimary)

                        if !station.detailLine.isEmpty {
                            Text(station.detailLine)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AvtunesysTheme.textSecondary)
                        }

                        if !station.tagsList.isEmpty {
                            Text(station.tagsList.prefix(4).joined(separator: " · "))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AvtunesysTheme.highlight)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        playAction()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            Text(isPlaying ? "Playing" : "Play")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AvtunesysTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(isFavorite ? Color(red: 1, green: 0.17, blue: 0.38) : AvtunesysTheme.textPrimary)
                            .frame(width: 50, height: 50)
                            .avRoundedControl(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)

                    if let homepageURL = station.resolvedHomepageURL {
                        Button {
                            openURL(homepageURL)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AvtunesysTheme.textPrimary)
                                .frame(width: 50, height: 50)
                                .avRoundedControl(cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }

                DetailBlock(title: "About") {
                    DetailInfoRow(title: "Country", value: station.country)
                    DetailInfoRow(title: "Language", value: station.language)
                    if let state = station.state, !state.isEmpty {
                        DetailInfoRow(title: "State", value: state)
                    }
                    if let codec = station.codec, !codec.isEmpty {
                        DetailInfoRow(title: "Codec", value: codec)
                    }
                    if let bitrate = station.bitrate {
                        DetailInfoRow(title: "Bitrate", value: "\(bitrate) kbps")
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 440)
        .background(AvtunesysTheme.shellBackground)
    }
}

private struct PlayerArtworkTile: View {
    let station: Station
    let artworkURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        StationArtworkView(station: station, size: size)
                    }
                }
            } else {
                StationArtworkView(station: station, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .stroke(AvtunesysTheme.borderSubtle, lineWidth: 1)
        }
    }
}

private struct PlayerIconButton: View {
    let systemImage: String
    var highlighted = false
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(highlighted ? .white : AvtunesysTheme.textPrimary)
                .frame(width: size, height: size)
                .background(highlighted ? AvtunesysTheme.highlight : AvtunesysTheme.elevatedSurface, in: Circle())
                .overlay {
                    Circle()
                        .stroke(highlighted ? Color.clear : AvtunesysTheme.borderSubtle.opacity(0.7), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .avCardSurface(cornerRadius: 22)
        }
    }
}

private struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AvtunesysTheme.highlight)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AvtunesysTheme.highlight.opacity(0.10), in: Capsule())
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(AvtunesysTheme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private struct DetailBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AvtunesysTheme.textPrimary)

            VStack(spacing: 12) {
                content
            }
            .padding(18)
            .avCardSurface(cornerRadius: 22)
        }
    }
}

private struct DetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AvtunesysTheme.textSecondary)
                .frame(width: 90, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AvtunesysTheme.textPrimary)

            Spacer()
        }
    }
}
