import ClerkKit
import Foundation

@MainActor
enum AppConfig {
    static var avAccountKey: String {
        stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY")
    }

    static var supportEmail: String? {
        nonEmptyStringValue(for: "TUNEAV_SUPPORT_EMAIL")
    }

    static var avAccountAPIBaseURL: URL? {
        urlValue(for: "ACCOUNTAV_API_BASE_URL")
    }

    static var accountManagementURL: URL? {
        urlValue(for: "ACCOUNTAV_MANAGEMENT_URL")
    }

    static var termsURL: URL? {
        urlValue(for: "TUNEAV_TERMS_URL")
    }

    static var privacyURL: URL? {
        urlValue(for: "TUNEAV_PRIVACY_URL")
    }

    static var openSourceURL: URL? {
        urlValue(for: "TUNEAV_OPEN_SOURCE_URL")
    }

    static var supportURL: URL? {
        guard let supportEmail else { return nil }
        let encodedSubject = "Tune AV Support".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Tune%20AV%20Support"
        return URL(string: "mailto:\(supportEmail)?subject=\(encodedSubject)")
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

    private static func stringValue(for key: String, fallbackKey: String) -> String {
        nonEmptyStringValue(for: key) ?? nonEmptyStringValue(for: fallbackKey) ?? ""
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

    private static func urlValue(for key: String, fallbackKey: String) -> URL? {
        guard let rawValue = nonEmptyStringValue(for: key) ?? nonEmptyStringValue(for: fallbackKey) else {
            return nil
        }
        return URL(string: rawValue)
    }
}
