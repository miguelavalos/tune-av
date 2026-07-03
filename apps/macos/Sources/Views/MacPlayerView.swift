import AppKit
import AVAppShellFoundation
import AVAviFoundation
import SwiftUI

struct MacFullPlayerView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: TuneAVMacModel
    @State private var reactionEmotion: TuneAVAviEmotion?
    @State private var reactionStartedAt: Date?
    @State private var isShowingMoreWithAvi = false

    var showsCloseButton = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("shell.liveNow.title"))
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)

                Spacer()

            }
            .padding(20)

            if let station = model.currentStation {
                ScrollView {
                    VStack(spacing: 12) {
                        MacFullPlayerAviHeader(
                            station: station,
                            emotion: aviEmotion(for: station),
                            reactionEmotion: reactionEmotion,
                            reactionStartedAt: reactionStartedAt
                        )

                        MacStationFeedbackCard(
                            station: station,
                            isMoreWithAviPresented: $isShowingMoreWithAvi,
                            showReaction: showAviReaction
                        )

                        MacNowPlayingDock(station: station)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            } else {
                VStack {
                    Spacer(minLength: 24)

                    MacEmptyPlayerCard()

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .frame(minWidth: showsCloseButton ? 520 : 360, minHeight: 620)
        .background(TuneAVTheme.shellBackground)
    }

    private func aviEmotion(for station: Station) -> TuneAVAviEmotion {
        TuneAVAviEmotionResolver.focusedSignalEmotion(
            focusedStation: station,
            isFocusedStationActive: model.currentStation?.id == station.id,
            isPlaying: model.isPlaying,
            isLoading: model.playbackStatus.isLoading,
            currentTrackTitle: model.currentTrackTitle,
            currentTrackArtist: model.currentTrackArtist,
            feedback: model.hasCurrentDiscovery ? model.currentDiscoveryFeedback : model.stationFeedback[station.id]
        )
    }

    private func showAviReaction(_ emotion: TuneAVAviEmotion) {
        let startedAt = Date()
        reactionEmotion = emotion
        reactionStartedAt = startedAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if reactionEmotion == emotion, reactionStartedAt == startedAt {
                reactionEmotion = nil
                reactionStartedAt = nil
            }
        }
    }
}

private struct MacFullPlayerAviHeader: View {
    @EnvironmentObject private var model: TuneAVMacModel

    let station: Station
    let emotion: TuneAVAviEmotion
    let reactionEmotion: TuneAVAviEmotion?
    let reactionStartedAt: Date?

    var body: some View {
        let activeEmotion = reactionEmotion ?? emotion
        let mode = reactionEmotion == nil ? "static" : "reaction"
        AVAviFocusedHeaderScaffold(
            label: L10n.string("shell.avi.state.listening"),
            title: model.nowPlayingDisplayLines?.trackTitleLine ?? station.name,
            summary: model.nowPlayingDisplayLines?.trackSupportingLine ?? station.primaryDetailLine,
            accessibilityValue: "\(mode):\(activeEmotion.assetName)"
        ) {
            MacAviReactionEmotionImage(
                emotion: emotion,
                reactionEmotion: reactionEmotion,
                reactionStartedAt: reactionStartedAt,
                size: 86
            )
            .frame(width: 86, height: 86)
            .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
            .overlay {
                Circle().stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
            }
            .accessibilityLabel(L10n.string("shell.avi.title"))
        }
    }
}

private struct MacAviReactionEmotionImage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let emotion: TuneAVAviEmotion
    let reactionEmotion: TuneAVAviEmotion?
    let reactionStartedAt: Date?
    let size: CGFloat

    @State private var displayedEmotion: TuneAVAviEmotion
    @State private var lastEmotionChange = Date.distantPast

    init(
        emotion: TuneAVAviEmotion,
        reactionEmotion: TuneAVAviEmotion?,
        reactionStartedAt: Date?,
        size: CGFloat
    ) {
        self.emotion = emotion
        self.reactionEmotion = reactionEmotion
        self.reactionStartedAt = reactionStartedAt
        self.size = size
        _displayedEmotion = State(initialValue: emotion)
    }

    private var activeEmotion: TuneAVAviEmotion {
        reactionEmotion ?? displayedEmotion
    }

    private var frames: [String] {
        guard reactionEmotion != nil, !reduceMotion else { return [activeEmotion.fullBodyAssetName] }
        return MacAviReactionFrames.frames(for: activeEmotion)
    }

    private var accessibilityState: String {
        let mode = reactionEmotion == nil ? "static" : "reaction"
        return "\(mode):\(activeEmotion.assetName)"
    }

    var body: some View {
        Group {
            if reactionEmotion != nil, !reduceMotion {
                TimelineView(.periodic(from: .now, by: MacAviReactionFrames.frameDuration)) { timeline in
                    let elapsed = reactionStartedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                    let frameIndex = MacAviReactionFrames.frameIndex(
                        elapsed: elapsed,
                        frameCount: frames.count
                    )

                    aviImage(named: frames[frameIndex])
                        .modifier(MacAviReactionMotion(emotion: activeEmotion, elapsed: elapsed))
                }
            } else {
                aviImage(named: activeEmotion.fullBodyAssetName)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .animation(.snappy(duration: 0.16), value: frames)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("shell.avi.title"))
        .accessibilityValue(accessibilityState)
        .accessibilityIdentifier("avi.fullPlayer.emotion")
        .onAppear {
            displayedEmotion = emotion
            lastEmotionChange = Date()
        }
        .onChange(of: emotion) { _, candidate in
            adopt(candidate)
        }
        .task(id: emotion) {
            await adoptWhenAllowed(emotion)
        }
    }

    private func aviImage(named assetName: String) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private func adopt(_ candidate: TuneAVAviEmotion) {
        let now = Date()
        guard TuneAVAviEmotionStability.shouldAdopt(
            displayed: displayedEmotion,
            candidate: candidate,
            elapsedSinceLastChange: now.timeIntervalSince(lastEmotionChange)
        ) else { return }

        displayedEmotion = candidate
        lastEmotionChange = now
    }

    @MainActor
    private func adoptWhenAllowed(_ candidate: TuneAVAviEmotion) async {
        guard displayedEmotion != candidate else { return }
        let minimumInterval = candidate.transitionPriority > displayedEmotion.transitionPriority
            ? TuneAVAviEmotionStability.immediateMinimumDisplayInterval
            : TuneAVAviEmotionStability.defaultMinimumDisplayInterval
        let elapsed = Date().timeIntervalSince(lastEmotionChange)
        let remaining = max(0, minimumInterval - elapsed)
        if remaining > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        adopt(candidate)
    }
}

private enum MacAviReactionFrames {
    static let frameDuration: TimeInterval = 1.0 / 12.0

    private static let listeningIdleFrames = availableFrames(for: "AviTuneListeningIdle", count: 20)
    private static let happyReactFrames = availableFrames(for: "AviTuneHappyReact", count: 20)
    private static let savedFrames = availableFrames(for: "AviTuneSaved", count: 20)
    private static let curiousFrames = availableFrames(for: "AviTuneCurious", count: 20)
    private static let thinkingFrames = availableFrames(for: "AviTuneThinking", count: 20)
    private static let dislikeFrames = availableFrames(for: "AviTuneDislike", count: 20)
    private static let surprisedFrames = availableFrames(for: "AviTuneSurprised", count: 20)
    private static let calmIdleFrames = availableFrames(for: "AviTuneCalmIdle", count: 20)
    private static let sleepIdleFrames = availableFrames(for: "AviTuneSleepIdle", count: 20)

    static func frameIndex(elapsed: TimeInterval, frameCount: Int) -> Int {
        guard frameCount > 1 else { return 0 }
        let tick = Int((max(0, elapsed) / frameDuration).rounded(.down))
        return tick % frameCount
    }

    static func frames(for emotion: TuneAVAviEmotion) -> [String] {
        switch emotion {
        case .neutral, .listening, .focused:
            return listeningIdleFrames ?? [emotion.fullBodyAssetName]
        case .happy, .liked, .celebrate:
            return happyReactFrames ?? [emotion.fullBodyAssetName]
        case .saved:
            return savedFrames ?? happyReactFrames ?? [emotion.fullBodyAssetName]
        case .curious:
            return curiousFrames ?? [emotion.fullBodyAssetName]
        case .thinking:
            return thinkingFrames ?? [emotion.fullBodyAssetName]
        case .dislike, .warning:
            return dislikeFrames ?? [emotion.fullBodyAssetName]
        case .surprised:
            return surprisedFrames ?? [emotion.fullBodyAssetName]
        case .calm:
            return calmIdleFrames ?? sleepIdleFrames ?? [emotion.fullBodyAssetName]
        case .sleep:
            return sleepIdleFrames ?? [emotion.fullBodyAssetName]
        }
    }

    private static func availableFrames(for prefix: String, count: Int) -> [String]? {
        let names = (0..<count).map { "\(prefix)\(String(format: "%03d", $0))" }
        let existing = names.filter { NSImage(named: $0) != nil }
        return existing.count >= 2 ? existing : nil
    }
}

private struct MacAviReactionMotion: ViewModifier {
    let emotion: TuneAVAviEmotion
    let elapsed: TimeInterval

    func body(content: Content) -> some View {
        let values = motionValues
        content
            .scaleEffect(values.scale)
            .rotationEffect(.degrees(values.rotation))
            .offset(x: values.x, y: values.y)
    }

    private var motionValues: (scale: CGFloat, rotation: Double, x: CGFloat, y: CGFloat) {
        let progress = min(max(elapsed / 1.45, 0), 1)
        let envelope = CGFloat(max(0.18, 1 - progress))
        let wave = CGFloat(sin(elapsed * .pi * 5.5))

        switch emotion {
        case .celebrate, .happy, .liked, .saved:
            return (
                scale: 1 + (0.075 * envelope * abs(wave)),
                rotation: Double(5.5 * envelope * wave),
                x: 0,
                y: -7 * envelope * abs(wave)
            )
        case .surprised:
            return (
                scale: 1 + (0.09 * envelope * abs(wave)),
                rotation: Double(-3.5 * envelope * wave),
                x: 0,
                y: -6 * envelope * abs(wave)
            )
        case .thinking, .focused, .curious:
            return (
                scale: 1 + (0.025 * envelope * abs(wave)),
                rotation: Double(4 * envelope * CGFloat(sin(elapsed * .pi * 3))),
                x: 4 * envelope * CGFloat(sin(elapsed * .pi * 2)),
                y: 0
            )
        case .dislike, .warning:
            return (
                scale: 1,
                rotation: Double(-4.5 * envelope * abs(wave)),
                x: 5 * envelope * CGFloat(sin(elapsed * .pi * 7)),
                y: 2.5 * envelope * abs(wave)
            )
        case .neutral, .listening, .calm, .sleep:
            return (
                scale: 1 + (0.04 * envelope * abs(wave)),
                rotation: 0,
                x: 0,
                y: -3 * envelope * abs(wave)
            )
        }
    }
}

private struct MacNowPlayingDock: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @State private var isShowingQueueSwitcher = false
    @State private var isShowingArtworkZoom = false

    let station: Station

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.string("shell.common.playingNow"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Spacer()

                MacPlaybackStatusView()
            }

            VStack(spacing: 12) {
                Text(station.name)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)

                Button {
                    isShowingArtworkZoom = true
                } label: {
                    MacNowPlayingArtwork(
                        station: station,
                        artworkURL: model.currentTrackArtworkURL ?? station.displayArtworkURL,
                        size: 152
                    )
                        .overlay(alignment: .topLeading) {
                            if let feedback = model.currentDiscoveryFeedback {
                                TuneAVFeedbackBadge(feedback: feedback, size: 24, fontSize: 10, borderOpacity: 0.82)
                                    .offset(x: -5, y: -5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(L10n.string("shell.accessibility.zoomArtwork"))
                .accessibilityIdentifier("avi.nowPlaying.artworkZoom")

                VStack(spacing: 5) {
                    Text(model.nowPlayingDisplayLines?.trackSupportingLine ?? L10n.string("player.track.liveNow"))
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(model.currentTrackArtist == nil ? TuneAVTheme.textSecondary : TuneAVTheme.highlight)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.78)

                    Text(model.nowPlayingDisplayLines?.trackTitleLine ?? station.primaryDetailLine)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("player.dock.summary")
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                queueButton

                transportButton(
                    systemImage: "backward.fill",
                    isDisabled: !model.canCyclePlaybackQueue,
                    accessibilityIdentifier: "avi.controls.previous"
                ) {
                    model.playPreviousInQueue()
                }

                Button {
                    model.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.isPlaying ? TuneAVTheme.brandGraphite : TuneAVTheme.highlight)

                        if model.playbackStatus.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 62, height: 62)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("avi.controls.playPause")

                transportButton(
                    systemImage: "forward.fill",
                    isDisabled: !model.canCyclePlaybackQueue,
                    accessibilityIdentifier: "avi.controls.next"
                ) {
                    model.playNextInQueue()
                }

                sleepTimerMenu

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .accessibilityIdentifier("player.dock")
        .sheet(isPresented: $isShowingQueueSwitcher) {
            MacQueueSwitcherSheet(
                currentSource: model.playbackQueueSource,
                options: model.playbackQueueSwitchOptions,
                selectOption: { option in
                    model.selectPlaybackQueue(option)
                    isShowingQueueSwitcher = false
                },
                onDismiss: {
                    isShowingQueueSwitcher = false
                }
            )
        }
        .sheet(isPresented: $isShowingArtworkZoom) {
            MacArtworkZoomSheet(
                station: station,
                artworkURL: model.currentTrackArtworkURL ?? station.displayArtworkURL,
                title: model.nowPlayingDisplayLines?.trackTitleLine ?? station.name,
                subtitle: model.nowPlayingDisplayLines?.trackSupportingLine ?? station.primaryDetailLine,
                onDismiss: {
                    isShowingArtworkZoom = false
                }
            )
            .environmentObject(model)
        }
    }

    private var queueButton: some View {
        Button {
            isShowingQueueSwitcher = true
        } label: {
            transportIconLabel(
                systemImage: "list.bullet",
                isDisabled: model.playbackQueueSwitchOptions.isEmpty
            )
        }
        .buttonStyle(.plain)
        .disabled(model.playbackQueueSwitchOptions.isEmpty)
        .accessibilityLabel(L10n.string("shell.queue.current", model.playbackQueueSourceTitle))
        .accessibilityIdentifier("avi.controls.queue")
    }

    private var sleepTimerMenu: some View {
        Menu {
            ForEach(sleepTimerOptions, id: \.self) { minutes in
                Button {
                    model.setSleepTimer(minutes: minutes)
                } label: {
                    Label(
                        sleepTimerOptionTitle(for: minutes),
                        systemImage: model.activeSleepTimerMinutes == minutes ? "checkmark" : "timer"
                    )
                }
            }
        } label: {
            transportIconLabel(
                systemImage: "timer",
                isDisabled: false,
                text: model.activeSleepTimerRemainingMinutes.map { "\($0)" }
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("profile.preferences.sleepTimer.title"))
        .accessibilityValue(sleepTimerOptionTitle(for: model.activeSleepTimerMinutes))
        .accessibilityIdentifier("avi.controls.sleepTimer")
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

    private func transportButton(
        systemImage: String,
        isDisabled: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            transportIconLabel(systemImage: systemImage, isDisabled: isDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func transportIconLabel(
        systemImage: String,
        isDisabled: Bool,
        text: String? = nil
    ) -> some View {
        ZStack {
            if let text {
                VStack(spacing: 1) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .black))
                    Text(text)
                        .font(.system(size: 9, weight: .black))
                        .monospacedDigit()
                }
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .black))
            }
        }
        .foregroundStyle(TuneAVTheme.textPrimary.opacity(isDisabled ? 0.35 : 0.95))
        .frame(width: 44, height: 44)
        .background(TuneAVTheme.mutedSurface.opacity(isDisabled ? 0.45 : 1), in: Circle())
        .overlay {
            Circle()
                .stroke(TuneAVTheme.borderSubtle.opacity(isDisabled ? 0.25 : 0.72), lineWidth: 1)
        }
    }
}

private struct MacNowPlayingArtwork: View {
    @Environment(\.displayScale) private var displayScale

    let station: Station
    let artworkURL: URL?
    let size: CGFloat

    var body: some View {
        AVFramedArtwork(
            size: size,
            cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size),
            strokeOpacity: 0.55
        ) {
            if let artworkURL {
                TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                    MacStationThumbnailView(station: station, size: size, textMode: .none)
                }
            } else {
                MacStationThumbnailView(station: station, size: size, textMode: .none)
            }
        }
    }
}

