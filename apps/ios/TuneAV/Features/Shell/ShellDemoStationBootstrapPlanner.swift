import Foundation

enum ShellDemoStationBootstrapAction: Equatable {
    case seed(favorite: Bool)
    case play
}

enum ShellDemoStationBootstrapPlanner {
    static func actions(
        hasDemoStation: Bool,
        seedFavorite: Bool,
        currentStationID: String?,
        demoStationID: String?
    ) -> [ShellDemoStationBootstrapAction] {
        guard hasDemoStation else { return [] }

        var actions: [ShellDemoStationBootstrapAction] = [.seed(favorite: seedFavorite)]
        if currentStationID != demoStationID {
            actions.append(.play)
        }
        return actions
    }
}
