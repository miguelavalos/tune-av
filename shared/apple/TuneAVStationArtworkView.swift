import SwiftUI

struct StationArtworkView: View {
    enum SurfaceStyle {
        case light
        case dark
    }

    let artworkURL: URL?
    var size: CGFloat = 84
    var cornerRadiusRatio: CGFloat = 0.24
    var contentInsetRatio: CGFloat = 0.18
    var surfaceStyle: SurfaceStyle = .light
    var stageWidthRatio: CGFloat = 0.64
    var stageHeightRatio: CGFloat = 0.48
    var basePlateShadowColor: Color = Color.black.opacity(0.12)

    init(
        artworkURL: URL?,
        size: CGFloat = 84,
        cornerRadiusRatio: CGFloat = 0.24,
        contentInsetRatio: CGFloat = 0.18,
        surfaceStyle: SurfaceStyle = .light,
        stageWidthRatio: CGFloat = 0.64,
        stageHeightRatio: CGFloat = 0.48,
        basePlateShadowColor: Color = Color.black.opacity(0.12)
    ) {
        self.artworkURL = artworkURL
        self.size = size
        self.cornerRadiusRatio = cornerRadiusRatio
        self.contentInsetRatio = contentInsetRatio
        self.surfaceStyle = surfaceStyle
        self.stageWidthRatio = stageWidthRatio
        self.stageHeightRatio = stageHeightRatio
        self.basePlateShadowColor = basePlateShadowColor
    }

    init(
        station: Station,
        size: CGFloat = 84,
        surfaceStyle: SurfaceStyle = .light,
        contentInsetRatio: CGFloat = 0.18,
        cornerRadiusRatio: CGFloat = 0.24,
        stageWidthRatio: CGFloat = 0.64,
        stageHeightRatio: CGFloat = 0.48,
        basePlateShadowColor: Color = Color.black.opacity(0.12)
    ) {
        self.init(
            artworkURL: station.faviconURL.flatMap(URL.init(string:)),
            size: size,
            cornerRadiusRatio: cornerRadiusRatio,
            contentInsetRatio: contentInsetRatio,
            surfaceStyle: surfaceStyle,
            stageWidthRatio: stageWidthRatio,
            stageHeightRatio: stageHeightRatio,
            basePlateShadowColor: basePlateShadowColor
        )
    }

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
            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(TuneAVTheme.highlight.opacity(surfaceStyle == .dark ? 0.24 : 0.18))
                .frame(width: size * 0.42, height: size * 0.42)

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundStyle(TuneAVTheme.highlight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artworkBackground: some View {
        ZStack {
            backgroundGradient

            Circle()
                .fill(TuneAVTheme.highlight.opacity(0.08))
                .frame(width: size * 0.7, height: size * 0.7)
                .offset(x: -size * 0.16, y: -size * 0.18)

            Circle()
                .fill(Color.white.opacity(surfaceStyle == .dark ? 0.06 : 0.34))
                .frame(width: size * 0.44, height: size * 0.44)
                .offset(x: size * 0.22, y: size * 0.2)
        }
    }

    private var artworkBasePlate: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color.white.opacity(0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size * 0.72, height: size * 0.58)
            .rotationEffect(.degrees(-7))
            .shadow(color: basePlateShadowColor, radius: size * 0.08, y: size * 0.04)
    }

    private var artworkShape: some Shape {
        RoundedRectangle(cornerRadius: size * cornerRadiusRatio, style: .continuous)
    }

    private var artworkStageWidth: CGFloat {
        size * stageWidthRatio
    }

    private var artworkStageHeight: CGFloat {
        size * stageHeightRatio
    }

    private var backgroundGradient: LinearGradient {
        switch surfaceStyle {
        case .light:
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.96, green: 0.98, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            LinearGradient(
                colors: [
                    TuneAVTheme.darkSurface,
                    TuneAVTheme.darkSurface.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.borderSubtle
        case .dark:
            return Color.white.opacity(0.08)
        }
    }

    private var shadowColor: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.softShadow.opacity(0.08)
        case .dark:
            return TuneAVTheme.softShadow.opacity(0.18)
        }
    }
}
