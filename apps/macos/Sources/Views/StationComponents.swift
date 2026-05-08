import SwiftUI

struct FeaturedStationCard: View {
    let station: Station
    let label: String
    let subtitle: String
    let isFavorite: Bool
    let playAction: () -> Void
    let favoriteAction: () -> Void
    let detailsAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 520

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Text(label)
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(TuneAVTheme.highlight)

                    Spacer()

                    Text(station.country)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                if compact {
                    VStack(alignment: .leading, spacing: 16) {
                        StationArtworkView(station: station, size: 86)
                        featuredCopy
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        StationArtworkView(station: station, size: 96)
                        featuredCopy
                    }
                }

                HStack(spacing: 10) {
                    Button(action: playAction) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text(L10n.string("player.control.play"))
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: favoriteAction) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isFavorite ? Color(red: 1, green: 0.17, blue: 0.38) : TuneAVTheme.textPrimary)
                            .frame(width: 48, height: 48)
                            .avRoundedControl(cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .avCardSurface(cornerRadius: 30)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .onTapGesture(perform: detailsAction)
        }
        .frame(minHeight: 168)
    }

    private var featuredCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(station.name)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(2)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !station.tagsList.isEmpty {
                Text(station.tagsList.prefix(3).joined(separator: " · "))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiveNowPanel: View {
    let currentStation: Station?
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("player.header.nowPlaying"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)

                Spacer()

                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
                    }
            }

            HStack(spacing: 12) {
                Group {
                    if let currentStation {
                        StationArtworkView(station: currentStation, size: 52)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TuneAVTheme.mutedSurface)
                            .frame(width: 52, height: 52)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(currentStation?.name ?? L10n.string("audio.status.ready"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)

                    Text(currentStation?.shortMeta ?? L10n.string("shell.home.empty.detail"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                livePill(title: currentStation == nil ? L10n.string("audio.status.ready") : L10n.string("player.header.nowPlaying"))

                if let currentStation {
                    livePill(title: currentStation.country, accent: currentStation.flagEmoji)
                }
            }
        }
        .padding(18)
        .avCardSurface(
            cornerRadius: 24,
            fill: TuneAVTheme.darkSurface,
            borderColor: TuneAVTheme.borderSubtle.opacity(0.48),
            shadowOpacity: 0.72,
            shadowRadius: 16,
            shadowY: 8
        )
    }

    private func livePill(title: String, accent: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let accent {
                Text(accent)
            }

            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(TuneAVTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(TuneAVTheme.mutedSurface, in: Capsule())
    }
}

struct StationSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
            }
            VStack(spacing: 8) {
                content
            }
        }
    }
}

struct StationThumbnailView: View {
    let station: Station
    let size: CGFloat
    var surfaceStyle: StationArtworkView.SurfaceStyle = .light

    private var cornerRadius: CGFloat {
        size * 0.24
    }

    var body: some View {
        Group {
            if let artworkURL = station.displayArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        if station.displayArtworkUsesFaviconProxy {
                            StationArtworkView(
                                station: station,
                                size: size,
                                surfaceStyle: surfaceStyle
                            )
                        } else {
                            image
                                .resizable()
                                .scaledToFill()
                        }
                    default:
                        StationArtworkView(
                            station: station,
                            size: size,
                            surfaceStyle: surfaceStyle
                        )
                    }
                }
            } else {
                StationArtworkView(
                    station: station,
                    size: size,
                    surfaceStyle: surfaceStyle
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(
            thumbnailBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(thumbnailBorder, lineWidth: 1)
        }
        .shadow(color: thumbnailShadow, radius: size * 0.08, y: size * 0.03)
    }

    private var thumbnailBackground: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.cardSurface
        case .dark:
            return TuneAVTheme.darkSurface
        }
    }

    private var thumbnailBorder: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.borderSubtle
        case .dark:
            return Color.white.opacity(0.08)
        }
    }

    private var thumbnailShadow: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.softShadow.opacity(0.08)
        case .dark:
            return TuneAVTheme.softShadow.opacity(0.18)
        }
    }
}

struct StationRowCard: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let station: Station
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let playAction: () -> Void
    let detailsAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let artworkSize = min(max(width, 118), 170)
            let isPlayingCurrentStation = audioPlayer.isCurrent(station) && audioPlayer.isPlaying

            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Button {
                        if audioPlayer.isCurrent(station) {
                            audioPlayer.togglePlayback()
                        } else {
                            playAction()
                        }
                    } label: {
                        StationThumbnailView(station: station, size: artworkSize)
                            .overlay {
                                RoundedRectangle(cornerRadius: artworkSize * 0.24, style: .continuous)
                                    .fill(isPlayingCurrentStation ? TuneAVTheme.highlight.opacity(0.16) : .clear)
                            }
                            .overlay {
                                if audioPlayer.isCurrent(station) {
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                        Circle()
                                            .stroke(TuneAVTheme.highlight.opacity(0.42), lineWidth: 1)
                                        Image(systemName: isPlayingCurrentStation ? "pause.fill" : "play.fill")
                                            .font(.system(size: 15, weight: .black))
                                            .foregroundStyle(isPlayingCurrentStation ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
                                    }
                                    .frame(width: 40, height: 40)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: artworkSize * 0.24, style: .continuous)
                                    .stroke(isPlayingCurrentStation ? TuneAVTheme.highlight : TuneAVTheme.borderSubtle, lineWidth: isPlayingCurrentStation ? 2 : 1)
                            }
                    }
                    .buttonStyle(.plain)

                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isFavorite ? Color(red: 1, green: 0.17, blue: 0.38) : TuneAVTheme.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(TuneAVTheme.borderSubtle.opacity(0.65), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)

                    Text(artistLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(audioPlayer.isCurrent(station) ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.9))
                        .lineLimit(1)
                        .frame(height: 14, alignment: .leading)

                    Text(titleLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.74))
                        .lineLimit(1)
                        .frame(height: 13, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: detailsAction)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture(perform: detailsAction)
        }
        .frame(height: 204)
    }

    private var artistLine: String {
        stationDisplayLines.artistLine
    }

    private var titleLine: String {
        stationDisplayLines.titleLine
    }

    private var stationDisplayLines: TuneAVStationDisplayLines {
        TuneAVStationDisplayLines.resolve(
            station: station,
            isCurrent: audioPlayer.isCurrent(station),
            currentArtist: audioPlayer.currentTrackArtist,
            currentTitle: audioPlayer.currentTrackTitle,
            currentAlbumTitle: audioPlayer.currentTrackAlbumTitle,
            nowPlayingTrack: nil,
            detailText: station.cardDetailText(
                preferCountryName: station.flagEmoji == nil,
                unknownValues: Station.unknownDetailValues,
                locale: L10n.locale
            ) ?? L10n.string("shell.station.row.defaultDetail"),
            liveFallback: L10n.string("shell.station.codec.live")
        )
    }

}
struct EmptyStateCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22))
                .foregroundStyle(TuneAVTheme.highlight)
            Text(title)
                .font(.headline)
                .foregroundStyle(TuneAVTheme.textPrimary)
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(TuneAVTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .avCardSurface(cornerRadius: 22)
    }
}
