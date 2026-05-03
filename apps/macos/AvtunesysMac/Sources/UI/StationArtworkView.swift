import SwiftUI

struct StationArtworkView: View {
    enum SurfaceStyle {
        case light
        case dark
    }

    let station: Station
    let size: CGFloat
    var surfaceStyle: SurfaceStyle = .light
    var contentInsetRatio: CGFloat = 0.16
    var cornerRadiusRatio: CGFloat = 0.24

    var body: some View {
        ZStack {
            artworkBackground
            artworkBasePlate
            artworkContent
                .frame(width: artworkStageWidth, height: artworkStageHeight)
                .padding(.horizontal, size * contentInsetRatio * 0.75)
                .padding(.vertical, size * contentInsetRatio * 0.6)
        }
        .frame(width: size, height: size)
        .clipShape(artworkShape)
        .overlay {
            artworkShape
                .stroke(borderColor, lineWidth: 1)
        }
        .shadow(color: shadowColor, radius: size * 0.12, y: size * 0.05)
    }

    private var artworkContent: some View {
        Group {
            if let artworkURL = station.displayArtworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(AvtunesysTheme.highlight.opacity(0.18))
                .frame(width: size * 0.62, height: size * 0.62)

            VStack(spacing: size * 0.08) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: size * 0.22, weight: .semibold))
                    .foregroundStyle(AvtunesysTheme.highlight)

                Text(station.initials)
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(fallbackTextColor)
            }
        }
    }

    private var artworkBackground: some View {
        ZStack {
            backgroundGradient
            Circle()
                .fill(AvtunesysTheme.highlight.opacity(0.08))
                .frame(width: size * 0.7, height: size * 0.7)
                .offset(x: size * 0.14, y: size * 0.12)
        }
    }

    private var artworkBasePlate: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.96), Color.white.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: artworkStageWidth, height: artworkStageHeight)
            .opacity(station.displayArtworkURL == nil ? 0 : 1)
            .shadow(color: Color.black.opacity(0.04), radius: size * 0.05, y: size * 0.02)
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * cornerRadiusRatio, style: .continuous)
    }

    private var artworkStageWidth: CGFloat { size * 0.76 }
    private var artworkStageHeight: CGFloat { size * 0.62 }

    private var backgroundGradient: LinearGradient {
        switch surfaceStyle {
        case .light:
            return LinearGradient(
                colors: [Color.white, Color(red: 0.96, green: 0.98, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [AvtunesysTheme.darkSurface, AvtunesysTheme.darkSurface.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch surfaceStyle {
        case .light: return AvtunesysTheme.borderSubtle
        case .dark: return Color.white.opacity(0.08)
        }
    }

    private var shadowColor: Color {
        switch surfaceStyle {
        case .light: return AvtunesysTheme.softShadow.opacity(0.08)
        case .dark: return AvtunesysTheme.softShadow.opacity(0.18)
        }
    }

    private var fallbackTextColor: Color {
        switch surfaceStyle {
        case .light: return AvtunesysTheme.textPrimary.opacity(0.92)
        case .dark: return AvtunesysTheme.textInverse.opacity(0.9)
        }
    }
}
