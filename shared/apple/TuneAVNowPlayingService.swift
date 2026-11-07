import Foundation
import os

typealias NowPlayingTrack = TuneAVNowPlayingTrack

actor NowPlayingService {
    private let session: URLSession
    private var inFlightTracks: [String: Task<NowPlayingTrack?, Never>] = [:]

    init(session: URLSession = TuneAVURLSessions.catalog) {
        self.session = session
    }

    nonisolated func supports(_ station: Station) -> Bool {
        provider(for: station) != nil
    }

    func fetchTrack(for station: Station) async -> NowPlayingTrack? {
        guard let provider = provider(for: station) else { return nil }
        let key = "\(station.id)|\(station.streamURL)|\(provider.cacheKey)"
        if let inFlightTrack = inFlightTracks[key] {
            return await inFlightTrack.value
        }

        let task = Task { [session] in
            do {
                return try await provider.fetchTrack(for: station, using: session)
            } catch {
                return nil
            }
        }
        inFlightTracks[key] = task
        let track = await task.value
        inFlightTracks[key] = nil
        return track
    }

    private nonisolated func provider(for station: Station) -> Provider? {
        if TuneAVEighties80sNowPlaying.supports(station) {
            return .eighties80s
        }

        if URL(string: station.streamURL) != nil {
            return .icyStream
        }

        return nil
    }
}

private extension NowPlayingService {
    enum Provider {
        case eighties80s
        case icyStream

        var cacheKey: String {
            switch self {
            case .eighties80s:
                return "eighties80s"
            case .icyStream:
                return "icyStream"
            }
        }

        func fetchTrack(for station: Station, using session: URLSession) async throws -> NowPlayingTrack? {
            switch self {
            case .eighties80s:
                return try await fetch80s80sTrack(for: station, using: session)
            case .icyStream:
                return try await fetchICYTrack(for: station, using: session)
            }
        }

        private func fetchICYTrack(for station: Station, using session: URLSession) async throws -> NowPlayingTrack? {
            guard let streamURL = URL(string: station.streamURL) else { return nil }

            if let track = try await fetchICYTrack(from: streamURL, using: session) {
                return track
            }

            guard let alternateStreamURL = await TuneAVAlternateMetadataStreamResolver(session: session)
                .resolveAlternateStreamURL(for: station)
            else {
                return nil
            }

            return try await fetchICYTrack(from: alternateStreamURL, using: session)
        }

        private func fetchICYTrack(from streamURL: URL, using session: URLSession) async throws -> NowPlayingTrack? {
            var request = URLRequest(url: streamURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 5
            request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
            request.setValue("TuneAV/0.1", forHTTPHeaderField: "User-Agent")
            return try await parseICYTrack(from: request, using: session)
        }

        private func parseICYTrack(from request: URLRequest, using session: URLSession) async throws -> NowPlayingTrack? {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<400 ~= httpResponse.statusCode else {
                return nil
            }

            guard let metadataInterval = TuneAVNowPlayingMetadata.metadataInterval(from: httpResponse), metadataInterval > 0 else {
                return nil
            }

            var bytesUntilMetadata = metadataInterval
            var totalBytesRead = 0
            let maxBytesToRead = min(metadataInterval + 4096, 262_144)
            var iterator = bytes.makeAsyncIterator()

            while let byte = try await iterator.next() {
                if Task.isCancelled { return nil }

                totalBytesRead += 1
                if totalBytesRead > maxBytesToRead {
                    return nil
                }

                if bytesUntilMetadata > 0 {
                    bytesUntilMetadata -= 1
                    continue
                }

                let metadataLength = Int(byte) * 16
                guard metadataLength > 0 else {
                    bytesUntilMetadata = metadataInterval
                    continue
                }

                var metadataBytes: [UInt8] = []
                metadataBytes.reserveCapacity(metadataLength)

                for _ in 0..<metadataLength {
                    guard let metadataByte = try await iterator.next() else { return nil }
                    metadataBytes.append(metadataByte)
                }

                if let track = TuneAVNowPlayingMetadata.parseICYMetadata(metadataBytes) {
                    return track
                }

                bytesUntilMetadata = metadataInterval
            }

            return nil
        }

        private func fetch80s80sTrack(for station: Station, using session: URLSession) async throws -> NowPlayingTrack? {
            let requestURL = TuneAVEighties80sNowPlaying.resolvedURL(for: station) ?? TuneAVEighties80sNowPlaying.fallbackURL
            var request = URLRequest(url: requestURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            request.setValue("TuneAV/0.1", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return nil
            }

            let html = String(decoding: data, as: UTF8.self)
            return TuneAVEighties80sNowPlaying.parseTrack(for: station, from: html)
        }
    }
}

/// Finds, on Radio Browser, a direct stream of the same station whose ICY
/// metadata can be read when the station's own stream carries none. The lookup
/// goes to the live Radio Browser mirrors (`TuneAVRadioBrowserMirrors`) with the
/// failover rules of the station search, so one mirror being down does not lose
/// the alternate stream.
struct TuneAVAlternateMetadataStreamResolver {
    private let session: URLSession
    private let radioBrowserMirrors: TuneAVRadioBrowserMirrors
    private let cache: TuneAVAlternateMetadataStreamCache

