import ImageIO
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias TuneAVPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias TuneAVPlatformImage = NSImage
#endif

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

    static let visibleSearchTags = TuneAVMusicGenreCatalog.visibleTags

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

private struct StationFallbackIdentity {
    enum Motif {
        case broadcast
        case editorial
        case waveform
        case orbit
        case skyline
    }

    let primary: Color
    let secondary: Color
    let accent: Color
    let motif: Motif
    let layoutSeed: Int

    init(seed: String, category: TuneAVFallbackArtworkCategory) {
        let hash = TuneAVFallbackArtwork.stableHash(seed)
        let baseHue = Self.baseHue(for: category)
        let hueOffset = Double(hash % 23) / 100.0
        let accentHue = (baseHue + hueOffset).truncatingRemainder(dividingBy: 1)
        let companionHue = (accentHue + 0.12 + Double((hash / 29) % 17) / 100.0).truncatingRemainder(dividingBy: 1)
        let saturation = Self.saturation(for: category, hash: hash)

        primary = Color(hue: accentHue, saturation: saturation, brightness: Self.primaryBrightness(for: category))
        secondary = Color(hue: companionHue, saturation: max(saturation - 0.16, 0.34), brightness: Self.secondaryBrightness(for: category))
        accent = Color(hue: (accentHue + 0.54).truncatingRemainder(dividingBy: 1), saturation: min(saturation + 0.12, 0.86), brightness: 0.92)
        motif = Self.motif(for: category, hash: hash)
        layoutSeed = hash
    }

    private static func baseHue(for category: TuneAVFallbackArtworkCategory) -> Double {
        switch category {
        case .popHits: return 0.92
        case .rockAlternative: return 0.02
        case .electronicDance: return 0.58
        case .jazzBluesSoul: return 0.72
        case .chillAmbient: return 0.47
        case .latinWorld: return 0.08
        case .decadesOldies: return 0.13
        case .classicalInstrumental: return 0.11
        case .countryFolk: return 0.26
        case .genericUnknown: return 0.40
        }
    }

    private static func saturation(for category: TuneAVFallbackArtworkCategory, hash: Int) -> Double {
        let jitter = Double(hash % 12) / 100.0
        switch category {
        case .classicalInstrumental, .chillAmbient:
            return 0.34 + jitter
        case .jazzBluesSoul, .countryFolk, .decadesOldies:
            return 0.46 + jitter
        default:
            return 0.58 + jitter
        }
    }

    private static func primaryBrightness(for category: TuneAVFallbackArtworkCategory) -> Double {
        switch category {
        case .rockAlternative, .electronicDance:
            return 0.42
        case .classicalInstrumental, .chillAmbient:
            return 0.84
        default:
            return 0.68
        }
    }

    private static func secondaryBrightness(for category: TuneAVFallbackArtworkCategory) -> Double {
        switch category {
        case .rockAlternative, .electronicDance:
            return 0.58
        case .classicalInstrumental, .chillAmbient:
            return 0.94
        default:
            return 0.82
        }
    }

    private static func motif(for category: TuneAVFallbackArtworkCategory, hash: Int) -> Motif {
        switch category {
        case .popHits, .electronicDance:
            return hash.isMultiple(of: 2) ? .waveform : .orbit
        case .rockAlternative:
            return hash.isMultiple(of: 2) ? .waveform : .broadcast
        case .jazzBluesSoul, .chillAmbient, .classicalInstrumental:
            return hash.isMultiple(of: 2) ? .orbit : .waveform
        case .latinWorld, .countryFolk:
            return hash.isMultiple(of: 2) ? .skyline : .broadcast
        case .decadesOldies:
            return hash.isMultiple(of: 2) ? .editorial : .orbit
        case .genericUnknown:
            switch hash % 5 {
            case 0: return .broadcast
            case 1: return .editorial
            case 2: return .waveform
            case 3: return .orbit
            default: return .skyline
            }
        }
    }
}

struct StationArtworkView: View {
    enum ArtworkStyle {
        static let cornerRadiusRatio: CGFloat = 0.12

        static func cornerRadius(for size: CGFloat) -> CGFloat {
            size * cornerRadiusRatio
        }
    }

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
    @Environment(\.displayScale) private var displayScale

