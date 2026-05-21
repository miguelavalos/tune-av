import AVAviFoundation
import SwiftUI

enum TuneAVActionReaction: Equatable {
    case like
    case dislike
    case notForMe
    case clear
    case save
}

extension View {
    func tuneAVActionReaction(_ reaction: TuneAVActionReaction, trigger: Int) -> some View {
        avAviActionReaction(reaction.sharedReaction, trigger: trigger)
    }
}

private extension TuneAVActionReaction {
    var sharedReaction: AVAviActionReaction {
        switch self {
        case .like:
            return .positive
        case .save:
            return .save
        case .dislike:
            return .negative
        case .notForMe:
            return .selection
        case .clear:
            return .clear
        }
    }
}
