import ClerkKit
import Foundation

@MainActor
enum AppConfig {
    static var avAccountKey: String {
        stringValue(for: "AVACCOUNT_PUBLISHABLE_KEY")
    }

    static var supportEmail: String? {
        nonEmptyStringValue(for: "AVTUNESYS_SUPPORT_EMAIL")
    }

    static var avAccountAPIBaseURL: URL? {
        urlValue(for: "AVACCOUNT_API_BASE_URL")
    }

    static var accountManagementURL: URL? {
        urlValue(for: "AVACCOUNT_MANAGEMENT_URL")
    }

    static var termsURL: URL? {
        urlValue(for: "AVTUNESYS_TERMS_URL")
    }

    static var privacyURL: URL? {
        urlValue(for: "AVTUNESYS_PRIVACY_URL")
    }

    static var openSourceURL: URL? {
        urlValue(for: "AVTUNESYS_OPEN_SOURCE_URL")
    }

    static var radioBrowserURL: URL? {
        URL(string: "https://www.radio-browser.info/")
    }

    static var supportURL: URL? {
        guard let supportEmail else { return nil }
        let encodedSubject = "AV Tunesys Support".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "AV%20Tunesys%20Support"
        return URL(string: "mailto:\(supportEmail)?subject=\(encodedSubject)")
    }

    static var premiumProductIDs: [String] {
        stringValue(for: "AVTUNESYS_PREMIUM_PRODUCT_IDS")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static var isPremiumSubscriptionAvailable: Bool {
        !premiumProductIDs.isEmpty
    }

    static var isAVAccountAvailable: Bool {
        !avAccountKey.isEmpty
    }

    static func configureAVAccountIfPossible() {
        guard isAVAccountAvailable else {
            return
        }

        Clerk.configure(publishableKey: avAccountKey)
    }

    private static func stringValue(for key: String) -> String {
        nonEmptyStringValue(for: key) ?? ""
    }

    private static func nonEmptyStringValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func urlValue(for key: String) -> URL? {
        guard let rawValue = nonEmptyStringValue(for: key) else {
            return nil
        }
        return URL(string: rawValue)
    }
}
