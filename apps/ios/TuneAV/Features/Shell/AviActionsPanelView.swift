import AVAviFoundation
import SwiftUI

struct AviActionsPanelView: View {
    let state: ShellAviActionsPanelState
    let showsStationDetailAction: Bool
    let showsCloseSignalAction: Bool
    let previousPage: () -> Void
    let nextPage: () -> Void
    let close: () -> Void
    let searchLyrics: () -> Void
    let searchYouTube: () -> Void
    let searchAppleMusic: () -> Void
    let searchArtist: () -> Void
    let searchPublicInfo: () -> Void
    let showRadioDetails: () -> Void
    let showHistory: () -> Void
    let openWebsite: () -> Void
    let findRelatedRadios: () -> Void
    let closeSignal: () -> Void

    var body: some View {
        AVAviActionPanel(
            title: state.title,
            pageLabel: state.pageLabel,
            canGoPrevious: state.canGoPrevious,
            canGoNext: state.canGoNext,
            previousAccessibilityLabel: L10n.string("shell.avi.actions.previousOptions"),
            nextAccessibilityLabel: L10n.string("shell.avi.actions.moreOptions"),
            closeAccessibilityLabel: L10n.string("shell.avi.actions.closeOptions"),
            previousPage: previousPage,
            nextPage: nextPage,
            close: close
        ) {
            Group {
                if state.showsSongActions {
                    songActions
                } else {
                    stationActions
                }
            }
        } footer: {
            if showsCloseSignalAction {
                AVAviCloseSignalPanelButton(title: L10n.string("shell.accessibility.closeSignal"), action: closeSignal)
            } else {
                EmptyView()
            }
        }
    }

    private var songActions: some View {
        Group {
            AVAviCommandButton(title: L10n.string("shell.avi.actions.searchLyrics"), systemImage: "text.quote", accessibilityIdentifier: "avi.actions.lyrics", action: searchLyrics)
            AVAviCommandButton(title: L10n.string("shell.avi.actions.searchYouTube"), systemImage: "play.rectangle", accessibilityIdentifier: "avi.actions.youtube", action: searchYouTube)
            AVAviCommandButton(title: L10n.string("shell.avi.actions.searchAppleMusic"), systemImage: "music.note", accessibilityIdentifier: "avi.actions.appleMusic", action: searchAppleMusic)
            AVAviCommandButton(title: L10n.string("shell.avi.actions.searchArtist"), systemImage: "person.crop.circle", accessibilityIdentifier: "avi.actions.artist", action: searchArtist)
        }
    }

    private var stationActions: some View {
        Group {
            AVAviCommandButton(title: L10n.string("shell.avi.actions.searchPublicInfo"), systemImage: "info.circle", accessibilityIdentifier: "avi.actions.publicInfo", action: searchPublicInfo)
            if showsStationDetailAction {
                AVAviCommandButton(title: L10n.string("shell.avi.recommendation.details"), systemImage: "dot.radiowaves.left.and.right", accessibilityIdentifier: "avi.actions.radioDetails", action: showRadioDetails)
            }
            AVAviCommandButton(title: L10n.string("shell.avi.actions.history"), systemImage: "clock.arrow.circlepath", accessibilityIdentifier: "avi.actions.history", action: showHistory)
            AVAviCommandButton(title: L10n.string("shell.avi.actions.openWebsite"), systemImage: "safari", accessibilityIdentifier: "avi.actions.web", action: openWebsite)
            AVAviCommandButton(title: L10n.string("shell.avi.actions.findRelatedRadios"), systemImage: "sparkles", accessibilityIdentifier: "avi.actions.relatedRadios", action: findRelatedRadios)
        }
    }
}