    private static let logger = Logger(subsystem: "com.avalsys.tuneav", category: "nowPlaying")

    init(
        session: URLSession = TuneAVURLSessions.catalog,
        radioBrowserMirrors: TuneAVRadioBrowserMirrors = .shared,
        cache: TuneAVAlternateMetadataStreamCache = .shared
    ) {
        self.session = session
        self.radioBrowserMirrors = radioBrowserMirrors
        self.cache = cache
    }

    func resolveAlternateStreamURL(for station: Station) async -> URL? {
        let components = Self.searchComponents(for: station)
        let key = Self.cacheKey(for: station, components: components)

        return await cache.url(for: key) {
            try await loadAlternateStreamURL(for: station, components: components)
        }
    }

    /// Runs the lookup against the live mirrors in turn, as the station search
    /// does: a mirror that cannot be reached, times out or answers 5xx is skipped
    /// for the next one, up to `TuneAVStationService.maxRadioBrowserMirrorAttempts`;
    /// any other error surfaces at once. When every mirror fails, the mirror list
    /// is marked for refresh and the last error surfaces.
    func loadAlternateStreamURL(for station: Station, components: URLComponents) async throws -> URL? {
        let hosts = await radioBrowserMirrors.hosts()
        var lastError: Error = URLError(.badURL)
        var attempts = 0

        for host in hosts where attempts < TuneAVStationService.maxRadioBrowserMirrorAttempts {
            var mirrorComponents = components
            mirrorComponents.host = host
            guard let url = mirrorComponents.url else { continue }
            attempts += 1

            do {
                return try await fetchAlternateStreamURL(for: station, url: url)
            } catch where TuneAVStationService.shouldTryNextRadioBrowserMirror(after: error) {
                Self.logger.notice("Radio Browser mirror \(host, privacy: .public) failed the alternate stream lookup; trying the next one")
                lastError = error
            }
        }

        await radioBrowserMirrors.recordTotalFailure()
        throw lastError
    }

    static func bestAlternateStreamURL(for station: Station, candidates: [RadioBrowserMetadataCandidate]) -> URL? {
        candidates
            .compactMap { candidate -> ScoredMetadataCandidate? in
                guard let url = candidate.streamURL else { return nil }
                guard !url.absoluteString.normalizedMetadataIdentityValue.isEmpty else { return nil }
                guard url.absoluteString.normalizedMetadataIdentityValue != station.streamURL.normalizedMetadataIdentityValue else { return nil }
                guard !candidate.isLikelyPlaylistStream else { return nil }
                guard candidate.lastcheckok ?? 1 == 1 else { return nil }

                let score = candidate.matchScore(for: station)
                guard score > 0 else { return nil }
                return ScoredMetadataCandidate(url: url, score: score)
            }
            .max { lhs, rhs in lhs.score < rhs.score }
            .map(\.url)
    }

    /// The Radio Browser search for the station, without a host: the mirror is
    /// set per attempt.
    static func searchComponents(for station: Station) -> URLComponents {
        var components = URLComponents()
        components.scheme = "https"
        components.path = TuneAVStationService.radioBrowserSearchPath
        components.queryItems = [
            URLQueryItem(name: "name", value: station.name),
            station.countryCode.map { URLQueryItem(name: "countrycode", value: $0) },
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: "12")
        ].compactMap { $0 }
        return components
    }

