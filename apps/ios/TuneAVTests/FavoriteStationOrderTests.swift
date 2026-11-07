import SwiftData
import XCTest
@testable import TuneAV

/// The order of saved radios the listener sets in Library: seeded from the save date for rows
/// that predate it, appended on save, compacted on unsave, kept through a Pro sync pull.
@MainActor
final class FavoriteStationOrderTests: XCTestCase {
    private let samples = Array(Station.samples.prefix(4))

    func testRowsSavedBeforeTheOrderExistedKeepNewestFirstAndGetPositions() throws {
        let container = PersistenceController(inMemory: true).container
        let seedContext = ModelContext(container)
        for (index, station) in samples.prefix(3).enumerated() {
            seedContext.insert(FavoriteStation(station: station, createdAt: Date(timeIntervalSince1970: 1_000 + Double(index))))
        }
        try seedContext.save()

        let store = LibraryStore(container: container)

        XCTAssertEqual(store.favorites.map(\.stationID), [samples[2].id, samples[1].id, samples[0].id])
        XCTAssertEqual(store.favorites.map(\.sortPosition), [0, 1, 2])

        let persisted = try ModelContext(container).fetch(FetchDescriptor<FavoriteStation>())
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: persisted.map { ($0.stationID, $0.sortPosition) }),
            [samples[2].id: 0, samples[1].id: 1, samples[0].id: 2]
        )
    }

    func testNewSavesAppendAtTheEnd() {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)

        store.toggleFavorite(for: samples[0])
        store.toggleFavorite(for: samples[1])
        store.toggleFavorite(for: samples[2])

        XCTAssertEqual(store.favorites.map(\.stationID), [samples[0].id, samples[1].id, samples[2].id])
        XCTAssertEqual(store.favorites.map(\.sortPosition), [0, 1, 2])
        XCTAssertEqual(store.favoriteStations().map(\.id), [samples[0].id, samples[1].id, samples[2].id])
    }

    func testMoveFavoritesPersistsTheListenerOrderAcrossLaunches() {
        let container = PersistenceController(inMemory: true).container
        let store = LibraryStore(container: container)
        store.toggleFavorite(for: samples[0])
        store.toggleFavorite(for: samples[1])
        store.toggleFavorite(for: samples[2])

        // `List.onMove` reports moving the last row above the first one as (from: [2], to: 0).
        store.moveFavorites(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(store.favorites.map(\.stationID), [samples[2].id, samples[0].id, samples[1].id])
        XCTAssertEqual(store.favorites.map(\.sortPosition), [0, 1, 2])

        let relaunchedStore = LibraryStore(container: container)
        XCTAssertEqual(relaunchedStore.favorites.map(\.stationID), [samples[2].id, samples[0].id, samples[1].id])
    }

    func testMoveFavoritesIgnoresADragThatChangesNothing() {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        store.toggleFavorite(for: samples[0])
        store.toggleFavorite(for: samples[1])

        store.moveFavorites(fromOffsets: IndexSet(integer: 0), toOffset: 1)

        XCTAssertEqual(store.favorites.map(\.stationID), [samples[0].id, samples[1].id])
        XCTAssertEqual(store.favorites.map(\.sortPosition), [0, 1])
    }

    func testUnsaveCompactsPositionsAndKeepsTheRest() {
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        store.toggleFavorite(for: samples[0])
        store.toggleFavorite(for: samples[1])
        store.toggleFavorite(for: samples[2])
        store.moveFavorites(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        store.toggleFavorite(for: samples[0])

        XCTAssertEqual(store.favorites.map(\.stationID), [samples[2].id, samples[1].id])
        XCTAssertEqual(store.favorites.map(\.sortPosition), [0, 1])

        store.toggleFavorite(for: samples[0])
        XCTAssertEqual(store.favorites.map(\.stationID), [samples[2].id, samples[1].id, samples[0].id])
    }

    func testCloudPullKeepsTheLocalOrderAndAppendsStationsItBringsIn() async throws {
        let localStations = Array(samples.prefix(3))
        let remoteOnlyStation = samples[3]
        // Remote records newer than the local ones, so the pull wins for every station; listed
        // newest first, as the merger orders them.
        let remoteFavorites = [
            FavoriteStationRecord(station: remoteOnlyStation.appDataRecord, createdAt: "2030-01-04T00:00:00Z"),
            FavoriteStationRecord(station: localStations[2].appDataRecord, createdAt: "2030-01-03T00:00:00Z"),
            FavoriteStationRecord(station: localStations[1].appDataRecord, createdAt: "2030-01-02T00:00:00Z"),
            FavoriteStationRecord(station: localStations[0].appDataRecord, createdAt: "2030-01-01T00:00:00Z"),
        ]
        let favoriteEntries = try String(decoding: JSONEncoder().encode(remoteFavorites), as: UTF8.self)
        FavoriteOrderTestURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let entries = path == "/v1/apps/tuneav/data/favorites" ? favoriteEntries : "[]"
            let resource = path.split(separator: "/").last.map(String.init) ?? "unknown"
            let body = """
            {
              "data": {
                "appId": "tuneav",
                "resource": "\(resource)",
                "deviceId": "test-device",
                "sentAt": "2030-01-05T00:00:00Z",
                "entries": \(entries)
              },
              "updatedAt": "2030-01-05T00:00:00Z",
              "revision": 7,
              "etag": "\\"revision-7\\""
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json", "ETag": "\"revision-7\""]
                )!,
                Data(body.utf8)
            )
        }
        defer { FavoriteOrderTestURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavoriteOrderTestURLProtocol.self]
        let client = AVAccountAPIClient(
            getToken: { "test-token" },
            baseURLProvider: { URL(string: "https://api.test") },
            urlSession: URLSession(configuration: configuration)
        )
        let store = LibraryStore(container: PersistenceController(inMemory: true).container)
        for station in localStations {
            store.toggleFavorite(for: station)
        }
        store.moveFavorites(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.favorites.map(\.stationID), [localStations[2].id, localStations[0].id, localStations[1].id])

        store.setAppDataService(TuneAVAppDataService(apiClient: client))
        await store.refreshCloudLibraryIfNeeded(force: true)

        guard case .synced = store.cloudSyncStatus else {
            return XCTFail("The pull must end synced, got \(store.cloudSyncStatus)")
        }
        XCTAssertEqual(
            store.favorites.map(\.stationID),
            [localStations[2].id, localStations[0].id, localStations[1].id, remoteOnlyStation.id]
        )
        XCTAssertEqual(store.favorites.map(\.sortPosition), [0, 1, 2, 3])
    }

    func testOrderedHelperPutsPositionedRowsFirstThenNewestUnpositioned() {
        struct Row { let id: String; let position: Int?; let savedAt: Date }
        let rows = [
            Row(id: "d", position: nil, savedAt: Date(timeIntervalSince1970: 10)),
            Row(id: "b", position: 1, savedAt: Date(timeIntervalSince1970: 50)),
            Row(id: "c", position: nil, savedAt: Date(timeIntervalSince1970: 30)),
            Row(id: "a", position: 0, savedAt: Date(timeIntervalSince1970: 5)),
        ]

        let ordered = FavoriteStationOrder.ordered(rows, position: \.position, savedAt: \.savedAt, id: \.id)

        XCTAssertEqual(ordered.map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(FavoriteStationOrder.nextPosition(after: rows, position: \.position), 2)
        XCTAssertEqual(FavoriteStationOrder.nextPosition(after: [Row](), position: \.position), 0)
    }
}

private final class FavoriteOrderTestURLProtocol: URLProtocol {
    private static let requestHandlerLock = NSLock()

    nonisolated(unsafe)
    private static var storedRequestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    nonisolated(unsafe)
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            requestHandlerLock.lock()
            defer { requestHandlerLock.unlock() }
            return storedRequestHandler
        }
        set {
            requestHandlerLock.lock()
            storedRequestHandler = newValue
            requestHandlerLock.unlock()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
