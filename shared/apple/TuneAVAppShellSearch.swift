import Foundation

enum TuneAVStationDiscoveryMode: String, Equatable {
    case music
    case allRadio
}

enum TuneAVStationFeedback: String, Codable, CaseIterable {
    case liked
    case disliked
    case notForMe

    var localizedState: String {
        switch self {
        case .liked:
            return L10n.string("shell.stationFeedback.like")
        case .disliked:
            return L10n.string("shell.stationFeedback.dislike")
        case .notForMe:
            return L10n.string("shell.stationFeedback.notForMe")
        }
    }

    var systemImage: String {
        switch self {
        case .liked:
            return "hand.thumbsup.fill"
        case .disliked:
            return "hand.thumbsdown.fill"
        case .notForMe:
            return "minus.circle.fill"
        }
    }
}

enum TuneAVMusicGenreCatalog {
    static let visibleTags = [
        "pop",
        "rock",
        "electronic",
        "latin",
        "dance",
        "jazz",
        "chill",
        "oldies",
        "classical",
        "hip-hop",
        "indie",
        "country"
    ]

    private static let canonicalTags = Set(visibleTags)
    private static let aliases: [String: String] = [
        "alternative": "rock",
        "alternative rock": "rock",
        "classic rock": "rock",
        "hard rock": "rock",
        "metal": "rock",
        "pop rock": "rock",
        "top 40": "pop",
        "hits": "pop",
        "charts": "pop",
        "electro": "electronic",
        "electronica": "electronic",
        "house": "electronic",
        "techno": "electronic",
        "latina": "latin",
        "latino": "latin",
        "world": "latin",
        "spanish": "latin",
        "espanol": "latin",
        "ambient": "chill",
        "lounge": "chill",
        "easy listening": "chill",
        "70s": "oldies",
        "80s": "oldies",
        "90s": "oldies",
        "2000s": "oldies",
        "retro": "oldies",
        "hiphop": "hip-hop",
        "hip hop": "hip-hop",
        "rap": "hip-hop",
        "folk": "country",
        "americana": "country"
    ]

    static func canonicalTag(for rawTag: String) -> String? {
        let normalized = rawTag
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        let direct = normalized.replacingOccurrences(of: " ", with: "-")
        if canonicalTags.contains(direct) {
            return direct
        }

        if let alias = aliases[normalized] {
            return alias
        }

        return aliases.first { normalized.contains($0.key) }?.value
    }
}

enum TuneAVStationMusicClassifier {
    static let musicTags = TuneAVMusicGenreCatalog.visibleTags

    private static let musicSignals = Set([
        "music",
        "pop",
        "rock",
        "electronic",
        "dance",
        "latin",
        "jazz",
        "chill",
        "classical",
        "oldies",
        "hip-hop",
        "hiphop",
        "indie",
        "ambient",
        "soul",
        "blues",
        "hits",
        "charts",
        "alternative",
        "house",
        "techno",
        "country",
        "folk",
        "reggae",
        "metal",
        "rnb",
        "instrumental"
    ])

    private static let nonMusicSignals = Set([
        "news",
        "sports",
        "sport",
        "talk",
        "culture",
        "religion",
        "religious",
        "public",
        "comedy",
        "politics",
        "business",
        "finance",
        "weather",
        "traffic",
        "podcast"
    ])

    static func isMusicStation(_ station: Station) -> Bool {
        musicScore(station) > 0 && nonMusicCategory(station) == nil
    }

    static func musicScore(_ station: Station) -> Int {
        var score = 0
        let category = normalized(station.category)
        if category == "music" {
            score += 6
        } else if let category, nonMusicSignals.contains(category) {
            score -= 6
        }

        for token in normalizedTokens(from: station.tagsList) {
            if musicSignals.contains(token) {
                score += 2
            }
            if nonMusicSignals.contains(token) {
                score -= 3
            }
        }

        if let editorial = station.editorial {
            score += musicIntensityScore(editorial.musicIntensity)
            score -= speechIntensityPenalty(editorial.speechIntensity)
            if normalized(editorial.primaryFormat) == "music" {
                score += 3
            }
            let discoveryProfile = editorial.discoveryProfile
            if let discoveryProfile {
                score += max(0, min(4, discoveryProfile.musicDiscoveryScore / 25))
            }
            for token in normalizedTokens(from: editorial.secondaryFormats + editorial.programming + (discoveryProfile?.genres ?? []) + (discoveryProfile?.moods ?? [])) {
                if musicSignals.contains(token) {
                    score += 1
                }
                if nonMusicSignals.contains(token) {
                    score -= 2
                }
            }
        }

        return score
    }

