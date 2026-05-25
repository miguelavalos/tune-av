import AVAppShellFoundation
import SwiftUI

let shellScreenHorizontalPadding: CGFloat = AVAppShellScreenMetric.horizontalPadding
let shellScreenTopPadding: CGFloat = AVAppShellScreenMetric.topPadding

extension View {
    func shellScreenContentPadding(bottom bottomPadding: CGFloat) -> some View {
        avShellScreenContentPadding(
            horizontal: shellScreenHorizontalPadding,
            top: shellScreenTopPadding,
            bottom: bottomPadding
        )
    }

    func shellScreenScrollBehavior() -> some View {
        avShellScreenScrollBehavior()
    }
}
