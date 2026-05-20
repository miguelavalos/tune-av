import Foundation

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
            "Missing Apps AV account token."
        case .missingBaseURL:
            "Missing Apps AV API base URL."
        case .requestFailed(let statusCode):
            "Apps AV API request failed with status \(statusCode)."
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

    init(
        getToken: @escaping () async throws -> String?,
        baseURLProvider: @escaping () -> URL? = { AppConfig.avAccountAPIBaseURL },
        urlSession: URLSession = TuneAVURLSessions.account,
        decoder: JSONDecoder = JSONDecoder(),
        retryPolicy: RetryPolicy = .account
    ) {
        self.getToken = getToken
        self.baseURLProvider = baseURLProvider
        self.urlSession = urlSession
        self.decoder = decoder
        self.retryPolicy = retryPolicy
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
        guard let token = try await getToken(), !token.isEmpty else {
            throw AVAccountAPIClientError.missingToken
        }

        guard let baseURL = baseURLProvider() else {
            throw AVAccountAPIClientError.missingBaseURL
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

        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AVAccountAPIClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return data
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 1

        while true {
            do {
                let (data, response) = try await urlSession.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   retryPolicy.shouldRetry(statusCode: httpResponse.statusCode, attempt: attempt),
                   !Task.isCancelled {
                    try await retryPolicy.sleep(beforeAttempt: attempt + 1)
                    attempt += 1
                    continue
                }
                return (data, response)
            } catch {
                guard retryPolicy.shouldRetry(error: error, attempt: attempt), !Task.isCancelled else {
                    throw error
                }
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
}

extension AVAccountAPIClient: AccountDeletionAPI {}

extension AVAccountAPIClient {
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
