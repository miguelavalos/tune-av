import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AppShellView {
    func playStation(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .singleStation,
        queue: [Station]? = nil
    ) {
        switch cellularPlaybackGateDecision {
        case .playImmediately:
            playStationAfterCellularCheck(station, queueSource: queueSource, queue: queue)
        case .requestConfirmation:
            pendingCellularPlayback = PendingPlayback(station: station, queueSource: queueSource, queue: queue)
        }
    }

    var cellularPlaybackGateDecision: ShellCellularPlaybackGateDecision {
        ShellCellularPlaybackGate.decision(
            warnBeforeCellularPlayback: libraryStore.settings.warnBeforeCellularPlayback,
            currentNetworkIsExpensive: audioPlayer.currentNetworkIsExpensive
        )
    }

    func playStationAfterCellularCheck(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .singleStation,
        queue: [Station]? = nil
    ) {
        let selection = ShellPlaybackQueueBuilder.playbackSelection(
            station: station,
            queueSource: queueSource,
            queue: queue,
            enrichStation: enrichedStation(_:),
            enrichStations: enrichedStations(_:)
        )
        AVHaptics.perform(.primaryAction)
        audioPlayer.play(station: selection.station, queue: selection.queue)
        beginListeningSession(for: selection.station, source: selection.queue.source)
        accessController.noteListeningDayForUpgradeMoment()
    }

    func requestStopPlaybackConfirmation() {
        guard audioPlayer.currentStation != nil else { return }
        isConfirmingStopPlayback = true
    }

    func stopPlaybackAndCloseSignal() {
        AVHaptics.perform(.stopAction)
        audioPlayer.stopAndClearCurrentStation()
        closeFocusedAviDetail(fallbackTab: .home)
    }

    func togglePlaybackWithHaptic() {
        AVHaptics.perform(.primaryAction)
        audioPlayer.togglePlayback()
    }

    func playPreviousInQueueWithHaptic() {
        AVHaptics.perform(.step)
        audioPlayer.playPreviousInQueue()
    }

    func playNextInQueueWithHaptic() {
        AVHaptics.perform(.step)
        audioPlayer.playNextInQueue()
    }

    func beginListeningSession(for station: Station, source: AudioPlayerService.PlaybackQueue.Source) {
        let endedSession = ShellListeningSessionCoordinator.begin(
            session: &listeningSession,
            station: station,
            source: source
        )
        if let endedSession {
            recordListeningSession(endedSession, endedReason: .stationChanged)
        }
    }

    func handlePlaybackStatusChange(
        from oldStatus: AudioPlayerService.PlaybackStatus,
        to newStatus: AudioPlayerService.PlaybackStatus
    ) {
        switch newStatus {
        case .paused:
            flushListeningSession(endedReason: .paused)
        case .idle:
            flushListeningSession(endedReason: .appClosed)
        case .failed:
            flushListeningSession(endedReason: .streamError)
            autoSkipUnstableStreamIfNeeded()
        case .playing:
            if let station = audioPlayer.currentStation {
                recordConfirmedPlaybackIfNeeded(station)
            }

            if let station = audioPlayer.currentStation {
                ShellListeningSessionCoordinator.resumeIfNeeded(
                    session: &listeningSession,
                    station: station,
                    source: audioPlayer.playbackQueue.source
                )
            }
        case .loading:
            break
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if ShellListeningSessionLifecycle.shouldFlushPendingSessions(scenePhase: phase) {
            flushListeningSession(endedReason: .appBackgrounded)
            libraryStore.flushPendingListeningSessions()
            return
        }

        guard ShellListeningSessionLifecycle.shouldResumeActiveSession(
            scenePhase: phase,
            isPlaying: audioPlayer.status == .playing,
            hasCurrentStation: audioPlayer.currentStation != nil
        ),
            let station = audioPlayer.currentStation
        else {
            return
        }

        ShellListeningSessionCoordinator.resumeIfNeeded(
            session: &listeningSession,
            station: station,
            source: audioPlayer.playbackQueue.source
        )
    }

    func recordConfirmedPlaybackIfNeeded(_ station: Station) {
        guard lastConfirmedPlaybackStationID != station.id else { return }
        libraryStore.recordPlayback(of: enrichedStation(station), recentLimit: accessController.limits.recentStations)
        stationPlayLog = stationPlayLog.recording(station.id)
        stationPlayLog.save()
        lastConfirmedPlaybackStationID = station.id
    }

    func autoSkipUnstableStreamIfNeeded() {
        guard libraryStore.settings.autoSkipUnstableStreams else { return }
        guard audioPlayer.shouldSuggestFailureRecovery, audioPlayer.canCyclePlaybackQueue else { return }
        let skippedStation = audioPlayer.currentStation
        guard audioPlayer.playNextStableInQueue() else {
            audioPlayer.showAutoSkipBlockedNotice()
            return
        }
        if let skippedStation {
            audioPlayer.showAutoSkipNotice(for: skippedStation)
        }
        if let station = audioPlayer.currentStation {
            beginListeningSession(for: station, source: audioPlayer.playbackQueue.source)
        }
    }

    func flushListeningSession(endedReason: TuneAVListeningEndedReason) {
        guard let session = ShellListeningSessionCoordinator.flush(session: &listeningSession) else { return }
        recordListeningSession(session, endedReason: endedReason)
    }

    func recordListeningSession(_ session: ActiveListeningSession, endedReason: TuneAVListeningEndedReason) {
        libraryStore.recordListeningSession(
            station: session.station,
            startedAt: session.startedAt,
            endedAt: .now,
            source: session.source,
            endedReason: endedReason,
            trackDetectedCount: session.trackKeys.count
        )
    }

    func toggleFavorite(_ station: Station) {
        let resolvedStation = enrichedStation(station)

        if libraryStore.isFavorite(resolvedStation) {
            AVHaptics.perform(.undo)
            libraryStore.toggleFavorite(for: resolvedStation)
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

        AVHaptics.perform(.affirm)
        libraryStore.toggleFavorite(for: resolvedStation)
    }

    func setStationFeedbackWithHaptic(_ station: Station, feedback: TuneAVStationFeedback?) {
        guard libraryStore.stationFeedback[station.id] != feedback else { return }
        libraryStore.setFeedback(feedback, for: station)
        AVHaptics.perform(stationFeedbackHapticEvent(for: feedback))
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
}
