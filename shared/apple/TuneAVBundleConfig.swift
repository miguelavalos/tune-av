import Foundation

enum TuneAVBundleConfig {
    static func stringValue(for key: String, in bundle: Bundle = .main) -> String {
        nonEmptyStringValue(for: key, in: bundle) ?? ""
    }

    static func nonEmptyStringValue(for key: String, in bundle: Bundle = .main) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func boolValue(for key: String, in bundle: Bundle = .main, default defaultValue: Bool = false) -> Bool {
        guard let rawValue = nonEmptyStringValue(for: key, in: bundle) else {
            return defaultValue
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "enabled":
            return true
        case "0", "false", "no", "disabled":
            return false
        default:
            return defaultValue
        }
    }

    static func urlValue(
        for key: String,
        in bundle: Bundle = .main,
        requireSupportedAVAccountBaseURL: Bool = false
    ) -> URL? {
        guard let rawValue = nonEmptyStringValue(for: key, in: bundle),
              let url = URL(string: rawValue) else {
            return nil
        }
        guard !requireSupportedAVAccountBaseURL || url.isSupportedAVAccountBaseURL else {
            return nil
        }
        return url
    }

    static func deleteAccountURL(
        explicitURL: URL?,
        accountManagementURL: URL?
    ) -> URL? {
        if let explicitURL {
            return explicitURL
        }

        guard let accountManagementURL else { return nil }
        guard let host = accountManagementURL.host, let scheme = accountManagementURL.scheme else {
            return accountManagementURL
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/danger-zone"
        return components.url
    }

    static func supportURL(explicitURL: URL?, email: String?) -> URL? {
        if let explicitURL {
            return explicitURL
        }
        guard let email else { return nil }
        let encodedSubject = "Tune AV Support".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Tune%20AV%20Support"
        return URL(string: "mailto:\(email)?subject=\(encodedSubject)")
    }
}
