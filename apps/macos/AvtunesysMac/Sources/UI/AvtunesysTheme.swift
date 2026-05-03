import AppKit
import SwiftUI

enum AvtunesysTheme {
    static let brandBlack = Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)
    static let brandGreen = Color(red: 57 / 255, green: 181 / 255, blue: 74 / 255)
    static let brandGraphite = Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
    static let brandWhite = Color.white

    static let neutral50 = Color(red: 247 / 255, green: 249 / 255, blue: 248 / 255)
    static let neutral100 = Color(red: 238 / 255, green: 242 / 255, blue: 239 / 255)
    static let neutral300 = Color(red: 200 / 255, green: 209 / 255, blue: 203 / 255)
    static let neutral600 = Color(red: 95 / 255, green: 104 / 255, blue: 98 / 255)
    static let neutral800 = Color(red: 26 / 255, green: 29 / 255, blue: 27 / 255)

    static let highlight = brandGreen
    static let textPrimary = dynamicColor(
        light: NSColor(red: 13 / 255, green: 13 / 255, blue: 13 / 255, alpha: 1),
        dark: NSColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1)
    )
    static let textSecondary = dynamicColor(
        light: NSColor(red: 95 / 255, green: 104 / 255, blue: 98 / 255, alpha: 1),
        dark: NSColor(red: 161 / 255, green: 170 / 255, blue: 165 / 255, alpha: 1)
    )
    static let textInverse = brandWhite

    static let cardSurface = dynamicColor(
        light: NSColor(red: 251 / 255, green: 252 / 255, blue: 251 / 255, alpha: 1),
        dark: NSColor(red: 30 / 255, green: 34 / 255, blue: 31 / 255, alpha: 1)
    )
    static let mutedSurface = dynamicColor(
        light: NSColor(red: 238 / 255, green: 242 / 255, blue: 239 / 255, alpha: 1),
        dark: NSColor(red: 42 / 255, green: 46 / 255, blue: 43 / 255, alpha: 1)
    )
    static let borderSubtle = dynamicColor(
        light: NSColor(red: 200 / 255, green: 209 / 255, blue: 203 / 255, alpha: 1),
        dark: NSColor(red: 72 / 255, green: 79 / 255, blue: 74 / 255, alpha: 1)
    )
    static let borderStrong = dynamicColor(
        light: NSColor(red: 149 / 255, green: 159 / 255, blue: 152 / 255, alpha: 1),
        dark: NSColor(red: 108 / 255, green: 116 / 255, blue: 111 / 255, alpha: 1)
    )
    static let darkSurface = brandBlack
    static let darkSurfaceAlt = neutral800
    static let footerGlass = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.86),
        dark: NSColor.white.withAlphaComponent(0.28)
    )
    static let footerGlassSelected = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.92),
        dark: NSColor.white.withAlphaComponent(0.34)
    )
    static let footerBackdrop = dynamicColor(
        light: NSColor(red: 247 / 255, green: 249 / 255, blue: 248 / 255, alpha: 1),
        dark: NSColor(red: 13 / 255, green: 13 / 255, blue: 13 / 255, alpha: 1)
    )
    static let elevatedSurface = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.94),
        dark: NSColor(red: 35 / 255, green: 39 / 255, blue: 36 / 255, alpha: 0.96)
    )
    static let skeletonHighlight = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.95),
        dark: NSColor(red: 58 / 255, green: 64 / 255, blue: 60 / 255, alpha: 1)
    )
    static let glassStroke = dynamicColor(
        light: NSColor.white.withAlphaComponent(0.5),
        dark: NSColor.white.withAlphaComponent(0.18)
    )
    static let glassShadow = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.black.withAlphaComponent(0.28)
    )
    static let softShadow = dynamicColor(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.black.withAlphaComponent(0.34)
    )

    static let shellBackground = LinearGradient(
        colors: [
            dynamicColor(
                light: NSColor.white,
                dark: NSColor(red: 11 / 255, green: 13 / 255, blue: 12 / 255, alpha: 1)
            ),
            dynamicColor(
                light: NSColor(red: 247 / 255, green: 249 / 255, blue: 248 / 255, alpha: 1),
                dark: NSColor(red: 18 / 255, green: 22 / 255, blue: 20 / 255, alpha: 1)
            ),
            dynamicColor(
                light: NSColor(red: 238 / 255, green: 242 / 255, blue: 239 / 255, alpha: 1),
                dark: NSColor(red: 24 / 255, green: 29 / 255, blue: 26 / 255, alpha: 1)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let onboardingBackground = LinearGradient(
        colors: [brandBlack, neutral800],
        startPoint: .top,
        endPoint: .bottom
    )

    static let signalGradient = LinearGradient(
        colors: [brandGreen.opacity(0.96), brandWhite.opacity(0.9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.darkAqua, .aqua])
            return best == .darkAqua ? dark : light
        })
    }
}

extension View {
    func avCardSurface(
        cornerRadius: CGFloat = 22,
        fill: Color = AvtunesysTheme.cardSurface,
        borderColor: Color = AvtunesysTheme.borderSubtle,
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
        .shadow(color: AvtunesysTheme.softShadow.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }

    func avRoundedControl(
        fill: Color = AvtunesysTheme.elevatedSurface,
        cornerRadius: CGFloat = 18,
        borderColor: Color = AvtunesysTheme.borderSubtle
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
    }
}
