import Foundation

struct TuneAVCountry: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }

    private static let excludedRegionCodes: Set<String> = [
        "AC", "CP", "CQ", "DG", "EA", "EU", "EZ", "IC", "QO", "TA", "UN"
    ]

    static func sanitizedCode(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let code = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return nil }
        guard code.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else { return nil }
        guard !excludedRegionCodes.contains(code) else { return nil }
        return code
    }

    var flag: String? {
        guard code.count == 2 else { return nil }
        let base: UInt32 = 127397
        let scalars = code.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    static func all(localizedName: (String) -> String) -> [TuneAVCountry] {
        Locale.Region.isoRegions
            .compactMap { region -> TuneAVCountry? in
                guard let code = sanitizedCode(region.identifier) else { return nil }
                return TuneAVCountry(code: code, name: localizedName(code))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func filtered(_ options: [TuneAVCountry], query: String) -> [TuneAVCountry] {
        guard let normalizedQuery = TuneAVText.normalizedValue(query) else {
            return options
        }

        return options.filter { option in
            option.name.localizedCaseInsensitiveContains(normalizedQuery) ||
                option.code.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}