    static func nonMusicCategory(_ station: Station) -> String? {
        if let category = normalized(station.category), nonMusicSignals.contains(category) {
            return category
        }

        return normalizedTokens(from: station.tagsList).first { nonMusicSignals.contains($0) }
    }

    static func isExplicitNonMusicIntent(query: String, tag: String?) -> Bool {
        let values = [query, tag].compactMap { $0 }
        return normalizedTokens(from: values).contains { nonMusicSignals.contains($0) }
    }

    static func orderedForDiscoveryMode(_ stations: [Station], mode: TuneAVStationDiscoveryMode, request: AppShellSearchRequest) -> [Station] {
        guard mode == .music else { return stations }
        guard !isExplicitNonMusicIntent(query: request.query, tag: request.tag) else { return stations }

        let scored = stations.map { station in
            (station: station, score: musicScore(station))
        }
        let musicStations = scored
            .filter { $0.score > 0 && nonMusicCategory($0.station) == nil }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return (lhs.station.clickCount ?? 0) > (rhs.station.clickCount ?? 0)
            }
            .map(\.station)

        if !musicStations.isEmpty {
            return musicStations
        }

        return scored
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .map(\.station)
    }

    private static func normalizedTokens(from values: [String]) -> [String] {
        values.flatMap { value in
            value
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
                .map(String.init)
        }
    }

    private static func normalized(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)?.lowercased()
    }

    private static func musicIntensityScore(_ value: String) -> Int {
        switch normalized(value) {
        case "high":
            return 4
        case "medium":
            return 2
        case "low":
            return 1
        default:
            return 0
        }
    }

    private static func speechIntensityPenalty(_ value: String) -> Int {
        switch normalized(value) {
        case "high":
            return 4
        case "medium":
            return 2
        default:
            return 0
        }
    }
}

enum TuneAVAviEmotion: Equatable {
    case neutral
    case listening
    case focused
    case happy
    case celebrate
    case surprised
    case thinking
    case warning
    case sleep
    case dislike

    var assetName: String {
        switch self {
        case .neutral:
            return "AviV2HeadNeutral"
        case .listening:
            return "AviV2TuneListening"
        case .focused:
            return "AviV2TuneFocused"
        case .happy:
            return "AviV2TuneHappy"
        case .celebrate:
            return "AviV2TuneCelebrate"
        case .surprised:
            return "AviV2TuneSurprised"
        case .thinking:
            return "AviV2Thinking"
        case .warning:
            return "AviV2Warning"
        case .sleep:
            return "AviV2Sleep"
        case .dislike:
            return "AviV2TuneDislike"
        }
    }

    var fullBodyAssetName: String {
        switch self {
        case .neutral:
            return "AviV2NeutralFullbody"
        default:
            return assetName
        }
    }

    var transitionPriority: Int {
        switch self {
        case .warning:
            return 4
        case .thinking:
            return 3
        case .celebrate, .dislike:
            return 2
        case .surprised, .happy:
            return 1
        case .neutral, .listening, .focused, .sleep:
            return 0
        }
    }
}

enum TuneAVAviEmotionStability {
    static let defaultMinimumDisplayInterval: TimeInterval = 2.4
    static let immediateMinimumDisplayInterval: TimeInterval = 0.45

    static func shouldAdopt(
        displayed: TuneAVAviEmotion,
        candidate: TuneAVAviEmotion,
        elapsedSinceLastChange: TimeInterval,
        minimumDisplayInterval: TimeInterval = defaultMinimumDisplayInterval
    ) -> Bool {
        guard displayed != candidate else { return false }
        if candidate.transitionPriority > displayed.transitionPriority {
            return elapsedSinceLastChange >= immediateMinimumDisplayInterval
        }
        return elapsedSinceLastChange >= minimumDisplayInterval
    }
}

