import XCTest
@testable import TuneAV

/// The emergency catalog fallback and the alternate metadata stream lookup
/// resolve the live Radio Browser mirrors and move to the next one when one
/// fails. No test here reaches the network: every request goes through
/// `MirrorTestURLProtocol`.
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

    // MARK: - Alternate metadata stream lookup

    func testAlternateStreamLookupUsesTheResolvedMirrorWithTheSameRequest() async throws {
        var requests: [URLRequest] = []
        MirrorTestURLProtocol.requestHandler = { request in
            requests.append(request)
            let host = request.url?.host ?? ""
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne]))
            }
            return (Self.response(request, status: 200), Self.candidateBody(mirror: host))
        }

        let resolver = makeAlternateStreamResolver(mirrors: makeMirrors())
        let url = await resolver.resolveAlternateStreamURL(for: Self.metadataStation)

        XCTAssertEqual(url, Self.alternateStreamURL(mirror: Self.mirrorOne))
        XCTAssertEqual(requests.map { $0.url?.host ?? "" }, [Self.serversHost, Self.mirrorOne])

        let lookup = try XCTUnwrap(requests.last)
        let lookupURL = try XCTUnwrap(lookup.url)
        XCTAssertEqual(lookupURL.scheme, "https")
        XCTAssertEqual(lookupURL.path, "/json/stations/search")
        XCTAssertEqual(
            URLComponents(url: lookupURL, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
            "name=Example%20Radio&countrycode=ES&hidebroken=true&order=clickcount&reverse=true&limit=12",
            "Only the host changes; the query stays the one the lookup always sent"
        )
        XCTAssertEqual(lookup.value(forHTTPHeaderField: "User-Agent"), "TuneAV/0.1")
        XCTAssertEqual(lookup.timeoutInterval, 8)
    }

    func testAlternateStreamLookupTriesTheNextMirrorWhenTheFirstAnswersAServerError() async {
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
                return (Self.response(request, status: 200), Self.candidateBody(mirror: host))
            }
        }

        let resolver = makeAlternateStreamResolver(mirrors: makeMirrors())
        let url = await resolver.resolveAlternateStreamURL(for: Self.metadataStation)

        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne, Self.mirrorTwo])
        XCTAssertEqual(url, Self.alternateStreamURL(mirror: Self.mirrorTwo))
    }

    func testAlternateStreamLookupTriesTheNextMirrorWhenTheFirstCannotBeReached() async {
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
                return (Self.response(request, status: 200), Self.candidateBody(mirror: host))
            }
        }

        let resolver = makeAlternateStreamResolver(mirrors: makeMirrors())
        let url = await resolver.resolveAlternateStreamURL(for: Self.metadataStation)

        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne, Self.mirrorTwo])
        XCTAssertEqual(url, Self.alternateStreamURL(mirror: Self.mirrorTwo))
    }

    func testAlternateStreamLookupSurfacesTheLastErrorWhenEveryMirrorFails() async throws {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            }
            return (Self.response(request, status: host == Self.staticHost ? 502 : 503), Data())
        }

        let clock = MirrorTestClock(Date(timeIntervalSince1970: 1_000))
        let resolver = makeAlternateStreamResolver(mirrors: makeMirrors(refreshInterval: 60, now: { clock.value }))
        let station = Self.metadataStation

        do {
            _ = try await resolver.loadAlternateStreamURL(
                for: station,
                components: TuneAVAlternateMetadataStreamResolver.searchComponents(for: station)
            )
            XCTFail("The last mirror error should surface")
        } catch TuneAVStationService.ServiceError.requestFailed(let statusCode) {
            XCTAssertEqual(statusCode, 502, "The error of the last mirror tried, the static one, surfaces")
        }
        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne, Self.mirrorTwo, Self.staticHost])

        requestedHosts = []
        clock.advance(by: 61)
        let url = await resolver.resolveAlternateStreamURL(for: station)
        XCTAssertNil(url, "Through the cache a lookup that failed on every mirror resolves to no alternate stream")
        XCTAssertEqual(
            requestedHosts,
            [Self.serversHost, Self.mirrorOne, Self.mirrorTwo, Self.staticHost],
            "After a total failure the mirror list is resolved again once the refresh interval passes"
        )
    }

    func testAlternateStreamLookupDoesNotTryAnotherMirrorAfterAClientError() async {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            }
            return (Self.response(request, status: 404), Data())
        }

        let resolver = makeAlternateStreamResolver(mirrors: makeMirrors())
        let url = await resolver.resolveAlternateStreamURL(for: Self.metadataStation)

        XCTAssertNil(url, "A client error resolves to no alternate stream, as before")
        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorOne])
    }

    func testTheSameAlternateStreamLookupIsServedFromTheCacheWhicheverMirrorWouldBeChosen() async {
        var requestedHosts: [String] = []
        MirrorTestURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            requestedHosts.append(host)
            if host == Self.serversHost {
                return (Self.response(request, status: 200), Self.serversBody([Self.mirrorOne, Self.mirrorTwo]))
            }
            return (Self.response(request, status: 200), Self.candidateBody(mirror: host))
        }

        let orderCalls = MirrorTestCounter()
        let mirrors = makeMirrors(order: { hosts in
            orderCalls.increment() % 2 == 1 ? Array(hosts.reversed()) : hosts
        })
        let resolver = makeAlternateStreamResolver(mirrors: mirrors)

        let first = await resolver.resolveAlternateStreamURL(for: Self.metadataStation)
        let second = await resolver.resolveAlternateStreamURL(for: Self.metadataStation)

        XCTAssertEqual(first, Self.alternateStreamURL(mirror: Self.mirrorTwo))
        XCTAssertEqual(second, Self.alternateStreamURL(mirror: Self.mirrorTwo))
        XCTAssertEqual(requestedHosts, [Self.serversHost, Self.mirrorTwo], "The cache key does not depend on the mirror")
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

    private func makeAlternateStreamResolver(mirrors: TuneAVRadioBrowserMirrors) -> TuneAVAlternateMetadataStreamResolver {
        TuneAVAlternateMetadataStreamResolver(
            session: makeSession(),
            radioBrowserMirrors: mirrors,
            cache: TuneAVAlternateMetadataStreamCache()
        )
    }

    /// An HLS station whose own stream carries no ICY metadata, the case the
    /// alternate stream lookup exists for.
    private static var metadataStation: Station {
        Station(
            id: "station-hls",
            name: "Example Radio",
            country: "Spain",
            countryCode: "ES",
            language: "Spanish",
            tags: "pop",
            streamURL: "https://example-radio.test/live/chunks.m3u8",
            homepageURL: "https://www.example-radio.test/",
            isHLS: true
        )
    }

    /// The direct stream a mirror answers for `metadataStation`; the query names
    /// the mirror so a test can tell which one answered.
    private static func alternateStreamURL(mirror: String) -> URL {
        URL(string: "http://stream.example-radio.test/live.mp3?mirror=\(mirror)")!
    }

    private static func candidateBody(mirror: String) -> Data {
        let streamURL = alternateStreamURL(mirror: mirror).absoluteString
        return Data(#"""
        [
          {
            "name": "Example Radio",
            "url": "\#(streamURL)",
            "url_resolved": "\#(streamURL)",
            "homepage": "https://example-radio.test/",
            "codec": "MP3",
            "hls": 0,
            "lastcheckok": 1
          }
        ]
        """#.utf8)
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
