import SwiftUI

extension View {
    func avCardSurface(
        cornerRadius: CGFloat = 22,
        fill: Color = TuneAVTheme.cardSurface,
        borderColor: Color = TuneAVTheme.borderSubtle,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                }
        )
        .shadow(color: TuneAVTheme.softShadow.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }

    func avRoundedControl(
        fill: Color = TuneAVTheme.elevatedSurface,
        cornerRadius: CGFloat = 18,
        borderColor: Color = TuneAVTheme.borderSubtle
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
    }
}