enum TuneAVAviEmotionResolver {
    static func playerEmotion(
        for station: Station,
        isPlaying: Bool,
        isLoading: Bool,
        hasFailure: Bool,
        hasDiscoverableTrack: Bool,
        isCurrentTrackSaved: Bool,
        feedback: TuneAVStationFeedback?,
        stationDiscoveryCount: Int
    ) -> TuneAVAviEmotion {
        if hasFailure {
            return .warning
        }
        if isLoading {
            return .thinking
        }
        if let feedback {
            return emotion(for: feedback)
        }
        if isCurrentTrackSaved {
            return .happy
        }
        if isPlaying, hasDiscoverableTrack {
            return stationDiscoveryCount == 0 ? .surprised : energeticEmotion(for: station)
        }
        if isPlaying {
            return ambientEmotion(for: station)
        }
        return .neutral
    }

    static func homeEmotion(currentStation: Station?, recentCount: Int, favoriteCount: Int) -> TuneAVAviEmotion {
        if let currentStation {
            return ambientEmotion(for: currentStation)
        }
        if favoriteCount > 0 {
            return .happy
        }
        if recentCount > 0 {
            return .focused
        }
        return .thinking
    }

    static func searchEmotion(isLoading: Bool, hasResults: Bool, query: String, discoveryMode: TuneAVStationDiscoveryMode) -> TuneAVAviEmotion {
        if isLoading {
            return .thinking
        }
        if !hasResults && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .surprised
        }
        switch discoveryMode {
        case .music:
            return .focused
        case .allRadio:
            return .neutral
        }
    }

    static func libraryEmotion(favoriteCount: Int, recentCount: Int, isFiltering: Bool) -> TuneAVAviEmotion {
        if isFiltering {
            return .focused
        }
        if favoriteCount == 0 && recentCount == 0 {
            return .thinking
        }
        if favoriteCount > 0 {
            return .happy
        }
        return .neutral
    }

    static func musicEmotion(visibleDiscoveryCount: Int, savedDiscoveryCount: Int, artistCount: Int) -> TuneAVAviEmotion {
        if visibleDiscoveryCount == 0 {
            return .listening
        }
        if savedDiscoveryCount >= 3 || artistCount >= 3 {
            return .celebrate
        }
        if savedDiscoveryCount > 0 {
            return .happy
        }
        return .focused
    }

    static func focusedSignalEmotion(
        focusedStation: Station?,
        isFocusedStationActive: Bool,
        isPlaying: Bool,
        isLoading: Bool,
        currentTrackTitle: String?,
        currentTrackArtist: String?,
        feedback: TuneAVStationFeedback?
    ) -> TuneAVAviEmotion {
        guard let focusedStation else {
            return .thinking
        }
        if isLoading {
            return .thinking
        }
        if let feedback {
            return emotion(for: feedback)
        }
        if isFocusedStationActive, isPlaying {
            let hasTrack = TuneAVText.normalizedValue(currentTrackTitle) != nil || TuneAVText.normalizedValue(currentTrackArtist) != nil
            return hasTrack ? energeticEmotion(for: focusedStation) : ambientEmotion(for: focusedStation)
        }
        return .focused
    }

    static func emotion(for feedback: TuneAVStationFeedback) -> TuneAVAviEmotion {
        switch feedback {
        case .liked:
            return .celebrate
        case .notForMe:
            return .thinking
        case .disliked:
            return .dislike
        }
    }

    private static func energeticEmotion(for station: Station) -> TuneAVAviEmotion {
        let tokens = Set(stationEmotionTokens(for: station))
        if !tokens.isDisjoint(with: ["dance", "electronic", "house", "techno", "hits", "charts", "pop", "party"]) {
            return .celebrate
        }
        if !tokens.isDisjoint(with: ["rock", "alternative", "metal", "hip-hop", "hiphop", "latin", "reggae"]) {
            return .happy
        }
        if !tokens.isDisjoint(with: ["news", "sports", "talk", "public", "politics", "business"]) {
            return .focused
        }
        return .listening
    }

    private static func ambientEmotion(for station: Station) -> TuneAVAviEmotion {
        let tokens = Set(stationEmotionTokens(for: station))
        if !tokens.isDisjoint(with: ["ambient", "chill", "chillout", "classical", "instrumental"]) {
            return .sleep
        }
        if !tokens.isDisjoint(with: ["jazz", "blues", "soul", "folk", "country"]) {
            return .listening
        }
        if TuneAVStationMusicClassifier.nonMusicCategory(station) != nil {
            return .focused
        }
        return energeticEmotion(for: station)
    }

    private static func stationEmotionTokens(for station: Station) -> [String] {
        var values = station.tagsList
        values.append(station.category ?? "")
        if let editorial = station.editorial {
            values.append(editorial.primaryFormat)
            values.append(editorial.musicIntensity)
            values.append(editorial.speechIntensity)
            values += editorial.secondaryFormats
            values += editorial.programming
            if let discoveryProfile = editorial.discoveryProfile {
                values.append(discoveryProfile.attentionMode)
                values.append(discoveryProfile.musicLevel)
                values.append(discoveryProfile.speechLevel)
                values += discoveryProfile.genres
                values += discoveryProfile.moods
                values += discoveryProfile.bestFor
            }
        }
        return values.flatMap { value in
            value
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
                .map(String.init)
        }
    }
}

