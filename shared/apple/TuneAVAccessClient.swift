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
    private let metricsSink: MetricsSink
    private let logger = Logger(subsystem: "com.avalsys.tuneav", category: "account-network")

    init(
        baseURL: URL?,
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        retryPolicy: RetryPolicy = .account,
        metricsSink: MetricsSink = .osLog
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.decoder = decoder
        self.retryPolicy = retryPolicy
        self.metricsSink = metricsSink
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

    func createTuneAVRealtimeSession() async throws -> String {
        let response: TuneAVSharedRealtimeSessionResponse = try await request(
            path: "/v1/tune/workspace/realtime-sessions",
            method: "POST",
            body: Data("{}".utf8),
            headers: ["Content-Type": "application/json"]
        )
        return response.realtimeSessionId
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
        let startedAt = Date()
        recordNetworkEvent(NetworkEvent(
            kind: .started,
            operation: operation,
            method: method,
            statusCode: nil,
            durationMilliseconds: nil,
            attempt: 1,
            errorCode: nil
        ))

        let data: Data
        let response: URLResponse
        let attempts: Int
        do {
            (data, response, attempts) = try await performDataTask(for: request, operation: operation, method: method)
        } catch {
            recordNetworkEvent(NetworkEvent(
                kind: .failed,
                operation: operation,
                method: method,
                statusCode: nil,
                durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                attempt: nil,
                errorCode: Self.sanitizedErrorCode(error)
            ))
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            recordNetworkEvent(NetworkEvent(
                kind: .failed,
                operation: operation,
                method: method,
                statusCode: nil,
                durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                attempt: attempts,
                errorCode: "bad_server_response"
            ))
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            recordNetworkEvent(NetworkEvent(
                kind: .failed,
                operation: operation,
                method: method,
                statusCode: httpResponse.statusCode,
                durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                attempt: attempts,
                errorCode: nil
            ))
            throw TuneAVAccessClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        recordNetworkEvent(NetworkEvent(
            kind: .completed,
            operation: operation,
            method: method,
            statusCode: httpResponse.statusCode,
            durationMilliseconds: Self.durationMilliseconds(since: startedAt),
            attempt: attempts,
            errorCode: nil
        ))
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
                    recordNetworkEvent(NetworkEvent(
                        kind: .retrying,
                        operation: operation,
                        method: method,
                        statusCode: httpResponse.statusCode,
                        durationMilliseconds: nil,
                        attempt: attempt + 1,
                        errorCode: nil
                    ))
                    try await retryPolicy.sleep(beforeAttempt: attempt + 1)
                    attempt += 1
                    continue
                }
                return (data, response, attempt)
            } catch {
                guard retryPolicy.shouldRetry(error: error, attempt: attempt), !Task.isCancelled else {
                    throw error
                }
                recordNetworkEvent(NetworkEvent(
                    kind: .retrying,
                    operation: operation,
                    method: method,
                    statusCode: nil,
                    durationMilliseconds: nil,
                    attempt: attempt + 1,
                    errorCode: Self.sanitizedErrorCode(error)
                ))
                try await retryPolicy.sleep(beforeAttempt: attempt + 1)
                attempt += 1
            }
        }
    }

    private func recordNetworkEvent(_ event: NetworkEvent) {
        metricsSink.record(event)
        switch event.kind {
        case .started:
            logger.debug("Account API request started operation=\(event.operation, privacy: .public) method=\(event.method, privacy: .public)")
        case .retrying:
            logger.info("Account API request retrying operation=\(event.operation, privacy: .public) method=\(event.method, privacy: .public) attempt=\(event.attempt ?? 0, privacy: .public) status=\(event.statusCode ?? 0, privacy: .public) error=\(event.errorCode ?? "none", privacy: .public)")
        case .completed:
            logger.info("Account API request completed operation=\(event.operation, privacy: .public) method=\(event.method, privacy: .public) status=\(event.statusCode ?? 0, privacy: .public) duration_ms=\(event.durationMilliseconds ?? 0, privacy: .public) attempts=\(event.attempt ?? 0, privacy: .public)")
        case .failed:
            logger.error("Account API request failed operation=\(event.operation, privacy: .public) method=\(event.method, privacy: .public) status=\(event.statusCode ?? 0, privacy: .public) duration_ms=\(event.durationMilliseconds ?? 0, privacy: .public) attempts=\(event.attempt ?? 0, privacy: .public) error=\(event.errorCode ?? "none", privacy: .public)")
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
        case ["v1", "apps", "tuneav", "link"]:
            return "v1.apps.tuneav.link"
        case let route where route.count == 5 && route.prefix(4) == ["v1", "tune", "feedback", "stations"]:
            return "v1.tune.feedback.stations.item"
        case let route where route.count == 5 && route.prefix(4) == ["v1", "tune", "feedback", "tracks"]:
            return "v1.tune.feedback.tracks.item"
        case ["v1", "tune", "analytics", "listening-sessions"]:
            return "v1.tune.analytics.listening_sessions"
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

    private static func durationMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }

    struct MetricsSink: Sendable {
        let record: @MainActor @Sendable (NetworkEvent) -> Void

        static let osLog = MetricsSink { _ in }
    }

    struct NetworkEvent: Equatable, Sendable {
        enum Kind: String, Sendable {
            case started
            case retrying
            case completed
            case failed
        }

        let kind: Kind
        let operation: String
        let method: String
        let statusCode: Int?
        let durationMilliseconds: Int?
        let attempt: Int?
        let errorCode: String?
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

private struct TuneAVSharedRealtimeSessionResponse: Decodable {
    let realtimeSessionId: String
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
