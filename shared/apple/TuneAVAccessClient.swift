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

final class TuneAVAccessClient {
    private let baseURL: URL?
    private let tokenProvider: () async throws -> String?
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(
        baseURL: URL?,
        tokenProvider: @escaping () async throws -> String?,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.decoder = decoder
    }

    func fetchTuneAVAccess() async throws -> AppAccess {
        guard let token = try await tokenProvider(), !token.isEmpty else {
            throw TuneAVAccessClientError.missingToken
        }
        guard let baseURL else {
            throw TuneAVAccessClientError.missingBaseURL
        }

        let url = baseURL.appending(path: "v1/me/access")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TuneAVAccessClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let payload = try decoder.decode(MeAccessResponse.self, from: data)
        guard let tuneAVAccess = payload.apps.first(where: { $0.appId == "tuneav" }) else {
            throw TuneAVAccessClientError.avTunesysAccessMissing
        }

        return tuneAVAccess
    }
}
