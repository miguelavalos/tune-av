import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    var hasCurrentSongContext: Bool {
        guard let station = focusedStation ?? currentStation else { return false }
        return TuneAVDisplayMetadata.plausibleTitle(currentTrackTitle, stationName: station.name) != nil &&
            TuneAVDisplayMetadata.plausibleArtist(currentTrackArtist, stationName: station.name) != nil
    }

    var currentSongIdentity: String {
        [
            currentTrackArtist ?? "",
            currentTrackTitle ?? "",
            currentTrackArtworkURL?.absoluteString ?? ""
        ].joined(separator: "|")
    }

    var currentTrackFeedback: TuneAVStationFeedback? {
        libraryStore.feedbackForDiscoveredTrack(
            title: currentTrackTitle,
            artist: currentTrackArtist
        )
    }

    var currentAviTransientState: ShellAviTransientState {
        ShellAviTransientState(
            isShowingActions: isShowingAviActions,
            isShowingMoreActions: isShowingMoreAviActions,
            isShowingFeedbackPicker: isShowingFeedbackPicker,
            actionsPage: aviActionsPage,
            isEditingRadioFeedback: isEditingRadioFeedback,
            isShowingArtworkZoom: isShowingArtworkZoom
        )
    }

    func applyAviTransientState(_ state: ShellAviTransientState) {
        isShowingAviActions = state.isShowingActions
        isShowingMoreAviActions = state.isShowingMoreActions
        isShowingFeedbackPicker = state.isShowingFeedbackPicker
        aviActionsPage = state.actionsPage
        isEditingRadioFeedback = state.isEditingRadioFeedback
        isShowingArtworkZoom = state.isShowingArtworkZoom
    }

    func resetTransientAviUI() {
        withAnimation(.snappy(duration: 0.18)) {
            applyAviTransientState(currentAviTransientState.resettingAll())
        }
    }

    func focusedPrimaryFeedback(for station: Station) -> TuneAVStationFeedback? {
        if aviFeedbackTarget(for: station).usesTrackFeedback {
            return currentTrackFeedback
        }
        return stationFeedback[station.id]
    }

    func focusedPrimaryFeedbackIdentity(for station: Station) -> String {
        aviFeedbackTarget(for: station).identity
    }

    func setFocusedPrimaryFeedback(_ feedback: TuneAVStationFeedback?, for station: Station) {
        if aviFeedbackTarget(for: station).usesTrackFeedback {
            setCurrentTrackFeedback(feedback)
        } else {
            setStationFeedback(station, feedback)
        }
    }

    func aviFeedbackTarget(for station: Station, isEditingRadioFeedback: Bool = false) -> ShellAviFeedbackTarget {
        ShellAviFeedbackResolver.primaryTarget(
            isNowPlayingFullPlayer: isNowPlayingFullPlayer,
            hasCurrentSongContext: hasCurrentSongContext,
            isEditingRadioFeedback: isEditingRadioFeedback,
            stationID: station.id,
            currentSongIdentity: currentSongIdentity
        )
    }

    func setCurrentTrackFeedback(_ feedback: TuneAVStationFeedback?) {
        guard currentTrackFeedback != feedback else { return }
        libraryStore.setFeedbackForDiscoveredTrack(
            feedback,
            title: currentTrackTitle,
            artist: currentTrackArtist,
            stationID: currentStation?.id
        )
        AVHaptics.perform(stationFeedbackHapticEvent(for: feedback))
    }
}
