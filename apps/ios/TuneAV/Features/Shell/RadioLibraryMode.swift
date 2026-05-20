import Foundation

enum RadioLibraryMode: String, CaseIterable, Identifiable {
    case saved
    case recent
    case tuned
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved:
            return L10n.string("shell.library.mode.saved")
        case .recent:
            return L10n.string("shell.library.mode.recent")
        case .tuned:
            return L10n.string("shell.library.overview.tuned")
        case .music:
            return L10n.string("shell.library.overview.musicStations")
        }
    }

    var subtitle: String {
        switch self {
        case .saved:
            return L10n.string("shell.library.favorites.subtitle")
        case .recent:
            return L10n.string("shell.library.recents.subtitle")
        case .tuned:
            return L10n.string("shell.avi.signals.feedback.title")
        case .music:
            return L10n.string("shell.library.musicStations.subtitle")
        }
    }

    var emptyTitle: String {
        switch self {
        case .saved:
            return L10n.string("shell.library.favorites.empty")
        case .recent:
            return L10n.string("shell.library.recents.empty")
        case .tuned:
            return L10n.string("shell.library.overview.empty")
        case .music:
            return L10n.string("shell.library.overview.empty")
        }
    }

    var emptyDetail: String {
        switch self {
        case .saved:
            return L10n.string("shell.library.favorites.empty.detail")
        case .recent:
            return L10n.string("shell.library.recents.empty.detail")
        case .tuned, .music:
            return L10n.string("shell.library.overview.empty.detail")
        }
    }
}
