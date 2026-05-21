import AVAppShellFoundation
import AVHaptics
import SwiftUI

struct AviQueueSwitchOption: Identifiable {
    let source: AudioPlayerService.PlaybackQueue.Source
    let title: String
    let stations: [Station]

    var id: String {
        "\(source.displayTitle)-\(stations.map(\.id).joined(separator: "-"))"
    }
}

struct RelatedStationContext: Identifiable {
    let baseStation: Station

    var id: String {
        baseStation.id
    }
}

struct AviQueueSwitcherSheet: View {
    let currentSource: AudioPlayerService.PlaybackQueue.Source
    let options: [AviQueueSwitchOption]
    let selectOption: (AviQueueSwitchOption) -> Void
    let onDismiss: () -> Void

    var body: some View {
        AVSelectionSheetScaffold(
            title: L10n.string("shell.queue.title"),
            closeTitle: L10n.string("shell.avi.plans.close"),
            onClose: onDismiss
        ) {
            ForEach(options) { option in
                AVSelectionSheetRow(
                    title: option.title,
                    detail: L10n.plural(singular: "shell.queue.stationCount.one", plural: "shell.queue.stationCount.other", count: option.stations.count, option.stations.count),
                    isSelected: option.source == currentSource
                ) {
                    selectOption(option)
                }
            }
        }
    }
}

