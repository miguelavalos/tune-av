import Foundation

enum TuneAVAppDataClientError: Error, Equatable {
    case missingToken
    case missingBaseURL
    case requestFailed(statusCode: Int)
}

typealias MacAppDataClientError = TuneAVAppDataClientError

enum TuneAVAppDataResource: String, CaseIterable {
    case favorites
    case recents
    case discoveries
    case settings

    static let syncResources: [TuneAVAppDataResource] = [
        .favorites,
        .recents,
        .discoveries,
        .settings
    ]
}

struct TuneAVAppDataResponsePayload<Entry: Codable>: Decodable {
    let data: TuneAVAppDataEnvelopePayload<Entry>
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

struct TuneAVAppDataResourceDocument<Entry: Codable> {
    let entries: [Entry]
    let updatedAt: Date
    let revision: Int
    let etag: String?
}

@MainActor
final class TuneAVAppDataSyncClient {
    typealias Request = (
        _ path: String,
        _ method: String,
        _ body: Data?,
        _ headers: [String: String]
    ) async throws -> Data

    private let appId: String
    private let deviceId: String
    private let isConfiguredHandler: () -> Bool
    private let request: Request
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var lastKnownRevisions: [String: Int] = [:]
    private var lastKnownEtags: [String: String] = [:]

    init(
        appId: String = "tuneav",
        deviceId: String,
        isConfigured: @escaping () -> Bool,
        request: @escaping Request,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.appId = appId
        self.deviceId = deviceId
        self.isConfiguredHandler = isConfigured
        self.request = request
        self.decoder = decoder
        self.encoder = encoder
    }

    func isConfigured() -> Bool {
        isConfiguredHandler()
    }

    func pullLibrary() async throws -> TuneAVLibraryDocument {
        let favorites = try await pullResource(.favorites, entryType: FavoriteStationRecord.self)
        let recents = try await pullResource(.recents, entryType: RecentStationRecord.self)
        let discoveries = try await pullResource(.discoveries, entryType: DiscoveredTrackRecord.self)
        let settings = try await pullResource(.settings, entryType: AppSettingsRecord.self)

        let snapshot = TuneAVLibrarySnapshot(
            favorites: favorites.entries,
            recents: recents.entries,
            discoveries: discoveries.entries,
            settings: settings.entries.first ?? .empty
        )
        let updatedAt = [
            favorites.updatedAt,
            recents.updatedAt,
            discoveries.updatedAt,
            settings.updatedAt
        ].max() ?? .distantPast

        return TuneAVLibraryDocument(
            snapshot: snapshot.hasMeaningfulContent ? snapshot : nil,
            updatedAt: updatedAt,
            revision: [
                favorites.revision,
                recents.revision,
                discoveries.revision,
                settings.revision
            ].max() ?? 0,
            etag: nil
        )
    }

    func pushLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        try await pushResource(.favorites, entries: snapshot.favorites)
        try await pushResource(.recents, entries: snapshot.recents)
        try await pushResource(.discoveries, entries: snapshot.discoveries)
        try await pushResource(.settings, entries: [snapshot.settings])
    }

    func overwriteLibrary(_ snapshot: TuneAVLibrarySnapshot) async throws {
        for resource in TuneAVAppDataResource.syncResources {
            forgetSyncVersion(for: resource)
        }

        try await pushLibrary(snapshot)
    }

    private func pullResource<Entry: Codable>(
        _ resource: TuneAVAppDataResource,
        entryType: Entry.Type
    ) async throws -> TuneAVAppDataResourceDocument<Entry> {
        let data = try await request(dataPath(for: resource), "GET", nil, [:])
        let payload = try decoder.decode(TuneAVAppDataResponsePayload<Entry>.self, from: data)
        rememberSyncVersion(for: resource, revision: payload.revision, etag: payload.etag)

        return TuneAVAppDataResourceDocument(
            entries: payload.data.entries,
            updatedAt: TuneAVDateCoding.date(from: payload.updatedAt),
            revision: payload.revision ?? 0,
            etag: payload.etag
        )
    }

    private func pushResource<Entry: Codable>(_ resource: TuneAVAppDataResource, entries: [Entry]) async throws {
        try await pushResource(resource, entries: entries, allowsConflictRetry: true)
    }

    private func pushResource<Entry: Codable>(
        _ resource: TuneAVAppDataResource,
        entries: [Entry],
        allowsConflictRetry: Bool
    ) async throws {
        let envelope = TuneAVAppDataEnvelopePayload(
            appId: appId,
            resource: resource.rawValue,
            deviceId: deviceId,
            sentAt: TuneAVDateCoding.string(from: .now),
            entries: entries
        )

        var headers: [String: String] = [:]
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
            guard allowsConflictRetry else {
                throw TuneAVAppDataError.conflict
            }

            _ = try await pullResource(resource, entryType: Entry.self)
            try await pushResource(resource, entries: entries, allowsConflictRetry: false)
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
}
