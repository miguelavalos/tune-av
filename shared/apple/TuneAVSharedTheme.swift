import SwiftUI

#if os(iOS)
import UIKit
typealias TuneAVPlatformColor = UIColor
#elseif os(macOS)
import AppKit
typealias TuneAVPlatformColor = NSColor
#endif

enum TuneAVTheme {
    static let brandBlack = Color(red: 58 / 255, green: 58 / 255, blue: 54 / 255)
    static let brandGreen = Color(red: 109 / 255, green: 190 / 255, blue: 69 / 255)
    static let brandGraphite = Color(red: 58 / 255, green: 58 / 255, blue: 54 / 255)
    static let brandWhite = Color.white

    static let neutral50 = Color(red: 247 / 255, green: 249 / 255, blue: 248 / 255)
    static let neutral100 = Color(red: 238 / 255, green: 242 / 255, blue: 239 / 255)
    static let neutral300 = Color(red: 200 / 255, green: 209 / 255, blue: 203 / 255)
    static let neutral600 = Color(red: 95 / 255, green: 104 / 255, blue: 98 / 255)
    static let neutral800 = Color(red: 26 / 255, green: 29 / 255, blue: 27 / 255)

    static let highlight = brandGreen
    static let textPrimary = dynamicColor(
        light: TuneAVPlatformColor(red: 58 / 255, green: 58 / 255, blue: 54 / 255, alpha: 1),
        dark: TuneAVPlatformColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1)
    )
    static let textSecondary = dynamicColor(
        light: TuneAVPlatformColor(red: 95 / 255, green: 104 / 255, blue: 98 / 255, alpha: 1),
        dark: TuneAVPlatformColor(red: 161 / 255, green: 170 / 255, blue: 165 / 255, alpha: 1)
    )
    static let textInverse = brandWhite

    static let cardSurface = dynamicColor(
        light: TuneAVPlatformColor(red: 251 / 255, green: 252 / 255, blue: 251 / 255, alpha: 1),
        dark: TuneAVPlatformColor(red: 30 / 255, green: 34 / 255, blue: 31 / 255, alpha: 1)
    )
    static let mutedSurface = dynamicColor(
        light: TuneAVPlatformColor(red: 238 / 255, green: 242 / 255, blue: 239 / 255, alpha: 1),
        dark: TuneAVPlatformColor(red: 42 / 255, green: 46 / 255, blue: 43 / 255, alpha: 1)
    )
    static let borderSubtle = dynamicColor(
        light: TuneAVPlatformColor(red: 200 / 255, green: 209 / 255, blue: 203 / 255, alpha: 1),
        dark: TuneAVPlatformColor(red: 72 / 255, green: 79 / 255, blue: 74 / 255, alpha: 1)
    )
    static let borderStrong = dynamicColor(
        light: TuneAVPlatformColor(red: 149 / 255, green: 159 / 255, blue: 152 / 255, alpha: 1),
        dark: TuneAVPlatformColor(red: 108 / 255, green: 116 / 255, blue: 111 / 255, alpha: 1)
    )
    static let darkSurface = brandBlack
    static let darkSurfaceAlt = neutral800
    static let footerGlass = dynamicColor(
        light: TuneAVPlatformColor.white.withAlphaComponent(0.86),
        dark: TuneAVPlatformColor.white.withAlphaComponent(0.28)
    )
    static let footerGlassSelected = dynamicColor(
        light: TuneAVPlatformColor.white.withAlphaComponent(0.92),
        dark: TuneAVPlatformColor.white.withAlphaComponent(0.34)
    )
    static let footerBackdrop = dynamicColor(
        light: TuneAVPlatformColor(red: 247 / 255, green: 249 / 255, blue: 248 / 255, alpha: 1),
        dark: TuneAVPlatformColor(red: 13 / 255, green: 13 / 255, blue: 13 / 255, alpha: 1)
    )
    static let glassStroke = dynamicColor(
        light: TuneAVPlatformColor.white.withAlphaComponent(0.5),
        dark: TuneAVPlatformColor.white.withAlphaComponent(0.18)
    )
    static let glassShadow = dynamicColor(
        light: TuneAVPlatformColor.black.withAlphaComponent(0.08),
        dark: TuneAVPlatformColor.black.withAlphaComponent(0.28)
    )
    static let elevatedSurface = dynamicColor(
        light: TuneAVPlatformColor.white.withAlphaComponent(0.94),
        dark: TuneAVPlatformColor(red: 35 / 255, green: 39 / 255, blue: 36 / 255, alpha: 0.96)
    )
    static let skeletonHighlight = dynamicColor(
        light: TuneAVPlatformColor.white.withAlphaComponent(0.95),
        dark: TuneAVPlatformColor(red: 58 / 255, green: 64 / 255, blue: 60 / 255, alpha: 1)
    )

    static let shellBackground = LinearGradient(
        colors: [
            dynamicColor(
                light: TuneAVPlatformColor.white,
                dark: TuneAVPlatformColor(red: 20 / 255, green: 22 / 255, blue: 20 / 255, alpha: 1)
            ),
            dynamicColor(
                light: TuneAVPlatformColor(red: 247 / 255, green: 249 / 255, blue: 248 / 255, alpha: 1),
                dark: TuneAVPlatformColor(red: 32 / 255, green: 35 / 255, blue: 32 / 255, alpha: 1)
            ),
            dynamicColor(
                light: TuneAVPlatformColor(red: 238 / 255, green: 242 / 255, blue: 239 / 255, alpha: 1),
                dark: TuneAVPlatformColor(red: 42 / 255, green: 46 / 255, blue: 42 / 255, alpha: 1)
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let onboardingBackground = LinearGradient(
        colors: [brandBlack, darkSurfaceAlt],
        startPoint: .top,
        endPoint: .bottom
    )

    static let signalGradient = LinearGradient(
        colors: [brandGreen.opacity(0.96), brandWhite.opacity(0.9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let softShadow = dynamicColor(
        light: TuneAVPlatformColor.black.withAlphaComponent(0.12),
        dark: TuneAVPlatformColor.black.withAlphaComponent(0.34)
    )

    private static func dynamicColor(light: TuneAVPlatformColor, dark: TuneAVPlatformColor) -> Color {
        #if os(iOS)
        return Color(
            uiColor: UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? dark : light
            }
        )
        #elseif os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.darkAqua, .aqua])
            return best == .darkAqua ? dark : light
        })
        #endif
    }
}
