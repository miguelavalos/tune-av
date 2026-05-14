import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    let station: Station
    let openPlayer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                miniArtwork
                feedbackBadge
                    .offset(x: -5, y: -5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(artistLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trackArtworkExists ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                    .lineLimit(1)

                Text(titleLine)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            queueButton(systemImage: "backward.fill", accessibilityIdentifier: "miniPlayer.previous") {
                audioPlayer.playPreviousInQueue()
            }

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

            queueButton(systemImage: "forward.fill", accessibilityIdentifier: "miniPlayer.next") {
                audioPlayer.playNextInQueue()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TuneAVTheme.elevatedSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [TuneAVTheme.glassStroke, TuneAVTheme.highlight.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: TuneAVTheme.glassShadow.opacity(0.7), radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: openPlayer)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L10n.string("shell.miniPlayer.accessibility.label", station.name))
        .accessibilityHint(L10n.string("shell.miniPlayer.accessibility.hint"))
        .accessibilityIdentifier("miniPlayer.container")
    }

    @ViewBuilder
    private var feedbackBadge: some View {
        if let feedback = currentTrackFeedback {
            Image(systemName: feedback.systemImage)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(feedback == .liked ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse)
                .frame(width: 22, height: 22)
                .background(feedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.86), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.78), lineWidth: 1)
                }
                .accessibilityLabel(feedback.localizedState)
                .accessibilityIdentifier("miniPlayer.trackFeedback")
        }
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
            .clipShape(RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 46), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 46), style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
        } else {
            StationArtworkView(
                station: station,
                size: 46,
                animationOverlay: .none,
                isAnimationActive: false
            )
        }
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
            detailText: station.cardDetailText(preferCountryName: station.flagEmoji == nil)
                ?? L10n.string("shell.station.row.defaultDetail"),
            liveFallback: L10n.string("player.track.liveStreamActive")
        )
    }

    private var trackArtworkExists: Bool {
        audioPlayer.currentTrackArtworkURL != nil
    }

    private var currentTrackFeedback: TuneAVStationFeedback? {
        libraryStore.feedbackForDiscoveredTrack(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist
        )
    }

    private var isCurrentStationLoading: Bool {
        audioPlayer.isCurrent(station) && audioPlayer.isLoading
    }

    private var playButtonBackground: Color {
        if audioPlayer.isPlaying {
            return TuneAVTheme.brandGraphite
        }
        return TuneAVTheme.highlight
    }

    private var playButtonForeground: Color {
        .white
    }

    private func queueButton(
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(audioPlayer.canCyclePlaybackQueue ? TuneAVTheme.textSecondary : TuneAVTheme.textSecondary.opacity(0.28))
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial.opacity(audioPlayer.canCyclePlaybackQueue ? 1 : 0.45), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(audioPlayer.canCyclePlaybackQueue ? 0.12 : 0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!audioPlayer.canCyclePlaybackQueue)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        TuneAVDisplayMetadata.normalized(value)
    }
}
