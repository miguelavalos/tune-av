import Foundation

enum ShellLaunchBootstrapAction: Equatable {
    case selectTab(AppShellTab)
    case openPlayer(useDemoStation: Bool)
    case restoreLastOpenedStation
}

enum ShellLaunchBootstrapRoute: Equatable {
    case selectTab(AppShellTab)
    case openPlayer(Station)
    case restoreLastOpenedStation
}

enum ShellLaunchBootstrapRouter {
    static func routes(
        for actions: [ShellLaunchBootstrapAction],
        lastPlayedStation: Station?,
        demoStation: Station?
    ) -> [ShellLaunchBootstrapRoute] {
        actions.compactMap { action in
            route(for: action, lastPlayedStation: lastPlayedStation, demoStation: demoStation)
        }
    }

    private static func route(
        for action: ShellLaunchBootstrapAction,
        lastPlayedStation: Station?,
        demoStation: Station?
    ) -> ShellLaunchBootstrapRoute? {
        switch action {
        case let .selectTab(tab):
            return .selectTab(tab)
        case let .openPlayer(useDemoStation):
            guard let station = useDemoStation ? demoStation : lastPlayedStation else { return nil }
            return .openPlayer(station)
        case .restoreLastOpenedStation:
            return .restoreLastOpenedStation
        }
    }
}

enum ShellLaunchBootstrapPlanner {
    static func actions(
        preferredTab: LaunchContext.Tab?,
        hasPreferredSearchQuery: Bool,
        shouldRestoreLastOpenedStation: Bool,
        hasLastPlayedStation: Bool,
        hasDemoStation: Bool
    ) -> [ShellLaunchBootstrapAction] {
        if let preferredTab {
            return actions(
                for: preferredTab,
                hasLastPlayedStation: hasLastPlayedStation,
                hasDemoStation: hasDemoStation
            )
        }

        if hasPreferredSearchQuery {
            return [.selectTab(.search)]
        }

        if shouldRestoreLastOpenedStation {
            return [.restoreLastOpenedStation]
        }

        return []
    }

    private static func actions(
        for preferredTab: LaunchContext.Tab,
        hasLastPlayedStation: Bool,
        hasDemoStation: Bool
    ) -> [ShellLaunchBootstrapAction] {
        switch preferredTab {
        case .home:
            return [.selectTab(.home)]
        case .search:
            return [.selectTab(.search)]
        case .library:
            return [.selectTab(.library)]
        case .music:
            return [.selectTab(.music)]
        case .player:
            if hasLastPlayedStation {
                return [.openPlayer(useDemoStation: false)]
            }
            return hasDemoStation ? [.openPlayer(useDemoStation: true)] : []
        case .settings:
            return [.selectTab(.profile)]
        }
    }
}
