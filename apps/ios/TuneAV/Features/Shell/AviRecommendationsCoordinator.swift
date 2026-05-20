import Foundation

enum AviRecommendationsCoordinator {
    static func rankedCandidates(
        stations: [Station],
        currentStation: Station?,
        scorer: TuneAVLocalRecommendationScorer
    ) -> [(station: Station, rank: TuneAVLocalRecommendationScorer.Rank)] {
        let excludedIDs = Set(([currentStation?.id].compactMap { $0 }))

        return scorer
            .rankedStations(stations.filter { !excludedIDs.contains($0.id) })
            .filter { $0.rank.score > 0 }
    }

    static func topRecommendation(
        from rankedCandidates: [(station: Station, rank: TuneAVLocalRecommendationScorer.Rank)]
    ) -> (station: Station, reason: String)? {
        guard let top = rankedCandidates.first else { return nil }
        return recommendation(from: top)
    }

    static func secondaryRecommendations(
        from rankedCandidates: [(station: Station, rank: TuneAVLocalRecommendationScorer.Rank)]
    ) -> [(station: Station, reason: String)] {
        rankedCandidates
            .dropFirst()
            .prefix(2)
            .map(recommendation(from:))
    }

    static func queue(
        from rankedCandidates: [(station: Station, rank: TuneAVLocalRecommendationScorer.Rank)]
    ) -> [Station] {
        rankedCandidates.map(\.station)
    }

    static func recommendation(
        from candidate: (station: Station, rank: TuneAVLocalRecommendationScorer.Rank)
    ) -> (station: Station, reason: String) {
        (
            station: candidate.station,
            reason: TuneAVLocalRecommendationScorer.localizedSummary(for: candidate.rank.primaryReason)
                ?? L10n.string("shell.avi.recommendation.reasonFallback")
        )
    }
}
