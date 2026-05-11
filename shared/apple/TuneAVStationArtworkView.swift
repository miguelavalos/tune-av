import SwiftUI

enum TuneAVFallbackArtworkCategory: String, Equatable {
    case popHits
    case rockAlternative
    case electronicDance
    case jazzBluesSoul
    case chillAmbient
    case latinWorld
    case decadesOldies
    case classicalInstrumental
    case countryFolk
    case genericUnknown

    static let visibleSearchTags = [
        popHits.searchTag,
        rockAlternative.searchTag,
        electronicDance.searchTag,
        jazzBluesSoul.searchTag,
        chillAmbient.searchTag,
        latinWorld.searchTag,
        decadesOldies.searchTag,
        classicalInstrumental.searchTag,
        countryFolk.searchTag
    ]

    var searchTag: String {
        switch self {
        case .popHits:
            return "pop"
        case .rockAlternative:
            return "rock"
        case .electronicDance:
            return "electronic"
        case .jazzBluesSoul:
            return "jazz"
        case .chillAmbient:
            return "ambient"
        case .latinWorld:
            return "latin"
        case .decadesOldies:
            return "oldies"
        case .classicalInstrumental:
            return "classical"
        case .countryFolk:
            return "country"
        case .genericUnknown:
            return "music"
        }
    }
}

struct TuneAVFallbackArtwork: Equatable {
    let category: TuneAVFallbackArtworkCategory
    let assetName: String

    static let popHitsA = TuneAVFallbackArtwork(category: .popHits, assetName: "fallback-pop-hits-a")
    static let popHitsB = TuneAVFallbackArtwork(category: .popHits, assetName: "fallback-pop-hits-b")
    static let rockAlternativeA = TuneAVFallbackArtwork(category: .rockAlternative, assetName: "fallback-rock-alternative-a")
    static let rockAlternativeB = TuneAVFallbackArtwork(category: .rockAlternative, assetName: "fallback-rock-alternative-b")
    static let electronicDance = TuneAVFallbackArtwork(category: .electronicDance, assetName: "fallback-electronic-dance")
    static let jazzBluesSoul = TuneAVFallbackArtwork(category: .jazzBluesSoul, assetName: "fallback-jazz-blues-soul")
    static let chillAmbient = TuneAVFallbackArtwork(category: .chillAmbient, assetName: "fallback-chill-ambient")
    static let latinWorld = TuneAVFallbackArtwork(category: .latinWorld, assetName: "fallback-latin-world")
    static let decadesOldies = TuneAVFallbackArtwork(category: .decadesOldies, assetName: "fallback-decades-oldies")
    static let classicalInstrumental = TuneAVFallbackArtwork(category: .classicalInstrumental, assetName: "fallback-classical-instrumental")
    static let countryFolk = TuneAVFallbackArtwork(category: .countryFolk, assetName: "fallback-country-folk")
    static let genericUnknown = TuneAVFallbackArtwork(category: .genericUnknown, assetName: "fallback-generic-unknown")
    static let all: [TuneAVFallbackArtwork] = [
        popHitsA,
        popHitsB,
        rockAlternativeA,
        rockAlternativeB,
        electronicDance,
        jazzBluesSoul,
        chillAmbient,
        latinWorld,
        decadesOldies,
        classicalInstrumental,
        countryFolk,
        genericUnknown
    ]

    private static let fallbackBackgrounds: [TuneAVFallbackArtworkCategory: [TuneAVFallbackArtwork]] = [
        .popHits: [.popHitsA, .popHitsB],
        .rockAlternative: [.rockAlternativeA, .rockAlternativeB],
        .electronicDance: [.electronicDance],
        .jazzBluesSoul: [.jazzBluesSoul],
        .chillAmbient: [.chillAmbient],
        .latinWorld: [.latinWorld],
        .decadesOldies: [.decadesOldies],
        .classicalInstrumental: [.classicalInstrumental],
        .countryFolk: [.countryFolk],
        .genericUnknown: [.genericUnknown]
    ]

