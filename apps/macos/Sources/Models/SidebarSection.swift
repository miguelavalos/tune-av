import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case home
    case search
    case library
    case music
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return L10n.string("tab.home")
        case .search:
            return L10n.string("tab.search")
        case .library:
            return L10n.string("tab.library")
        case .music:
            return L10n.string("tab.music")
        case .profile:
            return L10n.string("tab.profile")
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "dot.radiowaves.left.and.right"
        case .search:
            return "magnifyingglass"
        case .library:
            return "books.vertical"
        case .music:
            return "music.note.list"
        case .profile:
            return "person.crop.circle"
        }
    }
}