struct AppShellSearchRequest: Equatable {
    let query: String
    let tag: String?
    let countryCode: String?
    let discoveryMode: TuneAVStationDiscoveryMode

    init(query: String, tag: String?, countryCode: String?, discoveryMode: TuneAVStationDiscoveryMode = .music) {
        self.query = TuneAVText.normalizedValue(query) ?? ""
        self.tag = TuneAVText.normalizedValue(tag)
        self.countryCode = TuneAVCountry.sanitizedCode(countryCode)
        self.discoveryMode = discoveryMode
    }

    var key: String {
        "\(query)|\(tag ?? "")|\(countryCode ?? "")|\(discoveryMode.rawValue)"
    }

    var usesWorldwideDiscovery: Bool {
        query.isEmpty && countryCode == nil
    }

    var searchLimit: Int {
        query.isEmpty ? AppShellHomeFeed.defaultFeedLimit : 24
    }
}

struct AppShellSearch {
    private static let maxWorldwideDiscoveryCountryRequests = 6

    let stationService: StationService
    let resolvedDeviceCountryCode: () -> String?
    let hasResolvedCountry: (Station) -> Bool

    @MainActor
    func load(
        request: AppShellSearchRequest,
        recentStations: [Station],
        favoriteStations: [Station]
    ) async throws -> [Station] {
        if request.usesWorldwideDiscovery {
            let stations = try await loadPopularDiscoveryStations(
                limit: AppShellHomeFeed.defaultFeedLimit,
                tag: request.tag,
                countryCode: resolvedDeviceCountryCode(),
                language: Locale.autoupdatingCurrent.language.languageCode?.identifier,
                recentStations: recentStations,
                favoriteStations: favoriteStations
            )
            return TuneAVStationMusicClassifier.orderedForDiscoveryMode(stations, mode: request.discoveryMode, request: request)
        }

        let stations = try await stationService.searchStations(
            filters: .init(
                query: request.query,
                countryCode: request.countryCode ?? "",
                tag: request.tag ?? "",
                limit: request.searchLimit,
                allowsEmptySearch: request.query.isEmpty
            )
        )
        return TuneAVStationMusicClassifier.orderedForDiscoveryMode(stations, mode: request.discoveryMode, request: request)
    }

