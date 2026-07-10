import Combine
@preconcurrency import ConvexMobile
import Foundation
import OSLog

struct TuneAVProLibraryProjection: Decodable, Equatable {
    let ownerUserId: String
    let projectionVersion: Int
    let libraryGeneration: Int?
    let feedbackGeneration: Int?
    let resource: String?
    let sourceUpdatedAt: Double?
    let updatedAt: Double

    private enum CodingKeys: String, CodingKey {
        case ownerUserId
        case projectionVersion
        case libraryGeneration
        case feedbackGeneration
        case resource
        case sourceUpdatedAt
        case updatedAt
    }

    init(
        ownerUserId: String,
        projectionVersion: Int,
        libraryGeneration: Int? = nil,
        feedbackGeneration: Int? = nil,
        resource: String? = nil,
        sourceUpdatedAt: Double?,
        updatedAt: Double
    ) {
        self.ownerUserId = ownerUserId
        self.projectionVersion = projectionVersion
        self.libraryGeneration = libraryGeneration
        self.feedbackGeneration = feedbackGeneration
        self.resource = resource
        self.sourceUpdatedAt = sourceUpdatedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownerUserId = try container.decode(String.self, forKey: .ownerUserId)
        projectionVersion = try container.decode(Int.self, forKey: .projectionVersion)
        libraryGeneration = try container.decodeIfPresent(Int.self, forKey: .libraryGeneration)
        feedbackGeneration = try container.decodeIfPresent(Int.self, forKey: .feedbackGeneration)
        resource = try container.decodeIfPresent(String.self, forKey: .resource)
        sourceUpdatedAt = try container.decodeIfPresent(Double.self, forKey: .sourceUpdatedAt)
        updatedAt = try container.decode(Double.self, forKey: .updatedAt)
    }
}

struct TuneAVProRealtimeRefreshPlan: Equatable {
    let refreshLibrary: Bool
    let refreshFeedback: Bool

    static let none = TuneAVProRealtimeRefreshPlan(
        refreshLibrary: false,
        refreshFeedback: false
    )
}

struct TuneAVProRealtimeCoverage: Equatable {
    let librarySourceUpdatedAtByResource: [String: Date]
    let feedbackSourceUpdatedAt: Date?

    static let none = TuneAVProRealtimeCoverage(
        librarySourceUpdatedAtByResource: [:],
        feedbackSourceUpdatedAt: nil
    )
}

extension TuneAVProLibraryProjection {
    var sourceUpdatedAtDate: Date? {
        guard let sourceUpdatedAt, sourceUpdatedAt.isFinite, sourceUpdatedAt > 0 else { return nil }
        let seconds = sourceUpdatedAt >= 10_000_000_000 ? sourceUpdatedAt / 1_000 : sourceUpdatedAt
        return Date(timeIntervalSince1970: seconds)
    }
}

struct TuneAVProRealtimeProjectionCursor {
    private var ownerUserId: String?
    private var libraryGeneration: Int?
    private var feedbackGeneration: Int?
    private var legacyUpdatedAt: Double?

    mutating func consume(
        _ projection: TuneAVProLibraryProjection,
        coverage: TuneAVProRealtimeCoverage = .none
    ) -> TuneAVProRealtimeRefreshPlan {
        if ownerUserId != projection.ownerUserId {
            reset()
            ownerUserId = projection.ownerUserId
        }

        if projection.libraryGeneration != nil || projection.feedbackGeneration != nil {
            let nextLibraryGeneration = projection.libraryGeneration ?? 0
            let nextFeedbackGeneration = projection.feedbackGeneration ?? 0
            let refreshLibrary = nextLibraryGeneration > (libraryGeneration ?? 0)
            let refreshFeedback = nextFeedbackGeneration > (feedbackGeneration ?? 0)

            libraryGeneration = max(libraryGeneration ?? 0, nextLibraryGeneration)
            feedbackGeneration = max(feedbackGeneration ?? 0, nextFeedbackGeneration)
            legacyUpdatedAt = max(legacyUpdatedAt ?? 0, projection.updatedAt)

            return filtered(
                TuneAVProRealtimeRefreshPlan(
                    refreshLibrary: refreshLibrary,
                    refreshFeedback: refreshFeedback
                ),
                projection: projection,
                coverage: coverage
            )
        }

        if let legacyUpdatedAt, projection.updatedAt <= legacyUpdatedAt {
            return .none
        }

        legacyUpdatedAt = projection.updatedAt
        let isFeedback = projection.resource?.hasPrefix("feedback.") == true
        return filtered(
            TuneAVProRealtimeRefreshPlan(
                refreshLibrary: !isFeedback,
                refreshFeedback: isFeedback
            ),
            projection: projection,
            coverage: coverage
        )
    }

    private func filtered(
        _ plan: TuneAVProRealtimeRefreshPlan,
        projection: TuneAVProLibraryProjection,
        coverage: TuneAVProRealtimeCoverage
    ) -> TuneAVProRealtimeRefreshPlan {
        guard let sourceUpdatedAt = projection.sourceUpdatedAtDate else { return plan }

        var refreshLibrary = plan.refreshLibrary
        if refreshLibrary,
           let resource = projection.resource,
           projection.resource?.hasPrefix("feedback.") != true,
           let coveredThrough = coverage.librarySourceUpdatedAtByResource[resource],
           coveredThrough >= sourceUpdatedAt {
            refreshLibrary = false
        }

        var refreshFeedback = plan.refreshFeedback
        if refreshFeedback,
           let coveredThrough = coverage.feedbackSourceUpdatedAt,
           coveredThrough >= sourceUpdatedAt {
            refreshFeedback = false
        }

        return TuneAVProRealtimeRefreshPlan(
            refreshLibrary: refreshLibrary,
            refreshFeedback: refreshFeedback
        )
    }

