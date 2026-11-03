import AppIntents
import Foundation

enum TuneAVLiveActivityAction: Sendable {
    case togglePlayback
    case toggleHeart
}

@MainActor
enum TuneAVLiveActivityActionRouter {
    static var handler: (@MainActor (TuneAVLiveActivityAction) async -> Void)?

    static func perform(_ action: TuneAVLiveActivityAction) async {
        await handler?(action)
    }
}

struct TuneAVTogglePlaybackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "player.control.play"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TuneAVLiveActivityActionRouter.perform(.togglePlayback)
        return .result()
    }
}

struct TuneAVToggleHeartIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "player.discovery.saveShort"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TuneAVLiveActivityActionRouter.perform(.toggleHeart)
        return .result()
    }
}