    static func select(for station: Station) -> TuneAVFallbackArtwork {
        let category = category(forTags: station.tagsList) ?? .genericUnknown
        let variants = fallbackBackgrounds[category] ?? fallbackBackgrounds[.genericUnknown] ?? all
        return variants[stableHash(station.id) % variants.count]
    }

    static func category(forTags tags: [String]) -> TuneAVFallbackArtworkCategory? {
        let normalized = tags.map {
            $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: "-", with: " ")
                .lowercased()
        }

        if normalized.contains(where: { tag in
            tag.contains("rock") || tag.contains("metal") || tag.contains("alternative") || tag.contains("indie")
        }) {
            return .rockAlternative
        }

        if normalized.contains(where: { tag in
            tag.contains("pop") || tag.contains("hits") || tag.contains("top 40") || tag.contains("adult contemporary")
        }) {
            return .popHits
        }

        if normalized.contains(where: { tag in
            tag.contains("electronic") || tag.contains("dance") || tag.contains("house") || tag.contains("techno") || tag.contains("disco")
        }) {
            return .electronicDance
        }

        if normalized.contains(where: { tag in
            tag.contains("jazz") || tag.contains("blues") || tag.contains("soul")
        }) {
            return .jazzBluesSoul
        }

        if normalized.contains(where: { tag in
            tag.contains("chill") || tag.contains("ambient") || tag.contains("easy listening") || tag.contains("lounge")
        }) {
            return .chillAmbient
        }

        if normalized.contains(where: { tag in
            tag.contains("latin") || tag.contains("latino") || tag.contains("world") || tag.contains("mexican") || tag.contains("banda") || tag.contains("grupera") || tag.contains("espanol") || tag.contains("spanish")
        }) {
            return .latinWorld
        }

        if normalized.contains(where: { tag in
            tag.contains("oldies") || tag.contains("retro") || tag.contains("70s") || tag.contains("80s") || tag.contains("90s") || tag.contains("2000s")
        }) {
            return .decadesOldies
        }

        if normalized.contains(where: { tag in
            tag.contains("classical") || tag.contains("instrumental") || tag.contains("orchestra") || tag.contains("piano")
        }) {
            return .classicalInstrumental
        }

        if normalized.contains(where: { tag in
            tag.contains("country") || tag.contains("folk") || tag.contains("americana") || tag.contains("bluegrass")
        }) {
            return .countryFolk
        }

        return nil
    }

    static func stableHash(_ value: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(Int.max))
    }
}

struct StationArtworkView: View {
    enum SurfaceStyle {
        case light
        case dark
    }

    enum TextMode {
        case none
        case initials
        case stationName
    }

    enum AnimationOverlay {
        case none
        case radioWaves
        case equalizerBars
        case cardEqualizerBars
        case inkDots
        case floatingNotes
        case signalScan
        case waveformDraw
        case vinylDialPulse
        case automatic
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let artworkURL: URL?
    private let fallbackText: String?
    private let stationName: String?
    private let fallbackSeed: String
    private let fallbackArtwork: TuneAVFallbackArtwork
    var size: CGFloat = 84
    var cornerRadiusRatio: CGFloat = 0.24
    var contentInsetRatio: CGFloat = 0.18
    var surfaceStyle: SurfaceStyle = .light
    var stageWidthRatio: CGFloat = 0.64
    var stageHeightRatio: CGFloat = 0.48
    var basePlateShadowColor: Color = Color.black.opacity(0.12)
    var textMode: TextMode = .initials
    var animationOverlay: AnimationOverlay = .none
    var isAnimationActive: Bool = false
    var animationDuration: TimeInterval?

    @State private var isTimedAnimationActive = true
    @State private var timedAnimationGeneration = 0

