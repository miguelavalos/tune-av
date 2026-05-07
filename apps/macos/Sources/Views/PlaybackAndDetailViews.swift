import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var languageController: AppLanguageController

    let station: Station
    let openPlayer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlayerArtworkTile(station: station, artworkURL: audioPlayer.currentTrackArtworkURL, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(nowPlayingTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
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
                .stroke(TuneAVTheme.borderSubtle.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.16), radius: 10, y: 3)
        .id(languageController.currentLanguage)
    }

    private var nowPlayingTitle: String {
        if hasPlausibleTrackTitle,
           let title = TuneAVText.normalizedValue(audioPlayer.currentTrackTitle) {
            return title
        }
        return station.name
    }

    private var nowPlayingSubtitle: String {
        if hasPlausibleTrackArtist,
           let artist = TuneAVText.normalizedValue(audioPlayer.currentTrackArtist) {
            return artist
        }
        return statusLine
    }

    private var hasPlausibleTrackTitle: Bool {
        guard TuneAVText.normalizedValue(audioPlayer.currentTrackTitle) != nil else { return false }
        return !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(
            audioPlayer.currentTrackTitle,
            stationName: station.name
        )
    }

    private var hasPlausibleTrackArtist: Bool {
        guard TuneAVText.normalizedValue(audioPlayer.currentTrackArtist) != nil else { return false }
        return !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(
            audioPlayer.currentTrackArtist,
            stationName: station.name
        )
    }

    private var statusLine: String {
        switch audioPlayer.playbackState {
        case .idle:
            return station.shortMeta
        case .loading:
            return "\(L10n.string("mac.player.status.connecting")) · \(station.shortMeta)"
        case .playing:
            return "\(L10n.string("shell.status.live")) · \(station.shortMeta)"
        case .paused:
            return "\(L10n.string("audio.status.paused")) · \(station.shortMeta)"
        case .failed(let message):
            return "\(L10n.string("mac.player.status.error")) · \(message)"
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
                EmptyStateCard(title: L10n.string("player.track.pickStation"), detail: L10n.string("player.empty"))
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
                Text(L10n.string("player.header.nowPlaying"))
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
                Label(L10n.string("player.menu.openWebsite"), systemImage: "safari")
            }
            .disabled(station.resolvedHomepageURL == nil)

            Button(L10n.string("profile.alert.close"), action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func primaryPanel(for station: Station, compact: Bool) -> some View {
        VStack(spacing: 18) {
            DesktopPlayerArtwork(
                station: station,
                trackArtworkURL: audioPlayer.currentTrackArtworkURL,
                trackTitle: normalized(audioPlayer.currentTrackTitle),
                trackArtist: normalized(audioPlayer.currentTrackArtist),
                isDiscoverableTrack: hasDiscoverableTrack,
                isCurrentTrackSaved: isCurrentTrackSaved,
                isLoading: audioPlayer.playbackState == .loading,
                isFavorite: libraryStore.isFavorite(station),
                onSaveDiscovery: { saveCurrentDiscovery(for: station) },
                onShareDiscovery: { shareCurrentDiscovery(for: station) },
                onOpenYouTube: { openExternalSearch(.youtubeSearch, destination: .youtube) },
                onOpenLyrics: { openExternalSearch(.lyricsSearch, destination: .web, suffix: "lyrics") },
                onOpenArtist: { openArtistSearch(destination: .web, feature: .webSearch) },
                onOpenArtistYouTube: { openArtistSearch(destination: .youtube, feature: .youtubeSearch) },
                onTogglePlayback: audioPlayer.togglePlayback,
                onToggleFavorite: { libraryStore.toggleFavorite(station) },
                onOpenWebsite: {
                    if let homepageURL = station.resolvedHomepageURL {
                        openURL(homepageURL)
                    }
                }
            )
            .frame(width: compact ? 220 : 300, height: compact ? 220 : 300)

            VStack(spacing: 6) {
                Text(trackTitleLine(for: station))
                    .font(.system(size: compact ? 26 : 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                Text(trackSupportingLine(for: station))
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
                            .fill(TuneAVTheme.highlight)
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
            PlayerSection(title: L10n.string("player.header.nowPlaying")) {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(title: L10n.string("mac.player.detail.title"), value: trackTitleLine(for: station))
                    InfoRow(title: L10n.string("mac.player.detail.artist"), value: hasPlausibleTrackArtist(for: station) ? (normalized(audioPlayer.currentTrackArtist) ?? L10n.string("mac.sync.unavailable")) : L10n.string("mac.sync.unavailable"))
                    InfoRow(title: L10n.string("mac.player.detail.station"), value: station.name)

                    if hasDiscoverableTrack {
                        HStack(spacing: 8) {
                            Button {
                                saveCurrentDiscovery(for: station)
                            } label: {
                                Label(
                                    isCurrentTrackSaved ? L10n.string("player.discovery.savedShort") : L10n.string("player.discovery.saveShort"),
                                    systemImage: isCurrentTrackSaved ? "bookmark.fill" : "bookmark"
                                )
                            }

                            Button {
                                openExternalSearch(.youtubeSearch, destination: .youtube)
                            } label: {
                                Label(L10n.string("player.discovery.youtubeShort"), systemImage: "play.rectangle")
                            }

                            Button {
                                openExternalSearch(.lyricsSearch, destination: .web, suffix: "lyrics")
                            } label: {
                                Label(L10n.string("player.discovery.lyricsShort"), systemImage: "text.quote")
                            }
                        }
                    }
                }
            }

            PlayerSection(title: L10n.string("mac.player.detail.playback")) {
                VStack(alignment: .leading, spacing: 12) {
                    StatusBadge(text: playbackLabel)
                }
            }

            PlayerSection(title: L10n.string("mac.player.detail.station")) {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(title: L10n.string("mac.player.detail.country"), value: station.country)
                    InfoRow(title: L10n.string("mac.player.detail.language"), value: station.language)
                    if let codec = station.codec {
                        InfoRow(title: L10n.string("mac.player.detail.codec"), value: codec)
                    }
                    if let bitrate = station.bitrate {
                        InfoRow(title: L10n.string("mac.player.detail.bitrate"), value: "\(bitrate) kbps")
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
            return L10n.string("mac.player.status.idle")
        case .loading:
            return L10n.string("mac.player.status.connecting")
        case .playing:
            return L10n.string("shell.status.live")
        case .paused:
            return L10n.string("audio.status.paused")
        case .failed:
            return L10n.string("mac.player.status.error")
        }
    }

    private var hasDiscoverableTrack: Bool {
        guard let station = audioPlayer.currentStation else { return false }
        return hasPlausibleTrackTitle(for: station) && hasPlausibleTrackArtist(for: station)
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

    private func stationMetaLine(for station: Station) -> String {
        if hasPlausibleTrackTitle(for: station) {
            return station.name
        }

        let meta = station.shortMeta.trimmingCharacters(in: .whitespacesAndNewlines)
        return meta.isEmpty ? L10n.string("player.track.liveNow") : meta
    }

    private func trackTitleLine(for station: Station) -> String {
        if hasPlausibleTrackTitle(for: station),
           let title = normalized(audioPlayer.currentTrackTitle) {
            return title
        }
        return station.name
    }

    private func trackSupportingLine(for station: Station) -> String {
        if hasPlausibleTrackArtist(for: station),
           let artist = normalized(audioPlayer.currentTrackArtist) {
            return artist
        }

        let tags = station.normalizedTags.prefix(2).joined(separator: " · ")
        if !tags.isEmpty {
            return tags
        }

        return L10n.string("player.track.liveStreamActive")
    }

    private func hasPlausibleTrackTitle(for station: Station) -> Bool {
        guard normalized(audioPlayer.currentTrackTitle) != nil else { return false }
        return !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(
            audioPlayer.currentTrackTitle,
            stationName: station.name
        )
    }

    private func hasPlausibleTrackArtist(for station: Station) -> Bool {
        guard normalized(audioPlayer.currentTrackArtist) != nil else { return false }
        return !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(
            audioPlayer.currentTrackArtist,
            stationName: station.name
        )
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
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        guard var query = discoverySearchQuery else { return }
        if let suffix {
            query += " \(suffix)"
        }

        if let url = TuneAVExternalSearchURL.url(for: destination, query: query) {
            guard libraryStore.useDailyFeatureIfAllowed(feature, usageKey: url.absoluteString) else { return }
            openURL(url)
        }
    }

    private func openArtistSearch(destination: TuneAVExternalSearchURL.Destination, feature: LimitedFeature) {
        guard let artist = normalized(audioPlayer.currentTrackArtist),
              let url = TuneAVExternalSearchURL.url(for: destination, query: artist)
        else {
            return
        }

        guard libraryStore.useDailyFeatureIfAllowed(feature, usageKey: url.absoluteString) else { return }
        openURL(url)
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

    private var discoverySearchQuery: String? {
        guard
            let station = audioPlayer.currentStation,
            hasPlausibleTrackTitle(for: station),
            hasPlausibleTrackArtist(for: station),
            let title = normalized(audioPlayer.currentTrackTitle),
            let artist = normalized(audioPlayer.currentTrackArtist)
        else {
            return nil
        }

        return "\(artist) \(title)"
    }

    private func normalized(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)
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
                            .foregroundStyle(TuneAVTheme.textPrimary)

                        if !station.detailLine.isEmpty {
                            Text(station.detailLine)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(TuneAVTheme.textSecondary)
                        }

                        if !station.tagsList.isEmpty {
                            Text(station.tagsList.prefix(4).joined(separator: " · "))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(TuneAVTheme.highlight)
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
                            Text(isPlaying ? L10n.string("audio.status.playing") : L10n.string("player.control.play"))
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(isFavorite ? Color(red: 1, green: 0.17, blue: 0.38) : TuneAVTheme.textPrimary)
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
                                .foregroundStyle(TuneAVTheme.textPrimary)
                                .frame(width: 50, height: 50)
                                .avRoundedControl(cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }

                DetailBlock(title: L10n.string("shell.stationDetail.section.about")) {
                    DetailInfoRow(title: L10n.string("shell.stationDetail.field.country"), value: station.country)
                    DetailInfoRow(title: L10n.string("shell.stationDetail.field.language"), value: station.language)
                    if let state = station.state, !state.isEmpty {
                        DetailInfoRow(title: L10n.string("shell.stationDetail.field.state"), value: state)
                    }
                    if let codec = station.codec, !codec.isEmpty {
                        DetailInfoRow(title: L10n.string("mac.player.detail.codec"), value: codec)
                    }
                    if let bitrate = station.bitrate {
                        DetailInfoRow(title: L10n.string("mac.player.detail.bitrate"), value: "\(bitrate) kbps")
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 440)
        .background(TuneAVTheme.shellBackground)
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
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
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
                .foregroundStyle(highlighted ? .white : TuneAVTheme.textPrimary)
                .frame(width: size, height: size)
                .background(highlighted ? TuneAVTheme.highlight : TuneAVTheme.elevatedSurface, in: Circle())
                .overlay {
                    Circle()
                        .stroke(highlighted ? Color.clear : TuneAVTheme.borderSubtle.opacity(0.7), lineWidth: 1)
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
            .foregroundStyle(TuneAVTheme.highlight)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(TuneAVTheme.highlight.opacity(0.10), in: Capsule())
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
                .foregroundStyle(TuneAVTheme.textPrimary)
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
                .foregroundStyle(TuneAVTheme.textPrimary)

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
                .foregroundStyle(TuneAVTheme.textSecondary)
                .frame(width: 90, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Spacer()
        }
    }
}
