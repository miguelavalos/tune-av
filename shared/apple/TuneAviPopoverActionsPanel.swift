import AVAviFoundation
import SwiftUI

struct TuneAviPopoverActionsPanel<Content: View>: View {
    var page = 0
    var pageCount = 1
    var previous: () -> Void = {}
    var next: () -> Void = {}
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        AVAviPopoverActionPanel(
            title: L10n.string("shell.avi.actions.ask"),
            pageLabel: L10n.string("shell.avi.actions.page", page + 1, pageCount),
            showsPagingControls: pageCount > 1,
            canGoPrevious: page > 0,
            canGoNext: page < pageCount - 1,
            previousAccessibilityLabel: L10n.string("shell.avi.actions.previousOptions"),
            nextAccessibilityLabel: L10n.string("shell.avi.actions.moreOptions"),
            closeAccessibilityLabel: L10n.string("shell.avi.actions.closeOptions"),
            previousPage: previous,
            nextPage: next,
            close: close
        ) {
            content()
        }
    }
}