    init(
        artworkURL: URL?,
        fallbackText: String? = nil,
        fallbackSeed: String? = nil,
        fallbackArtwork: TuneAVFallbackArtwork = .popHitsA,
        stationName: String? = nil,
        size: CGFloat = 84,
        cornerRadiusRatio: CGFloat = 0.24,
        contentInsetRatio: CGFloat = 0.18,
        surfaceStyle: SurfaceStyle = .light,
        stageWidthRatio: CGFloat = 0.64,
        stageHeightRatio: CGFloat = 0.48,
        basePlateShadowColor: Color = Color.black.opacity(0.12),
        textMode: TextMode = .initials,
        animationOverlay: AnimationOverlay = .none,
        isAnimationActive: Bool = false,
        animationDuration: TimeInterval? = nil
    ) {
        self.artworkURL = artworkURL
        self.fallbackText = fallbackText
        self.stationName = stationName
        self.fallbackSeed = fallbackSeed ?? fallbackText ?? artworkURL?.absoluteString ?? "Tune AV"
        self.fallbackArtwork = fallbackArtwork
        self.size = size
        self.cornerRadiusRatio = cornerRadiusRatio
        self.contentInsetRatio = contentInsetRatio
        self.surfaceStyle = surfaceStyle
        self.stageWidthRatio = stageWidthRatio
        self.stageHeightRatio = stageHeightRatio
        self.basePlateShadowColor = basePlateShadowColor
        self.textMode = textMode
        self.animationOverlay = animationOverlay
        self.isAnimationActive = isAnimationActive
        self.animationDuration = animationDuration
    }

    init(
        station: Station,
        size: CGFloat = 84,
        surfaceStyle: SurfaceStyle = .light,
        contentInsetRatio: CGFloat = 0.18,
        cornerRadiusRatio: CGFloat = 0.24,
        stageWidthRatio: CGFloat = 0.64,
        stageHeightRatio: CGFloat = 0.48,
        basePlateShadowColor: Color = Color.black.opacity(0.12),
        textMode: TextMode = .initials,
        animationOverlay: AnimationOverlay = .none,
        isAnimationActive: Bool = false,
        animationDuration: TimeInterval? = nil
    ) {
        self.init(
            artworkURL: nil,
            fallbackText: station.initials,
            fallbackSeed: station.id,
            fallbackArtwork: station.fallbackArtwork,
            stationName: station.name,
            size: size,
            cornerRadiusRatio: cornerRadiusRatio,
            contentInsetRatio: contentInsetRatio,
            surfaceStyle: surfaceStyle,
            stageWidthRatio: stageWidthRatio,
            stageHeightRatio: stageHeightRatio,
            basePlateShadowColor: basePlateShadowColor,
            textMode: textMode,
            animationOverlay: animationOverlay,
            isAnimationActive: isAnimationActive,
            animationDuration: animationDuration
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
        .accessibilityHidden(true)
        .onAppear(perform: resetTimedAnimation)
        .onChange(of: isAnimationActive) { _, _ in
            resetTimedAnimation()
        }
        .onChange(of: fallbackSeed) { _, _ in
            resetTimedAnimation()
        }
    }

    @ViewBuilder
    private var artworkSurface: some View {
        if let artworkURL {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallbackCover
                }
            }
        } else {
            fallbackCover
        }
    }

