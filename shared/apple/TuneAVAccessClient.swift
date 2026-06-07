import Foundation
import OSLog

struct MeAccessResponse: Decodable {
    let viewer: MeAccessViewer?
    let apps: [AppAccess]
}

struct MeAccessViewer: Decodable, Equatable {
    let isAuthenticated: Bool
    let userId: String?
    let identityProvider: String?
}

struct AppAccess: Decodable {
    let appId: String
    let accessMode: AccessMode
    let planTier: PlanTier
    let capabilities: AccessCapabilities
    let limits: AccessLimits

    enum CodingKeys: String, CodingKey {
        case appId
        case accessMode
        case planTier
        case capabilities
        case limits
    }

    init(
        appId: String,
        accessMode: AccessMode,
        planTier: PlanTier,
        capabilities: AccessCapabilities,
        limits: AccessLimits
    ) {
        self.appId = appId
        self.accessMode = accessMode
        self.planTier = planTier
        self.capabilities = capabilities
        self.limits = limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decode(String.self, forKey: .appId)
        accessMode = try container.decode(AccessMode.self, forKey: .accessMode)
        planTier = try container.decode(PlanTier.self, forKey: .planTier)
        capabilities = try container.decodeIfPresent(AccessCapabilities.self, forKey: .capabilities)
            ?? .forMode(accessMode)
        limits = try container.decodeIfPresent(AccessLimits.self, forKey: .limits)
            ?? .forMode(accessMode)
    }
}

extension AppAccess: Equatable {}

enum TuneAVAccessClientError: Error, Equatable {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)
    case avTunesysAccessMissing
}

typealias MacMeAccessResponse = MeAccessResponse
typealias MacAppAccess = AppAccess
typealias MacAccessRefreshError = TuneAVAccessClientError

@MainActor
final class TuneAVAccessClient {
    private let baseURL: URL?
    private let tokenProvider: () async throws -> String?
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let retryPolicy: RetryPolicy
    private let logger = Logger(subsystem: "com.avalsys.tuneav", category: "account-network")

    init(
        baseURL: URL?,
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        retryPolicy: RetryPolicy = .account
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.decoder = decoder
        self.retryPolicy = retryPolicy
    }

    var isConfigured: Bool {
        baseURL != nil
    }

    func fetchMeAccess() async throws -> MeAccessResponse {
        try await request(path: "/v1/me/access")
    }

    func fetchTuneAVAccess() async throws -> AppAccess {
        let payload = try await fetchMeAccess()
        guard let tuneAVAccess = payload.apps.first(where: { $0.appId == "tuneav" }) else {
            throw TuneAVAccessClientError.avTunesysAccessMissing
        }

        return tuneAVAccess
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        let data = try await requestData(path: path, method: method, body: body, headers: headers)
        return try decoder.decode(T.self, from: data)
    }