private struct MacQueueSwitcherSheet: View {
    let currentSource: TuneAVPlaybackQueueSource
    let options: [MacQueueSwitchOption]
    let selectOption: (MacQueueSwitchOption) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("shell.queue.title"))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("shell.queue.current", currentSource.displayTitle))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(TuneAVTheme.mutedSurface, in: Circle())
                .help(L10n.string("shell.avi.plans.close"))
            }

            if options.isEmpty {
                Label(L10n.string("shell.queue.stationCount.other", 0), systemImage: "list.bullet")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(options) { option in
                        Button {
                            selectOption(option)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.source == currentSource ? "checkmark.circle.fill" : "list.bullet")
                                    .font(.system(size: 16, weight: .black))
                                    .foregroundStyle(option.source == currentSource ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title)
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundStyle(TuneAVTheme.textPrimary)
                                        .lineLimit(1)

                                    Text(L10n.plural(
                                        singular: "shell.queue.stationCount.one",
                                        plural: "shell.queue.stationCount.other",
                                        count: option.stations.count,
                                        option.stations.count
                                    ))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(TuneAVTheme.textSecondary)
                                    .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 58)
                            .background(
                                option.source == currentSource ? TuneAVTheme.highlight.opacity(0.12) : TuneAVTheme.cardSurface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        option.source == currentSource ? TuneAVTheme.highlight.opacity(0.34) : TuneAVTheme.borderSubtle.opacity(0.72),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 430)
        .background(TuneAVTheme.shellBackground)
    }
}