    private var fallbackCover: some View {
        ZStack {
            Image(fallbackArtwork.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()

            if shouldAnimateOverlay {
                selectedOverlay
                    .allowsHitTesting(false)
            }

            if textMode != .none {
                fallbackTextPlate
            }
        }
    }

    @ViewBuilder
    private var fallbackTextPlate: some View {
        let text = resolvedOverlayText
        let isName = textMode == .stationName && text == stationName

        Text(text)
            .font(.system(size: isName ? size * 0.135 : size * 0.25, weight: .black, design: .rounded))
            .foregroundStyle(inkColor)
            .multilineTextAlignment(.center)
            .lineLimit(isName ? 3 : 1)
            .minimumScaleFactor(isName ? 0.45 : 0.66)
            .allowsTightening(true)
            .padding(.horizontal, size * (isName ? 0.115 : 0.12))
            .padding(.vertical, size * (isName ? 0.08 : 0.055))
            .frame(maxWidth: size * 0.72, maxHeight: size * 0.42)
            .background(
                RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                    .fill(Color(red: 0.98, green: 0.96, blue: 0.9).opacity(isName ? 0.78 : 0.7))
                    .shadow(color: Color.black.opacity(0.08), radius: size * 0.05, y: size * 0.025)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                    .stroke(inkColor.opacity(0.1), lineWidth: max(1, size * 0.006))
            }
    }

    @ViewBuilder
    private var selectedOverlay: some View {
        switch resolvedOverlay {
        case .none:
            EmptyView()
        case .radioWaves:
            RadioWavesArtworkOverlay(size: size)
        case .equalizerBars:
            EqualizerBarsArtworkOverlay(size: size)
        case .cardEqualizerBars:
            CardEqualizerBarsArtworkOverlay(size: size)
        case .inkDots:
            InkDotsArtworkOverlay(size: size, seed: fallbackSeed)
        case .floatingNotes:
            FloatingNotesArtworkOverlay(size: size)
        case .signalScan:
            SignalScanArtworkOverlay(size: size)
        case .waveformDraw:
            WaveformDrawArtworkOverlay(size: size, seed: fallbackSeed)
        case .vinylDialPulse:
            VinylDialPulseArtworkOverlay(size: size)
        case .automatic:
            if textMode == .stationName {
                ProminentArtworkOverlay(size: size, seed: fallbackSeed)
            } else {
                automaticCompactOverlay
            }
        }
    }

    @ViewBuilder
    private var automaticCompactOverlay: some View {
        switch TuneAVFallbackArtwork.stableHash(fallbackSeed) % 7 {
        case 0:
            RadioWavesArtworkOverlay(size: size)
        case 1:
            EqualizerBarsArtworkOverlay(size: size)
        case 2:
            InkDotsArtworkOverlay(size: size, seed: fallbackSeed)
        case 3:
            FloatingNotesArtworkOverlay(size: size)
        case 4:
            SignalScanArtworkOverlay(size: size)
        case 5:
            WaveformDrawArtworkOverlay(size: size, seed: fallbackSeed)
        default:
            VinylDialPulseArtworkOverlay(size: size)
        }
    }

    private var resolvedOverlayText: String {
        switch textMode {
        case .none:
            return ""
        case .initials:
            return fallbackText ?? TuneAVInitials.make(from: stationName ?? "Tune AV")
        case .stationName:
            let name = TuneAVText.normalizedValue(stationName) ?? fallbackText ?? "Tune AV"
            return name.count <= 34 ? name : (fallbackText ?? TuneAVInitials.make(from: name))
        }
    }

    private var shouldAnimateOverlay: Bool {
        isAnimationActive && isTimedAnimationActive && !reduceMotion && scenePhase == .active && !isLowPowerModeEnabled
    }

    private var resolvedOverlay: AnimationOverlay {
        guard animationOverlay == .automatic else { return animationOverlay }
        switch TuneAVFallbackArtwork.stableHash(fallbackSeed) % 7 {
        case 0:
            return .radioWaves
        case 1:
            return .equalizerBars
        case 2:
            return .inkDots
        case 3:
            return .floatingNotes
        case 4:
            return .signalScan
        case 5:
            return .waveformDraw
        default:
            return .vinylDialPulse
        }
    }

    private var isLowPowerModeEnabled: Bool {
        #if os(iOS)
        ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        false
        #endif
    }

    private func resetTimedAnimation() {
        timedAnimationGeneration += 1
        let generation = timedAnimationGeneration
        isTimedAnimationActive = true
        guard isAnimationActive, let animationDuration else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(animationDuration * 1_000_000_000))
            guard generation == timedAnimationGeneration else { return }
            isTimedAnimationActive = false
        }
    }

    private var artworkShape: some Shape {
        RoundedRectangle(cornerRadius: size * cornerRadiusRatio, style: .continuous)
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

    private var inkColor: Color {
        Color(red: 0.08, green: 0.1, blue: 0.29)
    }
}

