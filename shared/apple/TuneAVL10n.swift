import AVSettingsFoundation
import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case catalan = "ca"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            L10n.string("language.english")
        case .spanish:
            L10n.string("language.spanish")
        case .french:
            L10n.string("language.french")
        case .german:
            L10n.string("language.german")
        case .catalan:
            L10n.string("language.catalan")
        }
    }

    var autonym: String {
        switch self {
        case .english:
            "English"
        case .spanish:
            "Español"
        case .french:
            "Français"
        case .german:
            "Deutsch"
        case .catalan:
            "Català"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static func resolved(from rawValue: String?) -> AppLanguage {
        resolvedInitial(storedLanguageCode: rawValue, preferredLanguages: [])
    }

    static func resolvedInitial(
        storedLanguageCode: String?,
        preferredLanguages: [String]
    ) -> AppLanguage {
        let languageCode = AVInitialAppLanguage.resolve(
            storedLanguageCode: storedLanguageCode,
            preferredLanguages: preferredLanguages,
            supportedLanguageCodes: Set(allCases.map(\.rawValue))
        )
        return AppLanguage(rawValue: languageCode) ?? .english
    }
}

final class AppLanguageController: ObservableObject {
    @Published private(set) var currentLanguage: AppLanguage

    var locale: Locale {
        currentLanguage.locale
    }

    private let userDefaults: UserDefaults
    private let userDefaultsKey = "tuneav.appLanguage"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let launchLanguage = ProcessInfo.processInfo.environment["TUNEAV_APP_LANGUAGE"] {
            let resolvedLanguage = AppLanguage.resolved(from: launchLanguage)
            currentLanguage = resolvedLanguage
            userDefaults.set(resolvedLanguage.rawValue, forKey: userDefaultsKey)
            return
        }

        let storedLanguage = userDefaults.string(forKey: userDefaultsKey)
        let resolvedLanguage = AppLanguage.resolvedInitial(
            storedLanguageCode: storedLanguage,
            preferredLanguages: Locale.preferredLanguages
        )
        currentLanguage = resolvedLanguage
        if storedLanguage != resolvedLanguage.rawValue {
            userDefaults.set(resolvedLanguage.rawValue, forKey: userDefaultsKey)
        }
    }

    func select(_ language: AppLanguage) {
        userDefaults.set(language.rawValue, forKey: userDefaultsKey)
        guard currentLanguage != language else { return }
        currentLanguage = language
    }
}

enum L10n {
    private static let userDefaultsKey = "tuneav.appLanguage"

    static var locale: Locale {
        AppLanguage.resolved(
            from: UserDefaults.standard.string(forKey: userDefaultsKey) ?? Locale.preferredLanguages.first
        ).locale
    }

    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments)
    }

    static func plural(singular singularKey: String, plural pluralKey: String, count: Int, _ arguments: CVarArg...) -> String {
        format(count == 1 ? singularKey : pluralKey, arguments: arguments)
    }

    static func markdown(_ key: String) -> AttributedString {
        let localized = string(key)
        return (try? AttributedString(markdown: localized)) ?? AttributedString(localized)
    }

    static func markdown(_ key: String, _ arguments: CVarArg...) -> AttributedString {
        let localized = format(key, arguments: arguments)
        return (try? AttributedString(markdown: localized)) ?? AttributedString(localized)
    }

    static func genreLabel(for tag: String) -> String {
        switch tag.lowercased() {
        case "rock":
            return string("genre.rock")
        case "pop":
            return string("genre.pop")
        case "jazz":
            return string("genre.jazz")
        case "dance":
            return string("genre.dance")
        case "chill":
            return string("genre.chill")
        case "hip-hop":
            return string("genre.hipHop")
        case "indie":
            return string("genre.indie")
        case "news":
            return string("genre.news")
        case "electronic":
            return string("genre.electronic")
        case "ambient":
            return string("genre.ambient")
        case "latin":
            return string("genre.latin")
        case "oldies":
            return string("genre.oldies")
        case "classical":
            return string("genre.classical")
        case "country":
            return string("genre.country")
        default:
            return tag.capitalized(with: locale)
        }
    }

    static func countryName(for countryCode: String) -> String {
        locale.localizedString(forRegionCode: countryCode) ??
            Locale(identifier: "en").localizedString(forRegionCode: countryCode) ??
            countryCode
    }

    private static func format(_ key: String, arguments: [CVarArg]) -> String {
        let format = string(key)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static var bundle: Bundle {
        let selectedLanguage = AppLanguage.resolved(
            from: UserDefaults.standard.string(forKey: userDefaultsKey) ?? Locale.preferredLanguages.first
        )

        guard let path = Bundle.main.path(forResource: selectedLanguage.rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return .main
        }

        return localizedBundle
    }
}