    let artworkURL: URL?
    private let fallbackText: String?
    private let stationName: String?
    private let fallbackSeed: String
    private let fallbackArtwork: TuneAVFallbackArtwork
    var size: CGFloat = 84
    var cornerRadiusRatio: CGFloat = ArtworkStyle.cornerRadiusRatio
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
        cornerRadiusRatio: CGFloat = ArtworkStyle.cornerRadiusRatio,
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
        cornerRadiusRatio: CGFloat = ArtworkStyle.cornerRadiusRatio,
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
            TuneAVRemoteArtworkImage(url: artworkURL, size: size, scale: displayScale) {
                fallbackCover
            }
        } else {
            fallbackCover
        }
    }

    private var fallbackCover: some View {
        let identity = StationFallbackIdentity(seed: fallbackSeed, category: fallbackArtwork.category)

        return ZStack {
            Image(fallbackArtwork.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
                .saturation(0.72)
                .contrast(0.92)

            identityColorWash(identity)
            identityMotif(identity)

            if shouldAnimateOverlay {
                selectedOverlay
                    .allowsHitTesting(false)
            }

            if textMode != .none {
                fallbackTextPlate
            }
        }
    }

    private func identityColorWash(_ identity: StationFallbackIdentity) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    identity.primary.opacity(0.46),
                    identity.secondary.opacity(0.28),
                    Color.white.opacity(0.10)
                ],
                startPoint: identity.layoutSeed.isMultiple(of: 2) ? .topLeading : .bottomLeading,
                endPoint: identity.layoutSeed.isMultiple(of: 2) ? .bottomTrailing : .topTrailing
            )

            RadialGradient(
                colors: [
                    identity.accent.opacity(0.34),
                    identity.accent.opacity(0.0)
                ],
                center: identity.layoutSeed.isMultiple(of: 3) ? .topTrailing : .bottomLeading,
                startRadius: size * 0.04,
                endRadius: size * 0.82
            )
            .blendMode(.softLight)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .blendMode(.screen)
        }
    }

    @ViewBuilder
    private func identityMotif(_ identity: StationFallbackIdentity) -> some View {
        switch identity.motif {
        case .broadcast:
            FallbackBroadcastMotif(size: size, color: identity.accent, seed: identity.layoutSeed)
        case .editorial:
            FallbackEditorialMotif(size: size, color: identity.accent, seed: identity.layoutSeed)
        case .waveform:
            FallbackWaveformMotif(size: size, color: identity.accent, seed: identity.layoutSeed)
        case .orbit:
            FallbackOrbitMotif(size: size, color: identity.accent, seed: identity.layoutSeed)
        case .skyline:
            FallbackSkylineMotif(size: size, color: identity.accent, seed: identity.layoutSeed)
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

struct TuneAVRemoteArtworkImage<Placeholder: View>: View {
    let url: URL
    let size: CGFloat
    let scale: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: requestKey) {
            image = nil
            let loadedImage = await TuneAVArtworkImagePipeline.shared.image(
                from: url,
                maxPixelSize: max(1, Int((size * scale).rounded(.up)))
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }

    private var requestKey: String {
        "\(url.absoluteString)|\(Int((size * scale).rounded(.up)))"
    }
}

actor TuneAVArtworkImagePipeline {
    static let shared = TuneAVArtworkImagePipeline()

    private let session: URLSession
    private let cache = NSCache<NSString, TuneAVPlatformImageBox>()
    private var inFlight: [String: Task<TuneAVPlatformImage?, Never>] = [:]

    init(session: URLSession = TuneAVURLSessions.artwork) {
        self.session = session
        cache.countLimit = 120
        cache.totalCostLimit = 36 * 1024 * 1024
    }

    func image(from url: URL, maxPixelSize: Int) async -> Image? {
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString)?.image {
            return Image(platformImage: cached)
        }

        if let task = inFlight[key] {
            return await task.value.map(Image.init(platformImage:))
        }

        let task = Task { [session] in
            await Self.loadImage(from: url, maxPixelSize: maxPixelSize, session: session)
        }
        inFlight[key] = task

        let loadedImage = await task.value
        inFlight[key] = nil
        if let loadedImage {
            cache.setObject(
                TuneAVPlatformImageBox(loadedImage),
                forKey: key as NSString,
                cost: maxPixelSize * maxPixelSize * 4
            )
        }
        return loadedImage.map(Image.init(platformImage:))
    }

    func clearMemoryCache() {
        cache.removeAllObjects()
    }

    private func cacheKey(url: URL, maxPixelSize: Int) -> String {
        "\(url.absoluteString)|\(maxPixelSize)"
    }

    private static func loadImage(from url: URL, maxPixelSize: Int, session: URLSession) async -> TuneAVPlatformImage? {
        do {
            let (data, response) = try await session.data(from: url)
            guard !Task.isCancelled else { return nil }
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return nil
            }
            return downsampleImage(data: data, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }

    private static func downsampleImage(data: Data, maxPixelSize: Int) -> TuneAVPlatformImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }
}

private final class TuneAVPlatformImageBox {
    let image: TuneAVPlatformImage

    init(_ image: TuneAVPlatformImage) {
        self.image = image
    }
}

private extension Image {
    init(platformImage: TuneAVPlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

private struct FallbackBroadcastMotif: View {
    let size: CGFloat
    let color: Color
    let seed: Int

    var body: some View {
        ZStack(alignment: seed.isMultiple(of: 2) ? .topTrailing : .bottomLeading) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .trim(from: 0.08, to: 0.36)
                    .stroke(color.opacity(0.18 + Double(index) * 0.05), lineWidth: max(1.2, size * 0.012))
                    .frame(width: size * (0.42 + CGFloat(index) * 0.16), height: size * (0.42 + CGFloat(index) * 0.16))
                    .rotationEffect(.degrees(seed.isMultiple(of: 2) ? -10 : 168))
            }

            Circle()
                .fill(color.opacity(0.22))
                .frame(width: size * 0.13, height: size * 0.13)
                .padding(size * 0.16)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

private struct FallbackEditorialMotif: View {
    let size: CGFloat
    let color: Color
    let seed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.045) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.015, style: .continuous)
                    .fill(color.opacity(0.16 + Double(index % 2) * 0.12))
                    .frame(width: lineWidth(index), height: max(1.5, size * 0.024))
            }
        }
        .rotationEffect(.degrees(seed.isMultiple(of: 2) ? -6 : 7))
        .frame(width: size, height: size, alignment: seed.isMultiple(of: 3) ? .bottomLeading : .topLeading)
        .padding(size * 0.16)
        .allowsHitTesting(false)
    }

    private func lineWidth(_ index: Int) -> CGFloat {
        let base = [0.62, 0.42, 0.7, 0.5, 0.34][index]
        return size * CGFloat(base)
    }
}

