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

enum ShellAviExternalSearchResolver {
    static func trackSearchURL(
        station: Station,
        currentTrackArtist: String?,
        currentTrackTitle: String?,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) -> URL? {
        let query = TuneAVExternalSearchURL.query(
            parts: [currentTrackArtist, currentTrackTitle, station.name],
            suffix: suffix
        )
        guard !query.isEmpty else { return nil }
        return TuneAVExternalSearchURL.url(for: destination, query: query)
    }

    static func artistSearchURL(artist: String?) -> URL? {
        guard let artist = TuneAVExternalSearchURL.normalizedValue(artist) else { return nil }
        return TuneAVExternalSearchURL.url(for: .web, query: artist)
    }

    static func stationSearchURL(station: Station) -> URL? {
        TuneAVExternalSearchURL.stationSearch(stationName: station.name)
    }

    static func externalSearchURL(
        query: String,
        destination: TuneAVExternalSearchURL.Destination = .web
    ) -> URL? {
        guard let query = TuneAVExternalSearchURL.normalizedValue(query) else { return nil }
        return TuneAVExternalSearchURL.url(for: destination, query: query)
    }
}

struct ShellAviActionsPanelState: Equatable {
    let hasSongStep: Bool
    let currentPage: Int

    var pageCount: Int {
        hasSongStep ? 2 : 1
    }

    var lastPage: Int {
        pageCount - 1
    }

    var visiblePage: Int {
        min(max(currentPage, 0), lastPage)
    }

    var pageDisplayIndex: Int {
        visiblePage + 1
    }

    var showsSongActions: Bool {
        hasSongStep && visiblePage == 0
    }

    var previousPage: Int {
        max(0, visiblePage - 1)
    }

    var nextPage: Int {
        min(lastPage, visiblePage + 1)
    }

    var canGoPrevious: Bool {
        pageCount > 1 && visiblePage > 0
    }

    var canGoNext: Bool {
        pageCount > 1 && visiblePage < lastPage
    }

    var title: String {
        showsSongActions
            ? L10n.string("shell.avi.actions.aboutSong")
            : L10n.string("shell.common.radio")
    }

    var pageLabel: String {
        L10n.string("shell.avi.actions.page", pageDisplayIndex, pageCount)
    }
}

enum ShellAviFeedbackTarget: Equatable {
    case track(identity: String)
    case station(id: String)

    var identity: String {
        switch self {
        case .track(let identity):
            "track:\(identity)"
        case .station(let id):
            "station:\(id)"
        }
    }

    var usesTrackFeedback: Bool {
        if case .track = self {
            return true
        }
        return false
    }
}

enum ShellAviFeedbackResolver {
    static func primaryTarget(
        isNowPlayingFullPlayer: Bool,
        hasCurrentSongContext: Bool,
        isEditingRadioFeedback: Bool = false,
        stationID: String,
        currentSongIdentity: String
    ) -> ShellAviFeedbackTarget {
        if isNowPlayingFullPlayer && hasCurrentSongContext && !isEditingRadioFeedback {
            return .track(identity: currentSongIdentity)
        }
        return .station(id: stationID)
    }
}

enum ShellAviAutomaticReactionDecision: Equatable {
    case reset
    case none
    case suppress(identity: String)
    case show(reaction: AviScreenReaction, identity: String, at: Date)
}

enum ShellAviAutomaticReactionResolver {
    static func decision(
        identity: String,
        lastIdentity: String,
        lastReactionAt: Date,
        now: Date = .now,
        isNowPlayingFullPlayer: Bool,
        isFocusedStationActive: Bool,
        isPlaying: Bool,
        currentTrackFeedback: TuneAVStationFeedback?,
        isSavedDiscoveredTrack: Bool
    ) -> ShellAviAutomaticReactionDecision {
        guard isNowPlayingFullPlayer, isFocusedStationActive, isPlaying, !identity.isEmpty else {
            return .reset
        }
        guard identity != lastIdentity else {
            return .none
        }

        let reaction = reaction(for: currentTrackFeedback, isSavedDiscoveredTrack: isSavedDiscoveredTrack)
        if reaction.usesAutomaticCooldown,
           now.timeIntervalSince(lastReactionAt) < AviScreenReaction.automaticCooldown {
            return .suppress(identity: identity)
        }

        return .show(reaction: reaction, identity: identity, at: now)
    }

    private static func reaction(
        for feedback: TuneAVStationFeedback?,
        isSavedDiscoveredTrack: Bool
    ) -> AviScreenReaction {
        switch feedback {
        case .liked:
            return .recognizedTrack
        case .disliked:
            return .disliked
        case .notForMe:
            return .notForMe
        case nil:
            return isSavedDiscoveredTrack ? .recognizedTrack : .newTrack
        }
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
