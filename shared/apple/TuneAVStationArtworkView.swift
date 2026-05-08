import SwiftUI

struct StationArtworkView: View {
    enum SurfaceStyle {
        case light
        case dark
    }

    let artworkURL: URL?
    private let fallbackText: String?
    private let fallbackSeed: String
    var size: CGFloat = 84
    var cornerRadiusRatio: CGFloat = 0.24
    var contentInsetRatio: CGFloat = 0.18
    var surfaceStyle: SurfaceStyle = .light
    var stageWidthRatio: CGFloat = 0.64
    var stageHeightRatio: CGFloat = 0.48
    var basePlateShadowColor: Color = Color.black.opacity(0.12)

    init(
        artworkURL: URL?,
        fallbackText: String? = nil,
        fallbackSeed: String? = nil,
        size: CGFloat = 84,
        cornerRadiusRatio: CGFloat = 0.24,
        contentInsetRatio: CGFloat = 0.18,
        surfaceStyle: SurfaceStyle = .light,
        stageWidthRatio: CGFloat = 0.64,
        stageHeightRatio: CGFloat = 0.48,
        basePlateShadowColor: Color = Color.black.opacity(0.12)
    ) {
        self.artworkURL = artworkURL
        self.fallbackText = fallbackText
        self.fallbackSeed = fallbackSeed ?? fallbackText ?? artworkURL?.absoluteString ?? "Tune AV"
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
            artworkURL: station.displayArtworkURL,
            fallbackText: station.initials,
            fallbackSeed: "\(station.id)|\(station.name)|\(station.countryCode ?? station.country)|\(station.tags)",
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
            artworkSurface
        }
        .frame(width: size, height: size)
        .clipShape(artworkShape)
        .overlay {
            artworkShape
                .stroke(borderColor, lineWidth: 1)
        }
        .shadow(color: shadowColor, radius: size * 0.12, y: size * 0.05)
    }

    @ViewBuilder
    private var artworkSurface: some View {
        if let artworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    logoSurface(image: image)
                default:
                    generatedFallbackCover
                }
            }
        } else {
            generatedFallbackCover
        }
    }

    private func logoSurface(image: Image) -> some View {
        ZStack {
            artworkBackground
            artworkBasePlate

            image
                .resizable()
                .scaledToFit()
                .frame(width: artworkStageWidth, height: artworkStageHeight)
                .padding(.horizontal, size * contentInsetRatio * 0.75)
                .padding(.vertical, size * contentInsetRatio * 0.6)
        }
        .accessibilityHidden(true)
    }

    private var generatedFallbackCover: some View {
        ZStack {
            fallbackGradient

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(fallbackAccent(index).opacity(index == 0 ? 0.34 : 0.2))
                    .frame(width: fallbackCircleSize(index), height: fallbackCircleSize(index))
                    .blur(radius: size * (index == 0 ? 0.018 : 0.03))
                    .offset(fallbackCircleOffset(index))
            }

            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: max(1, size * 0.012))
                .frame(width: size * 0.72, height: size * 0.72)
                .rotationEffect(.degrees(Double((fallbackHash % 19)) - 9))

            VStack(spacing: size * 0.07) {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.86))

                if let fallbackText {
                    Text(fallbackText)
                        .font(.system(size: size * 0.24, weight: .black))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .shadow(color: Color.black.opacity(0.18), radius: size * 0.08, y: size * 0.03)
        }
        .accessibilityHidden(true)
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

    private var fallbackTextColor: Color {
        switch surfaceStyle {
        case .light:
            return TuneAVTheme.textPrimary.opacity(0.92)
        case .dark:
            return TuneAVTheme.textInverse.opacity(0.9)
        }
    }

    private var fallbackGradient: LinearGradient {
        LinearGradient(
            colors: [
                fallbackBaseColor(hueOffset: 0, brightness: surfaceStyle == .dark ? 0.26 : 0.72),
                fallbackBaseColor(hueOffset: 0.08, brightness: surfaceStyle == .dark ? 0.18 : 0.52),
                fallbackBaseColor(hueOffset: -0.11, brightness: surfaceStyle == .dark ? 0.14 : 0.42)
            ],
            startPoint: fallbackHash.isMultiple(of: 2) ? .topLeading : .topTrailing,
            endPoint: fallbackHash.isMultiple(of: 2) ? .bottomTrailing : .bottomLeading
        )
    }

    private var fallbackSymbol: String {
        let symbols = [
            "dot.radiowaves.left.and.right",
            "antenna.radiowaves.left.and.right",
            "waveform",
            "music.note",
            "badge.plus.radiowaves.right"
        ]
        return symbols[fallbackHash % symbols.count]
    }

    private var fallbackHash: Int {
        var hash = 2_166_136_261
        for scalar in fallbackSeed.unicodeScalars {
            hash = (hash ^ Int(scalar.value)) &* 16_777_619
        }
        return abs(hash)
    }

    private func fallbackBaseColor(hueOffset: Double, brightness: Double) -> Color {
        let hue = (Double(fallbackHash % 360) / 360 + hueOffset).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.58, brightness: brightness)
    }

    private func fallbackAccent(_ index: Int) -> Color {
        fallbackBaseColor(hueOffset: Double(index + 1) * 0.17, brightness: surfaceStyle == .dark ? 0.54 : 0.9)
    }

    private func fallbackCircleSize(_ index: Int) -> CGFloat {
        size * [0.9, 0.58, 0.42][index]
    }

    private func fallbackCircleOffset(_ index: Int) -> CGSize {
        let xSigns: [CGFloat] = fallbackHash.isMultiple(of: 2) ? [-0.28, 0.34, -0.08] : [0.28, -0.34, 0.08]
        let ySigns: [CGFloat] = [-0.3, 0.28, 0.38]
        return CGSize(width: size * xSigns[index], height: size * ySigns[index])
    }
}