    @MainActor
    func loadPopularDiscoveryStations(
        limit: Int,
        tag: String?,
        countryCode: String?,
        language: String?,
        recentStations: [Station],
        favoriteStations: [Station]
    ) async throws -> [Station] {
        let sanitizedCountryCode = TuneAVCountry.sanitizedCode(countryCode)
        let normalizedLanguage = TuneAVText.normalizedValue(language)?.lowercased()
        do {
            let popularStations = try await stationService.popularStations(
                filters: .init(
                    query: "",
                    countryCode: sanitizedCountryCode ?? "",
                    language: normalizedLanguage ?? "",
                    tag: tag ?? "",
                    limit: limit,
                    allowsEmptySearch: true
                )
            )

            let countryStations = sanitizedCountryCode != nil && popularStations.count < limit
                ? (try? await stationService.popularStations(
                    filters: .init(
                        query: "",
                        countryCode: sanitizedCountryCode ?? "",
                        tag: tag ?? "",
                        limit: limit - popularStations.count,
                        allowsEmptySearch: true
                    )
                )) ?? []
                : []
            let regionalStations = Self.mergeUniqueStations(
                primary: popularStations,
                secondary: countryStations,
                limit: limit
            )
            let globalStations = regionalStations.count < limit
                ? (try? await stationService.popularStations(
                    filters: .init(
                        query: "",
                        language: normalizedLanguage ?? "",
                        tag: tag ?? "",
                        limit: limit - regionalStations.count,
                        allowsEmptySearch: true
                    )
                )) ?? []
                : []

            let merged = Self.mergeUniqueStations(
                primary: regionalStations,
                secondary: globalStations + recentStations + favoriteStations + Station.samples,
                limit: limit
            )

            if !merged.isEmpty {
                return merged
            }
        } catch {
            let localStations = Self.mergeUniqueStations(
                primary: recentStations + favoriteStations,
                secondary: Station.samples,
                limit: limit
            )
            if !localStations.isEmpty {
                return localStations
            }
        }

        return try await loadWorldwideDiscoveryStations(
            limit: limit,
            tag: tag,
            recentStations: recentStations,
            favoriteStations: favoriteStations
        )
    }

    @MainActor
    func loadWorldwideDiscoveryStations(
        limit: Int,
        tag: String?,
        recentStations: [Station],
        favoriteStations: [Station]
    ) async throws -> [Station] {
        let orderedCodes = Self.orderedDiscoveryCountryCodes(
            deviceCountryCode: resolvedDeviceCountryCode(),
            recentStations: recentStations,
            favoriteStations: favoriteStations
        )

        var merged: [Station] = []
        for code in orderedCodes.prefix(Self.maxWorldwideDiscoveryCountryRequests) {
            let stations = try await stationService.searchStations(
                filters: .init(
                    query: "",
                    countryCode: code,
                    tag: tag ?? "",
                    limit: tag == nil ? 4 : 6,
                    allowsEmptySearch: true
                )
            )
            merged = Self.mergeUniqueStations(
                primary: merged,
                secondary: stations.filter(hasResolvedCountry),
                limit: limit
            )

            if merged.count >= limit {
                break
            }
        }

        return Array(merged.prefix(limit))
    }

    static func localUITestSearchResults(
        samples: [Station] = Station.samples,
        request: AppShellSearchRequest
    ) -> [Station] {
        let matches = samples.filter { station in
            let matchesQuery =
                request.query.isEmpty
                || station.name.localizedCaseInsensitiveContains(request.query)
                || station.country.localizedCaseInsensitiveContains(request.query)
                || station.tags.localizedCaseInsensitiveContains(request.query)

            let matchesTag =
                request.tag?.isEmpty != false
                || station.tags.localizedCaseInsensitiveContains(request.tag ?? "")

            let matchesCountry =
                request.countryCode?.isEmpty != false
                || station.countryCode?.caseInsensitiveCompare(request.countryCode ?? "") == .orderedSame

            return matchesQuery && matchesTag && matchesCountry
        }
        return TuneAVStationMusicClassifier.orderedForDiscoveryMode(matches, mode: request.discoveryMode, request: request)
    }

    static func orderedDiscoveryCountryCodes(
        deviceCountryCode: String?,
        recentStations: [Station],
        favoriteStations: [Station],
        fallbackCountryCodes: [String] = ["US", "GB", "DE", "FR", "IT", "ES", "NL", "CA", "AU", "BR", "MX", "AR"]
    ) -> [String] {
        let seedCountryCodes =
            [deviceCountryCode] +
            recentStations.compactMap(\.countryCode) +
            favoriteStations.compactMap(\.countryCode) +
            fallbackCountryCodes

        var orderedCodes: [String] = []
        var seenCodes = Set<String>()
        for code in seedCountryCodes.compactMap(TuneAVCountry.sanitizedCode) where seenCodes.insert(code).inserted {
            orderedCodes.append(code)
        }

        return orderedCodes
    }

    private static func mergeUniqueStations(primary: [Station], secondary: [Station], limit: Int) -> [Station] {
        var seen = Set<String>()
        var merged: [Station] = []

        for station in primary + secondary {
            guard seen.insert(station.id).inserted else { continue }
            merged.append(station)
            if merged.count == limit {
                break
            }
        }

        return merged
    }
}
