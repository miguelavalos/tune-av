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

    static let navigationTabs: [AppShellTab] = [.home, .search, .library]

    var librarySegment: LibrarySegment? {
        switch self {
        case .library:
            return .radios
        case .music:
            return .songs
        case .home, .search, .avi, .profile:
            return nil
        }
    }

    var navigationTab: AppShellTab {
        librarySegment == nil ? self : .library
    }

    func selectingNavigationTab(_ tab: AppShellTab, lastLibraryTab: AppShellTab) -> AppShellTab {
        guard tab.librarySegment != nil else { return tab }
        if librarySegment != nil {
            return self
        }
        return lastLibraryTab.librarySegment == nil ? .library : lastLibraryTab
    }

    var navigationTitle: String {
        switch navigationTab {
        case .home:
            return L10n.string("tab.home")
        case .search:
            return L10n.string("tab.explore")
        case .library, .music:
            return L10n.string("tab.libraryHub")
        case .avi:
            return "Avi"
        case .profile:
            return L10n.string("profile.settingsScreen.title")
        }
    }

    var navigationSystemImage: String {
        switch navigationTab {
        case .home:
            return "house.fill"
        case .search:
            return "safari.fill"
        case .library, .music:
            return "books.vertical.fill"
        case .avi:
            return "sparkles"
        case .profile:
            return "gearshape.fill"
        }
    }

    var navigationAccessibilityIdentifier: String {
        switch navigationTab {
        case .home:
            return "shell.tab.home"
        case .search:
            return "shell.tab.explore"
        case .library, .music:
            return "shell.tab.library"
        case .avi:
            return "tune.sidebar.avi"
        case .profile:
            return "tune.sidebar.profile"
        }
    }
}

enum LibrarySegment: Hashable, CaseIterable {
    case radios
    case songs

    var tab: AppShellTab {
        switch self {
        case .radios:
            return .library
        case .songs:
            return .music
        }
    }

    var title: String {
        switch self {
        case .radios:
            return L10n.string("shell.libraryHub.segment.radios")
        case .songs:
            return L10n.string("shell.libraryHub.segment.songs")
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .radios:
            return "library.segment.radios"
        case .songs:
            return "library.segment.songs"
        }
    }
}
