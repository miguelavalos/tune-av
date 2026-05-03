import SwiftUI

struct ShellBrandHeader: View {
    let statusTitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .padding(10)
                .background(AvtunesysTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AvtunesysTheme.borderSubtle, lineWidth: 1)
                }

            (
                Text("AV ")
                    .foregroundStyle(AvtunesysTheme.highlight) +
                Text("Tune")
                    .foregroundStyle(AvtunesysTheme.textPrimary) +
                Text("sys")
                    .foregroundStyle(AvtunesysTheme.highlight)
            )
            .font(.system(size: 22, weight: .bold))

            Spacer()

            ShellStatusPill(title: statusTitle)
        }
    }
}

struct LiveNowPanel: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let currentStation: Station?
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("shell.liveNow.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AvtunesysTheme.highlight)

                Spacer()

                ShellStatusPill(title: status)
            }

            HStack(spacing: 12) {
                Group {
                    if let currentStation {
                        StationThumbnailView(station: currentStation, size: 64, surfaceStyle: .dark)
                    } else {
                        EmptyLiveArtwork(size: 64)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(audioPlayer.currentTrackTitle ?? currentStation?.name ?? L10n.string("shell.liveNow.ready"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(AvtunesysTheme.textInverse)
                        .lineLimit(2)

                    if let currentTrackArtist = audioPlayer.currentTrackArtist, !currentTrackArtist.isEmpty {
                        Text(currentTrackArtist)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AvtunesysTheme.highlight)
                    }

                    Text(audioPlayer.currentTrackAlbumTitle ?? currentStation?.shortMeta ?? L10n.string("shell.liveNow.subtitle.empty"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AvtunesysTheme.textInverse.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AvtunesysTheme.darkSurface)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AvtunesysTheme.highlight.opacity(0.18))
                        .padding(.top, 18)
                        .padding(.trailing, 16)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AvtunesysTheme.borderSubtle.opacity(0.48), lineWidth: 1)
                }
        )
        .shadow(color: AvtunesysTheme.softShadow.opacity(0.72), radius: 16, y: 8)
    }
}

struct EmptyLiveArtwork: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AvtunesysTheme.darkSurface,
                        AvtunesysTheme.highlight.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .overlay {
                ZStack {
                    Circle()
                        .fill(AvtunesysTheme.highlight.opacity(0.08))
                        .frame(width: size * 0.62, height: size * 0.62)

                    HStack(alignment: .bottom, spacing: size * 0.05) {
                        ForEach(Array([0.28, 0.46, 0.74, 0.46, 0.28].enumerated()), id: \.offset) { _, scale in
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AvtunesysTheme.textInverse.opacity(0.45),
                                            AvtunesysTheme.highlight.opacity(0.92)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: size * 0.07, height: size * CGFloat(scale))
                        }
                    }
                    .frame(height: size * 0.24)
                }
            }
            .shadow(color: AvtunesysTheme.highlight.opacity(0.07), radius: 10, y: 5)
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
                        image
                            .resizable()
                            .scaledToFill()
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
            return Color.white
        case .dark:
            return AvtunesysTheme.darkSurface
        }
    }

    private var thumbnailBorder: Color {
        switch surfaceStyle {
        case .light:
            return AvtunesysTheme.borderSubtle
        case .dark:
            return Color.white.opacity(0.08)
        }
    }

    private var thumbnailShadow: Color {
        switch surfaceStyle {
        case .light:
            return AvtunesysTheme.softShadow.opacity(0.08)
        case .dark:
            return AvtunesysTheme.softShadow.opacity(0.18)
        }
    }
}
