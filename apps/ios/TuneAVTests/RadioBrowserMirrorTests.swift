import XCTest
@testable import TuneAV

/// The emergency catalog fallback resolves the live Radio Browser mirrors and
/// moves to the next one when one fails. No test here reaches the network:
/// every request goes through `MirrorTestURLProtocol`.
final class RadioBrowserMirrorTests: XCTestCase {
    private static let serversHost = "all.test"
    private static let staticHost = "static.test"
    private static let mirrorOne = "one.api.radio-browser.info"
    private static let mirrorTwo = "two.api.radio-browser.info"
    private static let mirrorThree = "three.api.radio-browser.info"

    override func tearDown() {
        MirrorTestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSearchTriesTheNextMirrorWhenTheFirstAnswersAServerError() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            switch host {
            case Self.serversHost:
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            case Self.mirrorOne:
                return (Self.response(request, status: 503), Data())
            default:
                return (Self.response(request, status: 200), Self.stationBody(id: "from-\(host)"))
            }
        }

        let service = makeService(mirrors: makeMirrors())
        let stations = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))

        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne, Self.mirrorTwo])
        XCTAssertEqual(stations.map(\.id), ["from-\(Self.mirrorTwo)"])
    }

    func testSearchTriesTheNextMirrorWhenTheFirstCannotBeReached() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            switch host {
            case Self.serversHost:
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            case Self.mirrorOne:
                throw URLError(.timedOut)
            default:
                return (Self.response(request, status: 200), Self.stationBody(id: "from-\(host)"))
            }
        }

        let service = makeService(mirrors: makeMirrors())
        let stations = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))

        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne, Self.mirrorTwo])
        XCTAssertEqual(stations.map(\.id), ["from-\(Self.mirrorTwo)"])
    }

    func testSearchSurfacesTheLastErrorWhenEveryMirrorFails() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            }
            return (Self.response(request, status: host == Self.staticHost ? 502 : 503), Data())
        }

        let service = makeService(mirrors: makeMirrors())

        do {
            _ = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))
            XCTFail("The last mirror error should surface")
        } catch TuneAVStationService.ServiceError.requestFailed(let statusCode) {
            XCTAssertEqual(statusCode, 502, "The error of the last mirror tried, the static one, surfaces")
        }

        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne, Self.mirrorTwo, Self.staticHost])
    }

    func testSearchGivesUpAfterThreeMirrors() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo, Self.mirrorThree]))
            }
            return (Self.response(request, status: 503), Data())
        }

        let service = makeService(mirrors: makeMirrors())

        do {
            _ = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))
            XCTFail("The search should fail once the mirror attempts are used up")
        } catch TuneAVStationService.ServiceError.requestFailed(let statusCode) {
            XCTAssertEqual(statusCode, 503)
        }

        XCTAssertEqual(TuneAVStationService.maxRadioBrowserMirrorAttempts, 3)
        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne, Self.mirrorTwo, Self.mirrorThree])
    }

    func testSearchDoesNotTryAnotherMirrorAfterAClientError() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            }
            return (Self.response(request, status: 404), Data())
        }

        let service = makeService(mirrors: makeMirrors())

        do {
            _ = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))
            XCTFail("A client error should surface at once")
        } catch TuneAVStationService.ServiceError.requestFailed(let statusCode) {
            XCTAssertEqual(statusCode, 404)
        }

        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne])
    }

    func testSearchDoesNotTryAnotherMirrorWhileTheDeviceIsOffline() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            }
            throw URLError(.notConnectedToInternet)
        }

        let service = makeService(mirrors: makeMirrors())

        do {
            _ = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))
            XCTFail("An offline error should surface at once")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }

        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne])
    }

    func testMirrorsAreResolvedOnceAndReusedByLaterSearches() async throws {
        var requestedHosts: [String] = []
        var userAgents: Set<String> = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            userAgents.insert(request.value(forHTTPHeaderField: "User-Agent") ?? "")
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne]))
            }
            return (Self.response(request, status: 200), Self.stationBody(id: request.url?.query ?? ""))
        }

        let service = makeService(mirrors: makeMirrors())

        _ = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))
        _ = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "rock", limit: 5))
        _ = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "rock", limit: 5))

        XCTAssertEqual(
            requestedHosts,
            [Self.serversHost, Self.mirrorOne, Self.mirrorOne],
            "The mirror list is fetched once; the repeated search is served from the response cache"
        )
        XCTAssertEqual(userAgents, ["TuneAV/0.1"], "The mirror list and the searches send the same User-Agent")
    }

    func testTheSameSearchIsServedFromTheCacheWhicheverMirrorWouldBeChosen() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            }
            return (Self.response(request, status: 200), Self.stationBody(id: "from-\(host)"))
        }

        let orderCalls = MirrorTestCounter()
        let mirrors = makeMirrors(order: { hosts in
            orderCalls.increment() % 2 == 1 ? Array(hosts.reversed()) : hosts
        })
        let service = makeService(mirrors: mirrors)

        let first = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))
        let second = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))

        XCTAssertEqual(first.map(\.id), ["from-\(Self.mirrorTwo)"])
        XCTAssertEqual(second.map(\.id), ["from-\(Self.mirrorTwo)"])
        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorTwo], "The cache key does not depend on the mirror")
    }

    func testSearchUsesTheStaticMirrorWhileTheMirrorListIsUnavailable() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 500), Data())
            }
            return (Self.response(request, status: 200), Self.stationBody(id: "from-\(host)"))
        }

        let service = makeService(mirrors: makeMirrors())
        let stations = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5))

        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.staticHost])
        XCTAssertEqual(stations.map(\.id), ["from-\(Self.staticHost)"])
    }

    func testMirrorsAreResolvedAgainAfterATotalFailureOnceTheRefreshIntervalPasses() async throws {
        var requestedHosts: [String] = []
        var liveMirrors = [Self.mirrorOne]
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            switch host {
            case Self.serversHost:
                return (Self.response(request, status: 200), Self.serversBody(liveMirrors))
            case Self.mirrorTwo:
                return (Self.response(request, status: 200), Self.stationBody(id: "from-\(host)"))
            default:
                return (Self.response(request, status: 503), Data())
            }
        }

        let clock = MirrorTestClock(Date(timeIntervalSince1970: 1_000))
        let mirrors = makeMirrors(refreshInterval: 60, now: { clock.value })
        let service = makeService(mirrors: mirrors)

        await XCTAssertThrowsErrorAsync(try await service.searchStations(filters: TuneAVStationSearchFilters(query: "jazz", limit: 5)))
        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne, Self.staticHost])

        requestedHosts = []
        clock.advance(by: 30)
        await XCTAssertThrowsErrorAsync(try await service.searchStations(filters: TuneAVStationSearchFilters(query: "rock", limit: 5)))
        XCTAssertEqual(
            requestedHosts,
            [Self.mirrorOne, Self.staticHost],
            "Within the refresh interval the last known list is reused without a new lookup"
        )

        requestedHosts = []
        liveMirrors = [Self.mirrorTwo]
        clock.advance(by: 31)
        let stations = try await service.searchStations(filters: TuneAVStationSearchFilters(query: "pop", limit: 5))
        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorTwo], "After the interval the list is resolved again")
        XCTAssertEqual(stations.map(\.id), ["from-\(Self.mirrorTwo)"])
    }

    func testMirrorHostsKeepOnlyPlainRadioBrowserHostnames() {
        let hosts = TuneAVRadioBrowserMirrors.mirrorHosts(fromServerNames: [
            "de1.api.radio-browser.info",
            " FR1.api.radio-browser.info ",
            "de1.api.radio-browser.info",
            "",
            "evil.example.com",
            "api.radio-browser.info",
            ".api.radio-browser.info",
            "bad host.api.radio-browser.info",
            "a..b.api.radio-browser.info",
            "nl1.api.radio-browser.info/json",
            "de2.api.radio-browser.info"
        ])

        XCTAssertEqual(hosts, ["de1.api.radio-browser.info", "fr1.api.radio-browser.info", "de2.api.radio-browser.info"])
    }

    func testMirrorFailureRulesFollowTheErrorKind() {
        typealias Service = TuneAVStationService
        XCTAssertTrue(Service.shouldTryNextRadioBrowserMirror(after: Service.ServiceError.requestFailed(statusCode: 500)))
        XCTAssertTrue(Service.shouldTryNextRadioBrowserMirror(after: Service.ServiceError.requestFailed(statusCode: 503)))
        XCTAssertFalse(Service.shouldTryNextRadioBrowserMirror(after: Service.ServiceError.requestFailed(statusCode: 404)))
        XCTAssertFalse(Service.shouldTryNextRadioBrowserMirror(after: Service.ServiceError.requestFailed(statusCode: 429)))
        XCTAssertTrue(Service.shouldTryNextRadioBrowserMirror(after: URLError(.timedOut)))
        XCTAssertTrue(Service.shouldTryNextRadioBrowserMirror(after: URLError(.cannotFindHost)))
        XCTAssertTrue(Service.shouldTryNextRadioBrowserMirror(after: URLError(.cannotConnectToHost)))
        XCTAssertTrue(Service.shouldTryNextRadioBrowserMirror(after: URLError(.secureConnectionFailed)))
        XCTAssertFalse(Service.shouldTryNextRadioBrowserMirror(after: URLError(.cancelled)))
        XCTAssertFalse(Service.shouldTryNextRadioBrowserMirror(after: URLError(.notConnectedToInternet)))
        XCTAssertFalse(Service.shouldTryNextRadioBrowserMirror(after: Service.ServiceError.invalidResponse("bad")))
    }

    // MARK: - Helpers

    private func makeService(mirrors: TuneAVRadioBrowserMirrors) -> TuneAVStationService {
        TuneAVStationService(
            session: makeSession(),
            avalsysBaseURL: nil,
            avalsysPopularBaseURL: nil,
            radioBrowserMirrors: mirrors,
            backendGate: TuneAVBackendHealthGate(),
            responseCache: TuneAVStationResponseCache()
        )
    }

    private func makeMirrors(
        refreshInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() },
        order: @escaping @Sendable ([String]) -> [String] = { $0 }
    ) -> TuneAVRadioBrowserMirrors {
        TuneAVRadioBrowserMirrors(
            session: makeSession(),
            serversURL: URL(string: "https://\(Self.serversHost)/json/servers")!,
            staticHosts: [Self.staticHost],
            refreshInterval: refreshInterval,
            now: now,
            order: order
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MirrorTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func serversBody(_ names: [String]) -> Data {
        let entries = names.enumerated().map { index, name in
            #"{"ip": "203.0.113.\#(index + 1)", "name": "\#(name)"}"#
        }
        return Data("[\(entries.joined(separator: ","))]".utf8)
    }

    private static func stationBody(id: String) -> Data {
        Data(#"""
        [
          {
            "stationuuid": "\#(id)",
            "name": "Mirror Radio",
            "country": "Spain",
            "countrycode": "ES",
            "language": "Spanish",
            "tags": "jazz",
            "url": "https://example.com/stream.mp3",
            "url_resolved": "https://example.com/stream.mp3",
            "lastcheckok": 1
          }
        ]
        """#.utf8)
    }

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected the search to throw", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}

private final class MirrorTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) {
        storedValue = value
    }

    var value: Date {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        storedValue = storedValue.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class MirrorTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private final class MirrorTestURLProtocol: URLProtocol {
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
