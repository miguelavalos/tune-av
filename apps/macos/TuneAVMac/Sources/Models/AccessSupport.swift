import Foundation
import Security

extension AccessMode {
    var title: String {
        switch self {
        case .guest:
            return "Guest"
        case .signedInFree:
            return "Signed-in Free"
        case .signedInPro:
            return "Pro"
        }
    }
}

struct MacAccessState: Equatable {
    let accessMode: AccessMode
    let planTier: PlanTier
    let capabilities: AccessCapabilities
    let limits: AccessLimits

    static func localFallback(for accessMode: AccessMode) -> MacAccessState {
        MacAccessState(
            accessMode: accessMode,
            planTier: accessMode == .signedInPro ? .pro : .free,
            capabilities: AccessCapabilities.forMode(accessMode),
            limits: AccessLimits.forMode(accessMode)
        )
    }
}

struct MacMeAccessResponse: Decodable {
    let apps: [MacAppAccess]
}

struct MacAppAccess: Decodable {
    let appId: String
    let accessMode: AccessMode
    let planTier: PlanTier
    let capabilities: AccessCapabilities
    let limits: AccessLimits

    var state: MacAccessState {
        MacAccessState(
            accessMode: accessMode,
            planTier: planTier,
            capabilities: capabilities,
            limits: limits
        )
    }
}

enum MacAccessRefreshError: Error, Equatable {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)
    case avTunesysAccessMissing
}

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
    private let baseURL: URL?
    private let tokenProvider: () async throws -> String?
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(
        baseURL: URL? = MacAppConfig.avAccountAPIBaseURL,
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.decoder = decoder
    }

    func fetchAccessState() async throws -> MacAccessState {
        guard let token = try await tokenProvider(), !token.isEmpty else {
            throw MacAccessRefreshError.missingToken
        }
        guard let baseURL, baseURL.isSupportedAVAccountBaseURL else {
            throw MacAccessRefreshError.missingBaseURL
        }

        let url = baseURL.appending(path: "v1/me/access")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MacAccessRefreshError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let payload = try decoder.decode(MacMeAccessResponse.self, from: data)
        guard let avTunesysAccess = payload.apps.first(where: { $0.appId == "tuneav" }) else {
            throw MacAccessRefreshError.avTunesysAccessMissing
        }

        return avTunesysAccess.state
    }
}

enum MacAppConfig {
    static var avAccountAPIBaseURL: URL? {
        urlValue(for: "ACCOUNTAV_API_BASE_URL")
    }

    static var accountManagementURL: URL? {
        urlValue(for: "ACCOUNTAV_MANAGEMENT_URL")
    }

    static var hasAVAccountBackendConfiguration: Bool {
        avAccountAPIBaseURL != nil
    }

    private static func urlValue(for key: String) -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), url.isSupportedAVAccountBaseURL else {
            return nil
        }
        return url
    }

    private static func urlValue(for key: String, fallbackKey: String) -> URL? {
        urlValue(for: key) ?? urlValue(for: fallbackKey)
    }
}

extension URL {
    var isSupportedAVAccountBaseURL: Bool {
        guard let scheme = scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              host?.isEmpty == false else {
            return false
        }
        return true
    }
}

private enum MacAppDataConstants {
    static let appId = "tuneav"
    static let deviceId = "tuneav-macos"
}

private enum MacAppDataResource: String, CaseIterable {
    case favorites
    case recents
    case discoveries
    case settings
}

private struct MacAppDataResponsePayload<Entry: Codable>: Decodable {
    let data: MacAppDataEnvelopePayload<Entry>
    let updatedAt: String
    let revision: Int?
    let etag: String?
}

private struct MacAppDataEnvelopePayload<Entry: Codable>: Codable {
    let appId: String
    let resource: String
    let deviceId: String
    let sentAt: String
    let entries: [Entry]
}

private struct MacAppDataResourceDocument<Entry: Codable> {
    let entries: [Entry]
    let updatedAt: Date
    let revision: Int
    let etag: String?
}

