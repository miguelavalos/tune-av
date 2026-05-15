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
        modifier(TuneAVActionReactionEffect(reaction: reaction, trigger: trigger))
    }
}

private struct TuneAVActionReactionEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let reaction: TuneAVActionReaction
    let trigger: Int

    func body(content: Content) -> some View {
        content
            .phaseAnimator(TuneAVActionReactionPhase.allCases, trigger: trigger) { animatedContent, phase in
                let values = reduceMotion ? .identity : reaction.values(for: phase)

                animatedContent
                    .scaleEffect(values.scale)
                    .rotationEffect(values.angle)
                    .offset(y: values.verticalOffset)
            } animation: { phase in
                reduceMotion ? nil : phase.animation
            }
            .sensoryFeedback(reaction.sensoryFeedback, trigger: trigger)
    }
}

private enum TuneAVActionReactionPhase: CaseIterable {
    case resting
    case active
    case settle

    var animation: Animation {
        switch self {
        case .resting:
            return .smooth(duration: 0.08)
        case .active:
            return .snappy(duration: 0.16, extraBounce: 0.22)
        case .settle:
            return .smooth(duration: 0.14)
        }
    }
}

private struct TuneAVActionReactionValues {
    static let identity = TuneAVActionReactionValues()

    var scale = 1.0
    var verticalOffset = 0.0
    var angle = Angle.zero
}

private extension TuneAVActionReaction {
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .like, .save:
            return .success
        case .dislike:
            return .warning
        case .notForMe, .clear:
            return .selection
        }
    }

    func values(for phase: TuneAVActionReactionPhase) -> TuneAVActionReactionValues {
        switch (self, phase) {
        case (_, .resting), (_, .settle):
            return .identity
        case (.like, .active), (.save, .active):
            return TuneAVActionReactionValues(scale: 1.18, verticalOffset: -2, angle: .degrees(-7))
        case (.dislike, .active):
            return TuneAVActionReactionValues(scale: 1.1, verticalOffset: 1, angle: .degrees(8))
        case (.notForMe, .active):
            return TuneAVActionReactionValues(scale: 1.07)
        case (.clear, .active):
            return TuneAVActionReactionValues(scale: 0.9, angle: .degrees(10))
        }
    }
}
