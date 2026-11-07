import AVAppShellFoundation
import AVHaptics
import SwiftUI

enum MiniPlayerMetric {
    /// The mini player's tallest height at the default text size: a station name on two
    /// lines, the artist line and the song line, with the padding of the card (86.7 pt
    /// measured on an iPhone 17). The shell's scroll padding and footer backdrop are built
    /// on it; larger text sizes make the player taller and the shell adds the difference.
    static let height: CGFloat = 87
}

struct MiniPlayerView: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    let station: Station
    var artworkMorphNamespace: Namespace.ID? = nil
    let openPlayer: () -> Void

    var body: some View {
        AVMiniPlayerScaffold(
            title: station.name,
            subtitle: artistLine,
            detail: titleLine,
            isSubtitleHighlighted: trackArtworkExists,
            accessibilityLabel: L10n.string("shell.miniPlayer.accessibility.label", station.name),
            accessibilityHint: L10n.string("shell.miniPlayer.accessibility.hint"),
            action: openPlayer
        ) {
            ZStack(alignment: .topLeading) {
                miniArtwork
                    .tunePlayerArtworkMorph(in: artworkMorphNamespace, baseSize: Self.artworkSize)
                feedbackBadge
                    .offset(x: -5, y: -5)
            }
        } controls: {
            queueButton(systemImage: "backward.fill", accessibilityIdentifier: "miniPlayer.previous") {
                AVHaptics.perform(.step)
                audioPlayer.playPreviousInQueue()
            }

            Button {
                AVHaptics.perform(.primaryAction)
                if shouldRestartWithVisibleStation {
                    audioPlayer.play(station: station, queue: audioPlayer.playbackQueue)
                } else {
                    audioPlayer.togglePlayback()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(playButtonBackground)

                    if isCurrentStationLoading {
                        ProgressView()
                            .tint(playButtonForeground)
                    } else {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            // Scaled like the package's previous and next icons beside it, which
                            // grow with the text size inside a circle that keeps its size.
                            .tuneScaledFont(size: 14, weight: .bold)
                            .foregroundStyle(playButtonForeground)
                    }
                }
                .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("miniPlayer.playPause")

            queueButton(systemImage: "forward.fill", accessibilityIdentifier: "miniPlayer.next") {
                AVHaptics.perform(.step)
                audioPlayer.playNextInQueue()
            }
        }
        // The mini player is a compact overlay over the content: past the xxxLarge text size
        // its three wrapped lines would cover most of the screen, so it stops growing there,
        // keeping two lines of station name plus the song lines; the full player follows the
        // accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task(id: fullPlayerArtworkPrewarmKey) {
            guard let url = fullPlayerArtworkURL else { return }
            await TuneAVArtworkImagePipeline.shared.prewarm(url: url, size: Self.artworkSize, scale: displayScale)
            guard !Task.isCancelled else { return }
            await TuneAVArtworkImagePipeline.shared.prewarm(
                url: url,
                size: AviExpandedFooterPlayerView.artworkSize,
                scale: displayScale
            )
        }
    }

    private var fullPlayerArtworkURL: URL? {
        audioPlayer.currentTrackArtworkURL ?? station.displayArtworkURL
    }

    private var fullPlayerArtworkPrewarmKey: String {
        "\(fullPlayerArtworkURL?.absoluteString ?? "")|\(displayScale)"
    }

    private var shouldRestartWithVisibleStation: Bool {
        guard let currentStation = audioPlayer.currentStation else { return false }
        return currentStation.id == station.id && currentStation.streamURL != station.streamURL
    }

    @ViewBuilder
    private var feedbackBadge: some View {
        if let feedback = currentTrackFeedback {
            TuneAVFeedbackBadge(feedback: feedback, size: 22)
                .accessibilityIdentifier("miniPlayer.trackFeedback")
        }
    }

    @ViewBuilder
    private var miniArtwork: some View {
        if let artworkURL = audioPlayer.currentTrackArtworkURL {
            AVFramedArtwork(
                size: Self.artworkSize,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: Self.artworkSize),
                strokeOpacity: 0.55
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: Self.artworkSize, scale: displayScale) {
                    StationArtworkView(station: station, size: Self.artworkSize)
                }
            }
        } else {
            StationArtworkView(
                station: station,
                size: Self.artworkSize,
                animationOverlay: .none,
                isAnimationActive: false
            )
        }
    }

    private static let artworkSize: CGFloat = 46

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
        AVMiniPlayerControlButton(
            systemImage: systemImage,
            isEnabled: audioPlayer.canCyclePlaybackQueue,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        TuneAVDisplayMetadata.normalized(value)
    }
}
