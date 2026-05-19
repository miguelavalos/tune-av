struct HomeDerivedState {
    let displayedRecentStations: [Station]
    let displayedFavoriteStations: [Station]
    let displayedPopularStations: [Station]
    let displayedAviPickStations: [Station]
    let displayedAroundYouStations: [Station]
    let displayedRecentAndFavoriteStations: [Station]
    let moodGenreTags: [HomeMoodGenreSuggestion]
    let recommendationInsights: [String: String]
}

enum HomeDerivedStateBuilder {
    static func build(
        stations: [Station],
        recentStations: [Station],
        favoriteStations: [Station],
        currentStation: Station?,
        discoveries: [DiscoveredTrack],
        stationFeedback: [String: TuneAVStationFeedback],
        feedContext: HomeFeedContext,
        preferredTag: String,
        preferredCountryCode: String?,
        featuredStationID: String?,
        personalStationLimit: Int = 6,
        aviPickLimit: Int = 4,
        aroundYouFallbackStartOffset: Int = 4,
        aroundYouLimit: Int = 6,
        recentAndFavoriteLimit: Int = 8,
        moodStationLimit: Int = 8
    ) -> HomeDerivedState {
        let displayedRecentStations = HomePersonalStationSelector.select(
            from: recentStations,
            excludingFeaturedID: featuredStationID,
            limit: personalStationLimit
        )
        let displayedFavoriteStations = HomePersonalStationSelector.select(
            from: favoriteStations,
            excludingFeaturedID: featuredStationID,
            limit: personalStationLimit
        )
        let scorer = TuneAVLocalRecommendationScorer(
            currentStation: currentStation,
            recentStations: recentStations,
            favoriteStations: favoriteStations,
            discoveries: discoveries,
            stationFeedback: stationFeedback,
            feedContext: feedContext,
            preferredTag: preferredTag,
            currentCountryCode: preferredCountryCode
        )
        let displayedPopularStations = HomePopularStationSelector.select(
            from: stations,
            excludingFeaturedID: featuredStationID,
            excludingRecentStations: displayedRecentStations,
            favoriteStations: displayedFavoriteStations,
            scorer: scorer
        )
        let displayedAviPickStations = HomeAviPickStationSelector.select(
            from: displayedPopularStations,
            limit: aviPickLimit
        )
        let displayedAroundYouStations = HomeAroundYouStationSelector.select(
            from: displayedPopularStations,
            aviPickStations: displayedAviPickStations,
            preferredCountryCode: preferredCountryCode,
            currentCountryCode: currentStation?.countryCode,
            fallbackStartOffset: aroundYouFallbackStartOffset,
            limit: aroundYouLimit
        )
        let displayedRecentAndFavoriteStations = HomeRecentFavoriteStationSelector.select(
            recentStations: displayedRecentStations,
            favoriteStations: displayedFavoriteStations,
            limit: recentAndFavoriteLimit
        )
        let moodGenreTags = HomeMoodSuggestionBuilder.build(
            from: displayedPopularStations,
            stationLimit: moodStationLimit
        )
        let recommendationInsights = HomeRecommendationInsightBuilder.build(
            aviPickStations: displayedAviPickStations,
            aroundYouStations: displayedAroundYouStations,
            scorer: scorer
        )

        return HomeDerivedState(
            displayedRecentStations: displayedRecentStations,
            displayedFavoriteStations: displayedFavoriteStations,
            displayedPopularStations: displayedPopularStations,
            displayedAviPickStations: displayedAviPickStations,
            displayedAroundYouStations: displayedAroundYouStations,
            displayedRecentAndFavoriteStations: displayedRecentAndFavoriteStations,
            moodGenreTags: moodGenreTags,
            recommendationInsights: recommendationInsights
        )
    }
}
