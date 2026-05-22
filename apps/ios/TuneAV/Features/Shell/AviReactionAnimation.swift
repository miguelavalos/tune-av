import SwiftUI
import UIKit

enum AviReactionFrames {
    static let frameDuration: TimeInterval = 1.0 / 12.0

    private static let listeningIdleFrames = availableFrames(for: "AviTuneListeningIdle", count: 20)
    private static let happyReactFrames = availableFrames(for: "AviTuneHappyReact", count: 20)
    private static let savedFrames = availableFrames(for: "AviTuneSaved", count: 20)
    private static let curiousFrames = availableFrames(for: "AviTuneCurious", count: 20)
    private static let thinkingFrames = availableFrames(for: "AviTuneThinking", count: 20)
    private static let dislikeFrames = availableFrames(for: "AviTuneDislike", count: 20)
    private static let surprisedFrames = availableFrames(for: "AviTuneSurprised", count: 20)
    private static let calmIdleFrames = availableFrames(for: "AviTuneCalmIdle", count: 20)
    private static let sleepIdleFrames = availableFrames(for: "AviTuneSleepIdle", count: 20)

    static func frameIndex(elapsed: TimeInterval, frameCount: Int) -> Int {
        guard frameCount > 1 else { return 0 }
        let tick = Int((max(0, elapsed) / frameDuration).rounded(.down))
        return tick % frameCount
    }

    static func frames(for emotion: TuneAVAviEmotion) -> [String] {
        switch emotion {
        case .neutral, .listening, .focused:
            return listeningIdleFrames ?? [emotion.fullBodyAssetName]
        case .happy, .liked, .celebrate:
            return happyReactFrames ?? [emotion.fullBodyAssetName]
        case .saved:
            return savedFrames ?? happyReactFrames ?? [emotion.fullBodyAssetName]
        case .curious:
            return curiousFrames ?? [emotion.fullBodyAssetName]
        case .thinking:
            return thinkingFrames ?? [emotion.fullBodyAssetName]
        case .dislike, .warning:
            return dislikeFrames ?? [emotion.fullBodyAssetName]
        case .surprised:
            return surprisedFrames ?? [emotion.fullBodyAssetName]
        case .calm:
            return calmIdleFrames ?? sleepIdleFrames ?? [emotion.fullBodyAssetName]
        case .sleep:
            return sleepIdleFrames ?? [emotion.fullBodyAssetName]
        }
    }

    private static func availableFrames(for prefix: String, count: Int) -> [String]? {
        let names = (0..<count).map { "\(prefix)\(String(format: "%03d", $0))" }
        let existing = names.filter { UIImage(named: $0) != nil }
        return existing.count >= 2 ? existing : nil
    }
}

struct AviReactionMotion: ViewModifier {
    let emotion: TuneAVAviEmotion
    let elapsed: TimeInterval

    func body(content: Content) -> some View {
        let values = motionValues
        content
            .scaleEffect(values.scale)
            .rotationEffect(.degrees(values.rotation))
            .offset(x: values.x, y: values.y)
    }

    private var motionValues: (scale: CGFloat, rotation: Double, x: CGFloat, y: CGFloat) {
        let progress = min(max(elapsed / 1.45, 0), 1)
        let envelope = CGFloat(max(0.18, 1 - progress))
        let wave = CGFloat(sin(elapsed * .pi * 5.5))

        switch emotion {
        case .celebrate, .happy, .liked, .saved:
            return (
                scale: 1 + (0.075 * envelope * abs(wave)),
                rotation: Double(5.5 * envelope * wave),
                x: 0,
                y: -7 * envelope * abs(wave)
            )
        case .surprised:
            return (
                scale: 1 + (0.09 * envelope * abs(wave)),
                rotation: Double(-3.5 * envelope * wave),
                x: 0,
                y: -6 * envelope * abs(wave)
            )
        case .thinking, .focused, .curious:
            return (
                scale: 1 + (0.025 * envelope * abs(wave)),
                rotation: Double(4 * envelope * CGFloat(sin(elapsed * .pi * 3))),
                x: 4 * envelope * CGFloat(sin(elapsed * .pi * 2)),
                y: 0
            )
        case .dislike, .warning:
            return (
                scale: 1,
                rotation: Double(-4.5 * envelope * abs(wave)),
                x: 5 * envelope * CGFloat(sin(elapsed * .pi * 7)),
                y: 2.5 * envelope * abs(wave)
            )
        case .neutral, .listening, .calm, .sleep:
            return (
                scale: 1 + (0.04 * envelope * abs(wave)),
                rotation: 0,
                x: 0,
                y: -3 * envelope * abs(wave)
            )
        }
    }
}
