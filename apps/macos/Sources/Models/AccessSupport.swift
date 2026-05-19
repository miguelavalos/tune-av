import Foundation
import Security

typealias MacAccessState = TuneAVResolvedAccess

@MainActor
protocol MacAccessProviding {
    func fetchAccessState() async throws -> MacAccessState
}

protocol MacAccountTokenProviding {
    func currentToken() async throws -> String?
}

struct KeychainMacAccountTokenProvider: MacAccountTokenProviding {
    static let defaultService = "com.avalsys.tuneav.mac.av-account"
    static let defaultAccount = "session-token"

    private let service: String
    private let account: String
    private let keychain: MacKeychainReading

    init(
        service: String = Self.defaultService,
        account: String = Self.defaultAccount,
        keychain: MacKeychainReading = SystemMacKeychainReader()
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    func currentToken() async throws -> String? {
        guard let data = keychain.passwordData(service: service, account: account) else {
            return nil
        }
        let token = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

typealias LocalFallbackMacAccountTokenProvider = KeychainMacAccountTokenProvider

protocol MacKeychainReading {
    func passwordData(service: String, account: String) -> Data?
}

struct SystemMacKeychainReader: MacKeychainReading {
    func passwordData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }
        return item as? Data
    }
}

final class AVAccountMacAccessClient: MacAccessProviding {
    private let accessClient: TuneAVAccessClient

    init(
        baseURL: URL? = MacAppConfig.avAccountAPIBaseURL,
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        let supportedBaseURL = baseURL?.isSupportedAVAccountBaseURL == true ? baseURL : nil
        self.accessClient = TuneAVAccessClient(
            baseURL: supportedBaseURL,
            tokenProvider: tokenProvider,
            urlSession: urlSession,
            decoder: decoder
        )
    }

    func fetchAccessState() async throws -> MacAccessState {
        MacAccessState(access: try await accessClient.fetchTuneAVAccess())
    }
}

private extension MacAccessState {
    init(access: AppAccess) {
        self.init(
            planTier: access.planTier,
            accessMode: access.accessMode,
            capabilities: access.capabilities,
            limits: TuneAVAccessLimitPolicy.resolvedLimits(access.limits, accessMode: access.accessMode)
        )
    }
}

enum MacAppConfig {
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.avalsys.tuneav.mac"
    }

    static var keychainAccessGroup: String? {
        guard let appIdentifierPrefix = TuneAVBundleConfig.nonEmptyStringValue(for: "TUNEAV_APP_IDENTIFIER_PREFIX") else {
            return nil
        }
        return "\(appIdentifierPrefix)\(bundleIdentifier)"
    }

    static var avAccountKey: String {
        TuneAVBundleConfig.stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY")
    }

    static var avAccountAPIBaseURL: URL? {
        urlValue(for: "ACCOUNTAV_API_BASE_URL")
    }

    static var accountManagementURL: URL? {
        urlValue(for: "ACCOUNTAV_MANAGEMENT_URL")
    }

    static var deleteAccountURL: URL? {
        TuneAVBundleConfig.deleteAccountURL(
            explicitURL: urlValue(for: "TUNEAV_DELETE_ACCOUNT_URL"),
            accountManagementURL: accountManagementURL
        )
    }

    static var supportURL: URL? {
        TuneAVBundleConfig.supportURL(
            explicitURL: urlValue(for: "SUPPORTAV_BASE_URL"),
            email: TuneAVBundleConfig.nonEmptyStringValue(for: "TUNEAV_SUPPORT_EMAIL")
        )
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

    static var hasAVAccountBackendConfiguration: Bool {
        avAccountAPIBaseURL != nil
    }

    static var isAVAccountAvailable: Bool {
        !avAccountKey.isEmpty
    }

    private static func urlValue(for key: String) -> URL? {
        TuneAVBundleConfig.urlValue(for: key, requireSupportedAVAccountBaseURL: true)
    }

    private static func urlValue(for key: String, fallbackKey: String) -> URL? {
        urlValue(for: key) ?? urlValue(for: fallbackKey)
    }
}

@MainActor
protocol MacTuneAVLibrarySyncing {
    func isConfigured() -> Bool
    func pullLibrary() async throws -> TuneAVLibraryDocument
    func pushLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws
    func overwriteLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws
}

final class MacTuneAVAppDataClient: MacTuneAVLibrarySyncing {
    private let baseURL: URL?
    private let tokenProvider: () async throws -> String?
    private let urlSession: URLSession
    private let syncClient: TuneAVAppDataSyncClient