private struct FallbackWaveformMotif: View {
    let size: CGFloat
    let color: Color
    let seed: Int

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.024) {
            ForEach(0..<9, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color.opacity(0.24 + Double((index + seed) % 3) * 0.08))
                    .frame(width: size * 0.035, height: barHeight(index))
            }
        }
        .rotationEffect(.degrees(seed.isMultiple(of: 2) ? -8 : 8))
        .frame(width: size, height: size, alignment: .center)
        .allowsHitTesting(false)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let steps: [CGFloat] = [0.18, 0.38, 0.62, 0.44, 0.76, 0.42, 0.58, 0.32, 0.2]
        let shiftedIndex = (index + seed) % steps.count
        return size * steps[shiftedIndex]
    }
}

private struct FallbackOrbitMotif: View {
    let size: CGFloat
    let color: Color
    let seed: Int

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .stroke(color.opacity(0.16 + Double(index) * 0.08), lineWidth: max(1, size * 0.01))
                    .frame(width: size * (0.56 + CGFloat(index) * 0.16), height: size * (0.24 + CGFloat(index) * 0.08))
                    .rotationEffect(.degrees(Double((seed % 36) - 18) + Double(index) * 34))
            }

            Circle()
                .fill(color.opacity(0.22))
                .frame(width: size * 0.14, height: size * 0.14)
                .offset(x: size * (seed.isMultiple(of: 2) ? 0.24 : -0.24), y: size * -0.18)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

private struct FallbackSkylineMotif: View {
    let size: CGFloat
    let color: Color
    let seed: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: size * 0.02) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.015, style: .continuous)
                    .fill(color.opacity(0.16 + Double((index + seed) % 2) * 0.12))
                    .frame(width: size * 0.07, height: size * skylineHeight(index))
            }
        }
        .frame(width: size, height: size, alignment: seed.isMultiple(of: 2) ? .bottomLeading : .bottomTrailing)
        .padding(size * 0.13)
        .allowsHitTesting(false)
    }

    private func skylineHeight(_ index: Int) -> CGFloat {
        let heights: [CGFloat] = [0.18, 0.28, 0.44, 0.34, 0.52, 0.24, 0.38]
        return heights[(index + seed) % heights.count]
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
