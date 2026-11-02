import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AppShellView {
    func showStationDetails(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source = .singleStation,
        queue: [Station]? = nil,
        returnRadioMode: RadioLibraryMode? = nil,
        returnRadioOverview: Bool? = nil,
        initialSection: StationDetailSection = .about
    ) {
        let plan = ShellStationDetailOpenPlanner.detailPlan(
            station: station,
            queueSource: queueSource,
            queue: queue,
            returnRadioMode: returnRadioMode,
            returnRadioOverview: returnRadioOverview,
            initialSection: initialSection,
            presentation: LastOpenedStationPresentation.detail.rawValue,
            builder: aviStationDetailBuilder
        )
        applyStationDetailOpenPlan(plan)
    }

    func openNowPlayingFullPlayer(_ station: Station) {
        let plan = ShellStationDetailOpenPlanner.fullPlayerPlan(
            station: station,
            presentation: LastOpenedStationPresentation.player.rawValue,
            builder: aviStationDetailBuilder
        )
        applyStationDetailOpenPlan(plan)
    }

    func applyStationDetailOpenPlan(_ plan: ShellStationDetailOpenPlan) {
        AVHaptics.perform(.openPanel)
        captureAviReturnContext(
            radioMode: plan.returnRadioMode,
            radioOverview: plan.returnRadioOverview
        )
        if plan.clearsMusicDetail {
            selectedMusicAviDetail = nil
        }
        applyAviStationOpenSelection(plan.selection)
    }

    func openContextualAvi() {
        let plan = ShellStationDetailOpenPlanner.contextualAviPlan(
            currentStation: audioPlayer.currentStation,
            currentQueueSource: audioPlayer.playbackQueue.source,
            currentQueue: currentPlaybackQueue(fallbackStation:),
            presentation: LastOpenedStationPresentation.player.rawValue,
            builder: aviStationDetailBuilder
        )
        applyContextualAviOpenPlan(plan)
    }

    func applyContextualAviOpenPlan(_ plan: ShellContextualAviOpenPlan) {
        AVHaptics.perform(.openPanel)
        if plan.capturesReturnContext {
            captureAviReturnContext()
        }
        if plan.clearsStationDetail {
            selectedStationDetail = nil
        }
        if plan.clearsMusicDetail {
            selectedMusicAviDetail = nil
        }
        isAviNowPlayingFullPlayer = plan.isFullPlayer

        if let selection = plan.selection {
            applyAviStationOpenSelection(selection)
        }

        selectedTab = plan.selectedTab
    }

    func openDiscoveryInfo(_ discovery: DiscoveredTrack, returnMusicMode: MusicContentMode? = nil) {
        openMusicAviDetail(
            AviMusicDetailCoordinator.track(
                discovery,
                returnMusicMode: returnMusicMode
            )
        )
    }

    func openMusicAviDetail(_ selection: AviMusicDetailSelection) {
        let plan = AviMusicDetailCoordinator.openPlan(for: selection)
        applyMusicAviDetailOpenPlan(plan)
    }

    func applyMusicAviDetailOpenPlan(_ plan: AviMusicDetailOpenPlan) {
        AVHaptics.perform(.openPanel)
        captureAviReturnContext(
            musicMode: plan.returnMusicMode,
            musicOverview: plan.returnMusicOverview
        )
        if plan.clearsStationDetail {
            selectedStationDetail = nil
        }
        isAviNowPlayingFullPlayer = plan.isNowPlayingFullPlayer
        selectedMusicAviDetail = plan.detail
        selectedTab = plan.selectedTab
    }

    func openDiscoveryStationInfo(_ discovery: DiscoveredTrack) {
        guard let station = libraryStore.station(for: discovery.stationID) else { return }

        showStationDetails(
            station,
            queueSource: .libraryRecents,
            queue: enrichedRecentStations,
            initialSection: .history
        )
    }

    func openArtistInfo(_ summary: DiscoveryArtistSummary, returnMusicMode: MusicContentMode? = nil) {
        openMusicAviDetail(
            AviMusicDetailCoordinator.artist(
                summary,
                returnMusicMode: returnMusicMode
            )
        )
    }

    func closeFocusedAviDetail(fallbackTab: AppShellTab? = nil) {
        let plan = aviReturnCoordinator.closeFocusedDetailPlan(fallbackTab: fallbackTab)
        applyAviCloseFocusedDetailPlan(plan)
    }

    func applyAviCloseFocusedDetailPlan(_ plan: AviCloseFocusedDetailPlan) {
        AVHaptics.perform(.closePanel)
        if plan.clearsStationDetail {
            selectedStationDetail = nil
        }
        if plan.clearsMusicDetail {
            selectedMusicAviDetail = nil
        }
        isAviNowPlayingFullPlayer = plan.isNowPlayingFullPlayer
        if plan.clearsOpenedStationPresentation {
            libraryStore.clearOpenedStationPresentation()
        }
        restoreAviReturnState(plan)
        if let selectedTab = plan.selectedTab {
            self.selectedTab = selectedTab
        }
    }

    func captureAviReturnContext(
        radioMode: RadioLibraryMode? = nil,
        radioOverview: Bool? = nil,
        musicMode: MusicContentMode? = nil,
        musicOverview: Bool? = nil
    ) {
        aviReturnCoordinator.capture(
            selectedTab: selectedTab,
            radioMode: radioMode,
            radioOverview: radioOverview,
            musicMode: musicMode,
            musicOverview: musicOverview
        )
    }

    func restoreAviReturnState(_ plan: AviCloseFocusedDetailPlan) {
        if let request = plan.radioReturnRequest {
            applyRadioReturnRequest(request)
        } else if let request = plan.musicReturnRequest {
            applyMusicReturnRequest(request)
        }
    }

    func applyRadioReturnRequest(_ request: (mode: RadioLibraryMode?, overview: Bool?)) {
        requestedRadioMode = request.mode
        requestedRadioOverview = request.overview
    }

    func applyMusicReturnRequest(_ request: (mode: MusicContentMode?, overview: Bool?)) {
        requestedMusicMode = request.mode
        requestedMusicOverview = request.overview
    }

    func currentPlaybackQueue(fallbackStation: Station) -> [Station] {
        aviStationDetailBuilder.playbackQueue(
            stations: audioPlayer.playbackQueue.stations,
            fallbackStation: fallbackStation
        )
    }

    @discardableResult
    func selectAviStationDetail(
        _ station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station]
    ) -> Station {
        let selection = aviStationDetailBuilder.selection(
            station: station,
            queueSource: queueSource,
            queue: queue
        )
        let resolvedStation = selection.resolvedStation
        applySelectedStationDetail(selection.detail, resolvedStation: resolvedStation)
        return resolvedStation
    }

    func applyAviStationOpenSelection(_ selection: AviStationOpenSelection) {
        applySelectedStationDetail(selection.detail, resolvedStation: selection.resolvedStation)
        libraryStore.rememberOpenedStation(selection.resolvedStation, presentation: selection.presentation)
        isAviNowPlayingFullPlayer = selection.isFullPlayer
        selectedTab = selection.selectedTab
    }

    func applySelectedStationDetail(_ detail: SelectedStationDetail, resolvedStation: Station) {
        selectedStationDetail = detail
        refreshSelectedStationEnrichmentIfNeeded(resolvedStation)
    }

    func syncAviActiveSignalIfNeeded(previousStationID: String?, currentStation: Station) {
        guard aviStationDetailBuilder.shouldSyncActiveSignal(
            selectedTab: selectedTab,
            isFullPlayer: isAviNowPlayingFullPlayer,
            previousStationID: previousStationID,
            selectedDetailStationID: selectedStationDetail?.station.id
        ) else { return }

        selectAviStationDetail(
            currentStation,
            queueSource: audioPlayer.playbackQueue.source,
            queue: currentPlaybackQueue(fallbackStation:)
        )
    }

    func openStationHistory(_ station: Station) {
        selectedStationDetail = nil
        musicHistoryStationFilter = station
        selectedTab = .music
    }

    func stationDiscoveries(for station: Station) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(libraryStore.discoveries)
            .filter { $0.stationID == station.id }
            .sorted { $0.playedAt > $1.playedAt }
    }
}
