import AppIntents
import Foundation

enum TuneAVWidgetAction: Sendable, Equatable {
    case playStation(id: String, isFavoriteShortcut: Bool, expectsActivePlayback: Bool)
    case startMyRadio
    case startStation(id: String)
    case pausePlayback
}

enum TuneAVWidgetActionOutcome: Sendable, Equatable {
    case done
    case playing
    case alreadyPlaying
    case paused
    case nothingToPause
    case noStation
    case needsApp(TuneAVWidgetDeepLink)
}

@MainActor
enum TuneAVWidgetActionRouter {
    static var handler: (@MainActor (TuneAVWidgetAction) async -> TuneAVWidgetActionOutcome)?
    static var appLinkHandler: (@MainActor (TuneAVWidgetDeepLink) -> Void)?

    @discardableResult
    static func perform(_ action: TuneAVWidgetAction) async -> TuneAVWidgetActionOutcome {
        await handler?(action) ?? .noStation
    }
}

struct TuneAVPlayStationIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "widget.intent.playStation"
    static let isDiscoverable = false

    @Parameter(title: "widget.intent.station")
    var stationID: String

    @Parameter(title: "widget.intent.favoriteShortcut", default: false)
    var isFavoriteShortcut: Bool

    @Parameter(title: "widget.intent.wasPlaying", default: false)
    var expectsActivePlayback: Bool

    init() {}

    init(stationID: String, isFavoriteShortcut: Bool, expectsActivePlayback: Bool) {
        self.stationID = stationID
        self.isFavoriteShortcut = isFavoriteShortcut
        self.expectsActivePlayback = expectsActivePlayback
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await TuneAVWidgetActionRouter.perform(.playStation(
            id: stationID,
            isFavoriteShortcut: isFavoriteShortcut,
            expectsActivePlayback: expectsActivePlayback
        ))
        return .result()
    }
}
