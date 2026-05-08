import Foundation

@MainActor
final class TuneAVAppDataService {
    private let syncClient: TuneAVAppDataSyncClient

    init(apiClient: AVAccountAPIClient) {
        self.syncClient = TuneAVAppDataSyncClient(
            deviceId: "tuneav-ios",
            isConfigured: { apiClient.isConfigured() },
            request: { path, method, body, headers in
                do {
                    return try await apiClient.requestData(
                        path: path,
                        method: method,
                        body: body,
                        headers: headers
                    )
                } catch AVAccountAPIClientError.requestFailed(let statusCode) {
                    throw TuneAVAppDataClientError.requestFailed(statusCode: statusCode)
                } catch AVAccountAPIClientError.missingToken {
                    throw TuneAVAppDataClientError.missingToken
                } catch AVAccountAPIClientError.missingBaseURL {
                    throw TuneAVAppDataClientError.missingBaseURL
                } catch {
                    throw error
                }
            }
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

    static func isoString(from date: Date) -> String {
        TuneAVDateCoding.string(from: date)
    }
}
