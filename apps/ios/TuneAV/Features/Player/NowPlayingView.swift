import SwiftUI
import UIKit

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryStore: LibraryStore

    let startSignInFlow: (Bool) -> Void
    let stationHistoryAction: (Station) -> Void

    @State private var horizontalDragOffset: CGFloat = 0
    @State private var verticalDragOffset: CGFloat = 0
    @State private var browserDestination: BrowserDestination?
    @State private var aviReaction: PlayerAviReaction?

    private let swipeThreshold: CGFloat = 72
    private let dismissSwipeThreshold: CGFloat = 88
    private let playerHorizontalPadding: CGFloat = 16
    private let playerLandscapeHorizontalPadding: CGFloat = 12
    private let playerMaxContentWidth: CGFloat = 360
    private let playerMaxLandscapeContentWidth: CGFloat = 860
    private let playerControlsBottomLift: CGFloat = 28

    init(
        startSignInFlow: @escaping (Bool) -> Void = { _ in },
        stationHistoryAction: @escaping (Station) -> Void = { _ in }
    ) {
        self.startSignInFlow = startSignInFlow
        self.stationHistoryAction = stationHistoryAction
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = usesLandscapeLayout(in: proxy)
            let horizontalInsets = playerHorizontalInsets(in: proxy, isLandscape: isLandscape)
            let contentWidth = playerContentWidth(in: proxy, isLandscape: isLandscape, horizontalInsets: horizontalInsets)
            let topInset = playerTopInset(in: proxy, isLandscape: isLandscape)
            let bottomInset = playerBottomInset(
                in: proxy,
                isLandscape: isLandscape,
                horizontalInsets: horizontalInsets,
                contentWidth: contentWidth
            )
            let contentHeight = playerContentHeight(
                in: proxy,
                isLandscape: isLandscape,
                topInset: topInset,
                bottomInset: bottomInset
            )

            ZStack(alignment: .top) {
                playerBackdrop

                VStack(spacing: 0) {
                    dismissBar()

                    playerContent(
                        in: proxy,
                        isLandscape: isLandscape,
                        contentWidth: contentWidth,
                        contentHeight: contentHeight
                    )
                }
                .frame(width: contentWidth, alignment: .top)
                .padding(.leading, horizontalInsets.leading)
                .padding(.trailing, horizontalInsets.trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .offset(y: max(verticalDragOffset, 0))
            }
        }
        .simultaneousGesture(dismissSwipeGesture)
        .presentationBackground(.clear)
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .overlay {
            if let prompt = accessController.upgradePrompt {
                UpgradeRecommendationSheet(
                    prompt: prompt,
                    isGuest: accessController.accessMode == .guest,
                    accountIsAvailable: accessController.accountIsAvailable,
                    onPrimaryAction: {
                        accessController.upgradePrompt = nil
                        if accessController.accessMode == .guest {
                            dismiss()
                            startSignInFlow(true)
                        }
                    },
                    onDismiss: {
                        accessController.upgradePrompt = nil
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var playerBackdrop: some View {
        ZStack {
            TuneAVTheme.onboardingBackground.ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [TuneAVTheme.highlight.opacity(0.20), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 18)
                .offset(x: 118, y: -240)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [TuneAVTheme.highlight.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 24)
                .offset(x: -150, y: 250)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .blur(radius: 14)
                .offset(x: 54, y: 96)
        }
    }

    private func dismissBar() -> some View {
        ZStack {
            Text(headerTitle)
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("player.headerTitle")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
    }

    private func contextDeck(for station: Station, compact: Bool) -> some View {
        PlayerSignalDeck(
            station: station,
            trackTitle: audioPlayer.currentTrackTitle,
            trackArtist: audioPlayer.currentTrackArtist,
            trackAlbumTitle: audioPlayer.currentTrackAlbumTitle,
            trackArtworkURL: audioPlayer.currentTrackArtworkURL,
            trackArtistURL: audioPlayer.currentTrackArtistURL,
            isDiscoverableTrack: hasDiscoverableTrack,
            isCurrentTrackDiscovered: isCurrentTrackSaved,
            stationFeedback: libraryStore.feedback(for: station),
            isPlaying: audioPlayer.isPlaying,
            isLoading: audioPlayer.isLoading,
            isFavorite: libraryStore.isFavorite(station),
            homepageURL: homepageURL,
            onSetStationFeedback: { feedback in setFeedback(feedback, for: station) },
            onSaveDiscovery: { saveCurrentDiscovery(for: station) },
            onOpenAppleMusic: { openExternalSearch(.appleMusicSearch, destination: .appleMusic) },
            onOpenYouTube: { openExternalSearch(.youtubeSearch, destination: .youtube) },
            onOpenLyrics: { openExternalSearch(.lyricsSearch, destination: .web, suffix: "lyrics") },
            onOpenArtist: { openArtistSearch(destination: .web, feature: .webSearch) },
            onOpenStationSearch: { openStationSearch(for: station) },
            onTogglePlayback: audioPlayer.togglePlayback,
            onToggleFavorite: { toggleFavorite(station) },
            onOpenWebsite: { url in browserDestination = BrowserDestination(url: url) }
        )
        .id(station.id)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func playerContent(
        in proxy: GeometryProxy,
        isLandscape: Bool,
        contentWidth: CGFloat,
        contentHeight: CGFloat
    ) -> some View {
        if let station = audioPlayer.currentStation {
            let compact = isCompactPlayer(in: proxy, isLandscape: isLandscape)

            if isLandscape {
                landscapePlayerContent(
                    for: station,
                    in: proxy,
                    contentWidth: contentWidth,
                    contentHeight: contentHeight,
                    compact: compact
                )
            } else {
                portraitPlayerContent(
                    for: station,
                    in: proxy,
                    contentWidth: contentWidth,
                    contentHeight: contentHeight,
                    compact: compact
                )
            }
        } else {
            emptyState
                .frame(maxHeight: .infinity)
        }
    }

    private func portraitPlayerContent(
        for station: Station,
        in proxy: GeometryProxy,
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        compact: Bool
    ) -> some View {
        let verticalSpacing: CGFloat = compact ? 10 : 14
        let aviHeight = playerAviHeight(in: contentHeight, compact: compact)

        return VStack(spacing: verticalSpacing) {
            contextDeck(for: station, compact: compact)
                .offset(x: horizontalDragOffset)
                .gesture(stationSwipeGesture)

            aviPlayerStage(
                for: station,
                width: contentWidth,
                aviHeight: aviHeight,
                compact: compact
            )
                .offset(x: horizontalDragOffset)
                .gesture(stationSwipeGesture)

            Spacer(minLength: 0)

            playerControls(contentWidth: contentWidth, compact: compact)
                .padding(.bottom, playerControlsBottomLift)
        }
        .frame(height: contentHeight, alignment: .top)
    }

    private func landscapePlayerContent(
        for station: Station,
        in proxy: GeometryProxy,
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        compact: Bool
    ) -> some View {
        let columnSpacing: CGFloat = compact ? 14 : 18
        let columnWidth = max((contentWidth - (columnSpacing * 2)) / 3, 220)

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: columnSpacing) {
                contextDeck(for: station, compact: true)
                    .frame(width: columnWidth)
                    .offset(x: horizontalDragOffset)
                    .gesture(stationSwipeGesture)

                aviPlayerStage(
                    for: station,
                    width: columnWidth,
                    aviHeight: compact ? 126 : 136,
                    compact: true
                )
                    .frame(width: columnWidth)
                    .offset(x: horizontalDragOffset)
                    .gesture(stationSwipeGesture)

                playerControls(contentWidth: columnWidth, compact: true)
            }
            .frame(width: contentWidth)
            .padding(.top, compact ? 8 : 12)

            Spacer(minLength: 0)
        }
        .frame(height: contentHeight, alignment: .top)
    }

    private func aviPlayerStage(
        for station: Station,
        width: CGFloat,
        aviHeight: CGFloat,
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .center, spacing: compact ? 10 : 12) {
                aviSignalConsole(for: station, compact: compact)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PlayerAviBody(
                    assetName: playerAviAssetName,
                    size: min(aviHeight, compact ? 118 : 132),
                    offset: playerAviBodyOffset
                )
                .frame(width: compact ? 118 : 132, alignment: .trailing)
                .offset(x: compact ? 10 : 14)
                .accessibilityLabel(L10n.string("shell.avi.title"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playerAviStateTitle)
                    .font(.system(size: compact ? 14 : 16, weight: .black))
                    .foregroundStyle(TuneAVTheme.textInverse)
                    .lineLimit(1)

                Text(playerAviDetail(for: station))
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textInverse.opacity(0.68))
                    .multilineTextAlignment(.leading)
                    .lineLimit(compact ? 2 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 12 : 18)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: compact ? 26 : 30, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 26 : 30, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.avi.stage")
        .onChange(of: currentTrackIdentity) { _, _ in
            aviReaction = nil
        }
    }

    private func aviSignalConsole(for station: Station, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text(aviActionEyebrow)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(TuneAVTheme.highlight.opacity(0.94))
                .textCase(.uppercase)
                .lineLimit(1)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(TuneAVStationFeedback.allCases, id: \.self) { feedback in
                    let feedbackIdentifier = "player.avi.feedback." + feedback.rawValue
                    aviSignalButton(
                        systemImage: feedback.systemImage,
                        isSelected: aviSelectedFeedback(for: station) == feedback,
                        accessibilityLabel: feedback.localizedState,
                        accessibilityIdentifier: feedbackIdentifier
                    ) {
                        setAviFeedback(feedback, for: station)
                        showAviReaction(for: feedback)
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(playerAviContextPrompts(for: station).prefix(2), id: \.self) { prompt in
                    PlayerAviContextPill(title: prompt)
                }
            }
            .frame(height: 25, alignment: .leading)
            .accessibilityIdentifier("player.avi.context")
        }
    }

    private func aviSignalButton(
        systemImage: String,
        isSelected: Bool,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse.opacity(0.84))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            .background(isSelected ? TuneAVTheme.highlight : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var aviActionEyebrow: String {
        switch aviActionTarget {
        case .song:
            return L10n.string("player.avi.signal.song")
        case .radio:
            return L10n.string("player.avi.signal.radio")
        }
    }

    private func aviActionTitle(for station: Station) -> String {
        switch aviActionTarget {
        case .song:
            return TuneAVText.normalizedValue(audioPlayer.currentTrackTitle) ?? L10n.string("player.track.liveNow")
        case .radio:
            return station.name
        }
    }

    private var aviActionTarget: PlayerRatingTarget {
        currentTrackHasSongContext && audioPlayer.isPlaying ? .song : .radio
    }

    private func aviSelectedFeedback(for station: Station) -> TuneAVStationFeedback? {
        switch aviActionTarget {
        case .song:
            return libraryStore.feedbackForDiscoveredTrack(
                title: audioPlayer.currentTrackTitle,
                artist: audioPlayer.currentTrackArtist
            )
        case .radio:
            return libraryStore.feedback(for: station)
        }
    }

    private func setAviFeedback(_ feedback: TuneAVStationFeedback, for station: Station) {
        switch aviActionTarget {
        case .song:
            let currentFeedback = libraryStore.feedbackForDiscoveredTrack(
                title: audioPlayer.currentTrackTitle,
                artist: audioPlayer.currentTrackArtist
            )
            let nextFeedback = currentFeedback == feedback ? nil : feedback
            libraryStore.setFeedbackForDiscoveredTrack(
                nextFeedback,
                title: audioPlayer.currentTrackTitle,
                artist: audioPlayer.currentTrackArtist
            )
        case .radio:
            let nextFeedback = libraryStore.feedback(for: station) == feedback ? nil : feedback
            setFeedback(nextFeedback, for: station)
        }
    }

    private func showAviReaction(_ reaction: PlayerAviReaction) {
        aviReaction = reaction
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard aviReaction == reaction else { return }
            aviReaction = nil
        }
    }

    private func showAviReaction(for feedback: TuneAVStationFeedback) {
        switch feedback {
        case .liked:
            showAviReaction(.happy)
        case .disliked:
            showAviReaction(.thinking)
        case .notForMe:
            showAviReaction(.curious)
        }
    }

    private func trackSummary(
        for station: Station,
        contentWidth: CGFloat,
        minHeight: CGFloat = 126,
        compact: Bool = false
    ) -> some View {
        VStack(spacing: compact ? 6 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(stationMetaLine(for: station))
                    .font(.system(size: compact ? 15 : 17, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                favoriteButton(for: station)
                optionsMenu(for: station)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(trackTitleLine(for: station))
                .font(.system(size: compact ? 21 : 25, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textInverse)
                .multilineTextAlignment(.leading)
                .lineLimit(compact ? 2 : 3)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(trackSupportingLine(for: station))
                .font(compact ? .subheadline : .body)
                .foregroundStyle(TuneAVTheme.textInverse.opacity(0.68))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .padding(.top, compact ? 0 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            playerFeedbackRow(for: station, compact: compact)
                .padding(.top, compact ? 2 : 4)
        }
        .frame(width: contentWidth, alignment: .leading)
        .frame(minHeight: minHeight, alignment: .topLeading)
    }

    private func playerFeedbackRow(for station: Station, compact: Bool) -> some View {
        let activeFeedback = libraryStore.feedback(for: station)

        return HStack(spacing: 8) {
            ForEach(TuneAVStationFeedback.allCases, id: \.self) { feedback in
                Button {
                    let nextFeedback = activeFeedback == feedback ? nil : feedback
                    libraryStore.setFeedback(nextFeedback, for: station)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: feedback.systemImage)
                        .font(.system(size: compact ? 11 : 12, weight: .black))
                        .foregroundStyle(activeFeedback == feedback ? TuneAVTheme.brandBlack : TuneAVTheme.textInverse.opacity(0.76))
                        .frame(width: compact ? 32 : 36, height: compact ? 28 : 32)
                        .background(
                            activeFeedback == feedback ? TuneAVTheme.highlight : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(activeFeedback == feedback ? TuneAVTheme.highlight.opacity(0.44) : Color.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feedback.localizedState)
                .accessibilityValue(activeFeedback == feedback ? L10n.string("common.selected") : "")
                .accessibilityIdentifier("player.station.feedback.\(feedback.rawValue)")
            }

            if activeFeedback != nil {
                Button {
                    libraryStore.setFeedback(nil, for: station)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: compact ? 10 : 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textInverse.opacity(0.82))
                        .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("shell.stationFeedback.clear"))
                .accessibilityIdentifier("player.station.feedback.clear")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("player.station.feedback")
    }

    private func setFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        libraryStore.setFeedback(feedback, for: station)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func playerControls(contentWidth: CGFloat, compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            transportSection(contentWidth: contentWidth, compact: compact)

            if shouldShowStatusRow {
                statusRow(contentWidth: contentWidth)
            }

            retrySection
        }
    }

    private func transportSection(contentWidth: CGFloat, compact: Bool) -> some View {
        let sideButtonSize: CGFloat = compact ? 52 : 60
        let primaryButtonSize: CGFloat = compact ? 84 : 96

        return HStack(spacing: compact ? 14 : 18) {
            compactTransportButton(systemImage: "backward.fill", size: sideButtonSize, compact: compact, action: playPreviousStation)
                .disabled(!canCycleStations)

            Button {
                audioPlayer.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(TuneAVTheme.signalGradient)
                        .shadow(color: TuneAVTheme.highlight.opacity(0.25), radius: 18, y: 10)

                    if audioPlayer.isLoading {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.large)
                    } else {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: compact ? 28 : 32, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: primaryButtonSize, height: primaryButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audioPlayer.isLoading ? L10n.string("audio.status.loading") : (audioPlayer.isPlaying ? L10n.string("player.control.pause") : L10n.string("player.control.play")))
            .accessibilityIdentifier("player.transport.playPause")

            compactTransportButton(systemImage: "forward.fill", size: sideButtonSize, compact: compact, action: playNextStation)
                .disabled(!canCycleStations)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        }
        .frame(width: contentWidth)
        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
    }

    private func statusRow(contentWidth: CGFloat) -> some View {
        HStack {
            if audioPlayer.isLoading {
                loadingStatusPill
            }

            if let sleepTimerDescription = audioPlayer.sleepTimerDescription {
                statusPill(text: sleepTimerDescription)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private var loadingStatusPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(TuneAVTheme.textInverse.opacity(0.86))
                .controlSize(.small)

            Text(L10n.string("audio.status.loading"))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(TuneAVTheme.textInverse.opacity(0.86))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(TuneAVTheme.highlight.opacity(0.24), in: Capsule())
        .overlay {
            Capsule()
                .stroke(TuneAVTheme.highlight.opacity(0.28), lineWidth: 1)
        }
        .accessibilityIdentifier("player.status.loading")
    }

    private func statusPill(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    private var retrySection: some View {
        Button(L10n.string("player.retry"), action: audioPlayer.retry)
            .buttonStyle(.borderedProminent)
            .tint(TuneAVTheme.highlight)
            .opacity(audioPlayer.hasFailure ? 1 : 0)
            .disabled(!audioPlayer.hasFailure)
            .accessibilityHidden(!audioPlayer.hasFailure)
    }

    private func optionsMenu(for station: Station) -> some View {
        Menu {
            Button(L10n.string("player.menu.copyStreamURL")) {
                UIPasteboard.general.string = station.streamURL
            }

            ShareLink(item: station.shareText) {
                Text(L10n.string("player.menu.shareStation"))
            }

            Button(L10n.string("player.menu.stationHistory")) {
                stationHistoryAction(station)
                dismiss()
            }

            Button(L10n.string("player.menu.searchStation")) {
                openStationSearch(for: station)
            }

            if let homepageURL {
                Button(L10n.string("player.menu.openWebsite")) {
                    browserDestination = BrowserDestination(url: homepageURL)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TuneAVTheme.textInverse.opacity(0.78))
                .rotationEffect(.degrees(90))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func favoriteButton(for station: Station) -> some View {
        Button {
            toggleFavorite(station)
        } label: {
            TuneAVSavedStationIcon(
                isSaved: libraryStore.isFavorite(station),
                size: 18,
                inactiveColor: TuneAVTheme.textInverse,
                activeColor: TuneAVTheme.highlight
            )
                .frame(width: 36, height: 36)
                .background(libraryStore.isFavorite(station) ? TuneAVTheme.highlight.opacity(0.18) : Color.white.opacity(0.08), in: Circle())
                .overlay {
                    Circle()
                        .stroke(libraryStore.isFavorite(station) ? TuneAVTheme.highlight.opacity(0.36) : Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libraryStore.isFavorite(station) ? L10n.string("player.menu.removeFavorite") : L10n.string("player.menu.addFavorite"))
        .accessibilityIdentifier("player.station.favorite")
    }

    private func compactTransportButton(systemImage: String, size: CGFloat, compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 20 : 22, weight: .bold))
                .foregroundStyle(canCycleStations ? TuneAVTheme.textInverse : TuneAVTheme.textInverse.opacity(0.36))
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(systemImage.contains("backward") ? "player.transport.previous" : "player.transport.next")
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: size, height: size)
        }
    }

    private func playerContentWidth(in proxy: GeometryProxy, isLandscape: Bool, horizontalInsets: EdgeInsets) -> CGFloat {
        let availableWidth = proxy.size.width - horizontalInsets.leading - horizontalInsets.trailing
        let maxWidth = isLandscape ? playerMaxLandscapeContentWidth : playerMaxContentWidth
        return min(availableWidth, maxWidth)
    }

    private func playerHorizontalInsets(in proxy: GeometryProxy, isLandscape: Bool) -> EdgeInsets {
        let horizontalPadding = isLandscape ? playerLandscapeHorizontalPadding : playerHorizontalPadding

        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }

    private func playerTopInset(in proxy: GeometryProxy, isLandscape: Bool) -> CGFloat {
        if isLandscape {
            return 6
        }

        return 10
    }

    private func playerBottomInset(
        in proxy: GeometryProxy,
        isLandscape: Bool,
        horizontalInsets: EdgeInsets,
        contentWidth: CGFloat
    ) -> CGFloat {
        if isLandscape {
            return 28
        }

        return 0
    }

    private func playerContentHeight(
        in proxy: GeometryProxy,
        isLandscape: Bool,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        let headerAllowance: CGFloat = isLandscape ? 34 : 26
        return max(proxy.size.height - topInset - bottomInset - headerAllowance, 240)
    }

    private func usesLandscapeLayout(in proxy: GeometryProxy) -> Bool {
        if let verticalSizeClass {
            return verticalSizeClass == .compact
        }

        return proxy.size.width > proxy.size.height
    }

    private func isCompactPlayer(in proxy: GeometryProxy, isLandscape: Bool) -> Bool {
        isLandscape || proxy.size.height < 840
    }

    private func playerAviHeight(in contentHeight: CGFloat, compact: Bool) -> CGFloat {
        let preferredHeight: CGFloat = compact ? 122 : 152
        let availableHeight = max(contentHeight - 360, 104)
        return min(preferredHeight, availableHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Text(L10n.string("player.empty"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textInverse.opacity(0.84))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var stationSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard canCycleStations, abs(value.translation.width) > abs(value.translation.height) else { return }
                horizontalDragOffset = value.translation.width * 0.24
            }
            .onEnded { value in
                guard canCycleStations else {
                    resetHorizontalDrag()
                    return
                }

                let isHorizontalSwipe = abs(value.translation.width) > abs(value.translation.height)
                let shouldAdvance = isHorizontalSwipe && value.translation.width <= -swipeThreshold
                let shouldReverse = isHorizontalSwipe && value.translation.width >= swipeThreshold

                if shouldAdvance {
                    playNextStation()
                } else if shouldReverse {
                    playPreviousStation()
                }

                resetHorizontalDrag()
            }
    }

    private var dismissSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard isVerticalDismissSwipe(value) else { return }
                verticalDragOffset = value.translation.height * 0.38
            }
            .onEnded { value in
                guard isVerticalDismissSwipe(value) else {
                    resetVerticalDrag()
                    return
                }

                if value.translation.height >= dismissSwipeThreshold {
                    dismiss()
                } else {
                    resetVerticalDrag()
                }
            }
    }

    private var headerTitle: String {
        audioPlayer.currentStation?.name ?? L10n.string("player.header.nowPlaying")
    }

    private func stationMetaLine(for station: Station) -> String {
        nowPlayingDisplayLines(for: station).stationMetaLine
    }

    private func trackTitleLine(for station: Station) -> String {
        nowPlayingDisplayLines(for: station).trackTitleLine
    }

    private func trackSupportingLine(for station: Station) -> String {
        nowPlayingDisplayLines(for: station).trackSupportingLine
    }

    private var hasDiscoverableTrack: Bool {
        guard let station = audioPlayer.currentStation else { return false }
        return nowPlayingDisplayLines(for: station).hasDiscoverableTrack
    }

    private var currentTrackHasSongContext: Bool {
        hasDiscoverableTrack ||
            audioPlayer.currentTrackArtworkURL != nil ||
            TuneAVText.normalizedValue(audioPlayer.currentTrackTitle) != nil
    }

    private var currentTrackIdentity: String {
        [
            TuneAVText.normalizedValue(audioPlayer.currentTrackTitle),
            TuneAVText.normalizedValue(audioPlayer.currentTrackArtist),
            audioPlayer.currentTrackArtworkURL?.absoluteString
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    private var hasPlausibleCurrentTrack: Bool {
        guard let station = audioPlayer.currentStation else { return false }
        return hasPlausibleTrackTitle(for: station)
    }

    private func hasPlausibleTrackTitle(for station: Station) -> Bool {
        TuneAVDisplayMetadata.plausibleTitle(audioPlayer.currentTrackTitle, stationName: station.name) != nil
    }

    private var hasPlausibleCurrentArtist: Bool {
        guard let station = audioPlayer.currentStation else { return false }
        return hasPlausibleTrackArtist(for: station)
    }

    private func hasPlausibleTrackArtist(for station: Station) -> Bool {
        TuneAVDisplayMetadata.plausibleArtist(audioPlayer.currentTrackArtist, stationName: station.name) != nil
    }

    private func nowPlayingDisplayLines(for station: Station) -> TuneAVNowPlayingDisplayLines {
        TuneAVNowPlayingDisplayLines.resolve(
            station: station,
            currentTitle: audioPlayer.currentTrackTitle,
            currentArtist: audioPlayer.currentTrackArtist,
            currentAlbumTitle: audioPlayer.currentTrackAlbumTitle,
            liveNowFallback: L10n.string("player.track.liveNow"),
            liveStreamFallback: L10n.string("player.track.liveStreamActive")
        )
    }

    private var isCurrentTrackSaved: Bool {
        libraryStore.isSavedDiscoveredTrack(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: audioPlayer.currentStation
        )
    }

    private func trackTitle(for station: Station) -> String {
        if let title = audioPlayer.currentTrackTitle {
            return title
        }

        return audioPlayer.currentStation == nil ? L10n.string("player.track.pickStation") : L10n.string("player.track.liveStreamActive")
    }

    private var shouldShowStatusRow: Bool {
        audioPlayer.sleepTimerDescription != nil
    }

    private var playerAviAssetName: String {
        if let aviReaction {
            return aviReaction.assetName
        }
        if audioPlayer.hasFailure {
            return "AviV2Thinking"
        }
        if audioPlayer.isLoading {
            return "AviV2Thinking"
        }
        if audioPlayer.isPlaying {
            return "AviV2TuneHeadphones"
        }
        return "AviV2NeutralFullbody"
    }

    private var playerAviBodyOffset: CGSize {
        if audioPlayer.hasFailure {
            return CGSize(width: -3, height: 0)
        }
        if audioPlayer.isLoading {
            return CGSize(width: -4, height: 1)
        }
        if audioPlayer.isPlaying {
            return CGSize(width: 4, height: -2)
        }
        return .zero
    }

    private var playerAviStateTitle: String {
        if audioPlayer.hasFailure {
            return L10n.string("player.avi.state.error")
        }
        if audioPlayer.isLoading {
            return L10n.string("player.avi.state.thinking")
        }
        if audioPlayer.isPlaying {
            return L10n.string("player.avi.state.listening")
        }
        return L10n.string("player.avi.state.neutral")
    }

    private func playerAviDetail(for station: Station) -> String {
        if audioPlayer.hasFailure {
            return L10n.string("player.avi.detail.error")
        }
        if audioPlayer.isLoading {
            return L10n.string("player.avi.detail.thinking", station.name)
        }
        if audioPlayer.isPlaying {
            if let latestDiscovery = latestDiscovery(for: station) {
                return "Avi remembers \(stationDiscoveryCount(for: station)) tracks from \(station.name). Latest: \(latestDiscovery.title)."
            }

            return L10n.string("player.avi.detail.listening", station.name)
        }
        return L10n.string("player.avi.detail.neutral")
    }

    private func playerAviContextPrompts(for station: Station) -> [String] {
        var prompts: [String] = []

        if let feedback = libraryStore.feedback(for: station) {
            prompts.append(feedback.localizedState)
        }

        if isCurrentTrackSaved {
            prompts.append(L10n.string("player.discovery.savedShort"))
        } else if hasDiscoverableTrack {
            prompts.append(L10n.string("player.discovery.stateNew"))
        }

        if let country = playerStationCountryPrompt(for: station) {
            prompts.append(country)
        }

        let stationDiscoveries = stationDiscoveryCount(for: station)
        if stationDiscoveries > 0 {
            prompts.append("\(stationDiscoveries) discoveries")
        }

        if let tag = station.normalizedTags.first {
            prompts.append(tag.capitalized(with: L10n.locale))
        }

        return Array(prompts.prefix(3))
    }

    private func playerStationCountryPrompt(for station: Station) -> String? {
        if let countryCode = TuneAVCountry.sanitizedCode(station.countryCode) {
            return L10n.countryName(for: countryCode)
        }

        return TuneAVText.normalizedValue(station.country, excluding: Station.unknownDetailValues, locale: L10n.locale)
    }

    private func latestDiscovery(for station: Station) -> DiscoveredTrack? {
        playerDiscoveries(for: station)
            .max { first, second in first.playedAt < second.playedAt }
    }

    private func stationDiscoveryCount(for station: Station) -> Int {
        playerDiscoveries(for: station).count
    }

    private func playerDiscoveries(for station: Station) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(libraryStore.discoveries)
            .filter { $0.stationID == station.id }
    }

    private var homepageURL: URL? {
        audioPlayer.currentStation?.resolvedHomepageURL
    }

    private func saveCurrentDiscovery(for station: Station) -> Bool {
        let state = accessController.limitState(
            for: .savedTracks,
            currentUsage: libraryStore.savedDiscoveriesCount
        )

        let didToggle = libraryStore.toggleDiscoveredTrackSaved(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: station,
            artworkURL: audioPlayer.currentTrackArtworkURL,
            savedLimit: state.limit,
            discoveryLimit: accessController.limits.discoveredTracks
        )
        guard didToggle else {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return false
        }

        UIImpactFeedbackGenerator(style: isCurrentTrackSaved ? .rigid : .light).impactOccurred()
        return true
    }

    private func openExternalSearch(
        _ feature: LimitedFeature,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        guard
            let query = discoverySearchQuery,
            let search = TuneAVExternalSearchURL.discoverySearch(
                searchQuery: query,
                destination: destination,
                feature: feature,
                suffix: suffix
            )
        else { return }
        guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        browserDestination = BrowserDestination(url: search.url)
    }

    private func toggleFavorite(_ station: Station) {
        if libraryStore.isFavorite(station) {
            libraryStore.toggleFavorite(for: station)
            return
        }

        let state = accessController.limitState(
            for: .favoriteStations,
            currentUsage: libraryStore.favorites.count
        )
        guard state.isAllowed else {
            accessController.presentUpgradePrompt(for: .favoriteStations, currentUsage: state.currentUsage)
            return
        }

        libraryStore.toggleFavorite(for: station)
    }

    private func useDailyFeatureIfAllowed(_ feature: LimitedFeature, usageKey: String) -> Bool {
        guard accessController.canUseDailyFeature(feature, usageKey: usageKey) else {
            accessController.presentUpgradePrompt(for: feature)
            return false
        }

        accessController.recordDailyFeatureUse(feature, usageKey: usageKey)
        return true
    }

    private func openStationSearch(for station: Station) {
        guard let url = TuneAVExternalSearchURL.stationSearch(stationName: station.name) else { return }
        browserDestination = BrowserDestination(url: url)
    }

    private func openArtistSearch(destination: TuneAVExternalSearchURL.Destination, feature: LimitedFeature) {
        guard
            let discovery = currentDiscovery,
            let search = TuneAVExternalSearchURL.artistSearch(
                artist: discovery.artist,
                destination: destination,
                feature: feature
            )
        else { return }
        guard useDailyFeatureIfAllowed(search.feature, usageKey: search.url.absoluteString) else { return }
        browserDestination = BrowserDestination(url: search.url)
    }

    private var discoverySearchQuery: String? {
        currentDiscovery?.searchQuery
    }

    private var currentDiscovery: TuneAVCurrentDiscovery? {
        TuneAVCurrentDiscovery.resolve(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: audioPlayer.currentStation
        )
    }

    private func stationArtworkURL(for station: Station) -> URL? {
        nil
    }

    private var canCycleStations: Bool {
        audioPlayer.canCyclePlaybackQueue
    }

    private func playNextStation() {
        guard canCycleStations else { return }
        audioPlayer.playNextInQueue()
        recordCurrentPlayback()
    }

    private func playPreviousStation() {
        guard canCycleStations else { return }
        audioPlayer.playPreviousInQueue()
        recordCurrentPlayback()
    }

    private func recordCurrentPlayback() {
        guard let station = audioPlayer.currentStation else { return }
        libraryStore.recordPlayback(of: station, recentLimit: accessController.limits.recentStations)
    }

    private func resetHorizontalDrag() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            horizontalDragOffset = 0
        }
    }

    private func resetVerticalDrag() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            verticalDragOffset = 0
        }
    }

    private func isVerticalDismissSwipe(_ value: DragGesture.Value) -> Bool {
        value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width)
    }
}

private struct PlayerAviBody: View {
    let assetName: String
    let size: CGFloat
    let offset: CGSize

    var body: some View {
        ZStack {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .offset(offset)
        }
        .frame(width: size, height: size)
        .clipped()
        .animation(.snappy(duration: 0.24), value: assetName)
        .animation(.snappy(duration: 0.24), value: offset)
    }
}

private struct PlayerSignalDeck: View {
    let station: Station
    let trackTitle: String?
    let trackArtist: String?
    let trackAlbumTitle: String?
    let trackArtworkURL: URL?
    let trackArtistURL: URL?
    let isDiscoverableTrack: Bool
    let isCurrentTrackDiscovered: Bool
    let stationFeedback: TuneAVStationFeedback?
    let isPlaying: Bool
    let isLoading: Bool
    let isFavorite: Bool
    let homepageURL: URL?
    let onSetStationFeedback: (TuneAVStationFeedback?) -> Void
    let onSaveDiscovery: () -> Bool
    let onOpenAppleMusic: () -> Void
    let onOpenYouTube: () -> Void
    let onOpenLyrics: () -> Void
    let onOpenArtist: () -> Void
    let onOpenStationSearch: () -> Void
    let onTogglePlayback: () -> Void
    let onToggleFavorite: () -> Void
    let onOpenWebsite: (URL) -> Void

    private var hasSongContext: Bool {
        isDiscoverableTrack || trackArtworkURL != nil || TuneAVText.normalizedValue(trackTitle) != nil
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            stationHeaderLabel
            nowPlayingSummary
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.075))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.highlight.opacity(0.14), radius: 18, y: 10)
        .frame(height: 128, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private var stationHeaderLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .black))

            Text(station.name)
                .font(.system(size: 11, weight: .black))
                .lineLimit(1)
        }
        .foregroundStyle(TuneAVTheme.highlight.opacity(0.92))
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("player.signalDeck.stationHeader")
    }

    private var nowPlayingSummary: some View {
        HStack(alignment: .center, spacing: 10) {
            songArtwork(size: 54)

            nowPlayingLine
            .frame(maxWidth: .infinity, alignment: .leading)

            actionMenu
                .offset(x: 4)
        }
        .frame(height: 72)
    }

    @ViewBuilder
    private func songArtwork(size: CGFloat) -> some View {
        if hasSongContext, let trackArtworkURL {
            AsyncImage(url: trackArtworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    stationArtwork(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            stationArtwork(size: size)
        }
    }

    private var nowPlayingLine: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(station.name)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textInverse.opacity(0.94))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(stationDisplayLines.artistLine)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TuneAVTheme.textInverse.opacity(0.58))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(stationDisplayLines.titleLine)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TuneAVTheme.textInverse.opacity(0.72))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 54, alignment: .topLeading)
    }

    private func stationArtwork(size: CGFloat) -> some View {
        StationArtworkView(
            station: station,
            size: size,
            surfaceStyle: .dark,
            contentInsetRatio: 0.04,
            cornerRadiusRatio: 0.18,
            textMode: .stationName,
            animationOverlay: .automatic,
            isAnimationActive: isPlaying,
            animationDuration: 10
        )
        .frame(width: size, height: size)
    }

    private var actionMenu: some View {
        Menu {
            if hasSongContext {
                Section("Song") {
                    Button(isCurrentTrackDiscovered ? L10n.string("player.discovery.savedShort") : L10n.string("player.discovery.saveShort")) {
                        _ = onSaveDiscovery()
                    }
                    Button(L10n.string("player.discovery.appleMusic"), action: onOpenAppleMusic)
                    Button(L10n.string("player.discovery.lyrics"), action: onOpenLyrics)
                    Button(L10n.string("player.discovery.youtube"), action: onOpenYouTube)
                    Button(trackArtistURL == nil ? L10n.string("player.artist.search") : L10n.string("player.artist.view"), action: openArtist)
                }
            }

            Section("Radio") {
                Button(isFavorite ? L10n.string("player.menu.removeFavorite") : L10n.string("player.menu.addFavorite"), action: onToggleFavorite)

                if let homepageURL {
                    Button(L10n.string("player.menu.openWebsite")) {
                        onOpenWebsite(homepageURL)
                    }
                } else {
                    Button(L10n.string("player.menu.searchStation"), action: onOpenStationSearch)
                }
            }
        } label: {
            deckMoreIcon
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("player.signalDeck.more")
    }

    private var deckMoreIcon: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.82))
            .rotationEffect(.degrees(90))
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.10), in: Circle())
    }

    private var stationDisplayLines: TuneAVStationDisplayLines {
        TuneAVStationDisplayLines.resolve(
            station: station,
            isCurrent: true,
            currentArtist: trackArtist,
            currentTitle: trackTitle,
            currentAlbumTitle: trackAlbumTitle,
            nowPlayingTrack: nil,
            detailText: station.cardDetailText(preferCountryName: station.flagEmoji == nil)
                ?? L10n.string("shell.station.row.defaultDetail"),
            liveFallback: L10n.string("player.track.liveStreamActive")
        )
    }

    private func openArtist() {
        if let trackArtistURL {
            onOpenWebsite(trackArtistURL)
        } else {
            onOpenArtist()
        }
    }
}

