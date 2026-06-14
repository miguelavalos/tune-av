import Foundation
import OSLog

@MainActor
protocol AccountDeletionAPI {
    func fetchAccountSummary() async throws -> AccountSummary
    func requestAccountDeletion() async throws -> DeleteAccountRequestResponse
    func finalizeAccountDeletion() async throws -> DeleteAccountFinalizeResponse
    func unlinkCurrentApp() async throws -> UnlinkAppResponse
}

enum AVAccountAPIClientError: LocalizedError {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            L10n.string("accountAPI.error.missingToken")
        case .missingBaseURL:
            L10n.string("accountAPI.error.missingBaseURL")
        case .requestFailed(let statusCode):
            L10n.string("accountAPI.error.requestFailed", statusCode)
        }
    }
}

@MainActor
final class AVAccountAPIClient {
    private let getToken: () async throws -> String?
    private let baseURLProvider: () -> URL?
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let retryPolicy: RetryPolicy
    private let metricsSink: MetricsSink
    private let networkLogger = Logger(subsystem: "com.avalsys.tuneav", category: "account-network")

    init(
        getToken: @escaping () async throws -> String?,
        baseURLProvider: @escaping () -> URL? = { AppConfig.avAccountAPIBaseURL },
        urlSession: URLSession = TuneAVURLSessions.account,
        decoder: JSONDecoder = JSONDecoder(),
        retryPolicy: RetryPolicy = .account,
        metricsSink: MetricsSink = .osLog
    ) {
        self.getToken = getToken
        self.baseURLProvider = baseURLProvider
        self.urlSession = urlSession
        self.decoder = decoder
        self.retryPolicy = retryPolicy
        self.metricsSink = metricsSink
    }

    func isConfigured() -> Bool {
        baseURLProvider() != nil
    }

    func fetchMeAccess() async throws -> MeAccessResponse {
        try await request(path: "/v1/me/access")
    }

    func fetchAccountSummary() async throws -> AccountSummary {
        try await request(path: "/v1/me")
    }

    func requestAccountDeletion() async throws -> DeleteAccountRequestResponse {
        try await request(path: "/v1/me/delete-account-request", method: "POST")
    }

    func finalizeAccountDeletion() async throws -> DeleteAccountFinalizeResponse {
        try await request(path: "/v1/me/delete-account-finalize", method: "POST")
    }

    func unlinkCurrentApp() async throws -> UnlinkAppResponse {
        try await request(path: "/v1/apps/tuneav/link", method: "DELETE")
    }

    func createTuneAVRealtimeSession() async throws -> String {
        try await sharedClient().createTuneAVRealtimeSession()
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
        let operation = Self.operationName(method: method, path: path)
        let startedAt = Date()
        do {
            return try await sharedClient().requestData(
                path: path,
                method: method,
                body: body,
                headers: headers
            )
        } catch TuneAVAccessClientError.missingToken {
            let error = AVAccountAPIClientError.missingToken
            captureNetworkError(error, operation: operation, method: method, startedAt: startedAt)
            throw error
        } catch TuneAVAccessClientError.missingBaseURL {
            let error = AVAccountAPIClientError.missingBaseURL
            captureNetworkError(error, operation: operation, method: method, startedAt: startedAt)
            throw error
        } catch TuneAVAccessClientError.requestFailed(let statusCode) {
            let error = AVAccountAPIClientError.requestFailed(statusCode: statusCode)
            captureNetworkError(error, operation: operation, method: method, startedAt: startedAt)
            throw error
        } catch {
            captureNetworkError(error, operation: operation, method: method, startedAt: startedAt)
            throw error
        }
    }

    private func sharedClient() -> TuneAVAccessClient {
        TuneAVAccessClient(
            baseURL: baseURLProvider(),
            tokenProvider: getToken,
            urlSession: urlSession,
            decoder: decoder,
            retryPolicy: TuneAVAccessClient.RetryPolicy(
                maxAttempts: retryPolicy.maxAttempts,
                backoffNanoseconds: retryPolicy.backoffNanoseconds
            ),
            metricsSink: TuneAVAccessClient.MetricsSink { [weak self] event in
                self?.recordNetworkEvent(NetworkEvent(
                    kind: NetworkEvent.Kind(rawValue: event.kind.rawValue) ?? .failed,
                    operation: event.operation,
                    method: event.method,
                    statusCode: event.statusCode,
                    durationMilliseconds: event.durationMilliseconds,
                    attempt: event.attempt,
                    errorCode: event.errorCode
                ))
            }
        )
    }

    private func captureNetworkError(
        _ error: Error,
        operation: String,
        method: String,
        startedAt: Date
    ) {
        guard Self.shouldCaptureNetworkError(error) else { return }

        TuneAVDiagnostics.capture(
            error,
            feature: "tune.account_api",
            operation: operation,
            step: "network",
            data: [
                "method": method,
                "duration_ms": String(Self.durationMilliseconds(since: startedAt)),
            ]
        )
    }

    static func shouldCaptureNetworkError(_ error: Error) -> Bool {
        if let accountError = error as? AVAccountAPIClientError {
            switch accountError {
            case .missingToken, .missingBaseURL:
                return false
            case .requestFailed:
                return true
            }
        }
        return true
    }

    private func recordNetworkEvent(_ event: NetworkEvent) {
        metricsSink.record(event)
        switch event.kind {
        case .started:
            networkLogger.debug("Account API request started operation=\(event.operation, privacy: .public) method=\(event.method, privacy: .public)")
        case .retrying:
            networkLogger.info("Account API request retrying operation=\(event.operation, privacy: .public) method=\(event.method, privacy: .public) attempt=\(event.attempt ?? 0, privacy: .public) status=\(event.statusCode ?? 0, privacy: .public) error=\(event.errorCode ?? "none", privacy: .public)")
        case .completed:
            networkLogger.info("Account API request completed operation=\(event.operation, privacy: .public) method=\(event.method, privacy: .public) status=\(event.statusCode ?? 0, privacy: .public) duration_ms=\(event.durationMilliseconds ?? 0, privacy: .public) attempts=\(event.attempt ?? 0, privacy: .public)")
        case .failed:
            networkLogger.error("Account API request failed operation=\(event.operation, privacy: .public) method=\(event.method, privacy: .public) status=\(event.statusCode ?? 0, privacy: .public) duration_ms=\(event.durationMilliseconds ?? 0, privacy: .public) attempts=\(event.attempt ?? 0, privacy: .public) error=\(event.errorCode ?? "none", privacy: .public)")
        }
    }

    private static func durationMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
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
        case ["v1", "tune", "me", "summary"]:
            return "v1.tune.me.summary"
        case let route where route.count == 5 && route.prefix(4) == ["v1", "tune", "feedback", "stations"]:
            return "v1.tune.feedback.stations.item"
        case let route where route.count == 5 && route.prefix(4) == ["v1", "tune", "feedback", "tracks"]:
            return "v1.tune.feedback.tracks.item"
        case ["v1", "tune", "analytics", "listening-sessions"]:
            return "v1.tune.analytics.listening_sessions"
        default:
            return "unknown.\(method.lowercased())"
        }
    }
}

extension AVAccountAPIClient: AccountDeletionAPI {}

extension AVAccountAPIClient {
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
