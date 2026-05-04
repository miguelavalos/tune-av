import Foundation

struct MeAccessResponse: Decodable {
    let apps: [AppAccess]
}

struct AppAccess: Decodable {
    let appId: String
    let accessMode: AccessMode
    let planTier: PlanTier
    let capabilities: AccessCapabilities
    let limits: AccessLimits
}

private struct RegisterSubscriptionAccountTokenRequest: Encodable {
    let provider: String
    let appAccountToken: String
}

private struct RegisterSubscriptionAccountTokenResponse: Decodable {
    let generatedAt: String
}

enum AVAccountAPIClientError: LocalizedError {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "Missing Account AV token."
        case .missingBaseURL:
            "Missing Account AV API base URL."
        case .requestFailed(let statusCode):
            "Account AV API request failed with status \(statusCode)."
        }
    }
}

@MainActor
final class AVAccountAPIClient {
    private let getToken: () async throws -> String?
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(
        getToken: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.getToken = getToken
        self.urlSession = urlSession
        self.decoder = decoder
    }

    func isConfigured() -> Bool {
        AppConfig.avAccountAPIBaseURL != nil
    }

    func fetchMeAccess() async throws -> MeAccessResponse {
        try await request(path: "/v1/me/access")
    }

    func registerAppleSubscriptionAccountToken(_ appAccountToken: UUID, appId: String = "tuneav") async throws {
        let body = try JSONEncoder().encode(
            RegisterSubscriptionAccountTokenRequest(
                provider: "apple",
                appAccountToken: appAccountToken.uuidString.lowercased()
            )
        )
        let _: RegisterSubscriptionAccountTokenResponse = try await request(
            path: "/v1/apps/\(appId)/subscriptions/account-token",
            method: "PUT",
            body: body
        )
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        guard let token = try await getToken(), !token.isEmpty else {
            throw AVAccountAPIClientError.missingToken
        }

        guard let baseURL = AppConfig.avAccountAPIBaseURL else {
            throw AVAccountAPIClientError.missingBaseURL
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
            throw AVAccountAPIClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }
}
