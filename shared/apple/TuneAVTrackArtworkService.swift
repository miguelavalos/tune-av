import Foundation

struct TuneAVTrackArtwork: Equatable, Sendable {
    let albumTitle: String?
    let artworkURL: URL?
    let source: String
}

actor TuneAVTrackArtworkService {
    private let session: URLSession
    private let userAgent: String

    init(session: URLSession = .shared, userAgent: String = "TuneAV/0.1") {
        self.session = session
        self.userAgent = userAgent
    }

    func resolveArtwork(artist: String, title: String) async -> TuneAVTrackArtwork? {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedArtist.isEmpty, !trimmedTitle.isEmpty else { return nil }

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
                matchScore(lhs, artist: trimmedArtist, title: trimmedTitle) <
                    matchScore(rhs, artist: trimmedArtist, title: trimmedTitle)
            }) else {
                return nil
            }

            guard matchScore(bestMatch, artist: trimmedArtist, title: trimmedTitle) >= 100 else {
                return nil
            }

            return TuneAVTrackArtwork(
                albumTitle: bestMatch.collectionName,
                artworkURL: upgradedArtworkURL(from: bestMatch.artworkUrl100),
                source: "itunes"
            )
        } catch {
            return nil
        }
    }

    private func matchScore(_ item: TuneAVITunesTrack, artist: String, title: String) -> Int {
        let normalizedArtist = normalize(artist)
        let normalizedTitle = normalize(title)
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

    private func upgradedArtworkURL(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let upgraded = rawValue.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: upgraded)
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
}
