import Foundation

struct TuneAVNowPlayingTrack: Equatable, Sendable {
    let title: String
    let artist: String?
}

struct TuneAVStationDisplayLines: Equatable, Sendable {
    let artistLine: String
    let titleLine: String

    static func resolve(
        station: Station,
        isCurrent: Bool,
        currentArtist: String?,
        currentTitle: String?,
        currentAlbumTitle: String?,
        nowPlayingTrack: TuneAVNowPlayingTrack?,
        detailText: String,
        liveFallback: String
    ) -> TuneAVStationDisplayLines {
        let artistLine: String
        if isCurrent, let artist = TuneAVDisplayMetadata.normalized(currentArtist) {
            artistLine = artist
        } else if let artist = TuneAVDisplayMetadata.normalized(nowPlayingTrack?.artist) {
            artistLine = artist
        } else {
            artistLine = detailText
        }

        let titleLine: String
        if isCurrent, let title = TuneAVDisplayMetadata.normalized(currentTitle) {
            titleLine = title
        } else if let title = TuneAVDisplayMetadata.normalized(nowPlayingTrack?.title) {
            titleLine = title
        } else if isCurrent, let albumTitle = TuneAVDisplayMetadata.normalized(currentAlbumTitle) {
            titleLine = albumTitle
        } else if let primaryTag = station.normalizedTags.first {
            titleLine = primaryTag
        } else {
            titleLine = TuneAVDisplayMetadata.normalized(station.language) ?? liveFallback
        }

        return TuneAVStationDisplayLines(artistLine: artistLine, titleLine: titleLine)
    }
}

struct TuneAVNowPlayingDisplayLines: Equatable, Sendable {
    let stationMetaLine: String
    let trackTitleLine: String
    let trackSupportingLine: String
    let hasDiscoverableTrack: Bool

    static func resolve(
        station: Station,
        currentTitle: String?,
        currentArtist: String?,
        currentAlbumTitle: String?,
        liveNowFallback: String,
        liveStreamFallback: String
    ) -> TuneAVNowPlayingDisplayLines {
        let title = TuneAVDisplayMetadata.plausibleTitle(currentTitle, stationName: station.name)
        let artist = TuneAVDisplayMetadata.plausibleArtist(currentArtist, stationName: station.name)

        let stationMetaLine: String
        if title != nil {
            stationMetaLine = station.name
        } else {
            let meta = station.shortMeta.trimmingCharacters(in: .whitespacesAndNewlines)
            stationMetaLine = meta.isEmpty ? liveNowFallback : meta
        }

        let trackSupportingLine: String
        if let artist {
            trackSupportingLine = artist
        } else if let albumTitle = TuneAVDisplayMetadata.normalized(currentAlbumTitle) {
            trackSupportingLine = albumTitle
        } else {
            let tags = station.normalizedTags
                .compactMap(TuneAVMusicGenreCatalog.canonicalTag(for:))
                .map { L10n.genreLabel(for: $0) }
                .reduce(into: [String]()) { result, tag in
                    guard !result.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else { return }
                    result.append(tag)
                }
                .prefix(2)
                .joined(separator: " · ")
            trackSupportingLine = tags.isEmpty ? liveStreamFallback : tags
        }

        return TuneAVNowPlayingDisplayLines(
            stationMetaLine: stationMetaLine,
            trackTitleLine: title ?? station.name,
            trackSupportingLine: trackSupportingLine,
            hasDiscoverableTrack: title != nil && artist != nil
        )
    }
}

struct TuneAVCurrentDiscovery: Equatable, Sendable {
    let title: String
    let artist: String
    let stationName: String

    var searchQuery: String {
        "\(artist) \(title)"
    }

    var shareText: String {
        TuneAVDiscoveryShareTextFormatter.currentTrackText(
            title: title,
            artist: artist,
            stationName: stationName
        )
    }

    var localizedShareText: String {
        L10n.string("player.discovery.shareText", title, artist, stationName)
    }

    static func resolve(title: String?, artist: String?, station: Station?) -> TuneAVCurrentDiscovery? {
        guard let station else { return nil }
        guard
            let resolvedTitle = TuneAVDisplayMetadata.plausibleTitle(title, stationName: station.name),
            let resolvedArtist = TuneAVDisplayMetadata.plausibleArtist(artist, stationName: station.name)
        else {
            return nil
        }

        return TuneAVCurrentDiscovery(
            title: resolvedTitle,
            artist: resolvedArtist,
            stationName: station.name
        )
    }
}

