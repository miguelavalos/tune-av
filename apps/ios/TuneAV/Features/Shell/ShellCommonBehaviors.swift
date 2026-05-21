import SwiftUI

let shellScreenHorizontalPadding: CGFloat = 20
let shellScreenTopPadding: CGFloat = 24

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
