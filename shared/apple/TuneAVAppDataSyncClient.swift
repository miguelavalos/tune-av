import Foundation

enum TuneAVAppDataClientError: Error, Equatable {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int, retryAfterSeconds: TimeInterval? = nil)
}

typealias MacAppDataClientError = TuneAVAppDataClientError

enum TuneAVSyncRetryDisposition: Equatable {
    case retry(after: TimeInterval?)
    case stop
}

enum TuneAVSyncRetryPolicy {
    static let maximumAutomaticAttempts = 5

    static func disposition(for error: Error) -> TuneAVSyncRetryDisposition {
        if error is CancellationError {
            return .stop
        }
        if error is TuneAVAppDataError {
            return .stop
        }
        if let error = error as? TuneAVAppDataClientError {
            switch error {
            case .missingToken, .missingBaseURL:
                return .stop
            case .requestFailed(let statusCode, let retryAfterSeconds):
                return disposition(statusCode: statusCode, retryAfterSeconds: retryAfterSeconds)
            }
        }
        if let error = error as? TuneAVAccessClientError {
            switch error {
            case .missingToken, .missingBaseURL, .avTunesysAccessMissing:
                return .stop
            case .requestFailed(let statusCode, let retryAfterSeconds):
                return disposition(statusCode: statusCode, retryAfterSeconds: retryAfterSeconds)
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return .retry(after: nil)
            default:
                return .stop
            }
        }
        return .stop
    }

    static func disposition(
        statusCode: Int,
        retryAfterSeconds: TimeInterval? = nil
    ) -> TuneAVSyncRetryDisposition {
        if statusCode == 408 || statusCode == 425 || statusCode == 429 || (500..<600).contains(statusCode) {
            return .retry(after: retryAfterSeconds)
        }
        return .stop
    }

    static func canRetry(afterAttempt attempt: Int) -> Bool {
        attempt + 1 < maximumAutomaticAttempts
    }
}

/// Serializes backend mutations from one app process so bursts of local changes
/// cannot turn into parallel Worker requests.
@MainActor
final class TuneAVSyncMutationGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withPermit<Value>(_ operation: () async throws -> Value) async throws -> Value {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().resume()
    }
}

enum TuneAVAppDataResource: String, CaseIterable {
    case favorites
    case savedDiscoveries

    static let syncResources: [TuneAVAppDataResource] = [
        .favorites,
        .savedDiscoveries
    ]
}

struct TuneAVAppDataResponsePayload<Entry: Codable>: Decodable {
    let data: TuneAVAppDataEnvelopePayload<Entry>
    let updatedAt: String
    let revision: Int?
    let etag: String?
}

private struct TuneAVLossyAppDataResponsePayload<Entry: Decodable>: Decodable {
    let data: TuneAVLossyAppDataEnvelopePayload<Entry>
    let updatedAt: String
    let revision: Int?
    let etag: String?
}

struct TuneAVAppDataEnvelopePayload<Entry: Codable>: Codable {
    let appId: String
    let resource: String
    let deviceId: String
    let sentAt: String
    let entries: [Entry]
}

private struct TuneAVLossyAppDataEnvelopePayload<Entry: Decodable>: Decodable {
    let appId: String
    let resource: String
    let deviceId: String
    let sentAt: String
    let entries: [Entry]

    private enum CodingKeys: String, CodingKey {
        case appId
        case resource
        case deviceId
        case sentAt
        case entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decode(String.self, forKey: .appId)
        resource = try container.decode(String.self, forKey: .resource)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        sentAt = try container.decode(String.self, forKey: .sentAt)
        entries = try container.decode(TuneAVLossyDecodableArray<Entry>.self, forKey: .entries).values
    }
}

private struct TuneAVLossyDecodableArray<Element: Decodable>: Decodable {
    let values: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []

        while !container.isAtEnd {
            do {
                values.append(try container.decode(Element.self))
            } catch {
                _ = try? container.decode(TuneAVDiscardedDecodableValue.self)
            }
        }

        self.values = values
    }
}

private struct TuneAVDiscardedDecodableValue: Decodable {}

struct TuneAVAppDataResourceDocument<Entry: Codable> {
    let entries: [Entry]
    let updatedAt: Date
    let revision: Int
    let etag: String?
}