private struct MacArtworkZoomSheet: View {
    let station: Station
    let artworkURL: URL?
    let title: String
    let subtitle: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(TuneAVTheme.mutedSurface, in: Circle())
                .help(L10n.string("shell.avi.plans.close"))
            }

            MacNowPlayingArtwork(station: station, artworkURL: artworkURL, size: 330)
                .shadow(color: TuneAVTheme.glassShadow.opacity(0.22), radius: 24, y: 14)

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.74)

                Text(subtitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(22)
        .frame(width: 430)
        .background(TuneAVTheme.shellBackground)
    }
}

private struct MacEmptyPlayerCard: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("AviV2TuneFocused")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .padding(22)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                .overlay {
                    Circle()
                        .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
                }

            VStack(spacing: 8) {
                Label(L10n.string("player.track.pickStation"), systemImage: "radio")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(L10n.string("shell.home.empty.detail"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct MacPlayerHeroCard: View {
    @EnvironmentObject private var model: TuneAVMacModel

    let station: Station
    let title: String
    let subtitle: String
    let stationLine: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                Image("AviV2TuneFocused")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(22)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
                    }

                Image(systemName: model.isPlaying ? "waveform" : "radio")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.brandGraphite)
                    .frame(width: 34, height: 34)
                    .background(TuneAVTheme.highlight, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(TuneAVTheme.cardSurface, lineWidth: 3)
                    }
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(stationLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(1)
            }

            MacPlaybackStatusView()

            HStack(spacing: 16) {
                Button {
                    model.playPreviousInQueue()
                } label: {
                    Image(systemName: "backward.fill")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canCyclePlaybackQueue)

                Button {
                    model.togglePlayback()
                } label: {
                    if model.playbackStatus.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 64, height: 64)
                    } else {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .frame(width: 64, height: 64)
                    }
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())

                Button {
                    model.playNextInQueue()
                } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canCyclePlaybackQueue)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.10), radius: 16, y: 8)
    }
}

