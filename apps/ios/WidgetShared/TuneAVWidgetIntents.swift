import AppIntents
import Foundation

enum TuneAVWidgetAction: Sendable, Equatable {
    case playStation(id: String, isFavoriteShortcut: Bool)
}

@MainActor
enum TuneAVWidgetActionRouter {
    static var handler: (@MainActor (TuneAVWidgetAction) async -> Void)?

    static func perform(_ action: TuneAVWidgetAction) async {
        await handler?(action)
    }
}

struct TuneAVPlayStationIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "widget.intent.playStation"
    static let isDiscoverable = false

    @Parameter(title: "widget.intent.station")
    var stationID: String

    @Parameter(title: "widget.intent.favoriteShortcut", default: false)
    var isFavoriteShortcut: Bool

    init() {}

    init(stationID: String, isFavoriteShortcut: Bool) {
        self.stationID = stationID
        self.isFavoriteShortcut = isFavoriteShortcut
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await TuneAVWidgetActionRouter.perform(.playStation(id: stationID, isFavoriteShortcut: isFavoriteShortcut))
        return .result()
    }
}
