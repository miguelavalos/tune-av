import Foundation

enum AviRelatedStationsCoordinator {
    static func candidateStations(
        stations: [Station],
        playbackQueueStations: [Station],
        recentStations: [Station],
        favoriteStations: [Station]
    ) -> [Station] {
        AppShellNowPlayingPreviews.uniqueStations(
            stations + playbackQueueStations + recentStations + favoriteStations
        )
    }

    static func results(
        for station: Station,
        candidates: [Station],
        scorer: TuneAVLocalRecommendationScorer
    ) -> [(station: Station, reason: String)] {
        scorer
            .relatedStations(
                to: station,
                candidates: AppShellNowPlayingPreviews.uniqueStations(candidates)
            )
            .prefix(8)
            .map { candidate in
                (
                    station: candidate.station,
                    reason: TuneAVLocalRecommendationScorer.localizedSummary(for: candidate.rank.primaryReason)
                        ?? L10n.string("shell.avi.recommendation.reasonFallback")
                )
            }
    }

    static func remoteFilters(for station: Station) -> TuneAVStationSearchFilters? {
        guard let tag = primaryTag(for: station) else { return nil }
        return TuneAVStationSearchFilters(
            query: "",
            countryCode: station.countryCode ?? "",
            language: station.language,
            tag: tag,
            locale: Locale.current.identifier,
            limit: 24,
            allowsEmptySearch: true
        )
    }

    static func primaryTag(for station: Station) -> String? {
        station.tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
