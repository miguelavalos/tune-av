import SwiftUI

struct AviStableEmotionImage: View {
    enum AssetVariant {
        case head
        case fullBody
    }

    let emotion: TuneAVAviEmotion
    let assetVariant: AssetVariant
    let width: CGFloat
    var height: CGFloat?

    @State private var displayedEmotion: TuneAVAviEmotion
    @State private var lastEmotionChange = Date.distantPast

    init(
        emotion: TuneAVAviEmotion,
        assetVariant: AssetVariant,
        width: CGFloat,
        height: CGFloat? = nil
    ) {
        self.emotion = emotion
        self.assetVariant = assetVariant
        self.width = width
        self.height = height
        _displayedEmotion = State(initialValue: emotion)
    }

    private var assetName: String {
        switch assetVariant {
        case .head:
            return displayedEmotion.assetName
        case .fullBody:
            return displayedEmotion.fullBodyAssetName
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .animation(.snappy(duration: 0.24), value: assetName)
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
