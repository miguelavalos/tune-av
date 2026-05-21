import AVAviFoundation
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
    }

    private func assetName(for emotion: TuneAVAviEmotion) -> String {
        switch assetVariant {
        case .head:
            return emotion.assetName
        case .fullBody:
            return emotion.fullBodyAssetName
        }
    }

    var body: some View {
        AVAviStableAssetImage(
            value: emotion,
            width: width,
            height: height,
            defaultMinimumDisplayInterval: TuneAVAviEmotionStability.defaultMinimumDisplayInterval,
            immediateMinimumDisplayInterval: TuneAVAviEmotionStability.immediateMinimumDisplayInterval,
            assetName: assetName(for:),
            transitionPriority: { $0.transitionPriority }
        )
    }
}
