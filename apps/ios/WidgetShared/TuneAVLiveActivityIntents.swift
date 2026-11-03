import AppIntents
import Foundation

/// The one switch for the now playing Live Activity, shared by the app and the widget extension.
/// Off since 1.1.0 (62): the lock screen shows only the system Now Playing player. See
/// `TuneAVLiveActivityController.isEnabled` for the two other lines turning it back on needs.
enum TuneAVLiveActivityFeature {
    static let isEnabled = false
}

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

struct TuneAVTogglePlaybackIntent: AudioPlaybackIntent, LiveActivityIntent {
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
