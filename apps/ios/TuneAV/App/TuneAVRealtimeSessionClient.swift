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

    func createRealtimeSession() async throws -> TuneAVRealtimeSession {
        try await apiClient.createTuneAVRealtimeSession()
    }
}
