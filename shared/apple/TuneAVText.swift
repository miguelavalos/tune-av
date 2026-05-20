import Foundation

enum TuneAVText {
    static func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.isEmpty ? nil : collapsed
    }

    static func joinedQuery(parts: [String?], suffix: String? = nil) -> String {
        (parts + [suffix])
            .compactMap(normalizedValue)
            .joined(separator: " ")
    }

    static func normalizedValue(
        _ value: String?,
        excluding blockedValues: [String],
        locale: Locale = .current
    ) -> String? {
        guard let trimmed = normalizedValue(value) else { return nil }
        let normalizedTrimmed = normalizedComparisonValue(trimmed, locale: locale)
        let normalizedBlockedValues = Set(blockedValues.map { normalizedComparisonValue($0, locale: locale) })
        return normalizedBlockedValues.contains(normalizedTrimmed) ? nil : trimmed
    }

    static func normalizedComparisonValue(_ value: String, locale: Locale = .current) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .lowercased()
    }
}
