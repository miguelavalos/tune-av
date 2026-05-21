import AVAviFoundation
import SwiftUI
import UIKit

struct FullPlayerAviHeader: View {
    let emotion: TuneAVAviEmotion
    let reactionEmotion: TuneAVAviEmotion?
    let reactionStartedAt: Date?
    let label: String
    let title: String
    let summary: String

    private var accessibilityState: String {
        let activeEmotion = reactionEmotion ?? emotion
        let mode = reactionEmotion == nil ? "static" : "reaction"
        return "\(mode):\(activeEmotion.assetName)"
    }

    var body: some View {
        AVAviFullPlayerHeaderScaffold(
            label: label,
            title: title,
            summary: summary,
            accessibilityValue: accessibilityState
        ) {
            AviReactionEmotionImage(
                emotion: emotion,
                reactionEmotion: reactionEmotion,
                reactionStartedAt: reactionStartedAt,
                width: 82,
                height: 82
            )
                .frame(width: 86, height: 86)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                .overlay {
                    Circle().stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
                }
                .accessibilityLabel(L10n.string("shell.avi.title"))
        }
    }
}

private struct AviReactionEmotionImage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let emotion: TuneAVAviEmotion
    let reactionEmotion: TuneAVAviEmotion?
    let reactionStartedAt: Date?
    let width: CGFloat
    let height: CGFloat

    @State private var displayedEmotion: TuneAVAviEmotion
    @State private var lastEmotionChange = Date.distantPast

    init(
        emotion: TuneAVAviEmotion,
        reactionEmotion: TuneAVAviEmotion?,
        reactionStartedAt: Date?,
        width: CGFloat,
        height: CGFloat
    ) {
        self.emotion = emotion
        self.reactionEmotion = reactionEmotion
        self.reactionStartedAt = reactionStartedAt
        self.width = width
        self.height = height
        _displayedEmotion = State(initialValue: emotion)
    }

    private var activeEmotion: TuneAVAviEmotion {
        reactionEmotion ?? displayedEmotion
    }

    private var frames: [String] {
        guard reactionEmotion != nil, !reduceMotion else { return [activeEmotion.fullBodyAssetName] }
        return AviReactionFrames.frames(for: activeEmotion)
    }

    private var accessibilityState: String {
        let mode = reactionEmotion == nil ? "static" : "reaction"
        return "\(mode):\(activeEmotion.assetName)"
    }

    var body: some View {
        Group {
            if reactionEmotion != nil, !reduceMotion {
                TimelineView(.periodic(from: .now, by: AviReactionFrames.frameDuration)) { timeline in
                    let elapsed = reactionStartedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                    let frameIndex = AviReactionFrames.frameIndex(
                        elapsed: elapsed,
                        frameCount: frames.count
                    )

                    aviImage(named: frames[frameIndex])
                        .modifier(AviReactionMotion(emotion: activeEmotion, elapsed: elapsed))
                }
            } else {
                aviImage(named: activeEmotion.fullBodyAssetName)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .animation(.snappy(duration: 0.16), value: frames)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("shell.avi.title"))
        .accessibilityValue(accessibilityState)
        .accessibilityIdentifier("avi.fullPlayer.emotion")
        .onAppear {
            displayedEmotion = emotion
            lastEmotionChange = Date()
        }
        .onChange(of: emotion) { _, candidate in
            adopt(candidate)
        }
        .task(id: emotion) {
            await adoptWhenAllowed(emotion)
        }
    }

    private func aviImage(named assetName: String) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
    }

    private func adopt(_ candidate: TuneAVAviEmotion) {
        let now = Date()
        guard TuneAVAviEmotionStability.shouldAdopt(
            displayed: displayedEmotion,
            candidate: candidate,
            elapsedSinceLastChange: now.timeIntervalSince(lastEmotionChange)
        ) else { return }

        displayedEmotion = candidate
        lastEmotionChange = now
    }

    @MainActor
    private func adoptWhenAllowed(_ candidate: TuneAVAviEmotion) async {
        guard displayedEmotion != candidate else { return }
        let minimumInterval = candidate.transitionPriority > displayedEmotion.transitionPriority
            ? TuneAVAviEmotionStability.immediateMinimumDisplayInterval
            : TuneAVAviEmotionStability.defaultMinimumDisplayInterval
        let elapsed = Date().timeIntervalSince(lastEmotionChange)
        let remaining = max(0, minimumInterval - elapsed)
        if remaining > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        adopt(candidate)
    }
}

private enum AviReactionFrames {
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

private struct AviReactionMotion: ViewModifier {
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
