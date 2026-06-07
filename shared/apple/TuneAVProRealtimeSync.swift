import Combine
@preconcurrency import ConvexMobile
import Foundation
import OSLog

struct TuneAVProLibraryProjection: Decodable, Equatable {
    let ownerUserId: String
    let favorites: [FavoriteStationRecord]
    let recents: [RecentStationRecord]
    let discoveries: [DiscoveredTrackRecord]
    let stationFeedback: [TuneAVStationFeedbackRecord]
    let trackFeedback: [TuneAVTrackFeedbackRecord]
    let projectionVersion: Int
    let sourceUpdatedAt: Double?
    let updatedAt: Double

    private enum CodingKeys: String, CodingKey {
        case ownerUserId
        case favorites
        case recents
        case discoveries
        case stationFeedback
        case trackFeedback
        case projectionVersion
        case sourceUpdatedAt
        case updatedAt
    }

    init(
        ownerUserId: String,
        favorites: [FavoriteStationRecord],
        recents: [RecentStationRecord],
        discoveries: [DiscoveredTrackRecord],
        stationFeedback: [TuneAVStationFeedbackRecord] = [],
        trackFeedback: [TuneAVTrackFeedbackRecord] = [],
        projectionVersion: Int,
        sourceUpdatedAt: Double?,
        updatedAt: Double
    ) {
        self.ownerUserId = ownerUserId
        self.favorites = favorites
        self.recents = recents
        self.discoveries = discoveries
        self.stationFeedback = stationFeedback
        self.trackFeedback = trackFeedback
        self.projectionVersion = projectionVersion
        self.sourceUpdatedAt = sourceUpdatedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownerUserId = try container.decode(String.self, forKey: .ownerUserId)
        favorites = try container.decode([FavoriteStationRecord].self, forKey: .favorites)
        recents = try container.decode([RecentStationRecord].self, forKey: .recents)
        discoveries = try container.decode([DiscoveredTrackRecord].self, forKey: .discoveries)
        stationFeedback = try container.decodeIfPresent([TuneAVStationFeedbackRecord].self, forKey: .stationFeedback) ?? []
        trackFeedback = try container.decodeIfPresent([TuneAVTrackFeedbackRecord].self, forKey: .trackFeedback) ?? []
        projectionVersion = try container.decode(Int.self, forKey: .projectionVersion)
        sourceUpdatedAt = try container.decodeIfPresent(Double.self, forKey: .sourceUpdatedAt)
        updatedAt = try container.decode(Double.self, forKey: .updatedAt)
    }
}

enum TuneAVRealtimeProjectionFreshness {
    static func shouldApply(sourceUpdatedAt: Double?, localLibraryUpdatedAt: Date) -> Bool {
        guard let sourceUpdatedAt else { return true }
        let sourceDate = Date(timeIntervalSince1970: sourceUpdatedAt / 1_000)
        return localLibraryUpdatedAt <= sourceDate
    }
}

enum TuneAVRealtimeProjectionMerger {
    static func mergedSnapshot(
        projection: TuneAVProLibraryProjection,
        localSnapshot: TuneAVLibrarySnapshot
    ) -> TuneAVLibrarySnapshot {
        TuneAVLibrarySnapshotMerger.merged(
            local: localSnapshot,
            remote: TuneAVLibrarySnapshot(
                favorites: projection.favorites,
                recents: projection.recents,
                discoveries: projection.discoveries,
                settings: localSnapshot.settings
            )
        )
    }
}

struct TuneAVStationFeedbackRecord: Codable, Equatable {
    let stationID: String
    let feedback: TuneAVStationFeedback
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case stationID
        case feedback
        case updatedAt
    }

    init(stationID: String, feedback: TuneAVStationFeedback, updatedAt: String? = nil) {
        self.stationID = stationID
        self.feedback = feedback
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stationID = try container.decode(String.self, forKey: .stationID)
        feedback = try TuneAVStationFeedback(backendValue: container.decode(String.self, forKey: .feedback))
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct TuneAVTrackFeedbackRecord: Codable, Equatable {
    let trackKey: String
    let title: String
    let artist: String?
    let stationID: String?
    let feedback: TuneAVStationFeedback
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case trackKey
        case title
        case artist
        case stationID
        case feedback
        case updatedAt
    }

    init(
        trackKey: String,
        title: String,
        artist: String? = nil,
        stationID: String? = nil,
        feedback: TuneAVStationFeedback,
        updatedAt: String? = nil
    ) {
        self.trackKey = trackKey
        self.title = title
        self.artist = artist
        self.stationID = stationID
        self.feedback = feedback
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackKey = try container.decode(String.self, forKey: .trackKey)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        stationID = try container.decodeIfPresent(String.self, forKey: .stationID)
        feedback = try TuneAVStationFeedback(backendValue: container.decode(String.self, forKey: .feedback))
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

private extension TuneAVStationFeedback {
    init(backendValue: String) throws {
        switch backendValue {
        case "liked":
            self = .liked
        case "not_for_me", "notForMe":
            self = .notForMe
        case "disliked":
            self = .disliked
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Unknown Tune AV feedback value.")
            )
        }
    }
}

enum TuneAVProRealtimeSyncError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Tune AV Pro realtime sync is not configured."
        }
    }
}

