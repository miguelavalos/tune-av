import AppIntents
import Foundation

enum TuneAVSiriIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noRadio
    case stationUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noRadio:
            return "appShortcut.error.noRadio"
        case .stationUnavailable:
            return "appShortcut.error.stationUnavailable"
        }
    }
}

enum TuneAVSiriIntentRouting {
    @MainActor
    static func start(
        _ action: TuneAVWidgetAction,
        missing: TuneAVSiriIntentError,
        continueInForeground: (TuneAVWidgetDeepLink) -> any Error
    ) async throws {
        switch await TuneAVWidgetActionRouter.perform(action) {
        case let .needsApp(link):
            throw continueInForeground(link)
        case .noStation:
            throw missing
        case .done, .playing, .alreadyPlaying, .paused, .nothingToPause:
            return
        }
    }
}

struct TuneAVPlayMyRadioIntent: AudioPlaybackIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "appShortcut.playMyRadio"
    static let description = IntentDescription("appShortcut.playMyRadio.description")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try await TuneAVSiriIntentRouting.start(.startMyRadio, missing: .noRadio) { link in
            needsToContinueInForegroundError("appShortcut.dialog.continueInApp") {
                TuneAVWidgetController.shared.continueInApp(link)
            }
        }
        return .result()
    }
}

struct TuneAVPlayRadioIntent: AudioPlaybackIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "appShortcut.playStation"
    static let description = IntentDescription("appShortcut.playStation.description")

    @Parameter(title: "widget.intent.station")
    var station: TuneAVStationEntity

    init() {}

    init(station: TuneAVStationEntity) {
        self.station = station
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await TuneAVSiriIntentRouting.start(.startStation(id: station.id), missing: .stationUnavailable) { link in
            needsToContinueInForegroundError("appShortcut.dialog.continueInApp") {
                TuneAVWidgetController.shared.continueInApp(link)
            }
        }
        return .result()
    }
}

struct TuneAVPausePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "appShortcut.pause"
    static let description = IntentDescription("appShortcut.pause.description")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TuneAVWidgetActionRouter.perform(.pausePlayback)
        return .result()
    }
}
