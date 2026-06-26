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

    func shellScreenContentPadding(layout: TuneLayoutContext, bottom bottomPadding: CGFloat) -> some View {
        avShellScreenContentPadding(
            horizontal: layout.isTabletLike ? 28 : shellScreenHorizontalPadding,
            top: shellScreenTopPadding,
            bottom: layout.isTabletLike ? 56 : bottomPadding
        )
        .frame(maxWidth: layout.shellContentMaxWidth ?? .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    func shellScreenScrollBehavior() -> some View {
        avShellScreenScrollBehavior()
    }
}

extension TuneLayoutContext {
    var shellContentMaxWidth: CGFloat? {
        switch layoutClass {
        case .compact:
            nil
        case .regular:
            820
        case .expansive:
            1120
        }
    }
}
