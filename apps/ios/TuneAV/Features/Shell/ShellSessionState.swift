import SwiftUI

struct ActiveListeningSession {
    let station: Station
    let startedAt: Date
    let source: String
    var trackKeys: Set<String>
}

func nextShellHeaderVisibility(currentOffset: CGFloat, previousOffset: inout CGFloat, currentVisibility: Bool) -> Bool {
    defer { previousOffset = currentOffset }

    if currentOffset > -18 {
        return true
    }

    let delta = currentOffset - previousOffset
    if delta < -10 {
        return false
    }
    if delta > 8 {
        return true
    }
    return currentVisibility
}