actor TuneAVAppDataSyncClient {
    typealias Request = @Sendable (
        _ path: String,
        _ method: String,
        _ body: Data?,
        _ headers: [String: String]
    ) async throws -> Data

    private nonisolated let appId: String
    private nonisolated let deviceId: String
    private nonisolated let platform: String
    private let request: Request
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var lastKnownRevisions: [String: Int] = [:]
    private var lastKnownEtags: [String: String] = [:]
    private var lastPulledLibrarySnapshot: TuneAVLibrarySnapshot?

    init(
        appId: String = "tuneav",
        deviceId: String,
        platform: String = "unknown",
        request: @escaping Request,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.appId = appId
        self.deviceId = deviceId
        self.platform = platform
        self.request = request
        self.decoder = decoder
        self.encoder = encoder
    }

    func pullLibrary() async throws -> TuneAVLibraryDocument {
        let favorites = try await pullResource(.favorites, entryType: FavoriteStationRecord.self)
        let savedDiscoveries = try await pullLossyResource(.savedDiscoveries, entryType: DiscoveredTrackRecord.self)

        let snapshot = TuneAVLibrarySnapshot(
            favorites: favorites.entries,
            savedDiscoveries: savedDiscoveries.entries
        )
        lastPulledLibrarySnapshot = snapshot
        let updatedAt = [
            favorites.updatedAt,
            savedDiscoveries.updatedAt
        ].max() ?? .distantPast

        return TuneAVLibraryDocument(
            snapshot: snapshot.hasMeaningfulContent ? snapshot : nil,
            updatedAt: updatedAt,
            revision: [
                favorites.revision,
                savedDiscoveries.revision
            ].max() ?? 0,
            etag: nil,
            sourceUpdatedAtByResource: [
                TuneAVAppDataResource.favorites.rawValue: favorites.updatedAt,
                TuneAVAppDataResource.savedDiscoveries.rawValue: savedDiscoveries.updatedAt
            ]
        )
    }

    func pushLibrary(_ inputSnapshot: TuneAVLibrarySnapshot) async throws {
        let snapshot = TuneAVLibrarySnapshotMerger.canonicalized(inputSnapshot)
        guard let baseline = lastPulledLibrarySnapshot else {
            let favorites = try await pushResource(.favorites, entries: snapshot.favorites)
            let savedDiscoveries = try await pushResource(.savedDiscoveries, entries: snapshot.savedDiscoveries)
            lastPulledLibrarySnapshot = TuneAVLibrarySnapshotMerger.canonicalized(
                TuneAVLibrarySnapshot(
                    favorites: favorites,
                    savedDiscoveries: savedDiscoveries
                )
            )
            return
        }

        let canonicalBaseline = TuneAVLibrarySnapshotMerger.canonicalized(baseline)
        var favorites = canonicalBaseline.favorites
        var savedDiscoveries = canonicalBaseline.savedDiscoveries
        if snapshot.favorites != canonicalBaseline.favorites {
            favorites = try await pushResource(.favorites, entries: snapshot.favorites)
        }
        if snapshot.savedDiscoveries != canonicalBaseline.savedDiscoveries {
            savedDiscoveries = try await pushResource(.savedDiscoveries, entries: snapshot.savedDiscoveries)
        }
        lastPulledLibrarySnapshot = TuneAVLibrarySnapshotMerger.canonicalized(
            TuneAVLibrarySnapshot(
                favorites: favorites,
                savedDiscoveries: savedDiscoveries
            )
        )
    }

    func overwriteLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        for resource in TuneAVAppDataResource.syncResources {
            forgetSyncVersion(for: resource)
        }
        lastPulledLibrarySnapshot = nil

        try await pushLibrary(snapshot)
    }

    func upsertFavorite(_ record: FavoriteStationRecord, idempotencyKey: String? = nil) async throws {
        try await putLibraryOperation(.favorites, action: "upsert", entry: record, idempotencyKey: idempotencyKey)
    }

    func deleteFavorite(_ record: FavoriteStationRecord, idempotencyKey: String? = nil) async throws {
        try await putLibraryOperation(.favorites, action: "delete", entry: record, idempotencyKey: idempotencyKey)
    }

    func upsertSavedDiscovery(_ record: DiscoveredTrackRecord, idempotencyKey: String? = nil) async throws {
        try await putLibraryOperation(.savedDiscoveries, action: "upsert", entry: record, idempotencyKey: idempotencyKey)
    }

    func deleteSavedDiscovery(_ record: DiscoveredTrackRecord, idempotencyKey: String? = nil) async throws {
        try await putLibraryOperation(.savedDiscoveries, action: "delete", entry: record, idempotencyKey: idempotencyKey)
    }

    private func pullResource<Entry: Codable>(
        _ resource: TuneAVAppDataResource,
        entryType: Entry.Type
    ) async throws -> TuneAVAppDataResourceDocument<Entry> {
        let data = try await request(dataPath(for: resource), "GET", nil, defaultHeaders())
        let payload = try decoder.decode(TuneAVAppDataResponsePayload<Entry>.self, from: data)
        rememberSyncVersion(for: resource, revision: payload.revision, etag: payload.etag)

        return TuneAVAppDataResourceDocument(
            entries: payload.data.entries,
            updatedAt: TuneAVDateCoding.date(from: payload.updatedAt),
            revision: payload.revision ?? 0,
            etag: payload.etag
        )
    }

    private func pullLossyResource<Entry: Codable>(
        _ resource: TuneAVAppDataResource,
        entryType: Entry.Type
    ) async throws -> TuneAVAppDataResourceDocument<Entry> {
        let data = try await request(dataPath(for: resource), "GET", nil, defaultHeaders())
        let payload = try decoder.decode(TuneAVLossyAppDataResponsePayload<Entry>.self, from: data)
        rememberSyncVersion(for: resource, revision: payload.revision, etag: payload.etag)

        return TuneAVAppDataResourceDocument(
            entries: payload.data.entries,
            updatedAt: TuneAVDateCoding.date(from: payload.updatedAt),
            revision: payload.revision ?? 0,
            etag: payload.etag
        )
    }

    private func pushResource<Entry: Codable>(
        _ resource: TuneAVAppDataResource,
        entries: [Entry]
    ) async throws -> [Entry] {
        let envelope = TuneAVAppDataEnvelopePayload(
            appId: appId,
            resource: resource.rawValue,
            deviceId: deviceId,
            sentAt: TuneAVDateCoding.string(from: .now),
            entries: entries
        )

        var headers = defaultHeaders()
        if let lastKnownEtag = lastKnownEtags[resource.rawValue] {
            headers["If-Match"] = lastKnownEtag
        } else if let lastKnownRevision = lastKnownRevisions[resource.rawValue] {
            headers["If-Match"] = "\"revision-\(lastKnownRevision)\""
        }

        do {
            let data = try await request(
                dataPath(for: resource),
                "PUT",
                try encoder.encode(envelope),
                headers
            )
            let response = try decoder.decode(TuneAVAppDataResponsePayload<Entry>.self, from: data)
            rememberSyncVersion(for: resource, revision: response.revision, etag: response.etag)
            return response.data.entries
        } catch TuneAVAppDataClientError.requestFailed(let statusCode, _) where statusCode == 409 {
            throw TuneAVAppDataError.conflict
        }
    }

    private func putLibraryOperation<Entry: Codable>(
        _ resource: TuneAVAppDataResource,
        action: String,
        entry: Entry,
        idempotencyKey: String?
    ) async throws {
        var headers = defaultHeaders()
        if let idempotencyKey {
            headers["Idempotency-Key"] = idempotencyKey
        }
        do {
            let data = try await request(
                libraryOperationPath(for: resource, action: action),
                "PUT",
                try encoder.encode(entry),
                headers
            )
            let response = try decoder.decode(TuneAVAppDataResponsePayload<Entry>.self, from: data)
            rememberSyncVersion(for: resource, revision: response.revision, etag: response.etag)
            lastPulledLibrarySnapshot = nil
        } catch TuneAVAppDataClientError.requestFailed(let statusCode, _) where statusCode == 409 {
            throw TuneAVAppDataError.conflict
        }
    }

    private func rememberSyncVersion(for resource: TuneAVAppDataResource, revision: Int?, etag: String?) {
        lastKnownRevisions[resource.rawValue] = revision
        lastKnownEtags[resource.rawValue] = etag
    }

    private func forgetSyncVersion(for resource: TuneAVAppDataResource) {
        lastKnownRevisions[resource.rawValue] = nil
        lastKnownEtags[resource.rawValue] = nil
    }

    private func dataPath(for resource: TuneAVAppDataResource) -> String {
        "/v1/apps/\(appId)/data/\(resource.rawValue)"
    }

    private func libraryOperationPath(for resource: TuneAVAppDataResource, action: String) -> String {
        "/v1/apps/\(appId)/library/\(resource.rawValue)/\(action)"
    }

    private func defaultHeaders() -> [String: String] {
        [
            "x-appsav-device-id": deviceId,
            "x-appsav-platform": platform
        ]
    }
}
