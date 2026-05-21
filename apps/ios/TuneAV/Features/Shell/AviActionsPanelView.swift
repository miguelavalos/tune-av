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
                AviCloseSignalPanelButton(action: closeSignal)
            } else {
                EmptyView()
            }
        }
    }

    private var songActions: some View {
        Group {
            AviCommandButton(title: L10n.string("shell.avi.actions.searchLyrics"), systemImage: "text.quote", accessibilityIdentifier: "avi.actions.lyrics", action: searchLyrics)
            AviCommandButton(title: L10n.string("shell.avi.actions.searchYouTube"), systemImage: "play.rectangle", accessibilityIdentifier: "avi.actions.youtube", action: searchYouTube)
            AviCommandButton(title: L10n.string("shell.avi.actions.searchAppleMusic"), systemImage: "music.note", accessibilityIdentifier: "avi.actions.appleMusic", action: searchAppleMusic)
            AviCommandButton(title: L10n.string("shell.avi.actions.searchArtist"), systemImage: "person.crop.circle", accessibilityIdentifier: "avi.actions.artist", action: searchArtist)
        }
    }

    private var stationActions: some View {
        Group {
            AviCommandButton(title: L10n.string("shell.avi.actions.searchPublicInfo"), systemImage: "info.circle", accessibilityIdentifier: "avi.actions.publicInfo", action: searchPublicInfo)
            if showsStationDetailAction {
                AviCommandButton(title: L10n.string("shell.avi.recommendation.details"), systemImage: "dot.radiowaves.left.and.right", accessibilityIdentifier: "avi.actions.radioDetails", action: showRadioDetails)
            }
            AviCommandButton(title: L10n.string("shell.avi.actions.history"), systemImage: "clock.arrow.circlepath", accessibilityIdentifier: "avi.actions.history", action: showHistory)
            AviCommandButton(title: L10n.string("shell.avi.actions.openWebsite"), systemImage: "safari", accessibilityIdentifier: "avi.actions.web", action: openWebsite)
            AviCommandButton(title: L10n.string("shell.avi.actions.findRelatedRadios"), systemImage: "sparkles", accessibilityIdentifier: "avi.actions.relatedRadios", action: findRelatedRadios)
        }
    }

}

struct AviCommandButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        AVAviCommandButton(
            title: title,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }
}

struct AviCloseSignalPanelButton: View {
    let action: () -> Void

    var body: some View {
        AVAviCloseSignalPanelButton(title: L10n.string("shell.accessibility.closeSignal"), action: action)
    }
}