    mutating func reset() {
        ownerUserId = nil
        libraryGeneration = nil
        feedbackGeneration = nil
        legacyUpdatedAt = nil
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

struct TuneAVFeedbackSnapshot: Decodable, Equatable {
    let generatedAt: String
    let stationFeedback: [TuneAVStationFeedbackRecord]
    let trackFeedback: [TuneAVTrackFeedbackRecord]
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

struct TuneAVRealtimeSession: Equatable, Sendable {
    let realtimeSessionId: String
    let expiresAt: Date
}

struct TuneAVRealtimeSessionRenewalPolicy: Equatable, Sendable {
    let renewalLeadTime: TimeInterval
    let renewalJitter: TimeInterval
    let minimumRenewalDelay: TimeInterval
    let retryBaseDelay: TimeInterval
    let retryMaximumDelay: TimeInterval
    let maximumRetryAttempts: Int

    init(
        renewalLeadTime: TimeInterval = 60 * 60,
        renewalJitter: TimeInterval = 15 * 60,
        minimumRenewalDelay: TimeInterval = 1,
        retryBaseDelay: TimeInterval = 5,
        retryMaximumDelay: TimeInterval = 5 * 60,
        maximumRetryAttempts: Int = 5
    ) {
        self.renewalLeadTime = renewalLeadTime
        self.renewalJitter = renewalJitter
        self.minimumRenewalDelay = minimumRenewalDelay
        self.retryBaseDelay = retryBaseDelay
        self.retryMaximumDelay = retryMaximumDelay
        self.maximumRetryAttempts = maximumRetryAttempts
    }

    func renewalDelay(
        for session: TuneAVRealtimeSession,
        now: Date,
        jitterUnitInterval: Double
    ) -> TimeInterval {
        let lifetime = max(0, session.expiresAt.timeIntervalSince(now))
        let boundedLeadTime = min(renewalLeadTime, lifetime / 4)
        let boundedJitter = min(renewalJitter, lifetime / 10)
            * min(max(jitterUnitInterval, 0), 1)
        return max(minimumRenewalDelay, lifetime - boundedLeadTime - boundedJitter)
    }

    func canReuse(_ session: TuneAVRealtimeSession, now: Date) -> Bool {
        session.expiresAt.timeIntervalSince(now) > renewalLeadTime + renewalJitter
    }

    func retryDelay(attempt: Int, jitterUnitInterval: Double) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let exponentialDelay = retryBaseDelay * pow(2, Double(exponent))
        let boundedDelay = min(retryMaximumDelay, exponentialDelay)
        let jitterMultiplier = 0.8 + (0.4 * min(max(jitterUnitInterval, 0), 1))
        return min(retryMaximumDelay, boundedDelay * jitterMultiplier)
    }
}

@MainActor
final class TuneAVRealtimeSessionSupervisor: ObservableObject {
    typealias CreateSession = @MainActor () async throws -> TuneAVRealtimeSession
    typealias SessionHandler = @MainActor (TuneAVRealtimeSession) -> Void
    typealias FailureHandler = @MainActor (Error) -> Void

    private let policy: TuneAVRealtimeSessionRenewalPolicy
    private let now: @MainActor () -> Date
    private let jitterUnitInterval: @MainActor () -> Double
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private var renewalTask: Task<Void, Never>?
    private var currentSession: TuneAVRealtimeSession?

    init(
        policy: TuneAVRealtimeSessionRenewalPolicy = TuneAVRealtimeSessionRenewalPolicy(),
        now: @escaping @MainActor () -> Date = { .now },
        jitterUnitInterval: @escaping @MainActor () -> Double = { Double.random(in: 0...1) },
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { delay in
            try await Task.sleep(for: .seconds(delay))
        }
    ) {
        self.policy = policy
        self.now = now
        self.jitterUnitInterval = jitterUnitInterval
        self.sleep = sleep
    }

    func start(
        createSession: @escaping CreateSession,
        didCreateSession: @escaping SessionHandler,
        didExhaustRetries: @escaping FailureHandler
    ) {
        pause()
        renewalTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var failedAttempts = 0

            while !Task.isCancelled {
                do {
                    let session: TuneAVRealtimeSession
                    if let currentSession, policy.canReuse(currentSession, now: now()) {
                        session = currentSession
                    } else {
                        session = try await createSession()
                        currentSession = session
                    }
                    guard !Task.isCancelled else { return }
                    failedAttempts = 0
                    didCreateSession(session)
                    let delay = policy.renewalDelay(
                        for: session,
                        now: now(),
                        jitterUnitInterval: jitterUnitInterval()
                    )
                    try await sleep(delay)
                } catch {
                    guard !Task.isCancelled else { return }
                    failedAttempts += 1
                    guard failedAttempts < policy.maximumRetryAttempts else {
                        currentSession = nil
                        didExhaustRetries(error)
                        return
                    }
                    do {
                        try await sleep(policy.retryDelay(
                            attempt: failedAttempts,
                            jitterUnitInterval: jitterUnitInterval()
                        ))
                    } catch {
                        return
                    }
                }
            }
        }
    }

    func pause() {
        renewalTask?.cancel()
        renewalTask = nil
    }

    func stop() {
        pause()
        currentSession = nil
    }

    deinit {
        renewalTask?.cancel()
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
                                    "Received Tune AV Pro Convex invalidation resource=\(projection.resource ?? "unknown", privacy: .public) updatedAt=\(projection.updatedAt, privacy: .public)"
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
