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
        NavigationStack {
            List(options) { option in
                Button {
                    selectOption(option)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.source == currentSource ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(option.source == currentSource ? TuneAVTheme.highlight : TuneAVTheme.textSecondary.opacity(0.55))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(TuneAVTheme.textPrimary)

                            Text(L10n.plural(singular: "shell.queue.stationCount.one", plural: "shell.queue.stationCount.other", count: option.stations.count, option.stations.count))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TuneAVTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(L10n.string("shell.queue.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("shell.avi.plans.close"), action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
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
        VStack(spacing: 0) {
            Button(action: showArtworkZoom) {
                stationNameText
            }
            .buttonStyle(.plain)
            .accessibilityLabel(station.name)
            .accessibilityIdentifier("avi.footerPlayer.stationName")
            .frame(height: 22)

            Spacer()
                .frame(height: 8)

            Button(action: showArtworkZoom) {
                artwork
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.accessibility.zoomArtwork"))
            .accessibilityIdentifier("avi.footerPlayer.artworkZoom")
            .frame(height: 152)

            Spacer()
                .frame(height: 14)

            Button(action: showArtworkZoom) {
                metadataText
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("shell.accessibility.zoomArtwork"))
            .accessibilityIdentifier("avi.footerPlayer.textZoom")
            .frame(height: 58)

            Spacer(minLength: 0)

            controlsRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(height: 360)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TuneAVTheme.cardSurface)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("shell.miniPlayer.accessibility.label", station.name))
        .accessibilityHint(L10n.string("shell.miniPlayer.accessibility.hint"))
        .accessibilityIdentifier("avi.footerPlayer.container")
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
                audioPlayer.playPreviousInQueue()
            }

            playPauseButton

            queueButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.footerPlayer.next") {
                audioPlayer.playNextInQueue()
            }

            sleepTimerMenu
        }
        .frame(height: 72)
        .frame(maxWidth: .infinity)
    }

    private var playPauseButton: some View {
        Button {
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

    private var metadataText: some View {
        VStack(alignment: .center, spacing: 5) {
            Text(artistLine)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(trackArtworkExists ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 19, alignment: .center)

            Text(titleLine)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .truncationMode(.tail)
                .frame(height: 40, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    private var stationNameText: some View {
        Text(station.name)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(TuneAVTheme.textSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .truncationMode(.tail)
            .frame(height: 18, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
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
                Image(systemName: feedback.systemImage)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(feedback == .liked ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse)
                    .frame(width: 26, height: 26)
                    .background(feedback == .liked ? TuneAVTheme.highlight : TuneAVTheme.brandGraphite.opacity(0.86), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.78), lineWidth: 1)
                    }
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
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(audioPlayer.canCyclePlaybackQueue ? TuneAVTheme.textSecondary : TuneAVTheme.textSecondary.opacity(0.28))
                .frame(width: 54, height: 54)
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

    private var queueSourceButton: some View {
        Button {
            isShowingQueueSwitcher = true
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 18, weight: .black))
            .foregroundStyle(TuneAVTheme.textSecondary)
            .frame(width: 54, height: 54)
            .background(.ultraThinMaterial.opacity(1), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.queue.current", playbackQueueSource.displayTitle))
        .accessibilityIdentifier("avi.footerPlayer.queue")
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
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.76))
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            GeometryReader { proxy in
                let artworkSize = min(proxy.size.width - 8, 372)
                let captionWidth = min(artworkSize, 360)

                VStack(spacing: 12) {
                    artwork(size: artworkSize)
                        .shadow(color: .black.opacity(0.46), radius: 32, y: 18)

                    VStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 27, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        Text(subtitle)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.74)
                    }
                    .frame(width: captionWidth - 28)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 15)
                    .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.52), radius: 22, y: 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)
            }
        }
        .accessibilityIdentifier("avi.footerPlayer.artworkZoomOverlay")
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