    func requestData(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        guard let token = try await tokenProvider(), !token.isEmpty else {
            throw TuneAVAccessClientError.missingToken
        }
        guard let baseURL else {
            throw TuneAVAccessClientError.missingBaseURL
        }

        let url = Self.url(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("tuneav", forHTTPHeaderField: "x-appsav-app-id")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let operation = Self.operationName(method: method, path: path)
        let (data, response, attempts) = try await performDataTask(for: request, operation: operation, method: method)
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Account API request failed operation=\(operation, privacy: .public) method=\(method, privacy: .public) error=bad_server_response")
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            logger.error("Account API request failed operation=\(operation, privacy: .public) method=\(method, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) attempts=\(attempts, privacy: .public)")
            throw TuneAVAccessClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        logger.info("Account API request completed operation=\(operation, privacy: .public) method=\(method, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) attempts=\(attempts, privacy: .public)")
        return data
    }

    private func performDataTask(for request: URLRequest, operation: String, method: String) async throws -> (Data, URLResponse, Int) {
        var attempt = 1

        while true {
            do {
                let (data, response) = try await urlSession.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   retryPolicy.shouldRetry(statusCode: httpResponse.statusCode, attempt: attempt),
                   !Task.isCancelled {
                    logger.info("Account API request retrying operation=\(operation, privacy: .public) method=\(method, privacy: .public) attempt=\(attempt + 1, privacy: .public) status=\(httpResponse.statusCode, privacy: .public)")
                    try await retryPolicy.sleep(beforeAttempt: attempt + 1)
                    attempt += 1
                    continue
                }
                return (data, response, attempt)
            } catch {
                guard retryPolicy.shouldRetry(error: error, attempt: attempt), !Task.isCancelled else {
                    throw error
                }
                logger.info("Account API request retrying operation=\(operation, privacy: .public) method=\(method, privacy: .public) attempt=\(attempt + 1, privacy: .public) error=\(Self.sanitizedErrorCode(error), privacy: .public)")
                try await retryPolicy.sleep(beforeAttempt: attempt + 1)
                attempt += 1
            }
        }
    }

    private static func url(baseURL: URL, path: String) -> URL {
        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pathAndQuery = sanitizedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let url = baseURL.appending(path: String(pathAndQuery.first ?? ""))
        guard pathAndQuery.count == 2,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.percentEncodedQuery = String(pathAndQuery[1])
        return components.url ?? url
    }

    private static func operationName(method: String, path: String) -> String {
        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pathOnly = String(sanitizedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let components = pathOnly.split(separator: "/").map(String.init)

        switch components {
        case ["v1", "me"]:
            return "v1.me"
        case ["v1", "me", "access"]:
            return "v1.me.access"
        case ["v1", "me", "delete-account-request"]:
            return "v1.me.delete_account_request"
        case ["v1", "me", "delete-account-finalize"]:
            return "v1.me.delete_account_finalize"
        case let route where route.count == 5 && route.prefix(4) == ["v1", "tune", "feedback", "stations"]:
            return "v1.tune.feedback.stations.item"
        case let route where route.count == 5 && route.prefix(4) == ["v1", "tune", "feedback", "tracks"]:
            return "v1.tune.feedback.tracks.item"
        case ["v1", "tune", "workspace", "realtime-sessions"]:
            return "v1.tune.workspace.realtime_sessions"
        case ["v1", "tune", "me", "summary"]:
            return "v1.tune.me.summary"
        default:
            return "unknown.\(method.lowercased())"
        }
    }

    private static func sanitizedErrorCode(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.code.metricName
        }
        if let clientError = error as? TuneAVAccessClientError {
            switch clientError {
            case .missingToken:
                return "missing_token"
            case .missingBaseURL:
                return "missing_base_url"
            case .requestFailed:
                return "request_failed"
            case .avTunesysAccessMissing:
                return "tuneav_access_missing"
            }
        }
        return "network_error"
    }

    struct RetryPolicy {
        let maxAttempts: Int
        let backoffNanoseconds: UInt64

        static let account = RetryPolicy(maxAttempts: 2, backoffNanoseconds: 250_000_000)
        static let disabled = RetryPolicy(maxAttempts: 1, backoffNanoseconds: 0)

        func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
            attempt < maxAttempts && (500..<600).contains(statusCode)
        }

        func shouldRetry(error: Error, attempt: Int) -> Bool {
            guard attempt < maxAttempts, let urlError = error as? URLError else {
                return false
            }

            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }

        func sleep(beforeAttempt: Int) async throws {
            guard beforeAttempt > 1, backoffNanoseconds > 0 else { return }
            try await Task.sleep(nanoseconds: backoffNanoseconds)
        }
    }
}

private extension URLError.Code {
    var metricName: String {
        switch self {
        case .timedOut:
            return "timed_out"
        case .cannotFindHost:
            return "cannot_find_host"
        case .cannotConnectToHost:
            return "cannot_connect_to_host"
        case .networkConnectionLost:
            return "network_connection_lost"
        case .dnsLookupFailed:
            return "dns_lookup_failed"
        case .notConnectedToInternet:
            return "not_connected_to_internet"
        case .internationalRoamingOff:
            return "international_roaming_off"
        case .callIsActive:
            return "call_is_active"
        case .dataNotAllowed:
            return "data_not_allowed"
        case .badServerResponse:
            return "bad_server_response"
        default:
            return "url_error"
        }
    }
}
