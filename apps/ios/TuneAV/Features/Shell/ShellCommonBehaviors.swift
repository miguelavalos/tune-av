import AVHaptics
import SwiftUI

let shellScreenHorizontalPadding: CGFloat = 20
let shellScreenTopPadding: CGFloat = 24

enum TuneAVHaptics {
    @MainActor
    static func selection() {
        AVHaptics.perform(.selection)
    }

    @MainActor
    static func lightImpact() {
        AVHaptics.perform(.impactLight)
    }
}

extension View {
    func shellScreenContentPadding(bottom bottomPadding: CGFloat) -> some View {
        padding(.horizontal, shellScreenHorizontalPadding)
            .padding(.top, shellScreenTopPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func shellScreenScrollBehavior() -> some View {
        contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollIndicators(.hidden)
    }
}
