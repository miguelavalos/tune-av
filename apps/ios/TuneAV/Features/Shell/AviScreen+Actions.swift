import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    var aviActionsPanelState: ShellAviActionsPanelState {
        ShellAviActionsPanelState(
            hasSongStep: hasCurrentSongContext && isNowPlayingFullPlayer,
            currentPage: aviActionsPage
        )
    }

    var aviActionsRouter: ShellAviActionsRouter {
        ShellAviActionsRouter(
            changeActionsPage: { page in
                withAnimation(.snappy(duration: 0.2)) {
                    applyAviTransientState(currentAviTransientState.changingActionsPage(to: page))
                }
            },
            closeAviActions: closeAviActions,
            showReaction: showAviReaction,
            openTrackSearch: { station, destination, suffix in
                openAviSearch(for: station, destination: destination, suffix: suffix)
            },
            openArtistSearch: openAviArtistSearch,
            openStationSearch: openAviStationSearch,
            showStationDetails: { station, queue, initialSection in
                showStationDetails(station, queue, initialSection)
            },
            openStationWebsiteOrSearch: { station in
                browserRouter.openStationWebsiteOrSearch(station, closesAviActions: true)
            },
            showRelatedStations: showRelatedStations,
            stopPlayback: stopPlayback
        )
    }

    func aviActionsPanel(for station: Station) -> some View {
        aviActionsPanel(for: station, showsStationDetailAction: true)
    }

    func aviActionsPanel(for station: Station, showsStationDetailAction: Bool) -> some View {
        let panelState = aviActionsPanelState
        let router = aviActionsRouter

        return AviActionsPanelView(
            state: panelState,
            showsStationDetailAction: showsStationDetailAction,
            showsCloseSignalAction: isNowPlayingFullPlayer && isFocusedStationActive,
            previousPage: { router.previousPage(from: panelState) },
            nextPage: { router.nextPage(from: panelState) },
            close: closeAviActions,
            searchLyrics: { router.searchLyrics(for: station) },
            searchYouTube: { router.searchYouTube(for: station) },
            searchAppleMusic: { router.searchAppleMusic(for: station) },
            searchArtist: router.searchArtist,
            searchPublicInfo: { router.searchPublicInfo(for: station) },
            showRadioDetails: { router.showRadioDetails(for: station) },
            showHistory: { router.showHistory(for: station) },
            openWebsite: { router.openWebsite(for: station) },
            findRelatedRadios: { router.findRelatedRadios(for: station) },
            closeSignal: router.closeSignal
        )
    }

    func setAviMenuFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        if aviFeedbackTarget(for: station, isEditingRadioFeedback: isEditingRadioFeedback).usesTrackFeedback {
            guard currentTrackFeedback != feedback else { return }
            libraryStore.setFeedbackForDiscoveredTrack(
                feedback,
                title: currentTrackTitle,
                artist: currentTrackArtist,
                stationID: station.id
            )
        } else {
            guard stationFeedback[station.id] != feedback else { return }
            setStationFeedback(station, feedback)
        }
        if let feedback {
            showAviReaction(for: feedback)
        } else {
            AVHaptics.perform(.clear)
        }
    }

    func showAviReaction(_ reaction: AviScreenReaction) {
        if let current = aviReaction, current.priority > reaction.priority {
            return
        }

        let token = UUID()
        aviReaction = reaction
        aviReactionStartedAt = Date()
        aviReactionToken = token
        if let hapticEvent = reaction.hapticEvent {
            AVHaptics.perform(hapticEvent)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reaction.durationMilliseconds))
            guard aviReactionToken == token else { return }
            aviReaction = nil
        }
    }

    func showAviReactionForCurrentSongChange(identity: String) {
        let isSavedDiscoveredTrack = focusedStation.map {
            libraryStore.isSavedDiscoveredTrack(title: currentTrackTitle, artist: currentTrackArtist, station: $0)
        } ?? false
        let decision = ShellAviAutomaticReactionResolver.decision(
            identity: identity,
            lastIdentity: lastAutomaticAviReactionIdentity,
            lastReactionAt: lastAutomaticAviReactionAt,
            isNowPlayingFullPlayer: isNowPlayingFullPlayer,
            isFocusedStationActive: isFocusedStationActive,
            isPlaying: isPlaying,
            currentTrackFeedback: currentTrackFeedback,
            isSavedDiscoveredTrack: isSavedDiscoveredTrack
        )

        switch decision {
        case .reset:
            aviReaction = nil
            lastAutomaticAviReactionIdentity = ""
        case .none:
            break
        case .suppress(let identity):
            lastAutomaticAviReactionIdentity = identity
        case .show(let reaction, let identity, let at):
            lastAutomaticAviReactionIdentity = identity
            lastAutomaticAviReactionAt = at
            showAviReaction(reaction)
        }
    }

    func showAviReaction(for feedback: TuneAVStationFeedback) {
        switch feedback {
        case .liked:
            showAviReaction(.liked)
        case .notForMe:
            showAviReaction(.notForMe)
        case .disliked:
            showAviReaction(.disliked)
        }
    }

    func feedbackStatusBadge(_ feedback: TuneAVStationFeedback, size: CGFloat) -> some View {
        TuneAVFeedbackBadge(feedback: feedback, size: size)
    }

    func closeAviActions() {
        AVHaptics.perform(.closePanel)
        withAnimation(.snappy(duration: 0.2)) {
            applyAviTransientState(currentAviTransientState.closingActions())
        }
    }

    func openAviSearch(
        for station: Station,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        browserRouter.openTrackSearch(
            for: station,
            currentTrackArtist: currentTrackArtist,
            currentTrackTitle: currentTrackTitle,
            destination: destination,
            suffix: suffix
        )
    }

    func openAviArtistSearch() {
        browserRouter.openArtistSearch(currentTrackArtist: currentTrackArtist)
    }

    func openAviStationSearch(for station: Station) {
        browserRouter.openStationSearch(for: station)
    }

    func openExternalSearch(
        query: String,
        destination: TuneAVExternalSearchURL.Destination = .web
    ) {
        browserRouter.openExternalSearch(query: query, destination: destination)
    }

    func toggleDiscoverySaved(_ discovery: DiscoveredTrack) {
        ShellDiscoverySaveCoordinator.toggleDiscoverySaved(
            discovery,
            savedDiscoveriesCount: libraryStore.savedDiscoveriesCount,
            limitState: { currentUsage in
                accessController.limitState(for: .savedTracks, currentUsage: currentUsage)
            },
            toggleSaved: { discovery, limit in
                let wasSaved = discovery.isMarkedInteresting
                let didToggle = libraryStore.toggleDiscoverySaved(discovery, savedLimit: limit)
                if didToggle {
                    AVHaptics.perform(wasSaved ? .undo : .affirm)
                }
                return didToggle
            },
            presentUpgrade: { currentUsage in
                accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: currentUsage)
            }
        )
    }

    @discardableResult
    func saveAviCurrentDiscovery(for station: Station) -> Bool {
        guard !ShellCurrentDiscoveryCoordinator.shouldSaveStationFavorite(
            title: currentTrackTitle,
            artist: currentTrackArtist
        ) else {
            showAviReaction(.liked)
            toggleFavorite(station)
            return true
        }

        let state = accessController.limitState(
            for: .savedTracks,
            currentUsage: libraryStore.savedDiscoveriesCount
        )

        let isAlreadySaved = isCurrentTrackSaved(for: station)
        if !ShellCurrentDiscoveryCoordinator.canToggleTrack(
            isAlreadySaved: isAlreadySaved,
            canMarkInteresting: libraryStore.canMarkTrackInteresting(
                title: currentTrackTitle,
                artist: currentTrackArtist,
                station: station,
                limit: state.limit
            )
        ) {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return false
        }

        let didToggle = libraryStore.toggleDiscoveredTrackSaved(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            station: station,
            artworkURL: currentTrackArtworkURL,
            savedLimit: state.limit,
            discoveryLimit: accessController.limits.discoveredTracks
        )
        guard didToggle else {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return false
        }

        showAviReaction(
            ShellCurrentDiscoveryCoordinator.reactionAfterToggle(
                isSaved: isCurrentTrackSaved(for: station)
            )
        )
        return true
    }

    func isCurrentTrackSaved(for station: Station) -> Bool {
        libraryStore.isSavedDiscoveredTrack(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            station: station
        )
    }

    func currentTrackSaveActionTitle(for station: Station) -> String {
        isCurrentTrackSaved(for: station) ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort")
    }

    func stationSaveActionTitle(for station: Station) -> String {
        libraryStore.isFavorite(station) ? L10n.string("player.station.unsave") : L10n.string("player.station.save")
    }

    func stationSaveActionSystemImage(for station: Station) -> String {
        libraryStore.isFavorite(station) ? "bookmark.slash" : "bookmark"
    }

    func focusedSignalActions(for station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("shell.avi.can"))
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(TuneAVTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    AVAviActionChip(title: isFocusedStationActive ? L10n.string("player.discovery.lyricsShort") : L10n.string("shell.avi.actions.publicInfo"), systemImage: isFocusedStationActive ? "text.quote" : "info.circle") {
                        if isFocusedStationActive && hasCurrentSongContext {
                            openAviSearch(for: station, destination: .web, suffix: "lyrics")
                        } else {
                            openAviStationSearch(for: station)
                        }
                    }
                    AVAviActionChip(title: L10n.string("shell.avi.actions.historyShort"), systemImage: "clock.arrow.circlepath") {
                        showStationDetails(station, [station], .history)
                    }
                    AVAviActionChip(title: L10n.string("player.avi.action.web"), systemImage: "safari") {
                        browserRouter.openStationWebsiteOrSearch(station, closesAviActions: true)
                    }
                    AVAviActionChip(title: L10n.string("shell.avi.actions.findRelatedRadios"), systemImage: "sparkles") {
                        showRelatedStations(for: station)
                    }
                    if isFocusedStationActive {
                        AVAviActionChip(title: L10n.string("shell.accessibility.closeSignal"), systemImage: "power") {
                            stopPlayback()
                        }
                    }
                    AVAviActionChip(title: L10n.string("common.more"), systemImage: "ellipsis") {
                        withAnimation(.snappy(duration: 0.22)) {
                            applyAviTransientState(currentAviTransientState.openingActions())
                        }
                    }
                }
            }
        }
    }

    var aviPrimaryLine: String {
        guard focusedStation != nil || currentStation != nil else {
            return L10n.string("shell.avi.detail.ready")
        }
        if isFocusedStationActive, currentTrackTitle != nil {
            return L10n.string("shell.avi.primary.reacting")
        }
        return isFocusedStationActive ? L10n.string("shell.avi.primary.reading") : L10n.string("player.avi.detail.neutral")
    }

    var primaryFocusedActionTitle: String {
        guard !isLoading else { return L10n.string("audio.status.loading") }
        guard isFocusedStationActive else { return L10n.string("player.control.play") }
        return isPlaying ? L10n.string("player.control.pause") : L10n.string("player.control.listen")
    }

    var primaryFocusedActionIcon: String {
        guard !isLoading else { return "hourglass" }
        guard isFocusedStationActive else { return "play.fill" }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    func listeningControlButton(
        systemImage: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .frame(width: 52, height: 52)
                .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: systemImage))
        .accessibilityIdentifier(accessibilityIdentifier ?? systemImage)
    }

    func accessibilityLabel(for systemImage: String) -> String {
        switch systemImage {
        case "stop.fill": return L10n.string("shell.accessibility.stop")
        case "power": return L10n.string("shell.accessibility.closeSignal")
        case "backward.fill": return L10n.string("player.control.previous")
        case "forward.fill": return L10n.string("player.control.next")
        default: return systemImage
        }
    }

    @ViewBuilder
    var relatedStationsPanel: some View {
        if let relatedStationContext {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("shell.avi.related.title"))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)

                        Text(L10n.string("shell.avi.related.subtitle", relatedStationContext.baseStation.name))
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isLoadingRelatedStations {
                        ProgressView()
                            .tint(TuneAVTheme.highlight)
                    }
                }

                if relatedStationResults.isEmpty && !isLoadingRelatedStations {
                    Text(L10n.string("shell.avi.related.empty"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        ForEach(relatedStationResults.prefix(5), id: \.station.id) { result in
                            AviRelatedStationRow(
                                station: result.station,
                                reason: result.reason,
                                playAction: {
                                    playStation(result.station, relatedStationResults.map(\.station))
                                },
                                detailsAction: {
                                    showStationDetails(result.station, relatedStationResults.map(\.station), .about)
                                }
                            )
                        }
                    }
                }
            }
            .padding(18)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.related.card")
        }
    }

    @ViewBuilder
    var recommendationPanel: some View {
        if let recommendation = topRecommendation {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        StationThumbnailView(
                            station: recommendation.station,
                            size: 62,
                            animationOverlay: .none,
                            isAnimationActive: false
                        )

                        if let feedback = stationFeedback[recommendation.station.id] {
                            feedbackStatusBadge(feedback, size: 24)
                                .offset(x: -5, y: -5)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("shell.avi.recommendation.title"))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)

                        Text(recommendation.station.name)
                            .font(.system(size: 19, weight: .black))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        Text(recommendation.reason)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button {
                        playStation(recommendation.station, recommendationQueue)
                    } label: {
                        Label(L10n.string("shell.avi.recommendation.play"), systemImage: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("avi.recommendation.play")

                    Button {
                        showStationDetails(recommendation.station, recommendationQueue, .about)
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 48, height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TuneAVTheme.highlight)
                    .background(TuneAVTheme.highlight.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(L10n.string("shell.avi.recommendation.details"))
                    .accessibilityIdentifier("avi.recommendation.details")
                }

                StationFeedbackControl(
                    feedbackIdentity: "station:\(recommendation.station.id)",
                    selectedFeedback: stationFeedback[recommendation.station.id],
                    selectFeedback: { feedback in
                        let nextFeedback = stationFeedback[recommendation.station.id] == feedback ? nil : feedback
                        setStationFeedback(recommendation.station, nextFeedback)
                    },
                    clearFeedback: {
                        setStationFeedback(recommendation.station, nil)
                    }
                )
                .padding(.top, 2)

                if !secondaryRecommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("shell.avi.recommendation.nextTitle"))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TuneAVTheme.textPrimary)

                        ForEach(secondaryRecommendations, id: \.station.id) { recommendation in
                            AviRecommendationRow(
                                station: recommendation.station,
                                reason: recommendation.reason,
                                selectedFeedback: stationFeedback[recommendation.station.id],
                                playAction: {
                                    playStation(recommendation.station, recommendationQueue)
                                },
                                feedbackAction: { feedback in
                                    let nextFeedback = stationFeedback[recommendation.station.id] == feedback ? nil : feedback
                                    setStationFeedback(recommendation.station, nextFeedback)
                                },
                                clearFeedback: {
                                    setStationFeedback(recommendation.station, nil)
                                },
                                detailsAction: {
                                    showStationDetails(recommendation.station, recommendationQueue, .about)
                                }
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .background(TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
            }
            .accessibilityIdentifier("avi.recommendation.card")
        }
    }
}