    init(
        baseURL: URL? = MacAppConfig.avAccountAPIBaseURL,
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.syncClient = TuneAVAppDataSyncClient(
            deviceId: "tuneav-macos",
            isConfigured: { baseURL?.isSupportedAVAccountBaseURL == true },
            request: { path, method, body, headers in
                guard let token = try await tokenProvider(), !token.isEmpty else {
                    throw MacAppDataClientError.missingToken
                }
                guard let baseURL, baseURL.isSupportedAVAccountBaseURL else {
                    throw MacAppDataClientError.missingBaseURL
                }

                let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
                let url = baseURL.appending(path: sanitizedPath)
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                for (field, value) in headers {
                    request.setValue(value, forHTTPHeaderField: field)
                }
                if let body {
                    request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }

                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw MacAppDataClientError.requestFailed(statusCode: httpResponse.statusCode)
                }

                return data
            },
            decoder: decoder,
            encoder: encoder
        )
    }

    func isConfigured() -> Bool {
        syncClient.isConfigured()
    }

    func pullLibrary() async throws -> TuneAVLibraryDocument {
        try await syncClient.pullLibrary()
    }

    func pushLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        try await syncClient.pushLibrary(snapshot)
    }

    func overwriteLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        try await syncClient.overwriteLibrary(snapshot)
    }
}

@MainActor
final class MacAccessController: ObservableObject {
    @Published private(set) var state: MacAccessState

    private let defaults: UserDefaults
    private let accessModeKey: String
    private(set) var lastRefreshError: Error?

    init(defaults: UserDefaults = .standard, accessModeKey: String = "tuneav.mac.accessMode") {
        self.defaults = defaults
        self.accessModeKey = accessModeKey
        self.state = Self.uiTestAccessState()
            ?? .localFallback(for: AccessMode(rawValue: defaults.string(forKey: accessModeKey) ?? "") ?? .guest)
    }

    var accessMode: AccessMode { state.accessMode }
    var planTier: PlanTier { state.planTier }
    var capabilities: AccessCapabilities { state.capabilities }
    var limits: AccessLimits { state.limits }

    func updateAccessMode(_ accessMode: AccessMode) {
        state = .localFallback(for: accessMode)
        defaults.set(accessMode.rawValue, forKey: accessModeKey)
    }

    @discardableResult
    func refresh(using provider: MacAccessProviding) async -> Bool {
        if let uiTestAccessState = Self.uiTestAccessState() {
            state = uiTestAccessState
            defaults.set(uiTestAccessState.accessMode.rawValue, forKey: accessModeKey)
            lastRefreshError = nil
            return true
        }

        do {
            let refreshedState = try await provider.fetchAccessState()
            state = refreshedState
            defaults.set(refreshedState.accessMode.rawValue, forKey: accessModeKey)
            lastRefreshError = nil
            return true
        } catch {
            lastRefreshError = error
            return false
        }
    }

    private static func uiTestAccessState(environment: [String: String] = ProcessInfo.processInfo.environment) -> MacAccessState? {
        let uiTestEnvironment = TuneAVUITestEnvironment(environment: environment)
        guard uiTestEnvironment.isEnabled else { return nil }
        guard !uiTestEnvironment.shouldForceGuest else {
            return .localFallback(for: .guest)
        }
        guard uiTestEnvironment.hasAccountOverride else { return nil }

        return .localFallback(for: uiTestEnvironment.isProAccount ? .signedInPro : .signedInFree)
    }
}

typealias UpgradePromptContext = TuneAVUpgradePromptContext
