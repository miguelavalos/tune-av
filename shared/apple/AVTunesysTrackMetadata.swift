import Foundation

struct AVTunesysNowPlayingTrack: Equatable, Sendable {
    let title: String
    let artist: String?
}

enum AVTunesysNowPlayingMetadata {
    static func metadataInterval(from response: HTTPURLResponse) -> Int? {
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).caseInsensitiveCompare("icy-metaint") == .orderedSame else {
                continue
            }
            return Int(String(describing: value))
        }

        return nil
    }

    static func parseICYMetadata(_ bytes: [UInt8]) -> AVTunesysNowPlayingTrack? {
        let metadata = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            .replacingOccurrences(of: "\0", with: "")

        guard let streamTitle = metadataValue(named: "StreamTitle", in: metadata), !streamTitle.isEmpty else {
            return nil
        }

        return AVTunesysTrackMetadataParser.parse(streamTitle).nowPlayingTrack
    }

    private static func metadataValue(named name: String, in metadata: String) -> String? {
        let pattern = "\(name)='([^']*)'"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(metadata.startIndex..<metadata.endIndex, in: metadata)
        guard
            let match = regex.firstMatch(in: metadata, range: nsRange),
            let valueRange = Range(match.range(at: 1), in: metadata)
        else {
            return nil
        }

        return String(metadata[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AVTunesysTrackMetadata: Equatable, Sendable {
    var title: String?
    var artist: String?
}

enum AVTunesysTrackMetadataParser {
    static func parse(_ rawValue: String) -> AVTunesysTrackMetadata {
        let cleaned = rawValue
            .replacingOccurrences(of: "StreamTitle=", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "'; ").union(.whitespacesAndNewlines))

        for separator in [" - ", " – ", " — "] where cleaned.contains(separator) {
            let parts = cleaned.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }

            let artist = sanitizeArtist(parts[0])
            let title = sanitizeTitle(parts.dropFirst().joined(separator: separator), artist: artist)
            return AVTunesysTrackMetadata(title: title, artist: artist)
        }

        return AVTunesysTrackMetadata(title: sanitizeTitle(cleaned, artist: nil), artist: nil)
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

private extension AVTunesysTrackMetadata {
    var nowPlayingTrack: AVTunesysNowPlayingTrack? {
        guard let title else { return nil }
        return AVTunesysNowPlayingTrack(title: title, artist: artist)
    }
}
