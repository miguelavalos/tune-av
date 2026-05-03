import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    let station: Station
    let openPlayer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            miniArtwork

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(AvtunesysTheme.textPrimary)

                Text(artistLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trackArtworkExists ? AvtunesysTheme.highlight : AvtunesysTheme.textSecondary)
                    .lineLimit(1)

                Text(titleLine)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AvtunesysTheme.textSecondary.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                audioPlayer.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(playButtonBackground)

                    if isCurrentStationLoading {
                        ProgressView()
                            .tint(playButtonForeground)
                    } else {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(playButtonForeground)
                    }
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("miniPlayer.playPause")

            if audioPlayer.canCyclePlaybackQueue {
                Button {
                    audioPlayer.playNextInQueue()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AvtunesysTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("miniPlayer.next")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AvtunesysTheme.elevatedSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AvtunesysTheme.glassStroke, AvtunesysTheme.highlight.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: AvtunesysTheme.glassShadow.opacity(0.7), radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: openPlayer)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L10n.string("shell.miniPlayer.accessibility.label", station.name))
        .accessibilityHint(L10n.string("shell.miniPlayer.accessibility.hint"))
        .accessibilityIdentifier("miniPlayer.container")
    }

    @ViewBuilder
    private var miniArtwork: some View {
        if let artworkURL = audioPlayer.currentTrackArtworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    StationArtworkView(station: station, size: 46)
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AvtunesysTheme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
        } else {
            StationArtworkView(station: station, size: 46)
        }
    }

    private var artistLine: String {
        if let artist = normalizedMetadata(audioPlayer.currentTrackArtist) {
            return artist
        }

        return station.cardDetailText(preferCountryName: station.flagEmoji == nil)
            ?? L10n.string("shell.station.row.defaultDetail")
    }

    private var titleLine: String {
        if let title = normalizedMetadata(audioPlayer.currentTrackTitle) {
            return title
        }

        if let albumTitle = normalizedMetadata(audioPlayer.currentTrackAlbumTitle) {
            return albumTitle
        }

        return L10n.string("player.track.liveStreamActive")
    }

    private var trackArtworkExists: Bool {
        audioPlayer.currentTrackArtworkURL != nil
    }

    private var isCurrentStationLoading: Bool {
        audioPlayer.isCurrent(station) && audioPlayer.isLoading
    }

    private var playButtonBackground: Color {
        if audioPlayer.isPlaying {
            return AvtunesysTheme.brandGraphite
        }
        return AvtunesysTheme.highlight
    }

    private var playButtonForeground: Color {
        .white
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        AVTunesysText.normalizedValue(value)
    }
}
