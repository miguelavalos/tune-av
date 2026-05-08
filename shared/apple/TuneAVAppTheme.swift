import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

final class AppThemeController: ObservableObject {
    @Published private(set) var currentTheme: AppTheme

    private let userDefaults: UserDefaults
    private let userDefaultsKey: String

    init(userDefaults: UserDefaults = .standard, userDefaultsKey: String = "tuneav.appTheme") {
        self.userDefaults = userDefaults
        self.userDefaultsKey = userDefaultsKey
        currentTheme = AppTheme(rawValue: userDefaults.string(forKey: userDefaultsKey) ?? "") ?? .system
    }

    func select(_ theme: AppTheme) {
        guard currentTheme != theme else { return }
        currentTheme = theme
        userDefaults.set(theme.rawValue, forKey: userDefaultsKey)
    }
}
