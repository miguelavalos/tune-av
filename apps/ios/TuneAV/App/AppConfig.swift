import AccountAV
import AVDiagnosticsFoundation
import Foundation

@MainActor
enum AppConfig {
    static var avAccountKey: String {
        TuneAVBundleConfig.stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY")
    }

    static var supportEmail: String? {
        TuneAVBundleConfig.nonEmptyStringValue(for: "SUPPORT_EMAIL_TO")
    }

    static var supportBaseURL: URL? {
        TuneAVBundleConfig.urlValue(for: "SUPPORTAV_BASE_URL", requireSupportedAVAccountBaseURL: true)
    }

    static var avAccountAPIBaseURL: URL? {
        TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL", requireSupportedAVAccountBaseURL: true)
    }

    static var tuneAVAPIBaseURL: URL? {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_API_BASE_URL", requireSupportedAVAccountBaseURL: true)
            ?? avAccountAPIBaseURL
    }

    static var tuneConvexURL: String {
        TuneAVBundleConfig.stringValue(for: "TUNEAV_CONVEX_URL")
    }

    static var isListeningAnalyticsUploadEnabled: Bool {
        TuneAVBundleConfig.boolValue(for: "TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS")
    }

    static var accountManagementURL: URL? {
        TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_MANAGEMENT_URL", requireSupportedAVAccountBaseURL: true)
    }

    static var deleteAccountURL: URL? {
        TuneAVBundleConfig.deleteAccountURL(
            explicitURL: TuneAVBundleConfig.urlValue(for: "TUNEAV_DELETE_ACCOUNT_URL"),
            accountManagementURL: accountManagementURL
        )
    }

    static var termsURL: URL? {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_TERMS_URL", requireSupportedAVAccountBaseURL: true)
    }

    static var privacyURL: URL? {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_PRIVACY_URL", requireSupportedAVAccountBaseURL: true)
    }

    static var openSourceURL: URL? {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_OPEN_SOURCE_URL", requireSupportedAVAccountBaseURL: true)
    }

    static var revenueCatPublicAPIKey: String? {
        TuneAVBundleConfig.nonEmptyStringValue(for: "TUNEAV_REVENUECAT_PUBLIC_API_KEY")
    }

    static var revenueCatOfferingID: String? {
        TuneAVBundleConfig.nonEmptyStringValue(for: "TUNEAV_REVENUECAT_OFFERING_ID")
    }

    static var revenueCatMonthlyPackageID: String? {
        TuneAVBundleConfig.nonEmptyStringValue(for: "TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID")
    }

    static var supportURL: URL? {
        TuneAVBundleConfig.supportURL(explicitURL: supportBaseURL, email: supportEmail)
    }

    static var isAVAccountAvailable: Bool {
        !avAccountKey.isEmpty
    }

    static var diagnosticsConfiguration: AVDiagnosticsConfiguration {
        AVDiagnosticsConfiguration(
            dsn: TuneAVBundleConfig.stringValue(for: "TUNEAV_IOS_SENTRY_DSN"),
            environment: diagnosticsEnvironment,
            releaseName: diagnosticsReleaseName,
            tracesSampleRate: 0,
            capturesFailedRequests: false,
            isEnabled: isDiagnosticsEnabled
        )
    }

    static func configureAVAccountIfPossible() {
        AccountAVClerk.configureIfPossible(
            publishableKey: avAccountKey,
            keychainService: TuneAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_SERVICE"),
            keychainAccessGroup: TuneAVBundleConfig.nonEmptyStringValue(for: "ACCOUNTAV_KEYCHAIN_ACCESS_GROUP")
        )
    }

    private static var diagnosticsEnvironment: AVDiagnosticsEnvironment {
        switch TuneAVBundleConfig.stringValue(for: "TUNEAV_CONFIG_ENVIRONMENT").lowercased() {
        case "prod", "production":
            return .production
        case "staging", "preview":
            return .preview
        case "dev", "debug":
            return .debug
        default:
            return .debug
        }
    }

    private static var diagnosticsReleaseName: String? {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.avalsys.tuneav"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(bundleIdentifier)@\(version)+\(build)"
    }

    private static var isDiagnosticsEnabled: Bool {
        #if DEBUG
        false
        #else
        !TuneAVBundleConfig.stringValue(for: "TUNEAV_IOS_SENTRY_DSN").isEmpty
        #endif
    }
}