struct AviExpandedFooterPlayerView: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    let station: Station
    let playbackQueueSource: AudioPlayerService.PlaybackQueue.Source
    let playbackQueueStations: [Station]
    let stations: [Station]
    let recentStations: [Station]
    let favoriteStations: [Station]
    let openPlayer: () -> Void
    let showArtworkZoom: () -> Void
    let stopPlayback: () -> Void
    let playStationFromQueue: (Station, AudioPlayerService.PlaybackQueue.Source, [Station]) -> Void

    @State private var isShowingQueueSwitcher = false

    var body: some View {
        AVExpandedFooterPlayerScaffold(
            stationTitle: station.name,
            subtitle: artistLine,
            title: titleLine,
            isSubtitleHighlighted: trackArtworkExists,
            artworkAccessibilityLabel: L10n.string("shell.accessibility.zoomArtwork"),
            accessibilityLabel: L10n.string("shell.miniPlayer.accessibility.label", station.name),
            accessibilityHint: L10n.string("shell.miniPlayer.accessibility.hint"),
            stationAction: showArtworkZoom,
            artworkAction: showArtworkZoom,
            metadataAction: showArtworkZoom
        ) {
            artwork
        } controls: {
            controlsRow
        }
        .sheet(isPresented: $isShowingQueueSwitcher) {
            AviQueueSwitcherSheet(
                currentSource: playbackQueueSource,
                options: queueSwitchOptions,
                selectOption: selectQueueOption(_:),
                onDismiss: { isShowingQueueSwitcher = false }
            )
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            queueSourceButton

            queueButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.footerPlayer.previous") {
                AVHaptics.perform(.queueStep)
                audioPlayer.playPreviousInQueue()
            }

            playPauseButton

            queueButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.footerPlayer.next") {
                AVHaptics.perform(.queueStep)
                audioPlayer.playNextInQueue()
            }

            sleepTimerMenu
        }
        .frame(height: 72)
        .frame(maxWidth: .infinity)
    }

    private var playPauseButton: some View {
        Button {
            AVHaptics.perform(.playbackToggle)
            audioPlayer.togglePlayback()
        } label: {
            ZStack {
                Circle()
                    .fill(audioPlayer.isPlaying ? TuneAVTheme.brandGraphite : TuneAVTheme.highlight)

                if audioPlayer.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avi.footerPlayer.playPause")
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            if let artworkURL = audioPlayer.currentTrackArtworkURL {
                TuneAVRemoteArtworkImage(url: artworkURL, size: 152, scale: displayScale) {
                    StationArtworkView(station: station, size: 152)
                }
                .frame(width: 152, height: 152)
                .clipShape(RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 152), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: 152), style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(0.55), lineWidth: 1)
                }
            } else {
                StationArtworkView(
                    station: station,
                    size: 152,
                    animationOverlay: .none,
                    isAnimationActive: false
                )
            }

            if let feedback = currentTrackFeedback {
                TuneAVFeedbackBadge(feedback: feedback, size: 26, fontSize: 10)
                    .offset(x: -5, y: -5)
            }
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

    private func queueButton(
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        AVFooterPlayerControlButton(
            systemImage: systemImage,
            isEnabled: audioPlayer.canCyclePlaybackQueue,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }

    private var queueSourceButton: some View {
        AVCircularMaterialIconButton(
            systemImage: "list.bullet",
            size: 54,
            fontSize: 18,
            fontWeight: .black,
            accessibilityLabel: L10n.string("shell.queue.current", playbackQueueSource.displayTitle),
            accessibilityIdentifier: "avi.footerPlayer.queue"
        ) {
            isShowingQueueSwitcher = true
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            ForEach(sleepTimerOptions, id: \.self) { minutes in
                Button {
                    audioPlayer.setSleepTimer(minutes: minutes)
                } label: {
                    Label(
                        sleepTimerOptionTitle(for: minutes),
                        systemImage: audioPlayer.activeSleepTimerMinutes == minutes ? "checkmark" : "timer"
                    )
                }
            }
        } label: {
            sleepTimerMenuLabel(remainingMinutes: audioPlayer.activeSleepTimerRemainingMinutes)
        }
        .accessibilityLabel(L10n.string("profile.preferences.sleepTimer.title"))
        .accessibilityValue(sleepTimerOptionTitle(for: audioPlayer.activeSleepTimerMinutes))
        .accessibilityIdentifier("avi.footerPlayer.sleepTimer")
    }

    private func sleepTimerMenuLabel(remainingMinutes: Int?) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial.opacity(1))
            VStack(spacing: 1) {
                Image(systemName: "timer")
                    .font(.system(size: remainingMinutes == nil ? 18 : 15, weight: .black))
            if let remainingMinutes {
                Text("\(remainingMinutes) min")
                    .font(.system(size: 8, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            }
        }
        .foregroundStyle(TuneAVTheme.textSecondary)
        .frame(width: 54, height: 54)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .contentShape(Circle())
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var sleepTimerOptions: [Int?] {
        [nil, 15, 30, 45, 60]
    }

    private func sleepTimerOptionTitle(for minutes: Int?) -> String {
        guard let minutes else {
            return L10n.string("profile.preferences.sleepTimer.off")
        }
        return L10n.string("profile.preferences.sleepTimer.minutes", minutes)
    }

    private var queueSwitchOptions: [AviQueueSwitchOption] {
        AviQueueSwitchCoordinator.options(
            currentSource: playbackQueueSource,
            playbackQueueStations: playbackQueueStations,
            stations: stations,
            favoriteStations: favoriteStations,
            recentStations: recentStations
        )
    }

    private func selectQueueOption(_ option: AviQueueSwitchOption) {
        let queue = AviQueueSwitchCoordinator.queue(for: station, option: option)
        playStationFromQueue(station, option.source, queue)
        isShowingQueueSwitcher = false
    }
}

struct AppShellArtworkZoomOverlay: View {
    @Environment(\.displayScale) private var displayScale

    let station: Station
    let artworkURL: URL?
    let title: String
    let subtitle: String
    let dismiss: () -> Void

    var body: some View {
        AVArtworkZoomOverlay(
            title: title,
            subtitle: subtitle,
            accessibilityIdentifier: "avi.footerPlayer.artworkZoomOverlay",
            dismiss: dismiss
        ) { size in
            artwork(size: size)
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let artworkURL {
            TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                StationArtworkView(station: station, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(artworkShape(size: size))
            .overlay {
                artworkShape(size: size)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        } else {
            StationArtworkView(
                station: station,
                size: size,
                animationOverlay: .none,
                isAnimationActive: false
            )
        }
    }

    private func artworkShape(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size), style: .continuous)
    }
}