private struct RadioWavesArtworkOverlay: View {
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.08, to: 0.33)
                    .stroke(TuneAVTheme.highlight.opacity(0.36 - Double(index) * 0.055), lineWidth: max(2, size * 0.015))
                    .frame(width: size * (0.42 + CGFloat(index) * 0.18), height: size * (0.42 + CGFloat(index) * 0.18))
                    .rotationEffect(.degrees(-12))
                    .scaleEffect(pulse ? 1.11 + CGFloat(index) * 0.035 : 0.9)
                    .opacity(pulse ? 0.92 : 0.34)
            }
        }
        .frame(width: size, height: size, alignment: .topTrailing)
        .padding(size * 0.06)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct EqualizerBarsArtworkOverlay: View {
    let size: CGFloat

    private let scales: [CGFloat] = [0.34, 0.68, 0.48, 0.86, 0.56]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.7)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 0.7)

            HStack(alignment: .bottom, spacing: size * 0.018) {
                ForEach(scales.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: size * 0.01, style: .continuous)
                        .fill(TuneAVTheme.highlight.opacity(0.58))
                        .frame(width: size * 0.026, height: size * scales[index] * barScale(index: index, tick: tick))
                }
            }
            .frame(width: size, height: size, alignment: .bottomLeading)
            .padding(.leading, size * 0.12)
            .padding(.bottom, size * 0.13)
        }
    }

    private func barScale(index: Int, tick: Int) -> CGFloat {
        ((tick + index) % 3 == 0) ? 0.3 : 0.14
    }
}

private struct CardEqualizerBarsArtworkOverlay: View {
    let size: CGFloat

    private let scales: [CGFloat] = [0.42, 0.82, 0.58, 0.96, 0.68, 0.48]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.7)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 0.7)

            HStack(alignment: .bottom, spacing: size * 0.022) {
                ForEach(scales.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: size * 0.012, style: .continuous)
                        .fill(TuneAVTheme.highlight.opacity(0.74))
                        .frame(
                            width: size * 0.05,
                            height: size * scales[index] * animatedScale(for: index, tick: tick)
                        )
                        .shadow(color: TuneAVTheme.highlight.opacity(0.2), radius: size * 0.018, y: size * 0.006)
                }
            }
            .frame(width: size, height: size, alignment: .bottomLeading)
            .padding(.leading, size * 0.11)
            .padding(.bottom, size * 0.13)
        }
    }

    private func animatedScale(for index: Int, tick: Int) -> CGFloat {
        ((tick + index) % 3 == 0) ? 0.34 : 0.15
    }
}

private struct InkDotsArtworkOverlay: View {
    let size: CGFloat
    let seed: String
    @State private var sparkle = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(dotColor(index).opacity(sparkle ? 0.72 : 0.18))
                    .frame(width: dotSize(index), height: dotSize(index))
                    .offset(dotOffset(index))
                    .scaleEffect(sparkle && index.isMultiple(of: 2) ? 1.35 : 0.78)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                sparkle = true
            }
        }
    }

    private func dotSize(_ index: Int) -> CGFloat {
        size * (0.02 + CGFloat((hash + index) % 4) * 0.008)
    }

    private func dotOffset(_ index: Int) -> CGSize {
        let x = CGFloat(((hash >> UInt(index % 8)) + index * 37) % 74) / 100 - 0.37
        let y = CGFloat(((hash >> UInt((index + 3) % 8)) + index * 29) % 76) / 100 - 0.38
        return CGSize(width: size * x, height: size * y)
    }

    private func dotColor(_ index: Int) -> Color {
        index.isMultiple(of: 3) ? TuneAVTheme.highlight : Color(red: 0.08, green: 0.1, blue: 0.29)
    }

    private var hash: Int {
        TuneAVFallbackArtwork.stableHash(seed)
    }
}

