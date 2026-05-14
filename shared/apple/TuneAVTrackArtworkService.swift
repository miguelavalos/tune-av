import Foundation

struct TuneAVTrackArtwork: Equatable, Sendable {
    let albumTitle: String?
    let artworkURL: URL?
    let artistURL: URL?
    let source: String
}

actor TuneAVTrackArtworkService {
    private struct CachedLookup {
        let artwork: TuneAVTrackArtwork?
        let cachedAt: Date
    }

    private static let positiveCacheMaxAge: TimeInterval = 60 * 60 * 12
    private static let negativeCacheMaxAge: TimeInterval = 60 * 20

    private let session: URLSession
    private let userAgent: String
    private var cache: [String: CachedLookup] = [:]
    private var inFlightLookups: [String: Task<TuneAVTrackArtwork?, Never>] = [:]

    init(session: URLSession = TuneAVURLSessions.artwork, userAgent: String = "TuneAV/0.1") {
        self.session = session
        self.userAgent = userAgent
    }

    func resolveArtwork(artist: String, title: String) async -> TuneAVTrackArtwork? {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedArtist.isEmpty, !trimmedTitle.isEmpty else { return nil }

        let cacheKey = "\(normalize(trimmedArtist))|\(normalize(trimmedTitle))"
        if let cached = cache[cacheKey], Self.isFresh(cached, now: Date()) {
            return cached.artwork
        }
        if let inFlightLookup = inFlightLookups[cacheKey] {
            return await inFlightLookup.value
        }

        let task = Task { [session, userAgent] in
            await Self.fetchArtwork(
                artist: trimmedArtist,
                title: trimmedTitle,
                session: session,
                userAgent: userAgent
            )
        }
        inFlightLookups[cacheKey] = task

        let artwork = await task.value
        inFlightLookups[cacheKey] = nil
        cache[cacheKey] = CachedLookup(artwork: artwork, cachedAt: Date())
        return artwork
    }

    private static func isFresh(_ cached: CachedLookup, now: Date) -> Bool {
        let maxAge = cached.artwork == nil ? negativeCacheMaxAge : positiveCacheMaxAge
        return now.timeIntervalSince(cached.cachedAt) < maxAge
    }

    private static func fetchArtwork(
        artist trimmedArtist: String,
        title trimmedTitle: String,
        session: URLSession,
        userAgent: String
    ) async -> TuneAVTrackArtwork? {
        func normalize(_ value: String) -> String {
            value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        func matchScore(_ item: TuneAVITunesTrack) -> Int {
            let normalizedArtist = normalize(trimmedArtist)
            let normalizedTitle = normalize(trimmedTitle)
            let itemArtist = normalize(item.artistName)
            let itemTitle = normalize(item.trackName)

            var score = 0

            if itemArtist == normalizedArtist {
                score += 80
            } else if itemArtist.contains(normalizedArtist) || normalizedArtist.contains(itemArtist) {
                score += 50
            }

            if itemTitle == normalizedTitle {
                score += 80
            } else if itemTitle.contains(normalizedTitle) || normalizedTitle.contains(itemTitle) {
                score += 50
            }

            return score
        }

        func upgradedArtworkURL(from rawValue: String?) -> URL? {
            guard let rawValue else { return nil }
            let upgraded = rawValue.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            return URL(string: upgraded)
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(trimmedArtist) \(trimmedTitle)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "8")
        ]

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
                return nil
            }

            let payload = try JSONDecoder().decode(TuneAVITunesSearchResponse.self, from: data)
            guard let bestMatch = payload.results.max(by: { lhs, rhs in
                matchScore(lhs) < matchScore(rhs)
            }) else {
                return nil
            }

            guard matchScore(bestMatch) >= 100 else {
                return nil
            }

            return TuneAVTrackArtwork(
                albumTitle: bestMatch.collectionName,
                artworkURL: upgradedArtworkURL(from: bestMatch.artworkUrl100),
                artistURL: bestMatch.artistViewUrl.flatMap(URL.init(string:)),
                source: "itunes"
            )
        } catch {
            return nil
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct TuneAVITunesSearchResponse: Decodable {
    let results: [TuneAVITunesTrack]
}

private struct TuneAVITunesTrack: Decodable {
    let artistName: String
    let trackName: String
    let collectionName: String?
    let artworkUrl100: String?
    let artistViewUrl: String?
}
