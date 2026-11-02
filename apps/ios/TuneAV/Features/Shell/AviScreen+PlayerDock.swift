import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    var aviSleepTimerMenu: some View {
        Menu {
            ForEach(sleepTimerOptions, id: \.self) { minutes in
                Button {
                    setSleepTimer(minutes)
                } label: {
                    Label(
                        sleepTimerOptionTitle(for: minutes),
                        systemImage: activeSleepTimerMinutes == minutes ? "checkmark" : "timer"
                    )
                }
            }
        } label: {
            sleepTimerMenuLabel(remainingMinutes: activeSleepTimerRemainingMinutes)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("profile.preferences.sleepTimer.title"))
        .accessibilityValue(sleepTimerOptionTitle(for: activeSleepTimerMinutes))
        .accessibilityIdentifier("avi.controls.sleepTimer")
    }

    func sleepTimerMenuLabel(remainingMinutes: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .black))

            if let remainingMinutes {
                Text("\(remainingMinutes) min")
                    .font(.system(size: 12, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .foregroundStyle(TuneAVTheme.textPrimary)
        .frame(width: 70, height: 34)
        .background(Color.clear, in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
        .contentShape(Capsule())
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    var sleepTimerOptions: [Int?] {
        [nil, 15, 30, 45, 60]
    }

    func sleepTimerOptionTitle(for minutes: Int?) -> String {
        guard let minutes else {
            return L10n.string("profile.preferences.sleepTimer.off")
        }
        return L10n.string("profile.preferences.sleepTimer.minutes", minutes)
    }

    func queueDockButton(
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        AVCircularMaterialIconButton(
            systemImage: systemImage,
            size: 48,
            fontSize: 17,
            isEnabled: canCyclePlaybackQueue,
            accessibilityLabel: accessibilityLabel(for: systemImage),
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }

    var queueSourceDockButton: some View {
        AVCircularMaterialIconButton(
            systemImage: "list.bullet",
            size: 48,
            fontSize: 17,
            fontWeight: .black,
            accessibilityLabel: L10n.string("shell.queue.current", playbackQueueSource.displayTitle),
            accessibilityIdentifier: "avi.controls.queue"
        ) {
            isShowingQueueSwitcher = true
        }
    }

    var closeSignalDockButton: some View {
        AVCircularMaterialIconButton(
            systemImage: "power",
            size: 48,
            fontSize: 17,
            fontWeight: .black,
            accessibilityLabel: L10n.string("shell.accessibility.closeSignal"),
            accessibilityIdentifier: "avi.controls.closeSignal",
            action: stopPlayback
        )
    }

    var queueSwitchOptions: [AviQueueSwitchOption] {
        AviQueueSwitchCoordinator.options(
            currentSource: playbackQueueSource,
            playbackQueueStations: playbackQueueStations,
            stations: stations,
            favoriteStations: favoriteStations,
            recentStations: recentStations
        )
    }

    func selectQueueOption(_ option: AviQueueSwitchOption) {
        guard let currentStation = currentStation ?? focusedStation else { return }
        let queue = AviQueueSwitchCoordinator.queue(for: currentStation, option: option)
        playStationFromQueue(currentStation, option.source, queue)
        isShowingQueueSwitcher = false
    }

    @ViewBuilder
    func currentArtwork(for station: Station, size: CGFloat) -> some View {
        if let artworkURL = currentTrackArtworkURL ?? station.displayArtworkURL {
            AVFramedArtwork(
                size: size,
                cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size)
            ) {
                TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                    StationThumbnailView(station: station, size: size, textMode: .none, animationOverlay: .none, isAnimationActive: false)
                }
            }
        } else {
            StationThumbnailView(station: station, size: size, textMode: .none, animationOverlay: .none, isAnimationActive: false)
        }
    }

    func artworkZoomOverlay(for station: Station) -> some View {
        AVArtworkZoomOverlay(
            title: currentTrackTitle ?? station.name,
            subtitle: currentTrackArtist ?? station.name,
            accessibilityIdentifier: "avi.nowPlaying.artworkZoomOverlay",
            dismiss: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isShowingArtworkZoom = false
                }
            }
        ) { artworkSize in
            currentArtwork(for: station, size: artworkSize)
        }
    }
}
