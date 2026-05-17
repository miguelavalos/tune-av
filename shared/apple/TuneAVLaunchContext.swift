import Foundation

struct TuneAVLaunchContext {
    enum Tab: String {
        case search
        case library
        case music
        case player
        case settings
    }

    let preferredTab: Tab?
    let demoStation: Station?
    let seedFavorite: Bool
    let preferredSearchQuery: String?
    let isUITesting: Bool
    let shouldDisableSplash: Bool
    let shouldDisableOnboarding: Bool
    let shouldSeedUITestLibrary: Bool
    let shouldUseLocalUITestDiscovery: Bool
    let shouldUseLocalUITestSearch: Bool
    let uiTestTrackTitle: String?
    let uiTestTrackArtist: String?
    let uiTestUpgradePromptFeature: LimitedFeature?
    let uiTestCloudSyncStatus: String?

    static let current = TuneAVLaunchContext(environment: ProcessInfo.processInfo.environment)

    init(environment: [String: String]) {
        isUITesting = environment["TUNEAV_UI_TESTS"] == "1"
        shouldDisableSplash = isUITesting
            || environment["TUNEAV_DISABLE_SPLASH"] == "1"
        shouldDisableOnboarding = isUITesting
            || environment["TUNEAV_DISABLE_ONBOARDING"] == "1"
        shouldSeedUITestLibrary = environment["TUNEAV_UI_TESTS_DISABLE_LIBRARY_SEED"] != "1"
        shouldUseLocalUITestDiscovery = environment["TUNEAV_UI_TESTS_LOCAL_DISCOVERY"] == "1"
        shouldUseLocalUITestSearch = environment["TUNEAV_UI_TESTS_LOCAL_SEARCH"] == "1"
        uiTestTrackTitle = Self.nilIfEmpty(environment["TUNEAV_UI_TEST_TRACK_TITLE"])
        uiTestTrackArtist = Self.nilIfEmpty(environment["TUNEAV_UI_TEST_TRACK_ARTIST"])
        uiTestUpgradePromptFeature = environment["TUNEAV_UI_TEST_UPGRADE_PROMPT_FEATURE"]
            .flatMap(LimitedFeature.init(rawValue:))
        uiTestCloudSyncStatus = Self.nilIfEmpty(environment["TUNEAV_UI_TEST_CLOUD_SYNC_STATUS"])
        preferredTab = environment["TUNEAV_OPEN_TAB"].flatMap(Tab.init(rawValue:))
        seedFavorite = environment["TUNEAV_SEED_FAVORITE"] == "1"
        preferredSearchQuery = Self.nilIfEmpty(environment["TUNEAV_SEARCH_QUERY"])

        if environment["TUNEAV_DEMO_MODE"] == "1" {
            demoStation = Station(
                id: "demo-groove-salad",
                name: "SomaFM Groove Salad",
                country: "United States",
                language: "English",
                tags: "ambient,chillout,electronic",
                streamURL: "https://ice1.somafm.com/groovesalad-128-mp3",
                faviconURL: nil,
                bitrate: 128,
                codec: "MP3",
                homepageURL: "https://somafm.com/groovesalad/"
            )
        } else {
            demoStation = nil
        }
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct TuneAVUITestEnvironment {
    let environment: [String: String]

    static let current = TuneAVUITestEnvironment(environment: ProcessInfo.processInfo.environment)

    var isEnabled: Bool {
        environment["TUNEAV_UI_TESTS"] == "1"
    }

    var shouldForceGuest: Bool {
        isEnabled && environment["TUNEAV_UI_TESTS_FORCE_GUEST"] == "1"
    }

    var accountMode: String? {
        guard isEnabled else { return nil }
        return environment["TUNEAV_UI_TESTS_ACCOUNT_MODE"]
    }

    var hasAccountOverride: Bool {
        accountMode != nil
    }

    var isProAccount: Bool {
        accountMode == "pro"
    }

    var accountDeletionScenario: String? {
        guard isEnabled else { return nil }
        return environment["TUNEAV_UI_TEST_ACCOUNT_DELETION"]
    }

    var shouldUseSubscriptionPurchasingStub: Bool {
        isEnabled && environment["TUNEAV_UI_TEST_SUBSCRIPTION_STUB"] == "1"
    }

    static let accountUserId = "ui-test-user"
    static let accountUserDisplayName = "UI Test User"
    static let accountUserEmailAddress = "ui-test@example.test"
    static let accountToken = "ui-test-token"
}
