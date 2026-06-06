import Combine
@preconcurrency import ConvexMobile
import Foundation

struct TuneAVProLibraryProjection: Decodable, Equatable {
    let ownerUserId: String
    let favorites: [FavoriteStationRecord]
    let recents: [RecentStationRecord]
    let discoveries: [DiscoveredTrackRecord]
    let projectionVersion: Int
    let sourceUpdatedAt: Double?
    let updatedAt: Double
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
    @Published private(set) var projection: TuneAVProLibraryProjection?
    @Published private(set) var errorMessage: String?

    private let client: TuneAVProRealtimeClient
    private var observationTask: Task<Void, Never>?
    private var observationGeneration = 0

    init(client: TuneAVProRealtimeClient = TuneAVProRealtimeClient(deploymentURL: AppConfig.tuneConvexURL)) {
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
                            self?.projection = projection
                            self?.errorMessage = nil
                        }
                    }
                } catch {
                    await MainActor.run {
                        guard self?.observationGeneration == generation else { return }
                        self?.projection = nil
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            guard observationGeneration == generation else { return }
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
