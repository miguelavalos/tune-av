import Foundation

enum TuneAVDiscoveredTrackSupport {
    static func normalizedValue(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)
    }

    static func makeID(title: String, artist: String?, stationID: String, locale: Locale = .current) -> String {
        let rawValue = "\(artist ?? "")|\(title)|\(stationID)"
        return rawValue
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func trackKey(title: String, artist: String?, locale: Locale = .current) -> String {
        [title, artist ?? ""]
            .map { value in
                value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .lowercased()
            }
            .joined(separator: "::")
    }

    /// Matches the title/artist fallback used by the app-data backend when a
    /// legacy discovery has no explicit trackKey. Keep this separate from the
    /// client-generated key above: Foundation's case-insensitive folding can
    /// expand characters such as eszett while JavaScript NFD normalization does
    /// not, causing the client and backend to deduplicate different records.
    static func appDataFallbackTrackKey(title: String, artist: String?) -> String {
        [title, artist ?? ""]
            .map { value in
                let decomposed = value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .decomposedStringWithCanonicalMapping
                let withoutCombiningMarks = String(
                    decomposed.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) }
                )
                return withoutCombiningMarks
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .lowercased()
            }
            .joined(separator: "::")
    }

    static func artistDisplayText(_ artist: String?, liveFallback: String) -> String {
        normalizedValue(artist) ?? liveFallback
    }

    static func searchQuery(title: String, artist: String?) -> String {
        guard let artist = normalizedValue(artist) else {
            return title
        }
        return "\(artist) \(title)"
    }

    static func resolvedURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        return URL(string: value)
    }
}
