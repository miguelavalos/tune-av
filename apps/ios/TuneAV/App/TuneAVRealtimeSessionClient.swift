import Foundation

@MainActor
struct TuneAVRealtimeSessionClient {
    private let apiClient: AVAccountAPIClient

    init(apiClient: AVAccountAPIClient) {
        self.apiClient = apiClient
    }

    var isConfigured: Bool {
        apiClient.isConfigured()
    }

    func createRealtimeSession() async throws -> String {
        let response: TuneAVRealtimeSessionResponse = try await apiClient.request(
            path: "/v1/tune/workspace/realtime-sessions",
            method: "POST",
            body: Data("{}".utf8),
            headers: ["Content-Type": "application/json"]
        )
        return response.realtimeSessionId
    }
}

private struct TuneAVRealtimeSessionResponse: Decodable {
    let realtimeSessionId: String
}