private struct MacPlaybackStatusView: View {
    @EnvironmentObject private var model: TuneAVMacModel

    var body: some View {
        switch model.playbackStatus {
        case .idle:
            EmptyView()
        case .loading:
            Label(L10n.string("audio.status.loading"), systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
        case .playing:
            Label(L10n.string("shell.status.live"), systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.highlight)
        case .paused:
            Label(L10n.string("audio.status.paused"), systemImage: "pause.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
        case let .failed(message):
            HStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .lineLimit(1)

                Button(L10n.string("player.retry")) {
                    model.retryCurrentStation()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
        }
    }
}

private struct MacPlayerActionsCard: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: TuneAVMacModel
    @State private var page = 0

    let close: () -> Void

    var body: some View {
        AVAviActionPanel(
            title: panelTitle,
            pageLabel: L10n.string("shell.avi.actions.page", visiblePage + 1, pageCount),
            canGoPrevious: pageCount > 1 && visiblePage > 0,
            canGoNext: pageCount > 1 && visiblePage < pageCount - 1,
            previousAccessibilityLabel: L10n.string("shell.avi.actions.previousOptions"),
            nextAccessibilityLabel: L10n.string("shell.avi.actions.moreOptions"),
            closeAccessibilityLabel: L10n.string("shell.avi.actions.closeOptions"),
            previousPage: previousPage,
            nextPage: nextPage,
            close: close
        ) {
            if showsSongActions {
                AVAviCommandButton(
                    title: L10n.string("shell.avi.actions.searchLyrics"),
                    systemImage: "text.quote",
                    accessibilityIdentifier: "avi.actions.lyrics"
                ) {
                    openCurrentTrack(destination: .web, suffix: "lyrics")
                    close()
                }

                AVAviCommandButton(
                    title: L10n.string("shell.avi.actions.searchYouTube"),
                    systemImage: "play.rectangle",
                    accessibilityIdentifier: "avi.actions.youtube"
                ) {
                    openCurrentTrack(destination: .youtube)
                    close()
                }

                AVAviCommandButton(
                    title: L10n.string("shell.avi.actions.searchAppleMusic"),
                    systemImage: "music.note",
                    accessibilityIdentifier: "avi.actions.appleMusic"
                ) {
                    openCurrentTrack(destination: .appleMusic)
                    close()
                }

                AVAviCommandButton(
                    title: L10n.string("shell.avi.actions.searchArtist"),
                    systemImage: "person.crop.circle",
                    accessibilityIdentifier: "avi.actions.artist"
                ) {
                    guard let url = model.currentArtistSearchURL() else { return }
                    openURL(url)
                    close()
                }
            } else {
                AVAviCommandButton(
                    title: L10n.string("shell.avi.actions.searchPublicInfo"),
                    systemImage: "info.circle",
                    accessibilityIdentifier: "avi.actions.publicInfo"
                ) {
                    openStationSearch()
                    close()
                }

                AVAviCommandButton(
                    title: L10n.string("shell.avi.recommendation.details"),
                    systemImage: "dot.radiowaves.left.and.right",
                    accessibilityIdentifier: "avi.actions.radioDetails"
                ) {
                    if let station = model.currentStation {
                        model.openStationDetail(station, queue: model.playbackQueue, showsHistory: false)
                    }
                    close()
                }

                AVAviCommandButton(
                    title: L10n.string("shell.avi.actions.history"),
                    systemImage: "clock.arrow.circlepath",
                    accessibilityIdentifier: "avi.actions.history"
                ) {
                    if let station = model.currentStation {
                        model.openStationDetail(station, queue: model.playbackQueue, showsHistory: true)
                    }
                    close()
                }

                AVAviCommandButton(
                    title: L10n.string("shell.avi.actions.openWebsite"),
                    systemImage: "safari",
                    accessibilityIdentifier: "avi.actions.web"
                ) {
                    openStationWebsiteOrSearch()
                    close()
                }

                AVAviCommandButton(
                    title: L10n.string("shell.avi.actions.findRelatedRadios"),
                    systemImage: "sparkles",
                    accessibilityIdentifier: "avi.actions.relatedRadios"
                ) {
                    openStationSearch(suffix: "similar radio stations")
                    close()
                }
            }
        } footer: {
            EmptyView()
        }
    }

    private var pageCount: Int {
        model.hasCurrentDiscovery ? 2 : 1
    }

    private var visiblePage: Int {
        min(max(page, 0), pageCount - 1)
    }

    private var showsSongActions: Bool {
        model.hasCurrentDiscovery && visiblePage == 0
    }

    private var panelTitle: String {
        showsSongActions
            ? L10n.string("shell.avi.actions.aboutSong")
            : L10n.string("shell.common.radio")
    }

    private func previousPage() {
        withAnimation(.snappy(duration: 0.18)) {
            page = max(0, visiblePage - 1)
        }
    }

    private func nextPage() {
        withAnimation(.snappy(duration: 0.18)) {
            page = min(pageCount - 1, visiblePage + 1)
        }
    }

    private func openCurrentTrack(destination: TuneAVExternalSearchURL.Destination, suffix: String? = nil) {
        guard let url = model.currentTrackSearchURL(destination: destination, suffix: suffix) else { return }
        openURL(url)
    }

    private func openStationWebsiteOrSearch() {
        guard let station = model.currentStation else { return }
        if let url = station.resolvedHomepageURL {
            openURL(url)
            return
        }
        openStationSearch()
    }

    private func openStationSearch(suffix: String? = nil) {
        guard let station = model.currentStation else { return }
        let query = TuneAVExternalSearchURL.query(parts: [station.name, station.country], suffix: suffix)
        guard let url = TuneAVExternalSearchURL.url(for: .web, query: query) else { return }
        openURL(url)
    }
}

private struct MacMoreWithAviPopover: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("player.avi.moreWithAvi"))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("shell.avi.can"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(TuneAVTheme.mutedSurface, in: Circle())
                .help(L10n.string("shell.avi.plans.close"))
            }

