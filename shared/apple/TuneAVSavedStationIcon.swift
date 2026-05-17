import SwiftUI

struct TuneAVSavedStationIcon: View {
    let isSaved: Bool
    var size: CGFloat = 16
    var inactiveColor: Color = TuneAVTheme.textPrimary
    var activeColor: Color = TuneAVTheme.highlight

    var body: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(isSaved ? activeColor : inactiveColor.opacity(0.82))
            .frame(width: size * 1.45, height: size * 1.45, alignment: .center)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}