private enum PlayerRatingTarget {
    case song
    case radio

    var title: String {
        switch self {
        case .song:
            return "Song"
        case .radio:
            return "Radio"
        }
    }
}

private enum PlayerAviReaction: Equatable {
    case happy
    case thinking
    case curious
    case saved

    var assetName: String {
        switch self {
        case .happy, .saved:
            return "AviV2TuneHeadphones"
        case .thinking:
            return "AviV2Thinking"
        case .curious:
            return "AviV2NeutralFullbody"
        }
    }
}

private struct PlayerAviContextPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.86))
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct FlippingPlayerArtwork: View {
    let station: Station
    let size: CGFloat
    let trackTitle: String?
    let trackArtist: String?
    let trackAlbumTitle: String?
    let trackArtworkURL: URL?
    let trackArtistURL: URL?
    let isDiscoverableTrack: Bool
    let isCurrentTrackDiscovered: Bool
    let isPlaying: Bool
    let isLoading: Bool
    let isFavorite: Bool
    let homepageURL: URL?
    let onSaveDiscovery: () -> Bool
    let onOpenAppleMusic: () -> Void
    let onOpenYouTube: () -> Void
    let onOpenLyrics: () -> Void
    let onOpenArtist: () -> Void
    let onOpenStationSearch: () -> Void
    let onTogglePlayback: () -> Void
    let onToggleFavorite: () -> Void
    let onOpenWebsite: (URL) -> Void

    @State private var isShowingOptions = false
    @State private var discoveryFeedback: DiscoveryFeedback?

    var body: some View {
        ZStack {
            artworkFront
                .opacity(isShowingOptions ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isShowingOptions ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.7
                )
                .allowsHitTesting(!isShowingOptions)
                .accessibilityHidden(isShowingOptions)
                .onTapGesture {
                    flipToOptions()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(trackTitle ?? station.name))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("player.artwork.front")

            artworkOptionsBack
                .opacity(isShowingOptions ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isShowingOptions ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.7
                )
                .allowsHitTesting(isShowingOptions)
                .accessibilityHidden(!isShowingOptions)
                .accessibilityElement(children: .contain)
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var artworkFront: some View {
        heroArtwork
            .overlay {
                if isLoading {
                    loadingOverlay
                }
            }
            .overlay(alignment: .topTrailing) {
                artworkFlipIndicator
                    .padding(flipControlPadding)
            }
            .overlay(alignment: .bottomLeading) {
                if trackArtworkURL != nil {
                    stationBadgeArtwork(size: 58)
                        .padding(18)
                }
            }
    }

    private var artworkFlipIndicator: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: flipControlSize, height: flipControlSize)
            .background(.black.opacity(0.32), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .accessibilityHidden(true)
    }

    private var artworkOptionsBack: some View {
        let cornerRadius: CGFloat = 32

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.72),
                            TuneAVTheme.highlight.opacity(0.32),
                            Color.black.opacity(0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            blurredBackdrop

            Button(action: flipToFront) {
                Color.clear
                    .frame(width: size, height: size)
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("player.artwork.flipToFront.accessibility.label"))
            .accessibilityIdentifier("player.artwork.options.backgroundClose")
            .accessibilityHidden(true)

            VStack(spacing: optionsBlockSpacing) {
                if isDiscoverableTrack {
                    songInfoBlock
                    artistInfoBlock
                } else {
                    radioInfoBlock
                }
            }
            .padding(size < 260 ? 16 : 18)

            Button {
                flipToFront()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: flipControlSize, height: flipControlSize)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(width: flipControlSize, height: flipControlSize)
            .padding(flipControlPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityLabel(L10n.string("player.artwork.flipToFront.accessibility.label"))
            .accessibilityIdentifier("player.artwork.options.close")
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.highlight.opacity(0.18), radius: 26, y: 14)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }

    private func flipToOptions() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            isShowingOptions = true
        }
    }

    private func flipToFront() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isShowingOptions = false
        }
    }

    @ViewBuilder
    private var blurredBackdrop: some View {
        if let artworkURL = heroArtworkURL {
            AsyncImage(url: artworkURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .blur(radius: 24)
                        .opacity(0.22)
                        .clipped()
                }
            }
        }
    }

    private var radioInfoBlock: some View {
        VStack(spacing: size < 260 ? 12 : 16) {
            Button(action: flipToFront) {
                VStack(spacing: size < 260 ? 9 : 12) {
                    stationFallbackArtwork(size: size < 260 ? 76 : 94)

                    VStack(spacing: 4) {
                        Text(station.name)
                            .font(.system(size: size < 260 ? 16 : 18, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textInverse)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text(radioContextLine)
                            .font(.system(size: size < 260 ? 12 : 13, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.66))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player.artwork.options.radioInfo")

            HStack(spacing: 12) {
                artworkActionButton(
                    systemImage: isLoading ? "hourglass" : (isPlaying ? "pause.fill" : "play.fill"),
                    accessibilityLabel: isLoading ? L10n.string("audio.status.loading") : (isPlaying ? L10n.string("player.control.pause") : L10n.string("player.control.play")),
                    accessibilityIdentifier: "player.artwork.options.playPause",
                    action: onTogglePlayback
                )

                savedStationArtworkActionButton(
                    isSaved: isFavorite,
                    accessibilityLabel: isFavorite ? L10n.string("player.menu.removeFavorite") : L10n.string("player.menu.addFavorite"),
                    accessibilityIdentifier: "player.artwork.options.favorite",
                    action: onToggleFavorite
                )

                if let homepageURL {
                    artworkActionButton(
                        systemImage: "safari.fill",
                        accessibilityLabel: L10n.string("player.menu.openWebsite"),
                        accessibilityIdentifier: "player.artwork.options.website"
                    ) {
                        onOpenWebsite(homepageURL)
                    }
                }
            }
        }
        .padding(.horizontal, size < 260 ? 12 : 14)
        .padding(.vertical, size < 260 ? 14 : 18)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var songInfoBlock: some View {
        VStack(spacing: optionContentSpacing) {
            Button(action: flipToFront) {
                HStack(alignment: .center, spacing: optionArtworkTextSpacing) {
                    compactArtwork(size: optionArtworkSize)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(songPrimaryLine)
                            .font(.system(size: size < 260 ? 15 : 17, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textInverse)
                            .lineLimit(1)

                        Text(songSecondaryLine)
                            .font(.system(size: size < 260 ? 13 : 15, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.72))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: optionArtworkSize, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player.artwork.options.songInfo")

            if isDiscoverableTrack {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        artworkFlexibleActionButton(
                            systemImage: discoveryButtonSystemImage,
                            title: discoveryButtonTitle,
                            accessibilityLabel: discoveryButtonAccessibilityLabel,
                            accessibilityIdentifier: "player.artwork.options.discovery",
                            style: isCurrentTrackDiscovered ? .saved : .prominent,
                            action: toggleDiscoveryFromArtwork
                        )
                        .scaleEffect(discoveryFeedback == nil ? 1 : 1.035)
                        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: discoveryFeedback)
                        .accessibilityValue(discoveryFeedbackAccessibilityValue)

                        artworkFlexibleActionButton(
                            systemImage: "music.note",
                            title: L10n.string("player.discovery.itunesShort"),
                            accessibilityLabel: L10n.string("player.discovery.appleMusic"),
                            accessibilityIdentifier: "player.artwork.options.appleMusic",
                            action: onOpenAppleMusic
                        )
                    }

                    HStack(spacing: 8) {
                        artworkFlexibleActionButton(
                            systemImage: "text.quote",
                            title: L10n.string("player.discovery.lyricsShort"),
                            accessibilityLabel: L10n.string("player.discovery.lyrics"),
                            accessibilityIdentifier: "player.artwork.options.lyrics",
                            action: onOpenLyrics
                        )

                        artworkFlexibleActionButton(
                            systemImage: "play.rectangle.fill",
                            title: L10n.string("player.discovery.videoShort"),
                            accessibilityLabel: L10n.string("player.discovery.youtube"),
                            accessibilityIdentifier: "player.artwork.options.youtube",
                            action: onOpenYouTube
                        )
                    }
                }
            }
        }
        .padding(.horizontal, optionBlockHorizontalPadding)
        .padding(.vertical, optionBlockVerticalPadding)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var artistInfoBlock: some View {
        VStack(spacing: optionContentSpacing) {
            Button(action: flipToFront) {
                HStack(alignment: .center, spacing: optionArtworkTextSpacing) {
                    artistArtwork(size: optionArtworkSize)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(backSubtitle)
                            .font(.system(size: size < 260 ? 15 : 17, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textInverse)
                            .lineLimit(1)

                        Text(artistContextLine)
                            .font(.system(size: size < 260 ? 13 : 15, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textInverse.opacity(0.66))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: optionArtworkSize, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player.artwork.options.artistInfo")

            HStack(spacing: 8) {
                artworkFlexibleActionButton(
                    systemImage: "music.mic",
                    title: L10n.string("player.artist.viewShort"),
                    accessibilityLabel: trackArtistURL == nil ? L10n.string("player.artist.search") : L10n.string("player.artist.view"),
                    accessibilityIdentifier: "player.artwork.options.artist",
                    action: openArtist
                )

                if let homepageURL {
                    artworkFlexibleActionButton(
                        systemImage: "radio",
                        title: L10n.string("player.station.websiteShort"),
                        accessibilityLabel: L10n.string("player.menu.openWebsite"),
                        accessibilityIdentifier: "player.artwork.options.station",
                        action: { onOpenWebsite(homepageURL) }
                    )
                } else {
                    artworkFlexibleActionButton(
                        systemImage: "radio",
                        title: L10n.string("player.station.websiteShort"),
                        accessibilityLabel: L10n.string("player.menu.searchStation"),
                        accessibilityIdentifier: "player.artwork.options.station",
                        action: onOpenStationSearch
                    )
                }
            }
        }
        .padding(.horizontal, optionBlockHorizontalPadding)
        .padding(.vertical, optionBlockVerticalPadding)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var discoveryButtonSystemImage: String {
        if let discoveryFeedback {
            switch discoveryFeedback {
            case .saved:
                return "checkmark"
            case .removed:
                return "bookmark.slash"
            }
        }

        return isCurrentTrackDiscovered ? "bookmark.fill" : "bookmark"
    }

    private func openArtist() {
        if let trackArtistURL {
            onOpenWebsite(trackArtistURL)
        } else {
            onOpenArtist()
        }
    }

    private var discoveryButtonTitle: String {
        if let discoveryFeedback {
            switch discoveryFeedback {
            case .saved:
                return L10n.string("player.discovery.savedShort")
            case .removed:
                return L10n.string("player.discovery.removedShort")
            }
        }

        return isCurrentTrackDiscovered ? L10n.string("player.discovery.savedShort") : L10n.string("player.discovery.saveShort")
    }

    private var discoveryButtonAccessibilityLabel: String {
        if let discoveryFeedback {
            switch discoveryFeedback {
            case .saved:
                return L10n.string("player.discovery.saved")
            case .removed:
                return L10n.string("player.discovery.removed")
            }
        }

        return isCurrentTrackDiscovered ? L10n.string("player.discovery.saved") : L10n.string("player.discovery.save")
    }

    private var discoveryFeedbackAccessibilityValue: String {
        guard let discoveryFeedback else { return "" }

        switch discoveryFeedback {
        case .saved:
            return L10n.string("player.discovery.savedShort")
        case .removed:
            return L10n.string("player.discovery.removedShort")
        }
    }

    private func toggleDiscoveryFromArtwork() {
        let nextFeedback: DiscoveryFeedback = isCurrentTrackDiscovered ? .removed : .saved
        guard onSaveDiscovery() else { return }

        discoveryFeedback = nextFeedback
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(950))
            guard discoveryFeedback == nextFeedback else { return }
            discoveryFeedback = nil
        }
    }

    @ViewBuilder
    private func compactArtwork(size: CGFloat) -> some View {
        if let artworkURL = heroArtworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    stationFallbackArtwork(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(playerArtworkShape(for: size))
            .overlay {
                playerArtworkShape(for: size)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        } else {
            stationFallbackArtwork(size: size)
        }
    }

    @ViewBuilder
    private func artistArtwork(size: CGFloat) -> some View {
        stationFallbackArtwork(size: size)
    }

    @ViewBuilder
    private func stationFallbackArtwork(size: CGFloat) -> some View {
        StationArtworkView(
            station: station,
            size: size,
            surfaceStyle: .dark,
            contentInsetRatio: 0.04,
            cornerRadiusRatio: heroCornerRadiusRatio,
            textMode: .stationName,
            animationOverlay: .automatic,
            isAnimationActive: false
        )
    }

    private func playerArtworkShape(for size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: size * heroCornerRadiusRatio, style: .continuous)
    }

    @ViewBuilder
    private func stationBadgeArtwork(size: CGFloat) -> some View {
        let badgeCornerRadius: CGFloat = 16

        Group {
            stationBadgeFallback(size: size, badgeCornerRadius: badgeCornerRadius)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: badgeCornerRadius, style: .continuous))
        .padding(1)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: badgeCornerRadius + 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: badgeCornerRadius + 3, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func stationBadgeFallback(size: CGFloat, badgeCornerRadius: CGFloat) -> some View {
        StationThumbnailView(
            station: station,
            size: size,
            surfaceStyle: .light
        )
    }

    private var loadingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.black.opacity(0.24))

            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)

                Text(L10n.string("audio.status.loading"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.black.opacity(0.34), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func artworkActionButton(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(TuneAVTheme.textInverse)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.13), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func savedStationArtworkActionButton(
        isSaved: Bool,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            TuneAVSavedStationIcon(
                isSaved: isSaved,
                size: 22,
                inactiveColor: TuneAVTheme.textInverse,
                activeColor: TuneAVTheme.highlight
            )
            .frame(width: 56, height: 56)
            .background(isSaved ? TuneAVTheme.highlight.opacity(0.18) : Color.white.opacity(0.13), in: Circle())
            .overlay {
                Circle()
                    .stroke(isSaved ? TuneAVTheme.highlight.opacity(0.34) : Color.white.opacity(0.0), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func artworkFlexibleActionButton(
        systemImage: String,
        title: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        style: ArtworkActionStyle = .secondary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))

                Text(title)
                    .font(.system(size: 12, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(style.foreground)
            .frame(maxWidth: .infinity)
            .frame(height: size < 260 ? 34 : 38)
            .background(style.background, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var heroArtwork: some View {
        let cornerRadius: CGFloat = 32

        Group {
            if let heroArtworkURL {
                AsyncImage(url: heroArtworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
                    default:
                        fallbackArtwork(cornerRadius: cornerRadius)
                    }
                }
            } else {
                fallbackArtwork(cornerRadius: cornerRadius)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if trackArtworkURL == nil {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
        .shadow(color: TuneAVTheme.highlight.opacity(0.18), radius: 26, y: 14)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }

    private func fallbackArtwork(cornerRadius: CGFloat) -> some View {
        StationArtworkView(
            station: station,
            size: size,
            surfaceStyle: .dark,
            contentInsetRatio: 0.04,
            cornerRadiusRatio: cornerRadius / size,
            textMode: .stationName,
            animationOverlay: .automatic,
            isAnimationActive: trackArtworkURL == nil && isPlaying,
            animationDuration: 10
        )
    }

    private var heroArtworkURL: URL? {
        trackArtworkURL
    }

    private var heroCornerRadiusRatio: CGFloat {
        32 / size
    }

    private var flipControlSize: CGFloat {
        32
    }

    private var flipControlPadding: CGFloat {
        size < 260 ? 12 : 14
    }

    private var optionsBlockSpacing: CGFloat {
        size < 260 ? 10 : 14
    }

    private var optionContentSpacing: CGFloat {
        size < 260 ? 8 : 10
    }

    private var optionArtworkSize: CGFloat {
        size < 260 ? 40 : 50
    }

    private var optionArtworkTextSpacing: CGFloat {
        size < 260 ? 10 : 12
    }

    private var optionBlockHorizontalPadding: CGFloat {
        size < 260 ? 10 : 12
    }

    private var optionBlockVerticalPadding: CGFloat {
        size < 260 ? 9 : 12
    }

    private var backTitle: String {
        isDiscoverableTrack ? (trackTitle ?? station.name) : station.name
    }

    private var backSubtitle: String {
        isDiscoverableTrack ? (trackArtist ?? station.name) : station.shortMeta
    }

    private var artistContextLine: String {
        L10n.string("player.artist.stationContext", station.name)
    }

    private var radioContextLine: String {
        let meta = station.shortMeta.trimmingCharacters(in: .whitespacesAndNewlines)
        return meta.isEmpty ? L10n.string("player.track.liveNow") : meta
    }

    private var songPrimaryLine: String {
        if let albumTitle = TuneAVText.normalizedValue(trackAlbumTitle) {
            return albumTitle
        }

        return station.name
    }

    private var songSecondaryLine: String {
        backTitle
    }
}

private enum ArtworkActionStyle {
    case prominent
    case saved
    case secondary
    case disabled

    var foreground: Color {
        switch self {
        case .prominent, .saved:
            return .white
        case .secondary:
            return TuneAVTheme.textInverse.opacity(0.92)
        case .disabled:
            return TuneAVTheme.textInverse.opacity(0.42)
        }
    }

    var background: Color {
        switch self {
        case .prominent:
            return TuneAVTheme.highlight.opacity(0.78)
        case .saved:
            return Color.white.opacity(0.18)
        case .secondary:
            return Color.white.opacity(0.10)
        case .disabled:
            return Color.white.opacity(0.06)
        }
    }
}

private enum DiscoveryFeedback: Equatable {
    case saved
    case removed
}

private struct LandscapeNowPlayingRowLayout: Layout {
    let artworkSize: CGFloat
    let spacing: CGFloat
    let summaryHeight: CGFloat
    let controlsBottomNudge: CGFloat = 16

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        CGSize(width: proposal.width ?? (artworkSize + spacing), height: artworkSize)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard subviews.count >= 3 else { return }

        let artworkProposal = ProposedViewSize(width: artworkSize, height: artworkSize)
        let detailX = bounds.minX + artworkSize + spacing
        let detailWidth = max(bounds.width - artworkSize - spacing, 0)

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: artworkProposal
        )

        subviews[1].place(
            at: CGPoint(x: detailX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: detailWidth, height: summaryHeight)
        )

        let controlsSize = subviews[2].sizeThatFits(
            ProposedViewSize(width: detailWidth, height: nil)
        )
        let controlsY = max(bounds.minY, bounds.maxY - controlsSize.height + controlsBottomNudge)

        subviews[2].place(
            at: CGPoint(x: detailX, y: controlsY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: detailWidth, height: controlsSize.height)
        )
    }
}

#Preview {
    NowPlayingView()
        .environmentObject(AudioPlayerService())
        .environmentObject(LibraryStore(container: PersistenceController(inMemory: true).container))
}
