import AppKit
import AVAppShellFoundation
import AVAviFoundation
import SwiftUI

struct MacMusicDetailView: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @Environment(\.openURL) private var openURL

    let route: MacMusicDetailRoute
    @State private var selectedArtistSection: MacMusicArtistDetailSection = .info
    @State private var openAviActionsID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch route {
                case let .track(discovery):
                    trackDetail(discovery)
                case let .artist(name):
                    artistDetail(name)
                }
            }
            .padding(24)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
    }

    private func trackDetail(_ discovery: MacDiscoveredTrack) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            macTrackSummaryCard(discovery)
            macTrackQuickActions(discovery)
            AviFocusedTrackStats(
                artistName: discovery.artistDisplayText,
                stationName: discovery.stationName,
                feedbackLabel: feedbackLabel(for: discovery.stationID)
            )
            macMusicAviServices(for: .track(discovery))
            AviFocusedTrackArticle(
                artistName: discovery.artistDisplayText,
                stationName: discovery.stationName,
                lastSeenLabel: discovery.playedAt.formatted(date: .abbreviated, time: .shortened),
                feedbackLabel: feedbackLabel(for: discovery.stationID)
            )

            if let station = station(for: discovery.stationID) {
                macTrackStationBlock(station)
            }
        }
    }

    private func artistDetail(_ artistName: String) -> some View {
        let discoveries = artistDiscoveries(artistName)
        let stations = artistStations(discoveries)
        let summary = artistSummary(artistName, discoveries: discoveries)
        return VStack(alignment: .leading, spacing: 16) {
            macArtistSectionPicker(discoveryCount: discoveries.count)

            switch selectedArtistSection {
            case .info:
                AviFocusedArtistArticle {
                    macArtistSummaryCard(summary, discoveries: discoveries)
                } stats: {
                    AviFocusedArtistStats(
                        savedSongsCount: discoveries.filter(\.isMarkedInteresting).count,
                        stationCount: stations.count,
                        latestSeenLabel: discoveries.first?.playedAt.formatted(date: .numeric, time: .omitted) ?? L10n.string("shell.avi.music.feedback.empty")
                    )
                } services: {
                    macMusicAviServices(for: .artist(summary))
                } savedSongs: {
                    EmptyView()
                } stations: {
                    macArtistStationsBlock(stations)
                }
            case .songs:
                macArtistSongsBlock(discoveries, artistName: artistName)
            }
        }
    }

    private func macTrackSummaryCard(_ discovery: MacDiscoveredTrack) -> some View {
        AVAviFocusedSummaryCard(
            title: discovery.title,
            subtitle: "\(discovery.artistDisplayText) · \(discovery.stationName)",
            metadata: "\(L10n.string("shell.avi.music.lastSeen")) · \(discovery.playedAt.formatted(date: .numeric, time: .omitted))",
            artwork: {
                musicArtwork(for: discovery, size: 62)
            },
            badge: {
                if let feedback = model.stationFeedback[discovery.stationID] {
                    TuneAVFeedbackBadge(feedback: feedback, size: 24)
                        .offset(x: -5, y: -5)
                }
            }
        )
    }

    private func macTrackQuickActions(_ discovery: MacDiscoveredTrack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AVAviQuickActionButton(
                    title: discovery.isMarkedInteresting ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                    systemImage: discovery.isMarkedInteresting ? "bookmark.slash" : "bookmark",
                    isSelected: discovery.isMarkedInteresting,
                    accessibilityIdentifier: "avi.detail.track.save"
                ) {
                    model.toggleDiscoverySaved(discovery)
                }

                AVAviIconActionButton(
                    systemImage: "person.crop.circle",
                    accessibilityLabel: L10n.string("shell.avi.actions.searchArtist")
                ) {
                    model.openMusicArtistDetail(discovery.artistDisplayText)
                }
            }

            if let station = station(for: discovery.stationID) {
                StationFeedbackControl(
                    feedbackIdentity: "track:\(discovery.discoveryID)",
                    selectedFeedback: model.stationFeedback[discovery.stationID],
                    selectFeedback: { feedback in
                        let nextFeedback = model.stationFeedback[discovery.stationID] == feedback ? nil : feedback
                        model.setFeedback(nextFeedback, for: station)
                    },
                    clearFeedback: {
                        model.setFeedback(nil, for: station)
                    }
                )
            }
        }
        .padding(12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }

    private func macArtistSummaryCard(_ summary: TuneAVDiscoveryArtistSummary, discoveries: [MacDiscoveredTrack]) -> some View {
        AVAviFocusedSummaryCard(
            title: summary.name,
            subtitle: artistSummaryLine(summary, discoveries: discoveries),
            metadata: discoveries.first.map { "\(L10n.string("shell.avi.music.latestSong")) · \($0.title)" },
            artwork: {
                artistArtwork(discoveries: discoveries, size: 62)
            }
        )
    }

    private func macArtistSectionPicker(discoveryCount: Int) -> some View {
        HStack(spacing: 6) {
            macArtistSectionButton(
                .info,
                title: L10n.string("shell.stationDetail.section.about"),
                systemImage: "info.circle.fill",
                badge: nil
            )
            macArtistSectionButton(
                .songs,
                title: L10n.string("shell.music.mode.songs"),
                systemImage: "music.note.list",
                badge: discoveryCount == 0 ? nil : "\(discoveryCount)"
            )
        }
        .padding(4)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.82), lineWidth: 1)
        }
        .accessibilityIdentifier("avi.artistDetail.sections")
    }

    private func macArtistSectionButton(
        _ section: MacMusicArtistDetailSection,
        title: String,
        systemImage: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedArtistSection == section

        return Button {
            selectedArtistSection = section
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))

                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            (isSelected ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.cardSurface),
                            in: Capsule(style: .continuous)
                        )
                }
            }
            .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? TuneAVTheme.highlight.opacity(0.38) : TuneAVTheme.borderSubtle.opacity(0.78),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avi.artistDetail.section.\(section.rawValue)")
    }

    private func macMusicAviServices(for detail: MacMusicAviDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("shell.avi.actions.ask"))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .textCase(.uppercase)

            TuneAviPopoverActionsPanel(close: { openAviActionsID = nil }) {
                switch detail {
                case .track(let discovery):
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle") {
                        openDiscoverySearch(discovery, destination: .youtube)
                    }
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.lyrics"), systemImage: "text.quote") {
                        openDiscoverySearch(discovery, destination: .web, suffix: "lyrics")
                    }
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note") {
                        openDiscoverySearch(discovery, destination: .appleMusic)
                    }
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3") {
                        openDiscoverySearch(discovery, destination: .spotify)
                    }
                case .artist(let summary):
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.youtube"), systemImage: "play.rectangle") {
                        openArtistSearch(summary.name, destination: .youtube)
                    }
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.appleMusic"), systemImage: "music.note") {
                        openArtistSearch(summary.name, destination: .appleMusic)
                    }
                    AVAviPanelOptionButton(title: L10n.string("player.discovery.spotify"), systemImage: "music.quarternote.3") {
                        openArtistSearch(summary.name, destination: .spotify)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 12, y: 6)
    }

    private func macArtistSongsBlock(_ discoveries: [MacDiscoveredTrack], artistName: String) -> some View {
        Group {
            if discoveries.isEmpty {
                Text(L10n.string("shell.library.discoveries.empty"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(discoveries) { discovery in
                        MacMusicDiscoveryTrackCard(
                            discovery: discovery,
                            feedback: model.stationFeedback[discovery.stationID],
                            showsSaveButton: false,
                            openAviActionsID: $openAviActionsID,
                            openTrackInfo: { model.openMusicTrackDetail(discovery) },
                            openArtistInfo: { model.openMusicArtistDetail(artistName) },
                            openStationInfo: { openStation(discovery) },
                            toggleSaved: { model.toggleDiscoverySaved(discovery) },
                            hideAction: { model.hideDiscovery(discovery) },
                            removeAction: { model.removeDiscovery(discovery) },
                            openYouTube: { openDiscoverySearch(discovery, destination: .youtube) },
                            openLyrics: { openDiscoverySearch(discovery, destination: .web, suffix: "lyrics") },
                            openAppleMusic: { openDiscoverySearch(discovery, destination: .appleMusic) },
                            openSpotify: { openDiscoverySearch(discovery, destination: .spotify) }
                        )
                    }
                }
                .padding(14)
                .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func macTrackStationBlock(_ station: Station) -> some View {
        MacMusicDetailCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("shell.avi.music.station"))
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                MacStationArtworkCard(station: station)
                    .frame(width: 258, height: 112)
                    .environment(\.macStationPlaybackQueue, [station])
            }
        }
    }

    @ViewBuilder
    private func macArtistStationsBlock(_ stations: [Station]) -> some View {
        if !stations.isEmpty {
            MacMusicDetailCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("shell.avi.music.artist.radios"))
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(stations) { station in
                                MacStationArtworkCard(station: station)
                                    .frame(width: 258, height: 112)
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .environment(\.macStationPlaybackQueue, stations)
                }
            }
        }
    }

    private func musicArtwork(for discovery: MacDiscoveredTrack, size: CGFloat) -> some View {
        Group {
            if let url = discovery.resolvedArtworkURL ?? discovery.resolvedStationArtworkURL {
                TuneAVRemoteArtworkImage(url: url, size: size, scale: NSScreen.main?.backingScaleFactor ?? 2) {
                    MacMusicArtworkFallback(systemImage: "music.note", size: size)
                }
            } else {
                MacMusicArtworkFallback(systemImage: "music.note", size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }

    private func artistArtwork(discoveries: [MacDiscoveredTrack], size: CGFloat) -> some View {
        musicArtwork(for: discoveries.first ?? MacDiscoveredTrack(title: "", artist: nil, station: Station.samples[0]), size: size)
    }

    private func feedbackLabel(for stationID: String) -> String {
        model.stationFeedback[stationID]?.localizedState ?? L10n.string("shell.avi.music.feedback.empty")
    }

    private func artistDiscoveries(_ artistName: String) -> [MacDiscoveredTrack] {
        let normalizedArtist = TuneAVText.normalizedValue(artistName)
        return model.discoveredTracks
            .filter { TuneAVText.normalizedValue($0.artistDisplayText) == normalizedArtist }
            .sorted { $0.playedAt > $1.playedAt }
    }

    private func artistStations(_ discoveries: [MacDiscoveredTrack]) -> [Station] {
        var seen = Set<String>()
        return discoveries.compactMap { discovery in
            guard seen.insert(discovery.stationID).inserted else { return nil }
            return station(for: discovery.stationID)
        }
    }

    private func artistSummary(_ artistName: String, discoveries: [MacDiscoveredTrack]) -> TuneAVDiscoveryArtistSummary {
        TuneAVDiscoveryArtistSummary(
            name: artistName,
            trackCount: discoveries.count,
            artistArtworkURL: discoveries.first?.resolvedArtworkURL,
            fallbackArtworkURL: discoveries.first?.resolvedStationArtworkURL
        )
    }

    private func artistSummaryLine(_ summary: TuneAVDiscoveryArtistSummary, discoveries: [MacDiscoveredTrack]) -> String {
        let songCount = L10n.plural(
            singular: "shell.library.discoveries.artistSongs.one",
            plural: "shell.library.discoveries.artistSongs.other",
            count: summary.trackCount,
            summary.trackCount
        )
        guard let latestDiscovery = discoveries.first else { return songCount }
        return "\(songCount) · \(latestDiscovery.stationName)"
    }

    private func station(for stationID: String) -> Station? {
        (model.recentStations + model.favoriteStations + model.featuredStations).first { $0.id == stationID }
    }

    private func openStation(_ discovery: MacDiscoveredTrack) {
        guard let station = station(for: discovery.stationID) else { return }
        model.openStationDetail(station, queue: [station])
    }

    private func openDiscoverySearch(_ discovery: MacDiscoveredTrack, destination: TuneAVExternalSearchURL.Destination, suffix: String? = nil) {
        let query = [discovery.searchQuery, suffix].compactMap { $0 }.joined(separator: " ")
        guard model.canPerformPremiumAviSearch(destination: destination, suffix: suffix, usageKey: query) else { return }
        guard let url = TuneAVExternalSearchURL.url(for: destination, query: query) else { return }
        openURL(url)
    }

    private func openArtistSearch(_ artistName: String, destination: TuneAVExternalSearchURL.Destination) {
        guard model.canPerformPremiumAviSearch(destination: destination, usageKey: artistName) else { return }
        guard let url = TuneAVExternalSearchURL.url(for: destination, query: artistName) else { return }
        openURL(url)
    }
}

private enum MacMusicArtistDetailSection: String {
    case info
    case songs
}

private enum MacMusicAviDetail {
    case track(MacDiscoveredTrack)
    case artist(TuneAVDiscoveryArtistSummary)
}

private struct MacMusicDetailCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.76), lineWidth: 1)
            }
    }
}

private struct MacMusicArtworkFallback: View {
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
