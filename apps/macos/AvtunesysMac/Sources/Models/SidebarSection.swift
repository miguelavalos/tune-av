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
            return "Home"
        case .search:
            return "Search"
        case .library:
            return "Library"
        case .music:
            return "Music"
        case .profile:
            return "Profile"
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
