import Foundation

enum TuneAVAppDataClientError: Error, Equatable {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)
}

typealias MacAppDataClientError = TuneAVAppDataClientError

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
            etag: nil
        )
    }

    func pushLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        try await pushResource(.favorites, entries: snapshot.favorites)
        try await pushResource(.savedDiscoveries, entries: snapshot.savedDiscoveries)
    }

    func overwriteLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        for resource in TuneAVAppDataResource.syncResources {
            forgetSyncVersion(for: resource)
        }

        try await pushLibrary(snapshot)
    }

    func upsertFavorite(_ record: FavoriteStationRecord) async throws {
        try await putLibraryOperation(.favorites, action: "upsert", entry: record)
    }

    func deleteFavorite(_ record: FavoriteStationRecord) async throws {
        try await putLibraryOperation(.favorites, action: "delete", entry: record)
    }

    func upsertSavedDiscovery(_ record: DiscoveredTrackRecord) async throws {
        try await putLibraryOperation(.savedDiscoveries, action: "upsert", entry: record)
    }

    func deleteSavedDiscovery(_ record: DiscoveredTrackRecord) async throws {
        try await putLibraryOperation(.savedDiscoveries, action: "delete", entry: record)
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
    ) async throws {
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
        } catch TuneAVAppDataClientError.requestFailed(let statusCode) where statusCode == 409 {
            throw TuneAVAppDataError.conflict
        }
    }

    private func putLibraryOperation<Entry: Codable>(
        _ resource: TuneAVAppDataResource,
        action: String,
        entry: Entry
    ) async throws {
        do {
            let data = try await request(
                libraryOperationPath(for: resource, action: action),
                "PUT",
                try encoder.encode(entry),
                defaultHeaders()
            )
            let response = try decoder.decode(TuneAVAppDataResponsePayload<Entry>.self, from: data)
            rememberSyncVersion(for: resource, revision: response.revision, etag: response.etag)
        } catch TuneAVAppDataClientError.requestFailed(let statusCode) where statusCode == 409 {
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