            MacPlayerActionsCard(close: close)
        }
        .padding(20)
        .frame(width: 380)
        .background(TuneAVTheme.shellBackground)
    }
}

private struct MacCurrentDiscoveryDecisionCard: View {
    @EnvironmentObject private var model: TuneAVMacModel

    let station: Station

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(L10n.string("player.discovery.stateNew"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                if model.currentDiscoveryIsSaved {
                    Label(L10n.string("player.discovery.savedShort"), systemImage: "bookmark.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                }
            }

            HStack(spacing: 8) {
                MacDiscoveryDecisionButton(
                    title: model.currentDiscoveryIsSaved ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                    systemImage: model.currentDiscoveryIsSaved ? "bookmark.slash" : "bookmark",
                    isSelected: model.currentDiscoveryIsSaved,
                    isEnabled: model.hasCurrentDiscovery
                ) {
                    _ = model.toggleCurrentDiscoverySaved()
                }

                MacDiscoveryDecisionButton(
                    title: L10n.string("player.discovery.noSave"),
                    systemImage: "xmark",
                    isSelected: model.currentDiscoveryFeedback == .notForMe,
                    isEnabled: model.hasCurrentDiscovery
                ) {
                    model.setCurrentDiscoveryFeedback(.notForMe)
                }
            }

            MacFeedbackInfoRow(
                title: feedbackTitle,
                subtitle: feedbackSubtitle,
                systemImage: feedbackIcon
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
    }

    private var feedbackTitle: String {
        if model.currentDiscoveryIsSaved {
            return L10n.string("player.discovery.savedShort")
        }
        if model.currentDiscoveryFeedback == .notForMe {
            return L10n.string("player.discovery.noSave")
        }
        return L10n.string("player.avi.feedback.choose")
    }

    private var feedbackSubtitle: String {
        if model.currentDiscoveryIsSaved {
            return L10n.string("player.discovery.savedHintShort")
        }
        if model.currentDiscoveryFeedback == .notForMe {
            return L10n.string("player.discovery.noSaveHint")
        }
        return L10n.string("player.avi.feedback.chooseHint")
    }

    private var feedbackIcon: String {
        if model.currentDiscoveryIsSaved {
            return "bookmark.fill"
        }
        if model.currentDiscoveryFeedback == .notForMe {
            return "xmark"
        }
        return "slider.horizontal.3"
    }
}

private struct MacDiscoveryDecisionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .black))

                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary.opacity(isEnabled ? 0.96 : 0.35))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                isSelected ? TuneAVTheme.highlight : TuneAVTheme.cardSurface.opacity(isEnabled ? 1 : 0.5),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.44) : TuneAVTheme.borderSubtle.opacity(isEnabled ? 1 : 0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(title)
    }
}

