import Foundation

enum ShellCellularPlaybackGateDecision: Equatable {
    case playImmediately
    case requestConfirmation
}

enum ShellCellularPlaybackGate {
    static func decision(
        warnBeforeCellularPlayback: Bool,
        currentNetworkIsExpensive: Bool
    ) -> ShellCellularPlaybackGateDecision {
        if warnBeforeCellularPlayback, currentNetworkIsExpensive {
            return .requestConfirmation
        }
        return .playImmediately
    }
}
