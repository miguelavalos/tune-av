import AVHaptics
import Foundation

enum AviScreenReaction: Equatable {
    case newTrack
    case recognizedTrack
    case liked
    case curious
    case saved
    case disliked
    case notForMe
    case warning

    static let automaticCooldown: TimeInterval = 10

    var emotion: TuneAVAviEmotion {
        switch self {
        case .liked, .recognizedTrack:
            return .liked
        case .saved:
            return .saved
        case .newTrack:
            return .surprised
        case .curious:
            return .curious
        case .disliked, .notForMe:
            return .dislike
        case .warning:
            return .warning
        }
    }

    var durationMilliseconds: Int {
        switch self {
        case .newTrack:
            return 2200
        case .curious, .disliked, .notForMe:
            return 2600
        case .liked, .recognizedTrack, .saved:
            return 4200
        case .warning:
            return 2800
        }
    }

    var priority: Int {
        switch self {
        case .warning:
            return 100
        case .liked, .saved, .disliked, .notForMe:
            return 80
        case .recognizedTrack:
            return 70
        case .curious:
            return 60
        case .newTrack:
            return 30
        }
    }

    var usesAutomaticCooldown: Bool {
        switch self {
        case .newTrack:
            return true
        case .recognizedTrack, .liked, .curious, .saved, .disliked, .notForMe, .warning:
            return false
        }
    }

    var hapticEvent: AVHapticEvent? {
        switch self {
        case .newTrack:
            return nil
        case .recognizedTrack, .liked, .saved:
            return .affirm
        case .curious:
            return .selection
        case .disliked, .notForMe:
            return .negativeFeedback
        case .warning:
            return .warning
        }
    }
}

enum AviDiscoveryDecision {
    case saved
    case removed
    case ignored

    var localizedHint: String {
        switch self {
        case .saved:
            return L10n.string("player.avi.feedback.savedHint")
        case .removed:
            return L10n.string("player.discovery.removed")
        case .ignored:
            return L10n.string("player.discovery.noSaveHint")
        }
    }
}
