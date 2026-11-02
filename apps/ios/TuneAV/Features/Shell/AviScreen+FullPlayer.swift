import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    func focusedRadioBlock(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            focusedSignalHeader(for: station)

            if isFocusedStationActive {
                focusedNowBlock(for: station)
            }

            if !isFocusedStationActive {
                listenToFocusedStationButton
            }
        }
        .padding(18)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.24), radius: 14, y: 8)
    }

    func focusedSignalHeader(for station: Station) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(station.name)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)

                    Text(isFocusedStationActive ? L10n.string("shell.avi.status.playing") : L10n.string("shell.avi.status.info"))
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(TuneAVTheme.highlight.opacity(0.11), in: Capsule(style: .continuous))
                }

                if !isFocusedStationActive {
                    Text(defaultPublicSignalInfo(for: station))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func focusedNowBlock(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("shell.common.playingNow"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Spacer()

                Text(isFocusedStationActive ? L10n.string("shell.avi.status.live") : L10n.string("shell.avi.status.info"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
            }

            Text(currentTrackTitle ?? L10n.string("player.track.liveNow"))
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.74)

            Text(focusedSignalDetail(for: station))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineLimit(3)
        }
        .padding(16)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    var focusedPlayerControls: some View {
        HStack(alignment: .center, spacing: 12) {
            if isFocusedStationActive {
                listeningControlButton(systemImage: "backward.fill", accessibilityIdentifier: "avi.controls.previous", action: playPrevious)
            }

            if isFocusedStationActive && isPlaying {
                listeningControlButton(systemImage: "power", accessibilityIdentifier: "avi.controls.closeSignal", action: stopPlayback)
            }

            Button(action: openPlayer) {
                Image(systemName: primaryFocusedActionIcon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            if isFocusedStationActive {
                listeningControlButton(systemImage: "forward.fill", accessibilityIdentifier: "avi.controls.next", action: playNext)
            }
        }
    }

    var listenToFocusedStationButton: some View {
        Button(action: openPlayer) {
            focusedPlayButtonContent(height: 52, cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.accessibility.listenToRadio"))
        .accessibilityIdentifier("avi.controls.listen")
    }

    func focusedPlayButtonContent(height: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .tint(TuneAVTheme.brandBlack)
            } else {
                Image(systemName: primaryFocusedActionIcon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(TuneAVTheme.brandBlack)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func focusedFeedbackBlock(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                aviHeroImage(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isNowPlayingFullPlayer && hasCurrentSongContext ? L10n.string("player.avi.feedback.songQuestion") : L10n.string("player.avi.feedback.radioQuestion"))
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(aviPrimaryLine)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            StationFeedbackControl(
                feedbackIdentity: focusedPrimaryFeedbackIdentity(for: station),
                selectedFeedback: focusedPrimaryFeedback(for: station),
                selectFeedback: { feedback in
                    setFocusedPrimaryFeedback(feedback, for: station)
                },
                clearFeedback: {
                    setFocusedPrimaryFeedback(nil, for: station)
                }
            )
        }
        .padding(14)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.6), lineWidth: 1)
        }
    }

    func focusedAviBlock(for station: Station) -> some View {
        ZStack(alignment: .topLeading) {
            if isShowingAviActions {
                aviActionsPanel(for: station)
                    .transition(.opacity)
            } else {
                fullPlayerAviControlPanel(for: station)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 306, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: TuneAVTheme.softShadow.opacity(0.2), radius: 12, y: 6)
        .zIndex(isShowingAviActions ? 10 : 0)
    }

    func fullPlayerAviControlPanel(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hasCurrentSongContext ? L10n.string("shell.avi.actions.songFeedback") : L10n.string("shell.avi.actions.radioFeedback"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Text(aviPrimaryLine)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 28, height: 28)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                Text(hasCurrentSongContext ? L10n.string("shell.avi.detail.detecting") : L10n.string("shell.avi.primary.reading"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            StationFeedbackControl(
                feedbackIdentity: focusedPrimaryFeedbackIdentity(for: station),
                selectedFeedback: focusedPrimaryFeedback(for: station),
                selectFeedback: { feedback in
                    let currentFeedback = focusedPrimaryFeedback(for: station)
                    let nextFeedback = currentFeedback == feedback ? nil : feedback
                    setFocusedPrimaryFeedback(nextFeedback, for: station)
                    if let nextFeedback {
                        showAviReaction(for: nextFeedback)
                    }
                },
                clearFeedback: {
                    setFocusedPrimaryFeedback(nil, for: station)
                }
            )

            HStack(spacing: 10) {
                if !hasCurrentSongContext {
                    AVAviPrimaryActionButton(
                        title: stationSaveActionTitle(for: station),
                        systemImage: stationSaveActionSystemImage(for: station),
                        accessibilityIdentifier: "avi.fullPlayer.saveRadio"
                    ) {
                        showAviReaction(.liked)
                        toggleFavorite(station)
                    }
                }

                AVAviPrimaryActionButton(
                    title: L10n.string("shell.avi.actions.ask"),
                    systemImage: "sparkles",
                    accessibilityIdentifier: "avi.actions.toggle"
                ) {
                    withAnimation(.snappy(duration: 0.22)) {
                        applyAviTransientState(currentAviTransientState.openingActions())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func fullPlayerAviFeedbackBlock(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FullPlayerAviHeader(
                emotion: aviEmotion,
                reactionEmotion: aviReaction?.emotion,
                reactionStartedAt: aviReaction == nil ? nil : aviReactionStartedAt,
                label: fullPlayerAviCopy.label,
                title: fullPlayerAviCopy.title,
                summary: fullPlayerAviCopy.summary
            )

            Rectangle()
                .fill(TuneAVTheme.borderSubtle.opacity(0.64))
                .frame(height: 1)

            ZStack(alignment: .topLeading) {
                if isShowingAviActions {
                    aviActionsPanel(for: station)
                        .transition(.opacity)
                } else {
                    fullPlayerAviSignalSummary(for: station)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: isShowingAviActions ? 424 : 156, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: isShowingAviActions ? 570 : 300, alignment: .top)
        .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            TuneAVTheme.glassStroke.opacity(0.95),
                            TuneAVTheme.highlight.opacity(isShowingAviActions ? 0.14 : 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: TuneAVTheme.softShadow.opacity(0.2), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("avi.fullPlayer.feedbackBlock")
    }

    func fullPlayerAviSignalSummary(for station: Station) -> some View {
        let selectedFeedback = focusedPrimaryFeedback(for: station)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(hasCurrentSongContext ? L10n.string("shell.avi.actions.songFeedback") : L10n.string("shell.avi.actions.radioFeedback"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    openFullPlayerAviActions()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .black))
                        Text(L10n.string("player.avi.moreWithAvi"))
                            .font(.system(size: 12, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
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
                .accessibilityIdentifier("avi.actions.toggle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)

            Text(isNowPlayingFullPlayer && hasCurrentSongContext ? L10n.string("player.avi.feedback.songQuestion") : L10n.string("player.avi.feedback.radioQuestion"))
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22)

            fullPlayerFeedbackPicker(
                selectedFeedback: selectedFeedback,
                selectFeedback: { feedback in
                    let currentFeedback = focusedPrimaryFeedback(for: station)
                    let nextFeedback = currentFeedback == feedback ? nil : feedback
                    setFocusedPrimaryFeedback(nextFeedback, for: station)
                    if let nextFeedback {
                        showAviReaction(for: nextFeedback)
                    }
                },
                clearFeedback: {
                    setFocusedPrimaryFeedback(nil, for: station)
                }
            )
            .frame(height: 38)

            fullPlayerFeedbackFollowUp(
                feedback: selectedFeedback,
                station: station
            )
            .frame(height: 42, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func openFullPlayerAviActions() {
        AVHaptics.perform(.openPanel)
        withAnimation(.snappy(duration: 0.22)) {
            applyAviTransientState(currentAviTransientState.openingActions())
        }
    }

    @ViewBuilder
    func fullPlayerFeedbackPicker(
        selectedFeedback: TuneAVStationFeedback?,
        selectFeedback: @escaping (TuneAVStationFeedback) -> Void,
        clearFeedback: @escaping () -> Void
    ) -> some View {
        if let selectedFeedback {
            HStack(spacing: 8) {
                SelectedStationFeedbackStatus(feedback: selectedFeedback)

                AVAviFeedbackClearButton(
                    accessibilityLabel: L10n.string("shell.stationFeedback.clear"),
                    accessibilityIdentifier: "stationFeedback.clear",
                    action: clearFeedback
                )
            }
            .frame(height: 38)
        } else {
            StationFeedbackOptionsRow(selectFeedback: selectFeedback)
            .frame(height: 38)
        }
    }

    @ViewBuilder
    func fullPlayerFeedbackFollowUp(
        feedback: TuneAVStationFeedback?,
        station: Station
    ) -> some View {
        if hasCurrentSongContext {
            fullPlayerFeedbackDecisionRow(station: station)
        } else if feedback != nil {
            AVAviFeedbackInfoRow(
                title: L10n.string("player.avi.feedback.tuned"),
                subtitle: L10n.string("player.avi.feedback.tunedHint"),
                systemImage: "sparkles",
                isAction: false
            )
        } else {
            AVAviFeedbackInfoRow(
                title: L10n.string("player.avi.feedback.choose"),
                subtitle: L10n.string("player.avi.feedback.chooseHint"),
                systemImage: "slider.horizontal.3",
                isAction: false
            )
        }
    }

    func fullPlayerFeedbackDecisionRow(station: Station) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if aviDiscoveryDecision == .ignored {
                HStack(spacing: 8) {
                    AVAviFeedbackInfoRow(
                        title: L10n.string("player.discovery.noSave"),
                        subtitle: L10n.string("player.discovery.noSaveHint"),
                        systemImage: "xmark",
                        isAction: false
                    )
                    .accessibilityIdentifier("avi.fullPlayer.discoveryNoSave")

                    fullPlayerDiscoveryCompactButton(
                        title: L10n.string("player.discovery.saveShort"),
                        systemImage: "bookmark",
                        accessibilityIdentifier: "avi.fullPlayer.saveAfterNoSave"
                    ) {
                        let didToggle = saveAviCurrentDiscovery(for: station)
                        if didToggle {
                            aviDiscoveryDecision = .saved
                        }
                    }
                }
                .frame(height: 42)
            } else if isCurrentTrackSaved(for: station) {
                HStack(spacing: 8) {
                    AVAviFeedbackInfoRow(
                        title: L10n.string("player.discovery.savedShort"),
                        subtitle: L10n.string("player.discovery.savedHintShort"),
                        systemImage: "bookmark.fill",
                        isAction: false
                    )

                    fullPlayerDiscoveryCompactButton(
                        title: L10n.string("player.discovery.unsaveShort"),
                        systemImage: "bookmark.slash",
                        accessibilityIdentifier: "avi.fullPlayer.unsaveSong"
                    ) {
                        let didToggle = saveAviCurrentDiscovery(for: station)
                        if didToggle {
                            aviDiscoveryDecision = .removed
                        }
                    }
                }
                .frame(height: 42)
            } else {
                HStack(spacing: 8) {
                    fullPlayerDiscoveryDecisionButton(
                        title: currentTrackSaveActionTitle(for: station),
                        systemImage: currentTrackSaveActionSystemImage(for: station),
                        isSelected: isCurrentTrackSaved(for: station),
                        accessibilityIdentifier: "avi.fullPlayer.saveSong"
                    ) {
                        let didToggle = saveAviCurrentDiscovery(for: station)
                        if didToggle {
                            aviDiscoveryDecision = isCurrentTrackSaved(for: station) ? .saved : .removed
                        }
                    }

                    fullPlayerDiscoveryDecisionButton(
                        title: L10n.string("player.discovery.noSave"),
                        systemImage: "xmark",
                        isSelected: false,
                        accessibilityIdentifier: "avi.fullPlayer.noSaveSong"
                    ) {
                        aviDiscoveryDecision = .ignored
                        showAviReaction(.notForMe)
                    }
                }
                .frame(height: 42)

            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("avi.fullPlayer.discoveryDecision")
    }

    func fullPlayerDiscoveryCompactButton(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            fullPlayerDiscoveryButtonLabel(title: title, systemImage: systemImage)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 126, height: 42)
                .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    func fullPlayerDiscoveryDecisionButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            fullPlayerDiscoveryButtonLabel(title: title, systemImage: systemImage)
                .foregroundStyle(isSelected ? TuneAVTheme.brandBlack : TuneAVTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    isSelected ? TuneAVTheme.highlight : TuneAVTheme.cardSurface,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.44) : TuneAVTheme.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    func fullPlayerDiscoveryButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))

            Text(title)
                .font(.system(size: 11, weight: .black))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .padding(.horizontal, 8)
    }

    func compactAviActionsSheet(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.string("shell.avi.actions.ask"))
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Spacer(minLength: 0)

                AVAviPanelCloseButton(
                    accessibilityLabel: L10n.string("shell.avi.actions.closeOptions"),
                    accessibilityIdentifier: "avi.actions.close",
                    action: closeAviActions
                )
            }

            HStack(spacing: 8) {
                AVAviPanelOptionButton(
                    title: L10n.string("shell.avi.actions.searchYouTube"),
                    systemImage: "play.rectangle",
                    style: .compact,
                    accessibilityIdentifier: "avi.actions.youtube"
                ) {
                    showAviReaction(.curious)
                    openAviSearch(for: station, destination: .youtube)
                }
                AVAviPanelOptionButton(
                    title: L10n.string("shell.avi.actions.searchArtist"),
                    systemImage: "person.crop.circle",
                    style: .compact,
                    accessibilityIdentifier: "avi.actions.artist"
                ) {
                    showAviReaction(.curious)
                    openAviArtistSearch()
                }
            }

            HStack(spacing: 8) {
                AVAviPanelOptionButton(
                    title: L10n.string("shell.avi.actions.searchAppleMusic"),
                    systemImage: "music.note",
                    style: .compact,
                    accessibilityIdentifier: "avi.actions.appleMusic"
                ) {
                    showAviReaction(.curious)
                    openAviSearch(for: station, destination: .appleMusic)
                }
                AVAviPanelOptionButton(
                    title: L10n.string("shell.avi.actions.radioFeedback"),
                    systemImage: "dot.radiowaves.left.and.right",
                    style: .compact,
                    accessibilityIdentifier: "avi.actions.radioFeedback"
                ) {
                    setAviMenuFeedback(.liked, for: station)
                    closeAviActions()
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 184, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(TuneAVTheme.elevatedSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: TuneAVTheme.glassShadow, radius: 24, y: 12)
    }
}
