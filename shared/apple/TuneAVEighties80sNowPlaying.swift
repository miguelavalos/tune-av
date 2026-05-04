import Foundation

enum TuneAVEighties80sNowPlaying {
    static let fallbackURL = URL(string: "https://www.80s80s.de/80s80s-app")!

    static func supports(_ station: Station) -> Bool {
        let homepageHost = station.resolvedHomepageURL?.host?.lowercased()
        let streamHost = URL(string: station.streamURL)?.host?.lowercased()
        return homepageHost?.contains("80s80s.de") == true || streamHost?.contains("80s80s") == true
    }

    static func resolvedURL(for station: Station) -> URL? {
        guard let homepageURL = station.resolvedHomepageURL else { return nil }
        let host = homepageURL.host?.lowercased() ?? ""
        guard host.contains("80s80s.de") else { return nil }
        return homepageURL
    }

    static func parseTrack(for station: Station, from html: String) -> TuneAVNowPlayingTrack? {
        let entries = parseEntries(from: html)
        guard let entry = bestEntry(for: station, in: entries) else { return nil }
        return TuneAVNowPlayingTrack(title: entry.songTitle, artist: entry.artistName)
    }

    private static func parseEntries(from html: String) -> [Entry] {
        let pattern = #"(stream|song_title|artist_name):"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var currentStream: String?
        var currentTitle: String?
        var currentArtist: String?
        var entries: [Entry] = []

        regex.enumerateMatches(in: html, options: [], range: nsRange) { match, _, _ in
            guard
                let match,
                let keyRange = Range(match.range(at: 1), in: html),
                let valueRange = Range(match.range(at: 2), in: html)
            else {
                return
            }

            let key = String(html[keyRange])
            let value = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "stream":
                appendEntry(
                    streamName: currentStream,
                    songTitle: currentTitle,
                    artistName: currentArtist,
                    to: &entries
                )
                currentStream = value
                currentTitle = nil
                currentArtist = nil
            case "song_title":
                currentTitle = value
            case "artist_name":
                currentArtist = value
            default:
                break
            }
        }

        appendEntry(
            streamName: currentStream,
            songTitle: currentTitle,
            artistName: currentArtist,
            to: &entries
        )

        return entries
    }

    private static func appendEntry(
        streamName: String?,
        songTitle: String?,
        artistName: String?,
        to entries: inout [Entry]
    ) {
        guard let streamName, let songTitle, !songTitle.isEmpty else { return }
        entries.append(Entry(streamName: streamName, songTitle: songTitle, artistName: artistName))
    }

    private static func bestEntry(for station: Station, in entries: [Entry]) -> Entry? {
        let stationKeys = stationKeys(station)

        return entries
            .compactMap { entry in
                let score = score(entry, stationKeys: stationKeys)
                return score > 0 ? (score, entry) : nil
            }
            .max { lhs, rhs in lhs.0 < rhs.0 }?
            .1
    }

    private static func stationKeys(_ station: Station) -> Set<String> {
        var keys: Set<String> = []
        let normalizedStationName = normalizedToken(station.name)
        if !normalizedStationName.isEmpty {
            keys.insert(normalizedStationName)
        }

        if let homepageURL = station.resolvedHomepageURL {
            let normalizedSlug = normalizedToken(homepageURL.lastPathComponent)
            if !normalizedSlug.isEmpty {
                keys.insert(normalizedSlug)
            }
        }

        let lowercasedName = station.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if normalizedStationName.isEmpty || normalizedStationName == "RADIO" || lowercasedName == "80s80s" {
            keys.insert("LIVE")
        }

        if lowercasedName.contains("depeche mode") {
            keys.insert("DM")
        }

        return keys
    }

    private static func score(_ entry: Entry, stationKeys: Set<String>) -> Int {
        let normalizedStream = normalizedToken(entry.streamName)

        if stationKeys.contains(normalizedStream) {
            return 100
        }

        if stationKeys.contains(where: { key in
            !key.isEmpty && (normalizedStream.contains(key) || key.contains(normalizedStream))
        }) {
            return 70
        }

        return 0
    }

    private static func normalizedToken(_ rawValue: String) -> String {
        let uppercased = rawValue
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()

        let withoutPrefix = uppercased.replacingOccurrences(of: "80S80S", with: " ")
        let filteredScalars = withoutPrefix.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(filteredScalars))
    }

    private struct Entry: Equatable {
        let streamName: String
        let songTitle: String
        let artistName: String?
    }
}