enum MacAppDataClientError: Error, Equatable {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)
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
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var lastKnownRevisions: [String: Int] = [:]
    private var lastKnownEtags: [String: String] = [:]

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
        self.decoder = decoder
        self.encoder = encoder
    }

    func isConfigured() -> Bool {
        baseURL?.isSupportedAVAccountBaseURL == true
    }

    func pullLibrary() async throws -> TuneAVLibraryDocument {
        let favorites = try await pullResource(.favorites, entryType: FavoriteStationRecord.self)
        let recents = try await pullResource(.recents, entryType: RecentStationRecord.self)
        let discoveries = try await pullResource(.discoveries, entryType: DiscoveredTrackRecord.self)
        let settings = try await pullResource(.settings, entryType: AppSettingsRecord.self)

        let snapshot = TuneAVLibrarySnapshot(
            favorites: favorites.entries,
            recents: recents.entries,
            discoveries: discoveries.entries,
            settings: settings.entries.first ?? .empty
        )
        let updatedAt = [
            favorites.updatedAt,
            recents.updatedAt,
            discoveries.updatedAt,
            settings.updatedAt
        ].max() ?? .distantPast

        return TuneAVLibraryDocument(
            snapshot: snapshot.hasMeaningfulContent ? snapshot : nil,
            updatedAt: updatedAt,
            revision: [
                favorites.revision,
                recents.revision,
                discoveries.revision,
                settings.revision
            ].max() ?? 0,
            etag: nil
        )
    }

    func pushLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        try await pushResource(.favorites, entries: snapshot.favorites)
        try await pushResource(.recents, entries: snapshot.recents)
        try await pushResource(.discoveries, entries: snapshot.discoveries)
        try await pushResource(.settings, entries: [snapshot.settings])
    }

    func overwriteLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        for resource in MacAppDataResource.allCases {
            forgetSyncVersion(for: resource)
        }
        try await pushLibrary(snapshot)
    }

    private func pullResource<Entry: Codable>(
        _ resource: MacAppDataResource,
        entryType: Entry.Type
    ) async throws -> MacAppDataResourceDocument<Entry> {
        let payload: MacAppDataResponsePayload<Entry> = try await request(path: dataPath(for: resource))
        rememberSyncVersion(for: resource, revision: payload.revision, etag: payload.etag)

        return MacAppDataResourceDocument(
            entries: payload.data.entries,
            updatedAt: TuneAVDateCoding.date(from: payload.updatedAt),
            revision: payload.revision ?? 0,
            etag: payload.etag
        )
    }

    private func pushResource<Entry: Codable>(_ resource: MacAppDataResource, entries: [Entry]) async throws {
        try await pushResource(resource, entries: entries, allowsConflictRetry: true)
    }

    private func pushResource<Entry: Codable>(
        _ resource: MacAppDataResource,
        entries: [Entry],
        allowsConflictRetry: Bool
    ) async throws {
        let envelope = MacAppDataEnvelopePayload(
            appId: MacAppDataConstants.appId,
            resource: resource.rawValue,
            deviceId: MacAppDataConstants.deviceId,
            sentAt: TuneAVDateCoding.string(from: .now),
            entries: entries
        )

        var headers: [String: String] = [:]
        if let lastKnownEtag = lastKnownEtags[resource.rawValue] {
            headers["If-Match"] = lastKnownEtag
        } else if let lastKnownRevision = lastKnownRevisions[resource.rawValue] {
            headers["If-Match"] = "\"revision-\(lastKnownRevision)\""
        }

        let response: MacAppDataResponsePayload<Entry>
        do {
            response = try await request(
                path: dataPath(for: resource),
                method: "PUT",
                body: try encoder.encode(envelope),
                headers: headers
            )
        } catch MacAppDataClientError.requestFailed(let statusCode) where statusCode == 409 {
            guard allowsConflictRetry else {
                throw TuneAVAppDataError.conflict
            }

            _ = try await pullResource(resource, entryType: Entry.self)
            try await pushResource(resource, entries: entries, allowsConflictRetry: false)
            return
        }
        rememberSyncVersion(for: resource, revision: response.revision, etag: response.etag)
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
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

        return try decoder.decode(T.self, from: data)
    }

    private func rememberSyncVersion(for resource: MacAppDataResource, revision: Int?, etag: String?) {
        lastKnownRevisions[resource.rawValue] = revision
        lastKnownEtags[resource.rawValue] = etag
    }

    private func forgetSyncVersion(for resource: MacAppDataResource) {
        lastKnownRevisions[resource.rawValue] = nil
        lastKnownEtags[resource.rawValue] = nil
    }

    private func dataPath(for resource: MacAppDataResource) -> String {
        "/v1/apps/\(MacAppDataConstants.appId)/data/\(resource.rawValue)"
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
        let storedMode = AccessMode(rawValue: defaults.string(forKey: accessModeKey) ?? "") ?? .guest
        self.state = .localFallback(for: storedMode)
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
}

struct UpgradePromptContext: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let benefit: String
    let progressText: String?

    static func favorites(current: Int, limit: Int) -> UpgradePromptContext {
        UpgradePromptContext(
            title: "Favorite station limit reached",
            message: "You have saved \(current) of \(limit) favorite stations.",
            benefit: "Pro unlocks a larger radio library, cloud sync, and richer discovery history.",
            progressText: "\(current) of \(limit) favorites used"
        )
    }

    static func savedTracks(current: Int, limit: Int) -> UpgradePromptContext {
        UpgradePromptContext(
            title: "Saved track limit reached",
            message: "You have saved \(current) of \(limit) discovered tracks.",
            benefit: "Pro unlocks a larger radio library, cloud sync, and richer discovery history.",
            progressText: "\(current) of \(limit) saved tracks used"
        )
    }

    static func dailyFeature(_ feature: LimitedFeature, current: Int, limit: Int) -> UpgradePromptContext {
        let featureName: String
        switch feature {
        case .favoriteStations:
            featureName = "favorite stations"
        case .savedTracks:
            featureName = "saved tracks"
        case .discoveredTracks:
            featureName = "discovered tracks"
        case .lyricsSearch:
            featureName = "lyrics searches"
        case .webSearch:
            featureName = "web searches"
        case .youtubeSearch:
            featureName = "YouTube opens"
        case .appleMusicSearch:
            featureName = "Apple Music opens"
        case .spotifySearch:
            featureName = "Spotify opens"
        case .discoveryShare:
            featureName = "discovery shares"
        }

        return UpgradePromptContext(
            title: "Daily \(featureName) limit reached",
            message: "You have used \(current) of today's \(limit) \(featureName).",
            benefit: "Pro unlocks practical unlimited music lookups and cloud-backed discovery history.",
            progressText: "\(current) of \(limit) used today"
        )
    }
}
