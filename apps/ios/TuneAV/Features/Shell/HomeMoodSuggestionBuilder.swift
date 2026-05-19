enum HomeMoodSuggestionBuilder {
    static func build(from stations: [Station], stationLimit: Int) -> [HomeMoodGenreSuggestion] {
        let visibleDiscoveryTags = HomeDiscoveryTagBuilder.build(
            from: stations,
            stationLimit: stationLimit
        )

        return HomeMoodGenreTagBuilder.build(visibleDiscoveryTags: visibleDiscoveryTags)
    }
}
