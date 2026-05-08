import Foundation

enum TuneAVExternalSearchURL {
    enum Destination {
        case web
        case youtube
        case appleMusic
        case spotify
    }

    struct FeatureSearch {
        let feature: LimitedFeature
        let url: URL
    }

    static func url(for destination: Destination, query: String) -> URL? {
        switch destination {
        case .web:
            return web(query: query, youtube: false)
        case .youtube:
            return web(query: query, youtube: true)
        case .appleMusic:
            return appleMusic(query: query)
        case .spotify:
            return spotify(query: query)
        }
    }

    static func stationSearch(stationName: String) -> URL? {
        web(query: query(parts: [stationName], suffix: "radio"), youtube: false)
    }

    static func discoverySearch(searchQuery: String, suffix: String?, youtube: Bool) -> FeatureSearch? {
        let feature: LimitedFeature = youtube ? .youtubeSearch : (suffix == nil ? .webSearch : .lyricsSearch)
        let query = query(parts: [searchQuery], suffix: suffix)
        guard let url = web(query: query, youtube: youtube) else { return nil }
        return FeatureSearch(feature: feature, url: url)
    }

    static func discoverySearch(
        searchQuery: String,
        destination: Destination,
        feature: LimitedFeature,
        suffix: String? = nil
    ) -> FeatureSearch? {
        let query = query(parts: [searchQuery], suffix: suffix)
        guard let url = url(for: destination, query: query) else { return nil }
        return FeatureSearch(feature: feature, url: url)
    }

    static func artistSearch(
        artist: String,
        destination: Destination,
        feature: LimitedFeature
    ) -> FeatureSearch? {
        guard let url = url(for: destination, query: artist) else { return nil }
        return FeatureSearch(feature: feature, url: url)
    }

    static func web(query: String, youtube: Bool) -> URL? {
        var components = URLComponents(string: youtube ? "https://www.youtube.com/results" : "https://www.google.com/search")
        components?.queryItems = [
            URLQueryItem(name: youtube ? "search_query" : "q", value: query)
        ]
        return components?.url
    }

    static func appleMusic(query: String) -> URL? {
        var components = URLComponents(string: "https://music.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query)
        ]
        return components?.url
    }

    static func spotify(query: String) -> URL? {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://open.spotify.com/search/\(encodedQuery)")
    }

    static func query(parts: [String?], suffix: String? = nil) -> String {
        TuneAVText.joinedQuery(parts: parts, suffix: suffix)
    }

    static func normalizedValue(_ value: String?) -> String? {
        TuneAVText.normalizedValue(value)
    }
}