    private func fetchAlternateStreamURL(for station: Station, url: URL) async throws -> URL? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("TuneAV/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw TuneAVStationService.ServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let candidates = try JSONDecoder().decode([RadioBrowserMetadataCandidate].self, from: data)
        return Self.bestAlternateStreamURL(for: station, candidates: candidates)
    }

    /// The same lookup is served from the cache whichever mirror answered it.
    private static func cacheKey(for station: Station, components: URLComponents) -> String {
        [
            station.id,
            station.name.normalizedMetadataIdentityValue,
            station.countryCode ?? "",
            station.streamURL.normalizedMetadataIdentityValue,
            "\(components.path)?\(components.percentEncodedQuery ?? "")"
        ].joined(separator: "\u{1F}")
    }
}

actor TuneAVAlternateMetadataStreamCache {
    static let shared = TuneAVAlternateMetadataStreamCache()

    private struct Entry {
        let url: URL?
        let cachedAt: Date
    }

    private static let positiveMaxAge: TimeInterval = 60 * 60 * 12
    private static let negativeMaxAge: TimeInterval = 60 * 20
    private static let maxEntries = 120

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]

    func url(for key: String, load: @escaping @Sendable () async throws -> URL?) async -> URL? {
        if let entry = entries[key], Self.isFresh(entry, now: .now) {
            return entry.url
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task {
            do {
                return try await load()
            } catch {
                return nil
            }
        }
        inFlight[key] = task

        let url = await task.value
        inFlight[key] = nil
        save(Entry(url: url, cachedAt: .now), for: key)
        return url
    }

    private func save(_ entry: Entry, for key: String, now: Date = .now) {
        removeExpiredEntries(now: now)
        if entries.count >= Self.maxEntries,
           let oldestKey = entries.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key {
            entries[oldestKey] = nil
        }
        entries[key] = entry
    }

    private func removeExpiredEntries(now: Date) {
        for (key, entry) in entries where !Self.isFresh(entry, now: now) {
            entries[key] = nil
        }
    }

    func clearMemoryCache() {
        entries.removeAll(keepingCapacity: false)
    }

    private static func isFresh(_ entry: Entry, now: Date) -> Bool {
        let maxAge = entry.url == nil ? negativeMaxAge : positiveMaxAge
        return now.timeIntervalSince(entry.cachedAt) < maxAge
    }
}

private struct ScoredMetadataCandidate {
    let url: URL
    let score: Int
}

struct RadioBrowserMetadataCandidate: Decodable {
    let name: String
    let url: String?
    let url_resolved: String?
    let homepage: String?
    let codec: String?
    let hls: Int?
    let lastcheckok: Int?

    var streamURL: URL? {
        let rawValue = url_resolved?.isEmpty == false ? url_resolved : url
        guard let rawValue else { return nil }
        return URL(string: rawValue)
    }

    var isLikelyPlaylistStream: Bool {
        if hls == 1 { return true }
        guard let streamURL else { return false }
        return streamURL.isLikelyPlaylistStream
    }

    func matchScore(for station: Station) -> Int {
        var score = 0
        var matchedIdentity = false

        if name.normalizedMetadataIdentityValue == station.name.normalizedMetadataIdentityValue {
            score += 80
            matchedIdentity = true
        } else if name.normalizedMetadataIdentityValue.contains(station.name.normalizedMetadataIdentityValue) ||
                    station.name.normalizedMetadataIdentityValue.contains(name.normalizedMetadataIdentityValue) {
            score += 40
            matchedIdentity = true
        }

        if let homepageHost = URL(string: homepage ?? "")?.host?.normalizedMetadataIdentityValue,
           let stationHomepageHost = station.resolvedHomepageURL?.host?.normalizedMetadataIdentityValue,
           homepageHost == stationHomepageHost {
            score += 60
            matchedIdentity = true
        }

        let normalizedCodec = codec?.normalizedMetadataIdentityValue ?? ""
        if matchedIdentity && ["mp3", "mpeg", "aac", "aacp"].contains(normalizedCodec) {
            score += 20
        }

        return score
    }
}

private extension URL {
    var isLikelyPlaylistStream: Bool {
        let path = path.lowercased()
        return path.hasSuffix(".m3u8") || path.hasSuffix(".m3u") || path.hasSuffix(".pls")
    }
}

private extension String {
    var normalizedMetadataIdentityValue: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
