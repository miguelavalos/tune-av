enum HomeRecommendationInsightBuilder {
    static func build(
        aviPickStations: [Station],
        aroundYouStations: [Station],
        scorer: TuneAVLocalRecommendationScorer
    ) -> [String: String] {
        Dictionary(
            (aviPickStations + aroundYouStations).map { station in
                (
                    station.id,
                    TuneAVLocalRecommendationScorer.localizedSummary(
                        for: scorer.rank(station).primaryReason
                    ) ?? L10n.string("shell.avi.recommendation.reasonFallback")
                )
            },
            uniquingKeysWith: { current, _ in current }
        )
    }
}
