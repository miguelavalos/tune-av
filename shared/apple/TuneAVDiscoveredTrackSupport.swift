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