@MainActor
final class TuneAVRealtimeSessionStore {
    static let shared = TuneAVRealtimeSessionStore()

    private(set) var ownerUserId: String?
    private(set) var realtimeSessionId: String?

    private init() {}

    func update(ownerUserId: String, realtimeSessionId: String) {
        self.ownerUserId = ownerUserId
        self.realtimeSessionId = realtimeSessionId
    }

    func clear() {
        ownerUserId = nil
        realtimeSessionId = nil
    }

    func sessionId(for ownerUserId: String) throws -> String {
        guard self.ownerUserId == ownerUserId, let realtimeSessionId else {
            throw TuneAVProRealtimeSyncError.notConfigured
        }

        return realtimeSessionId
    }
}

@MainActor
struct TuneAVProRealtimeClient {
    private static let logger = Logger(subsystem: "com.avalsys.tuneav", category: "pro-realtime")

    private let client: ConvexClient?
    private let realtimeSessionStore: TuneAVRealtimeSessionStore

    init(
        deploymentURL: String,
        realtimeSessionStore: TuneAVRealtimeSessionStore = .shared
    ) {
        let trimmedURL = deploymentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        client = trimmedURL.isEmpty ? nil : ConvexClient(deploymentUrl: trimmedURL)
        self.realtimeSessionStore = realtimeSessionStore
    }

    var isConfigured: Bool {
        client != nil
    }

    func observeLibraryProjection(ownerUserId: String) throws -> AnyPublisher<TuneAVProLibraryProjection?, Error> {
        let client = try requireClient()
        let realtimeSessionId = try realtimeSessionStore.sessionId(for: ownerUserId)
        Self.logger.info("Starting Tune AV Pro Convex subscription ownerUserId=\(ownerUserId, privacy: .private(mask: .hash))")

        return client.subscribe(
            to: "tune:getProLibraryProjection",
            with: [
                "ownerUserId": ownerUserId,
                "realtimeSessionId": realtimeSessionId
            ],
            yielding: TuneAVProLibraryProjection?.self
        )
        .mapError { $0 as Error }
        .eraseToAnyPublisher()
    }

    private func requireClient() throws -> ConvexClient {
        guard let client else {
            throw TuneAVProRealtimeSyncError.notConfigured
        }

        return client
    }
}

@MainActor
final class TuneAVProLibraryObserver: ObservableObject {
    private static let logger = Logger(subsystem: "com.avalsys.tuneav", category: "pro-realtime")

    @Published private(set) var projection: TuneAVProLibraryProjection?
    @Published private(set) var errorMessage: String?

    private let client: TuneAVProRealtimeClient
    private var observationTask: Task<Void, Never>?
    private var observationGeneration = 0

    init(deploymentURL: String) {
        client = TuneAVProRealtimeClient(deploymentURL: deploymentURL)
    }

    init(client: TuneAVProRealtimeClient) {
        self.client = client
    }

    var isConfigured: Bool {
        client.isConfigured
    }

    func observeLibraryProjection(ownerUserId: String?) {
        observationGeneration += 1
        let generation = observationGeneration
        observationTask?.cancel()
        projection = nil
        errorMessage = nil

        guard let ownerUserId else { return }

        do {
            let updates = try client.observeLibraryProjection(ownerUserId: ownerUserId).values

            observationTask = Task { [weak self] in
                do {
                    for try await projection in updates {
                        await MainActor.run {
                            guard self?.observationGeneration == generation else { return }
                            if let projection {
                                Self.logger.info(
                                    "Received Tune AV Pro Convex projection favorites=\(projection.favorites.count, privacy: .public) recents=\(projection.recents.count, privacy: .public) discoveries=\(projection.discoveries.count, privacy: .public) updatedAt=\(projection.updatedAt, privacy: .public)"
                                )
                            } else {
                                Self.logger.info("Received empty Tune AV Pro Convex projection")
                            }
                            self?.projection = projection
                            self?.errorMessage = nil
                        }
                    }
                } catch {
                    await MainActor.run {
                        guard self?.observationGeneration == generation else { return }
                        Self.logger.error("Tune AV Pro Convex subscription failed errorType=\(String(describing: type(of: error)), privacy: .public)")
                        self?.projection = nil
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            guard observationGeneration == generation else { return }
            Self.logger.error("Tune AV Pro Convex subscription setup failed errorType=\(String(describing: type(of: error)), privacy: .public)")
            projection = nil
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        observationGeneration += 1
        observationTask?.cancel()
        projection = nil
        errorMessage = nil
    }

    deinit {
        observationTask?.cancel()
    }
}
