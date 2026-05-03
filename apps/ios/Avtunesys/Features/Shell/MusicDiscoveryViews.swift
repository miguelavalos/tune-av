import SwiftUI

struct DiscoveryTrackCard: View {
    let discovery: DiscoveredTrack
    let stationArtworkURL: URL?
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
            Button(action: openStation) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 3) {
                        Text(discovery.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AvtunesysTheme.textPrimary)
                            .lineLimit(1)

                        Text(discovery.artistDisplayText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AvtunesysTheme.highlight)
                            .lineLimit(1)

                        Text(discovery.stationName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AvtunesysTheme.textSecondary.opacity(0.82))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(discovery.title), \(discovery.artistDisplayText), \(discovery.stationName)")
            .accessibilityHint(L10n.string("shell.music.discovery.openStation.hint"))
            .accessibilityIdentifier("discoveryTrack.openStation.\(discovery.discoveryID)")

            discoverySaveButton
            discoveryMenu
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AvtunesysTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AvtunesysTheme.borderSubtle, lineWidth: 1)
                }
        )
        .shadow(color: AvtunesysTheme.softShadow.opacity(0.18), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discoveryTrack.\(discovery.discoveryID)")
    }

    private var discoverySaveButton: some View {
        discoveryStateButton(
            systemImage: discovery.isMarkedInteresting ? "bookmark.fill" : "bookmark",
            isActive: discovery.isMarkedInteresting,
            activeColor: AvtunesysTheme.highlight,
            accessibilityLabel: discovery.isMarkedInteresting
                ? L10n.string("player.discovery.unsave")
                : L10n.string("player.discovery.save"),
            accessibilityIdentifier: "discoveryTrack.save.\(discovery.discoveryID)",
            action: toggleSaved
        )
    }

    private func discoveryStateButton(
        systemImage: String,
        isActive: Bool,
        activeColor: Color,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isActive ? activeColor : AvtunesysTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.14) : AvtunesysTheme.mutedSurface)
                )
                .overlay {
                    Circle()
                        .stroke(isActive ? activeColor.opacity(0.28) : AvtunesysTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var discoveryMenu: some View {
        Menu {
            Button(L10n.string("player.discovery.youtube"), action: openYouTube)
            Button(L10n.string("player.discovery.lyrics"), action: openLyrics)
            Button(L10n.string("player.discovery.appleMusic"), action: openAppleMusic)
            Button(L10n.string("player.discovery.spotify"), action: openSpotify)

            Button(L10n.string("player.discovery.hide"), role: .destructive, action: hideAction)
            Button(L10n.string("player.discovery.remove"), role: .destructive, action: removeAction)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AvtunesysTheme.textPrimary)
                .rotationEffect(.degrees(90))
                .frame(width: 34, height: 34)
                .background(AvtunesysTheme.mutedSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("common.more"))
        .accessibilityIdentifier("discoveryTrack.menu.\(discovery.discoveryID)")
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = discovery.resolvedArtworkURL {
            remoteArtwork(url: artworkURL, fallback: AnyView(fallbackArtwork))
        } else if let stationArtworkURL {
            remoteArtwork(url: stationArtworkURL, fallback: AnyView(fallbackArtwork))
        } else if let stationArtworkURL = discovery.resolvedStationArtworkURL {
            remoteArtwork(url: stationArtworkURL, fallback: AnyView(fallbackArtwork))
        } else {
            fallbackArtwork
        }
    }

    private func remoteArtwork(url: URL, fallback: AnyView) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                fallback
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(AvtunesysTheme.mutedSurface)
            .frame(width: 54, height: 54)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AvtunesysTheme.highlight)
            }
    }
}

struct MusicSignalSummary: View {
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
                accessibilityIdentifier: "music.mode.songs",
                isSelected: selectedMode == .songs,
                action: { selectMode(.songs) }
            )

            MusicSignalButton(
                title: MusicLibraryMode.artists.title,
                value: artistCount,
                systemImage: "person.2.fill",
                accessibilityIdentifier: "music.mode.artists",
                isSelected: selectedMode == .artists,
                action: { selectMode(.artists) }
            )

            MusicSignalButton(
                title: MusicLibraryMode.history.title,
                value: historyCount,
                systemImage: "clock.fill",
                accessibilityIdentifier: "music.mode.history",
                isSelected: selectedMode == .history,
                action: { selectMode(.history) }
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MusicSignalButton: View {
    let title: String
    let value: Int
    let systemImage: String
    let accessibilityIdentifier: String
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
                .foregroundStyle(isSelected ? Color.white : AvtunesysTheme.textSecondary)

                Text("\(value)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : AvtunesysTheme.textPrimary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AvtunesysTheme.highlight.opacity(0.82) : AvtunesysTheme.mutedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? AvtunesysTheme.highlight.opacity(0.95) : AvtunesysTheme.borderSubtle, lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct DiscoveryArtistCard: View {
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
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AvtunesysTheme.textPrimary)
                            .lineLimit(1)

                        Text(L10n.plural(
                            singular: "shell.library.discoveries.artistSongs.one",
                            plural: "shell.library.discoveries.artistSongs.other",
                            count: summary.trackCount,
                            summary.trackCount
                        ))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AvtunesysTheme.textSecondary)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(AvtunesysTheme.textPrimary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 32, height: 32)
                    .background(AvtunesysTheme.mutedSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("common.more"))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AvtunesysTheme.cardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AvtunesysTheme.borderSubtle, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("discoveryArtist.\(summary.id)")
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
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(AvtunesysTheme.mutedSurface)
            .frame(width: 42, height: 42)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AvtunesysTheme.highlight)
            }
    }
}

struct DiscoveryArtistRow: View {
    let summary: DiscoveryArtistSummary
    let openArtist: () -> Void
    let openYouTube: () -> Void
    let openAppleMusic: () -> Void
    let openSpotify: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openArtist) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AvtunesysTheme.textPrimary)
                            .lineLimit(1)

                        Text(L10n.plural(
                            singular: "shell.library.discoveries.artistSongs.one",
                            plural: "shell.library.discoveries.artistSongs.other",
                            count: summary.trackCount,
                            summary.trackCount
                        ))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AvtunesysTheme.highlight)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AvtunesysTheme.textSecondary)
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
                    .foregroundStyle(AvtunesysTheme.textPrimary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 34, height: 34)
                    .background(AvtunesysTheme.mutedSurface.opacity(0.85), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("common.more"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AvtunesysTheme.mutedSurface.opacity(0.64))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(AvtunesysTheme.highlight)
                        .frame(width: 3)
                        .padding(.vertical, 12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AvtunesysTheme.borderSubtle, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("discoveryArtistRow.\(summary.id)")
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
            .fill(AvtunesysTheme.cardSurface)
            .frame(width: 46, height: 46)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AvtunesysTheme.highlight)
            }
    }
}
