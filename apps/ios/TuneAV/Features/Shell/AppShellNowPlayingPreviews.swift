import Foundation

enum AppShellNowPlayingPreviews {
    static func candidateStations(
        selectedTab: AppShellTab,
        homeSnapshot: HomeFeedSnapshot,
        searchResults: [Station],
        favoriteStations: [Station],
        recentStations: [Station],
        isEnabled: Bool
    ) -> [Station] {
        guard isEnabled else { return [] }

        switch selectedTab {
        case .home:
            return uniqueStations(
                homeSnapshot.recentStations.prefix(6) +
                homeSnapshot.favoriteStations.prefix(6) +
                homeSnapshot.stations.prefix(8)
            )
        case .search:
            return uniqueStations(searchResults.prefix(9))
        case .library:
            return uniqueStations(favoriteStations.prefix(9) + recentStations.prefix(6))
        case .music, .profile:
            return []
        }
    }

    static func uniqueStations<S: Sequence>(_ stations: S) -> [Station] where S.Element == Station {
        var seenIDs = Set<String>()
        var result: [Station] = []

        for station in stations where !seenIDs.contains(station.id) {
            seenIDs.insert(station.id)
            result.append(station)
        }

        return result
    }
}
