import Foundation
import OSLog

@MainActor
final class TuneAVAppDataService {
    private let syncClient: TuneAVAppDataSyncClient
    private let apiClient: AVAccountAPIClient
    private let encoder = JSONEncoder()
    private let analyticsLogger = Logger(subsystem: "com.avalsys.tuneav", category: "listening-analytics")

    init(apiClient: AVAccountAPIClient) {
        self.apiClient = apiClient
        self.syncClient = TuneAVAppDataSyncClient(
            deviceId: "tuneav-ios",
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
        apiClient.isConfigured()
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
        let idempotencyKey = Self.idempotencyKey(parts: ["station-feedback", stationID, feedback?.backendValue ?? "clear"])
        _ = try await apiClient.requestData(
            path: "/v1/tune/feedback/stations/\(stationID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stationID)",
            method: "PUT",
            body: try encoder.encode(payload),
            headers: ["Idempotency-Key": idempotencyKey]
        )
    }

    func setTrackFeedback(_ feedback: TuneAVStationFeedback?, title: String, artist: String?, stationID: String?) async throws {
        let key = Self.trackFeedbackKey(title: title, artist: artist)
        let idempotencyKey = Self.idempotencyKey(parts: ["track-feedback", key, stationID ?? "unknown-station", feedback?.backendValue ?? "clear"])
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
            body: try encoder.encode(payload),
            headers: ["Idempotency-Key": idempotencyKey]
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

    @discardableResult
    func recordListeningSessions(_ sessions: [TuneAVListeningSessionDraft]) async throws -> TuneAVListeningSessionsUploadResult {
        let inputs = sessions
            .filter { $0.durationSeconds >= 10 }
            .map { session in
                TuneAVListeningSessionInput(
                    id: session.id,
                    stationId: session.stationID,
                    stationName: session.stationName,
                    startedAt: TuneAVDateCoding.string(from: session.startedAt),
                    endedAt: TuneAVDateCoding.string(from: session.endedAt),
                    durationSeconds: session.durationSeconds,
                    source: session.source,
                    endedReason: session.endedReason,
                    trackDetectedCount: session.trackDetectedCount
                )
            }
        guard !inputs.isEmpty else {
            return TuneAVListeningSessionsUploadResult(accepted: 0, duplicate: 0, rejected: sessions.count)
        }

        let payload = TuneAVListeningSessionsRequest(
            deviceId: "tuneav-ios",
            sessions: inputs
        )
        let response: TuneAVListeningSessionsResponse = try await apiClient.request(
            path: "/v1/tune/analytics/listening-sessions",
            method: "POST",
            body: try encoder.encode(payload),
            headers: ["Idempotency-Key": Self.idempotencyKey(parts: ["listening-sessions"] + inputs.map(\.id))]
        )
        let result = TuneAVListeningSessionsUploadResult(response: response)
        analyticsLogger.debug(
            "Listening sessions uploaded accepted=\(result.accepted, privacy: .public) duplicate=\(result.duplicate, privacy: .public) rejected=\(result.rejected, privacy: .public)"
        )
        return result
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

    private static func idempotencyKey(parts: [String]) -> String {
        parts
            .map { part in
                part
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
                    .replacingOccurrences(of: "[^a-z0-9._:-]", with: "-", options: .regularExpression)
                    .lowercased()
            }
            .filter { !$0.isEmpty }
            .joined(separator: ":")
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

struct TuneAVListeningSessionDraft: Codable, Equatable {
    let id: String
    let stationID: String
    let stationName: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let source: String
    let endedReason: String
    let trackDetectedCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case station
        case stationID
        case stationName
        case startedAt
        case endedAt
        case durationSeconds
        case source
        case endedReason
        case trackDetectedCount
    }

    init(
        id: String = UUID().uuidString,
        station: Station,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        source: String,
        endedReason: String,
        trackDetectedCount: Int
    ) {
        self.id = id
        self.stationID = station.id
        self.stationName = station.name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.source = source
        self.endedReason = endedReason
        self.trackDetectedCount = trackDetectedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        if let stationID = try container.decodeIfPresent(String.self, forKey: .stationID),
           let stationName = try container.decodeIfPresent(String.self, forKey: .stationName) {
            self.stationID = stationID
            self.stationName = stationName
        } else {
            let station = try container.decode(Station.self, forKey: .station)
            stationID = station.id
            stationName = station.name
        }

        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        source = try container.decode(String.self, forKey: .source)
        endedReason = try container.decode(String.self, forKey: .endedReason)
        trackDetectedCount = try container.decode(Int.self, forKey: .trackDetectedCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(stationID, forKey: .stationID)
        try container.encode(stationName, forKey: .stationName)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(source, forKey: .source)
        try container.encode(endedReason, forKey: .endedReason)
        try container.encode(trackDetectedCount, forKey: .trackDetectedCount)
    }
}

private struct TuneAVListeningSessionsRequest: Encodable {
    let deviceId: String
    let sessions: [TuneAVListeningSessionInput]
}

struct TuneAVListeningSessionsUploadResult: Equatable {
    let accepted: Int
    let duplicate: Int
    let rejected: Int

    init(accepted: Int, duplicate: Int, rejected: Int) {
        self.accepted = accepted
        self.duplicate = duplicate
        self.rejected = rejected
    }

    fileprivate init(response: TuneAVListeningSessionsResponse) {
        self.init(
            accepted: response.accepted,
            duplicate: response.duplicate,
            rejected: response.rejected
        )
    }
}

private struct TuneAVListeningSessionsResponse: Decodable {
    let accepted: Int
    let duplicate: Int
    let rejected: Int

    private enum CodingKeys: String, CodingKey {
        case accepted
        case duplicate
        case rejected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decodeIfPresent(Int.self, forKey: .accepted) ?? 0
        duplicate = try container.decodeIfPresent(Int.self, forKey: .duplicate) ?? 0
        rejected = try container.decodeIfPresent(Int.self, forKey: .rejected) ?? 0
    }
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
