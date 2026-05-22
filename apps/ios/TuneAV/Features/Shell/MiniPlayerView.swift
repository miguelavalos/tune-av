import AVAppShellFoundation
import AVHaptics
import SwiftUI

struct MiniPlayerView: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    let station: Station
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
                            .font(.system(size: 14, weight: .bold))
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
                size: 46,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 46),
                strokeOpacity: 0.55
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: 46, scale: displayScale) {
                    StationArtworkView(station: station, size: 46)
                }
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
