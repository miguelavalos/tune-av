import AccountAV
import Foundation

@MainActor
enum AppConfig {
    static var avAccountKey: String {
        TuneAVBundleConfig.stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY")
    }

    static var supportEmail: String? {
        TuneAVBundleConfig.nonEmptyStringValue(for: "TUNEAV_SUPPORT_EMAIL")
    }

    static var avAccountAPIBaseURL: URL? {
        TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_API_BASE_URL")
    }

    static var isListeningAnalyticsUploadEnabled: Bool {
        TuneAVBundleConfig.boolValue(for: "TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS")
    }

    static var accountManagementURL: URL? {
        TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_MANAGEMENT_URL")
    }

    static var deleteAccountURL: URL? {
        TuneAVBundleConfig.deleteAccountURL(
            explicitURL: TuneAVBundleConfig.urlValue(for: "TUNEAV_DELETE_ACCOUNT_URL"),
            accountManagementURL: accountManagementURL
        )
    }

    static var termsURL: URL? {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_TERMS_URL")
    }

    static var privacyURL: URL? {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_PRIVACY_URL")
    }

    static var openSourceURL: URL? {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_OPEN_SOURCE_URL")
    }

    static var supportURL: URL? {
        TuneAVBundleConfig.supportURL(email: supportEmail)
    }

    static var isAVAccountAvailable: Bool {
        !avAccountKey.isEmpty
    }

    static func configureAVAccountIfPossible() {
        AccountAVClerk.configureIfPossible(publishableKey: avAccountKey)
    }
}