private struct MacFeedbackInfoRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 30, height: 30)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacAviActionChip: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .black))

                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(TuneAVTheme.textPrimary.opacity(isEnabled ? 0.96 : 0.35))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 36)
            .background(TuneAVTheme.mutedSurface.opacity(isEnabled ? 1 : 0.45), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(TuneAVTheme.borderSubtle.opacity(isEnabled ? 0.72 : 0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(title)
    }
}

private struct MacStationFeedbackCard: View {
    @EnvironmentObject private var model: TuneAVMacModel

    let station: Station
    @Binding var isMoreWithAviPresented: Bool
    let showReaction: (TuneAVAviEmotion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.hasCurrentDiscovery {
                songFeedbackContent
            } else {
                radioFeedbackContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [TuneAVTheme.glassStroke.opacity(0.95), TuneAVTheme.highlight.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.18), radius: 10, y: 5)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(model.hasCurrentDiscovery ? L10n.string("shell.avi.actions.songFeedback") : L10n.string("shell.avi.actions.radioFeedback"))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight)
                .textCase(.uppercase)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                isMoreWithAviPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .black))
                    Text(L10n.string("player.avi.moreWithAvi"))
                        .font(.system(size: 12, weight: .black))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .black))
                }
                .foregroundStyle(TuneAVTheme.brandBlack)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(TuneAVTheme.highlight, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(TuneAVTheme.brandBlack.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isMoreWithAviPresented, arrowEdge: .trailing) {
                MacMoreWithAviPopover {
                    isMoreWithAviPresented = false
                }
                .environmentObject(model)
            }
            .accessibilityIdentifier("avi.actions.toggle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var radioFeedbackContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            feedbackQuestion(
                title: L10n.string("player.avi.feedback.radioQuestion"),
                selectedFeedback: model.stationFeedback[station.id],
                selectFeedback: { feedback in
                    let nextFeedback = model.stationFeedback[station.id] == feedback ? nil : feedback
                    model.setFeedback(nextFeedback, for: station)
                    if let nextFeedback {
                        showReaction(TuneAVAviEmotionResolver.emotion(for: nextFeedback))
                    }
                },
                clearFeedback: {
                    model.setFeedback(nil, for: station)
                }
            )

            MacDiscoveryDecisionButton(
                title: model.isFavorite(station) ? L10n.string("player.station.unsave") : L10n.string("player.station.save"),
                systemImage: model.isFavorite(station) ? "bookmark.slash" : "bookmark",
                isSelected: model.isFavorite(station),
                isEnabled: true
            ) {
                model.toggleFavorite(station)
                showReaction(model.isFavorite(station) ? .liked : .curious)
            }

            MacFeedbackInfoRow(
                title: model.stationFeedback[station.id] == nil ? L10n.string("player.avi.feedback.choose") : L10n.string("player.avi.feedback.tuned"),
                subtitle: model.stationFeedback[station.id] == nil ? L10n.string("player.avi.feedback.chooseHint") : L10n.string("player.avi.feedback.tunedHint"),
                systemImage: model.stationFeedback[station.id] == nil ? "slider.horizontal.3" : "sparkles"
            )
        }
    }

    private func feedbackQuestion(
        title: String,
        selectedFeedback: TuneAVStationFeedback?,
        selectFeedback: @escaping (TuneAVStationFeedback) -> Void,
        clearFeedback: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let selectedFeedback {
                HStack(spacing: 8) {
                    MacSelectedFeedbackStatus(feedback: selectedFeedback)

                    Button(action: clearFeedback) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(TuneAVTheme.mutedSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.string("shell.stationFeedback.clear"))
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(TuneAVStationFeedback.displayOrder, id: \.self) { feedback in
                        Button {
                            selectFeedback(feedback)
                        } label: {
                            Label(feedback.localizedState, systemImage: feedback.systemImage)
                                .labelStyle(.iconOnly)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                                .frame(width: 44, height: 36)
                                .background(TuneAVTheme.mutedSurface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(feedback.localizedState)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var songFeedbackContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            feedbackQuestion(
                title: L10n.string("player.avi.feedback.songQuestion"),
                selectedFeedback: model.currentDiscoveryFeedback,
                selectFeedback: { feedback in
                    let nextFeedback = model.currentDiscoveryFeedback == feedback ? nil : feedback
                    model.setCurrentDiscoveryFeedback(nextFeedback)
                    if let nextFeedback {
                        showReaction(TuneAVAviEmotionResolver.emotion(for: nextFeedback))
                    }
                },
                clearFeedback: {
                    model.setCurrentDiscoveryFeedback(nil)
                }
            )

            HStack(spacing: 8) {
                MacDiscoveryDecisionButton(
                    title: model.currentDiscoveryIsSaved ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                    systemImage: model.currentDiscoveryIsSaved ? "bookmark.slash" : "bookmark",
                    isSelected: model.currentDiscoveryIsSaved,
                    isEnabled: model.hasCurrentDiscovery
                ) {
                    _ = model.toggleCurrentDiscoverySaved()
                    showReaction(model.currentDiscoveryIsSaved ? .saved : .curious)
                }

                MacDiscoveryDecisionButton(
                    title: L10n.string("player.discovery.noSave"),
                    systemImage: "xmark",
                    isSelected: model.currentDiscoveryFeedback == .notForMe,
                    isEnabled: model.hasCurrentDiscovery
                ) {
                    model.setCurrentDiscoveryFeedback(.notForMe)
                    showReaction(.dislike)
                }
            }

            MacFeedbackInfoRow(
                title: songFeedbackTitle,
                subtitle: songFeedbackSubtitle,
                systemImage: songFeedbackIcon
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var songFeedbackTitle: String {
        if model.currentDiscoveryIsSaved {
            return L10n.string("player.discovery.savedShort")
        }
        if model.currentDiscoveryFeedback == .notForMe {
            return L10n.string("player.discovery.noSave")
        }
        return L10n.string("player.avi.feedback.choose")
    }

    private var songFeedbackSubtitle: String {
        if model.currentDiscoveryIsSaved {
            return L10n.string("player.discovery.savedHintShort")
        }
        if model.currentDiscoveryFeedback == .notForMe {
            return L10n.string("player.discovery.noSaveHint")
        }
        return L10n.string("player.avi.feedback.chooseHint")
    }

    private var songFeedbackIcon: String {
        if model.currentDiscoveryIsSaved {
            return "bookmark.fill"
        }
        if model.currentDiscoveryFeedback == .notForMe {
            return "xmark"
        }
        return "slider.horizontal.3"
    }
}

private struct MacSelectedFeedbackStatus: View {
    let feedback: TuneAVStationFeedback

    var body: some View {
        Label(feedback.localizedState, systemImage: feedback.systemImage)
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(TuneAVTheme.brandBlack)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(TuneAVTheme.highlight, in: Capsule(style: .continuous))
    }
}

private struct MacCurrentTrackActions: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: TuneAVMacModel

    var body: some View {
        HStack(spacing: 10) {
            actionButton(
                title: model.currentDiscoveryIsSaved ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort"),
                systemImage: model.currentDiscoveryIsSaved ? "bookmark.slash" : "bookmark",
                isEnabled: model.hasCurrentDiscovery
            ) {
                _ = model.toggleCurrentDiscoverySaved()
            }

            actionButton(
                title: L10n.string("shell.avi.actions.searchLyrics"),
                systemImage: "text.quote",
                isEnabled: model.hasCurrentDiscovery
            ) {
                openCurrentTrack(destination: .web, suffix: "lyrics")
            }

            actionButton(
                title: L10n.string("shell.avi.actions.searchYouTube"),
                systemImage: "play.rectangle",
                isEnabled: model.hasCurrentDiscovery
            ) {
                openCurrentTrack(destination: .youtube)
            }

            actionButton(
                title: L10n.string("shell.avi.actions.searchAppleMusic"),
                systemImage: "music.note",
                isEnabled: model.hasCurrentDiscovery
            ) {
                openCurrentTrack(destination: .appleMusic)
            }

            actionButton(
                title: L10n.string("player.discovery.spotify"),
                systemImage: "music.quarternote.3",
                isEnabled: model.hasCurrentDiscovery
            ) {
                openCurrentTrack(destination: .spotify)
            }

            actionButton(
                title: L10n.string("common.share"),
                systemImage: "square.and.arrow.up",
                isEnabled: model.currentDiscoveryShareText() != nil
            ) {
                copyCurrentDiscovery()
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary.opacity(isEnabled ? 0.95 : 0.35))
                .frame(width: 42, height: 38)
                .background(TuneAVTheme.mutedSurface.opacity(isEnabled ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle.opacity(isEnabled ? 0.72 : 0.25), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(title)
    }

    private func openCurrentTrack(destination: TuneAVExternalSearchURL.Destination, suffix: String? = nil) {
        guard let url = model.currentTrackSearchURL(destination: destination, suffix: suffix) else { return }
        openURL(url)
    }

    private func copyCurrentDiscovery() {
        guard let text = model.currentDiscoveryShareText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct MacQueueCard: View {
    @EnvironmentObject private var model: TuneAVMacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("shell.queue.title"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Spacer()

                Text("\(model.playbackQueue.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.playbackQueue) { station in
                        Button {
                            model.play(station, queue: model.playbackQueue)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: model.currentStation?.id == station.id ? "waveform" : "radio")
                                    .foregroundStyle(model.currentStation?.id == station.id ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(TuneAVTheme.textPrimary)
                                        .lineLimit(1)

                                    Text(station.country)
                                        .font(.caption)
                                        .foregroundStyle(TuneAVTheme.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 46)
                            .background(model.currentStation?.id == station.id ? TuneAVTheme.highlight.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 190)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct MacStationPlaybackQueueKey: EnvironmentKey {
    static let defaultValue: [Station] = []
}

extension EnvironmentValues {
    var macStationPlaybackQueue: [Station] {
        get { self[MacStationPlaybackQueueKey.self] }
        set { self[MacStationPlaybackQueueKey.self] = newValue }
    }
}
