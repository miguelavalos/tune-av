import Foundation

@MainActor
final class TuneAVAppDataService {
    private let syncClient: TuneAVAppDataSyncClient
    private let apiClient: AVAccountAPIClient
    private let encoder = JSONEncoder()

    init(apiClient: AVAccountAPIClient) {
        self.apiClient = apiClient
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

    func fetchUserSummary(limit: Int = 12) async throws -> TuneAVUserSummary {
        try await apiClient.request(path: "/v1/tune/me/summary?limit=\(limit)")
    }

    func setStationFeedback(_ feedback: TuneAVStationFeedback?, stationID: String) async throws {
        let payload = TuneAVFeedbackRequest(deviceId: "tuneav-ios", feedback: feedback?.backendValue)
        _ = try await apiClient.requestData(
            path: "/v1/tune/feedback/stations/\(stationID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stationID)",
            method: "PUT",
            body: try encoder.encode(payload)
        )
    }

    func setTrackFeedback(_ feedback: TuneAVStationFeedback?, title: String, artist: String?, stationID: String?) async throws {
        let key = Self.trackFeedbackKey(title: title, artist: artist)
        let payload = TuneAVTrackFeedbackRequest(
            deviceId: "tuneav-ios",
            title: title,
            artist: artist,
            stationId: stationID,
            feedback: feedback?.backendValue
        )
        _ = try await apiClient.requestData(
            path: "/v1/tune/feedback/tracks/\(key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key)",
            method: "PUT",
            body: try encoder.encode(payload)
        )
    }

    func recordListeningSession(
        station: Station,
        startedAt: Date,
        endedAt: Date,
        source: String,
        endedReason: String,
        trackDetectedCount: Int
    ) async throws {
        let duration = max(0, Int(endedAt.timeIntervalSince(startedAt).rounded()))
        guard duration >= 10 else { return }

        try await recordListeningSessions([
            TuneAVListeningSessionDraft(
                station: station,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: duration,
                source: source,
                endedReason: endedReason,
                trackDetectedCount: trackDetectedCount
            )
        ])
    }

    func recordListeningSessions(_ sessions: [TuneAVListeningSessionDraft]) async throws {
        let inputs = sessions
            .filter { $0.durationSeconds >= 10 }
            .map { session in
                TuneAVListeningSessionInput(
                    id: UUID().uuidString,
                    stationId: session.station.id,
                    stationName: session.station.name,
                    startedAt: TuneAVDateCoding.string(from: session.startedAt),
                    endedAt: TuneAVDateCoding.string(from: session.endedAt),
                    durationSeconds: session.durationSeconds,
                    source: session.source,
                    endedReason: session.endedReason,
                    trackDetectedCount: session.trackDetectedCount
                )
            }
        guard !inputs.isEmpty else { return }

        let payload = TuneAVListeningSessionsRequest(
            deviceId: "tuneav-ios",
            sessions: inputs
        )
        _ = try await apiClient.requestData(
            path: "/v1/tune/analytics/listening-sessions",
            method: "POST",
            body: try encoder.encode(payload)
        )
    }

    static func isoString(from date: Date) -> String {
        TuneAVDateCoding.string(from: date)
    }

    private static func trackFeedbackKey(title: String, artist: String?) -> String {
        [title, artist ?? ""]
            .map { value in
                value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .lowercased()
            }
            .joined(separator: "::")
    }
}

private struct TuneAVFeedbackRequest: Encodable {
    let deviceId: String
    let feedback: String?
}

private struct TuneAVTrackFeedbackRequest: Encodable {
    let deviceId: String
    let title: String
    let artist: String?
    let stationId: String?
    let feedback: String?
}

struct TuneAVListeningSessionDraft: Equatable {
    let station: Station
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let source: String
    let endedReason: String
    let trackDetectedCount: Int
}

private struct TuneAVListeningSessionsRequest: Encodable {
    let deviceId: String
    let sessions: [TuneAVListeningSessionInput]
}

private struct TuneAVListeningSessionInput: Encodable {
    let id: String
    let stationId: String
    let stationName: String
    let startedAt: String
    let endedAt: String
    let durationSeconds: Int
    let source: String
    let endedReason: String
    let trackDetectedCount: Int
}

struct TuneAVUserSummary: Decodable, Equatable {
    let generatedAt: String
    let period: String
    let limit: Int
    let accessMode: String
    let radio: TuneAVRadioSummary
    let music: TuneAVMusicSummary
}

struct TuneAVRadioSummary: Decodable, Equatable {
    let cards: TuneAVRadioSummaryCards
}

struct TuneAVRadioSummaryCards: Decodable, Equatable {
    let saved: TuneAVSummaryCard
    let recent: TuneAVSummaryCard
    let topWeek: TuneAVSummaryCard
    let tuned: TuneAVSummaryCard
}

struct TuneAVMusicSummary: Decodable, Equatable {
    let cards: TuneAVMusicSummaryCards
}

struct TuneAVMusicSummaryCards: Decodable, Equatable {
    let songs: TuneAVSummaryCard
    let artists: TuneAVSummaryCard
    let radios: TuneAVSummaryCard
    let history: TuneAVSummaryCard
}

struct TuneAVSummaryCard: Decodable, Equatable {
    let count: Int
}

enum TuneAVUserSummaryRefreshState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed
    case unavailable
}

extension TuneAVUserSummary {
    var hasAnyActivity: Bool {
        radio.cards.saved.count > 0 ||
            radio.cards.recent.count > 0 ||
            radio.cards.topWeek.count > 0 ||
            radio.cards.tuned.count > 0 ||
            music.cards.songs.count > 0 ||
            music.cards.artists.count > 0 ||
            music.cards.radios.count > 0 ||
            music.cards.history.count > 0
    }
}

private extension TuneAVStationFeedback {
    var backendValue: String {
        switch self {
        case .liked:
            return "liked"
        case .notForMe:
            return "not_for_me"
        case .disliked:
            return "disliked"
        }
    }
}
