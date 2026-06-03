import AVAviFoundation
import SwiftUI

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
        HStack(alignment: .center, spacing: 12) {
            AviReactionEmotionImage(
                emotion: emotion,
                reactionEmotion: reactionEmotion,
                reactionStartedAt: reactionStartedAt,
                width: 64,
                height: 64
            )
                .frame(width: 68, height: 68)
                .background(TuneAVTheme.highlight.opacity(0.12), in: Circle())
                .overlay {
                    Circle().stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
                }
                .accessibilityLabel(L10n.string("shell.avi.title"))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)

                Text(title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .truncationMode(.tail)

                Text(summary)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 76)
        .accessibilityElement(children: .contain)
        .accessibilityValue(accessibilityState)
        .accessibilityIdentifier("avi.focused.header")
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
