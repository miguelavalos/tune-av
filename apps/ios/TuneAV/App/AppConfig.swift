import AccountAV
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

    static func configureAVAccountIfPossible() {
        AccountAVClerk.configureIfPossible(publishableKey: avAccountKey)
    }
}