enum TuneAVNowPlayingMetadata {
    static func metadataInterval(from response: HTTPURLResponse) -> Int? {
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).caseInsensitiveCompare("icy-metaint") == .orderedSame else {
                continue
            }
            return Int(String(describing: value))
        }

        return nil
    }

    static func parseICYMetadata(_ bytes: [UInt8]) -> TuneAVNowPlayingTrack? {
        let metadata = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            .replacingOccurrences(of: "\0", with: "")

        guard let streamTitle = metadataValue(named: "StreamTitle", in: metadata), !streamTitle.isEmpty else {
            return nil
        }

        return TuneAVTrackMetadataParser.parse(streamTitle).nowPlayingTrack
    }

    static func metadataValue(named name: String, in metadata: String) -> String? {
        guard
            let nameRange = metadata.range(of: name, options: [.caseInsensitive]),
            let equalsRange = metadata[nameRange.upperBound...].range(of: "=")
        else {
            return nil
        }

        var cursor = equalsRange.upperBound
        while cursor < metadata.endIndex, metadata[cursor].isWhitespace {
            cursor = metadata.index(after: cursor)
        }

        guard cursor < metadata.endIndex else { return nil }

        let quote = metadata[cursor]
        if quote == "'" || quote == "\"" {
            cursor = metadata.index(after: cursor)
            var value = ""
            var isEscaped = false

            while cursor < metadata.endIndex {
                let character = metadata[cursor]

                if isEscaped {
                    value.append(character)
                    isEscaped = false
                    cursor = metadata.index(after: cursor)
                    continue
                }

                if character == "\\" {
                    isEscaped = true
                    cursor = metadata.index(after: cursor)
                    continue
                }

                let nextIndex = metadata.index(after: cursor)
                if character == quote {
                    if nextIndex == metadata.endIndex || metadata[nextIndex] == ";" {
                        break
                    }
                }

                value.append(character)
                cursor = nextIndex
            }

            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let endIndex = metadata[cursor...].firstIndex(of: ";") ?? metadata.endIndex
        return String(metadata[cursor..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TuneAVTrackMetadata: Equatable, Sendable {
    var title: String?
    var artist: String?
}

enum TuneAVDisplayMetadata {
    static func normalized(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)
    }

    static func plausibleTitle(_ value: String?, stationName: String?) -> String? {
        guard let title = normalized(value) else { return nil }
        guard !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(title, stationName: stationName) else {
            return nil
        }
        return title
    }

    static func plausibleArtist(_ value: String?, stationName: String?) -> String? {
        guard let artist = normalized(value) else { return nil }
        guard !TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(artist, stationName: stationName) else {
            return nil
        }
        return artist
    }
}

enum TuneAVTrackMetadataParser {
    static func parse(_ rawValue: String) -> TuneAVTrackMetadata {
        let unwrappedValue = TuneAVNowPlayingMetadata.metadataValue(named: "StreamTitle", in: rawValue) ?? rawValue
        let cleaned = unwrappedValue
            .trimmingCharacters(in: CharacterSet(charactersIn: "'; ").union(.whitespacesAndNewlines))

        for separator in [" - ", " – ", " — "] where cleaned.contains(separator) {
            let parts = cleaned.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }

            let artist = sanitizeArtist(parts[0])
            let title = sanitizeTitle(parts.dropFirst().joined(separator: separator), artist: artist)
            return TuneAVTrackMetadata(title: title, artist: artist)
        }

        return TuneAVTrackMetadata(title: sanitizeTitle(cleaned, artist: nil), artist: nil)
    }

    static func sanitizeTitle(_ rawValue: String?, artist: String?) -> String? {
        guard var value = sanitizeMetadataField(rawValue) else { return nil }

        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if containsLetters(value) {
            return value
        }

        if isNumericOnlyMetadata(value) {
            let digits = value.filter(\.isNumber).count

            // Large numeric-only metadata values are typically IDs, not song titles.
            if digits > 4 {
                return nil
            }

            // Short numeric titles can be legitimate, but not without a plausible artist.
            return artist == nil ? nil : value
        }

        return nil
    }

    static func sanitizeArtist(_ rawValue: String?) -> String? {
        guard var value = sanitizeMetadataField(rawValue) else { return nil }

        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return containsLetters(value) ? value : nil
    }

    static func titleLooksLikeStationName(_ title: String?, stationName: String?) -> Bool {
        guard
            let title = sanitizedComparableValue(title),
            let stationName = sanitizedComparableValue(stationName)
        else {
            return false
        }

        if title.compact == stationName.compact {
            return true
        }

        let shorterCount = min(title.compact.count, stationName.compact.count)
        let longerCount = max(title.compact.count, stationName.compact.count)
        if shorterCount >= 8, title.compact.contains(stationName.compact) || stationName.compact.contains(title.compact) {
            return true
        }

        if shorterCount >= 5, Double(shorterCount) / Double(longerCount) >= 0.72 {
            if title.compact.contains(stationName.compact) || stationName.compact.contains(title.compact) {
                return true
            }
        }

        if title.compact.count >= 5, stationName.compact.hasPrefix(title.compact) {
            return true
        }

        let distance = levenshteinDistance(title.compact, stationName.compact)
        let similarity = 1 - (Double(distance) / Double(longerCount))
        if longerCount >= 6, similarity >= 0.86 {
            return true
        }

        let titleTokenSet = Set(title.tokens)
        let stationTokenSet = Set(stationName.tokens)
        let sharedTokens = titleTokenSet.intersection(stationTokenSet).count
        let totalTokens = titleTokenSet.union(stationTokenSet).count

        if title.tokens.count >= 2, title.compact.count >= 8, titleTokenSet.isSubset(of: stationTokenSet) {
            return true
        }

        if title.tokens.count == 1, title.compact.count >= 8, stationTokenSet.contains(title.compact) {
            return true
        }

        return totalTokens > 0 && Double(sharedTokens) / Double(totalTokens) >= 0.80
    }

    static func valueLooksLikeBroadcastMetadata(_ value: String?, stationName: String?) -> Bool {
        guard let comparable = sanitizedComparableValue(value) else {
            return false
        }

        if titleLooksLikeStationName(value, stationName: stationName) {
            return true
        }

        let compact = comparable.compact
        let tokenSet = Set(comparable.tokens)

        let exactPlaceholders: Set<String> = [
            "live",
            "onair",
            "online",
            "streaming",
            "nowplaying",
            "noplaying",
            "unknown",
            "sininfo",
            "envivo",
            "endirecto"
        ]
        if exactPlaceholders.contains(compact) {
            return true
        }

        let phrasePlaceholders: [[String]] = [
            ["now", "playing"],
            ["currently", "playing"],
            ["live", "stream"],
            ["live", "radio"],
            ["radio", "online"],
            ["on", "air"],
            ["en", "vivo"],
            ["en", "directo"],
            ["sin", "informacion"],
            ["no", "metadata"],
            ["no", "title"]
        ]
        if phrasePlaceholders.contains(where: { Set($0).isSubset(of: tokenSet) }) {
            return true
        }

        if comparable.tokens.count <= 3 {
            let stationLikeTokens: Set<String> = [
                "radio",
                "fm",
                "am",
                "dab",
                "stream",
                "station",
                "emisora",
                "broadcast"
            ]
            if tokenSet.isSubset(of: stationLikeTokens) {
                return true
            }
        }

        return false
    }

    static func artistLooksLikeBroadcastMetadata(_ artist: String?, stationName: String?) -> Bool {
        guard let comparable = sanitizedComparableValue(artist) else {
            return false
        }

        if let artistComparable = sanitizedComparableValue(artist),
           let stationComparable = sanitizedComparableValue(stationName),
           artistComparable.compact == stationComparable.compact,
           !containsBroadcastContextToken(artistComparable.tokens) {
            return false
        }

        if valueLooksLikeBroadcastMetadata(artist, stationName: stationName) {
            return true
        }

        let tokenSet = Set(comparable.tokens)
        if comparable.tokens.count <= 4 {
            let stationContextTokens: Set<String> = [
                "radio",
                "fm",
                "am",
                "live",
                "online",
                "stream",
                "station",
                "emisora"
            ]
            return !tokenSet.intersection(stationContextTokens).isEmpty
        }

        return false
    }

    static func titleLooksLikeTruncatedContraction(_ title: String?) -> Bool {
        guard let title = sanitizeMetadataField(title) else { return false }

        let folded = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let normalized = folded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastToken = normalized.split(separator: " ").last.map(String.init) else { return false }

        let truncatedContractionPrefixes: Set<String> = [
            "i",
            "don",
            "doesn",
            "didn",
            "can",
            "couldn",
            "won",
            "wouldn",
            "shouldn",
            "isn",
            "aren",
            "wasn",
            "weren",
            "hasn",
            "haven",
            "hadn",
            "ain"
        ]

        return truncatedContractionPrefixes.contains(lastToken)
    }

    private static func containsBroadcastContextToken(_ tokens: [String]) -> Bool {
        let stationContextTokens: Set<String> = [
            "radio",
            "fm",
            "am",
            "dab",
            "live",
            "online",
            "stream",
            "station",
            "emisora",
            "broadcast"
        ]

        return !Set(tokens).intersection(stationContextTokens).isEmpty
    }

    private static func sanitizeMetadataField(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let trimmed = rawValue
            .trimmingCharacters(in: CharacterSet(charactersIn: "'; ").union(.whitespacesAndNewlines))

        guard !trimmed.isEmpty else { return nil }

        let blockedValues: Set<String> = ["unknown", "n/a", "na", "null", "nil", "-", "--"]
        guard !blockedValues.contains(trimmed.lowercased()) else { return nil }

        return trimmed
    }

    private static func containsLetters(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private static func isNumericOnlyMetadata(_ value: String) -> Bool {
        let filtered = value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        guard !filtered.isEmpty else { return false }
        return filtered.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func sanitizedComparableValue(_ rawValue: String?) -> (compact: String, tokens: [String])? {
        guard let rawValue = sanitizeMetadataField(rawValue) else { return nil }

        let folded = rawValue
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let scalars = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        let spaced = String(scalars)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = spaced.split(separator: " ").map(String.init)
        let compact = tokens.joined()

        return compact.isEmpty ? nil : (compact, tokens)
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)

        for lhsIndex in 1...lhs.count {
            current[0] = lhsIndex
            for rhsIndex in 1...rhs.count {
                let cost = lhs[lhsIndex - 1] == rhs[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + cost
                )
            }
            previous = current
        }

        return previous[rhs.count]
    }
}

private extension TuneAVTrackMetadata {
    var nowPlayingTrack: TuneAVNowPlayingTrack? {
        guard let title else { return nil }
        return TuneAVNowPlayingTrack(title: title, artist: artist)
    }
}
