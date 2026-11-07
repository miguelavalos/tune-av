import Foundation
import os

/// The live Radio Browser API mirrors, resolved the way Radio Browser documents.
///
/// Radio Browser is a volunteer-run directory whose mirrors come and go, and its
/// documentation asks clients not to pin one of them: the live mirrors form the
/// `all.api.radio-browser.info` pool, listed by
/// `https://all.api.radio-browser.info/json/servers` as
/// `[{"ip": "...", "name": "de1.api.radio-browser.info"}, ...]`, and a client
/// picks one at random and moves to the next one when it fails.
///
/// The resolved list is kept for the life of the process. When every mirror
/// fails a request, `recordTotalFailure()` marks it stale and the next `hosts()`
/// resolves again, at most once per `refreshInterval`; the last known list stays
/// in use in between. The static hosts are always tried last, so the fallback is
/// never worse than the fixed mirror it replaces.
actor TuneAVRadioBrowserMirrors {
    static let shared = TuneAVRadioBrowserMirrors()

    /// The Radio Browser endpoint that lists the live mirrors.
    static let defaultServersURL = URL(string: "https://all.api.radio-browser.info/json/servers")!
    /// Tried last, and alone while the live list cannot be resolved.
    static let defaultStaticHosts = ["de1.api.radio-browser.info"]
    /// Only names under the Radio Browser API domain are accepted from the list.
    static let hostSuffix = ".api.radio-browser.info"

    private static let logger = Logger(subsystem: "com.avalsys.tuneav", category: "stations")
    private static let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")

    private let session: URLSession
    private let serversURL: URL?
    private let staticHosts: [String]
    private let refreshInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let order: @Sendable ([String]) -> [String]

    private var resolvedHosts: [String] = []
    private var needsRefresh = true
    private var lastResolveAttemptAt: Date?
    private var inFlightResolution: Task<Void, Never>?

    /// - Parameters:
    ///   - serversURL: where the live list is fetched from; `nil` uses only
    ///     `staticHosts` (tests).
    ///   - staticHosts: appended after the live mirrors when not already listed.
    ///   - refreshInterval: the least time between two resolution attempts after
    ///     a failure.
    ///   - order: how the live mirrors are ordered for one request; random by
    ///     default, as Radio Browser asks.
    init(
        session: URLSession = TuneAVURLSessions.catalog,
        serversURL: URL? = TuneAVRadioBrowserMirrors.defaultServersURL,
        staticHosts: [String] = TuneAVRadioBrowserMirrors.defaultStaticHosts,
        refreshInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() },
        order: @escaping @Sendable ([String]) -> [String] = { $0.shuffled() }
    ) {
        self.session = session
        self.serversURL = serversURL
        self.staticHosts = staticHosts
        self.refreshInterval = refreshInterval
        self.now = now
        self.order = order
    }

    /// The hosts to try for one request, in order: the live mirrors in random
    /// order, then the static hosts that are not already among them.
    func hosts() async -> [String] {
        await refreshIfNeeded()
        var ordered = order(resolvedHosts)
        for host in staticHosts where !ordered.contains(host) {
            ordered.append(host)
        }
        return ordered
    }

    /// Every host failed one request: the next `hosts()` resolves the list again
    /// once `refreshInterval` has passed since the last attempt.
    func recordTotalFailure() {
        needsRefresh = true
    }

    private func refreshIfNeeded() async {
        guard needsRefresh, let serversURL else { return }
        if let inFlightResolution {
            await inFlightResolution.value
            return
        }
        if let lastResolveAttemptAt, now().timeIntervalSince(lastResolveAttemptAt) < refreshInterval {
            return
        }

        lastResolveAttemptAt = now()
        let resolution = Task { await self.resolve(from: serversURL) }
        inFlightResolution = resolution
        await resolution.value
        inFlightResolution = nil
    }

    private func resolve(from url: URL) async {
        guard let hosts = await fetchHosts(from: url) else {
            Self.logger.notice("Radio Browser mirror list unavailable; keeping \(self.resolvedHosts.count, privacy: .public) known mirrors and the static one")
            return
        }
        resolvedHosts = hosts
        needsRefresh = false
        Self.logger.info("Resolved \(hosts.count, privacy: .public) Radio Browser mirrors")
    }

    private func fetchHosts(from url: URL) async -> [String]? {
        var request = URLRequest(url: url)
        request.setValue("TuneAV/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 4

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return nil
            }
            let servers = try JSONDecoder().decode([RadioBrowserServerDTO].self, from: data)
            let hosts = Self.mirrorHosts(fromServerNames: servers.map { $0.name ?? "" })
            return hosts.isEmpty ? nil : hosts
        } catch {
            return nil
        }
    }

    /// The usable mirror hostnames in a `/json/servers` response: lower-cased,
    /// de-duplicated, under `hostSuffix`, and plain hostnames. The list is
    /// fetched over TLS from Radio Browser, but search queries only ever go to
    /// its own domain.
    static func mirrorHosts(fromServerNames names: [String]) -> [String] {
        var hosts: [String] = []
        for name in names {
            let host = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard host.hasSuffix(hostSuffix),
                  host.count > hostSuffix.count,
                  !host.hasPrefix("."),
                  !host.hasPrefix("-"),
                  !host.contains(".."),
                  host.unicodeScalars.allSatisfy(hostCharacters.contains),
                  !hosts.contains(host) else {
                continue
            }
            hosts.append(host)
        }
        return hosts
    }
}

private struct RadioBrowserServerDTO: Decodable {
    let name: String?
}
