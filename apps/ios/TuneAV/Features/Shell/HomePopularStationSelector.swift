enum HomePopularStationSelector {
    static func select(
        from stations: [Station],
        excludingRecentStations recentStations: [Station],
        favoriteStations: [Station],
        scorer: TuneAVLocalRecommendationScorer
    ) -> [Station] {
        let excludedIDs = Set(recentStations.map(\.id) + favoriteStations.map(\.id))
        let candidates = stations.filter { !excludedIDs.contains($0.id) }

        return scorer.rankedStations(candidates).map(\.station)
    }
}
