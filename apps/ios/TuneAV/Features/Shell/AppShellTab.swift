import Foundation

enum AppShellTab: Equatable, Hashable {
    case home
    case search
    case avi
    case library
    case music
    case profile

    init(_ preferredTab: LaunchContext.Tab?, preferredSearchQuery: String?) {
        switch preferredTab {
        case .home:
            self = .home
        case .search:
            self = .search
        case .library:
            self = .library
        case .music:
            self = .music
        case .settings:
            self = .profile
        case .player, .none:
            self = preferredSearchQuery == nil ? .home : .search
        }
    }
}
