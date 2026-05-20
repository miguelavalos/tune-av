import SwiftUI

struct ActiveListeningSession {
    let station: Station
    let startedAt: Date
    let source: String
    var trackKeys: Set<String>
}

enum ShellListeningSessionCoordinator {
    static func begin(
        session: inout ActiveListeningSession?,
        station: Station,
        source: AudioPlayerService.PlaybackQueue.Source,
        now: Date = .now
    ) -> ActiveListeningSession? {
        let endedSession = session?.station.id == station.id ? nil : session
        session = ActiveListeningSession(
            station: station,
            startedAt: now,
            source: source.analyticsSource,
            trackKeys: []
        )
        return endedSession
    }

    static func resumeIfNeeded(
        session: inout ActiveListeningSession?,
        station: Station,
        source: AudioPlayerService.PlaybackQueue.Source,
        now: Date = .now
    ) {
        guard session == nil else { return }
        session = ActiveListeningSession(
            station: station,
            startedAt: now,
            source: source.analyticsSource,
            trackKeys: []
        )
    }

    static func rememberTrack(session: inout ActiveListeningSession?, title: String, artist: String?) {
        guard var currentSession = session else { return }
        currentSession.trackKeys.insert("\(artist ?? "")|\(title)".lowercased())
        session = currentSession
    }

    static func flush(session: inout ActiveListeningSession?) -> ActiveListeningSession? {
        defer { session = nil }
        return session
    }
}

enum ShellCurrentDiscoveryCoordinator {
    static func shouldSaveStationFavorite(title: String?, artist: String?) -> Bool {
        title == nil && artist == nil
    }

    static func canToggleTrack(isAlreadySaved: Bool, canMarkInteresting: Bool) -> Bool {
        isAlreadySaved || canMarkInteresting
    }

    static func reactionAfterToggle(isSaved: Bool) -> AviScreenReaction {
        isSaved ? .saved : .curious
    }
}

enum ShellDiscoverySaveCoordinator {
    static func toggleDiscoverySaved(
        _ discovery: DiscoveredTrack,
        savedDiscoveriesCount: Int,
        limitState: (Int) -> FeatureLimitState,
        toggleSaved: (DiscoveredTrack, Int?) -> Bool,
        presentUpgrade: (Int) -> Void
    ) {
        if discovery.isMarkedInteresting {
            _ = toggleSaved(discovery, nil)
            return
        }

        let state = limitState(savedDiscoveriesCount)
        guard state.isAllowed else {
            presentUpgrade(state.currentUsage)
            return
        }

        _ = toggleSaved(discovery, state.limit)
    }
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