private struct ProminentArtworkOverlay: View {
    let size: CGFloat
    let seed: String

    var body: some View {
        ZStack {
            RadioWavesArtworkOverlay(size: size)
            WaveformDrawArtworkOverlay(size: size, seed: seed)
            InkDotsArtworkOverlay(size: size, seed: seed)
        }
        .frame(width: size, height: size)
    }
}

private struct FloatingNotesArtworkOverlay: View {
    let size: CGFloat
    @State private var float = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index == 1 ? "music.quarternote.3" : "music.note")
                    .font(.system(size: size * (index == 1 ? 0.09 : 0.075), weight: .bold))
                    .foregroundStyle(index == 1 ? TuneAVTheme.highlight.opacity(0.58) : Color(red: 0.08, green: 0.1, blue: 0.29).opacity(0.34))
                    .offset(noteOffset(index, isFloating: float))
                    .opacity(float ? 0.82 : 0.34)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                float = true
            }
        }
    }

    private func noteOffset(_ index: Int, isFloating: Bool) -> CGSize {
        let baseX = [-0.28, 0.24, 0.33][index]
        let baseY = [-0.2, -0.32, 0.2][index]
        return CGSize(width: size * CGFloat(baseX), height: size * (CGFloat(baseY) + (isFloating ? -0.035 : 0.025)))
    }
}

private struct SignalScanArtworkOverlay: View {
    let size: CGFloat
    @State private var scan = false

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, TuneAVTheme.highlight.opacity(0.32), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: size * 0.16, height: size * 1.25)
            .rotationEffect(.degrees(12))
            .offset(x: scan ? size * 0.58 : -size * 0.58)
            .frame(width: size, height: size)
            .clipped()
            .onAppear {
                withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: false)) {
                    scan = true
                }
            }
    }
}

private struct WaveformDrawArtworkOverlay: View {
    let size: CGFloat
    let seed: String
    @State private var drawn = false

    var body: some View {
        WaveformShape(seed: TuneAVFallbackArtwork.stableHash(seed))
            .trim(from: 0, to: drawn ? 1 : 0.22)
            .stroke(TuneAVTheme.highlight.opacity(0.58), style: StrokeStyle(lineWidth: max(2, size * 0.012), lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.68, height: size * 0.18)
            .offset(x: size * 0.02, y: size * 0.29)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    drawn = true
                }
            }
    }
}

private struct WaveformShape: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let samples = 8
        for index in 0..<samples {
            let progress = CGFloat(index) / CGFloat(samples - 1)
            let x = rect.minX + rect.width * progress
            let hashOffset = CGFloat((seed >> UInt(index % 8)) & 3) / 3
            let amplitude = (index.isMultiple(of: 2) ? 0.18 : 0.82) * 0.72 + hashOffset * 0.16
            let y = rect.midY + (amplitude - 0.5) * rect.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

private struct VinylDialPulseArtworkOverlay: View {
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.08, green: 0.1, blue: 0.29).opacity(0.18), lineWidth: max(1, size * 0.01))
                .frame(width: size * 0.34, height: size * 0.34)

            Circle()
                .stroke(TuneAVTheme.highlight.opacity(pulse ? 0.42 : 0.16), lineWidth: max(2, size * 0.014))
                .frame(width: size * (pulse ? 0.44 : 0.28), height: size * (pulse ? 0.44 : 0.28))

            Circle()
                .fill(TuneAVTheme.highlight.opacity(0.42))
                .frame(width: size * 0.045, height: size * 0.045)
        }
        .frame(width: size, height: size, alignment: .bottomTrailing)
        .padding(.trailing, size * 0.12)
        .padding(.bottom, size * 0.12)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
