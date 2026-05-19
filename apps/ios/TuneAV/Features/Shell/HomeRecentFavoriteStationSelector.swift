enum HomeRecentFavoriteStationSelector {
    static func select(recentStations: [Station], favoriteStations: [Station], limit: Int) -> [Station] {
        Array(AppShellNowPlayingPreviews.uniqueStations(recentStations + favoriteStations).prefix(limit))
    }
}
