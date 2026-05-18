import Foundation

enum TuneAVPlaybackQueueSource: Equatable {
    case homeRecents
    case homeFavorites
    case homeDiscovery
    case searchResults
    case libraryRecents
    case libraryFavorites
    case singleStation
}

enum TuneAVPlaybackQueueLogic {
    struct ResolvedQueue {
        let stations: [Station]
        let currentIndex: Int
    }

    static func sanitizedStations(_ stations: [Station], currentStation: Station?, currentStationID: String) -> [Station] {
        var seenStationIDs = Set<String>()
        var resolvedStations = stations.filter { station in
            seenStationIDs.insert(station.id).inserted
        }

        if let currentStation, seenStationIDs.insert(currentStation.id).inserted, currentStation.id == currentStationID {
            resolvedStations.insert(currentStation, at: 0)
        }

        return resolvedStations
    }

    static func resolvedQueue(stations: [Station], currentStation: Station?) -> ResolvedQueue? {
        guard let currentStation else { return nil }
        guard stations.count > 1,
              let currentIndex = stations.firstIndex(where: { $0.id == currentStation.id }) else {
            return nil
        }

        return ResolvedQueue(stations: stations, currentIndex: currentIndex)
    }

    static func nextStation(in resolvedQueue: ResolvedQueue) -> Station {
        let nextIndex = resolvedQueue.stations.index(after: resolvedQueue.currentIndex)
        let resolvedIndex = nextIndex < resolvedQueue.stations.endIndex ? nextIndex : resolvedQueue.stations.startIndex
        return resolvedQueue.stations[resolvedIndex]
    }

    static func nextStation(
        in resolvedQueue: ResolvedQueue,
        excluding excludedStationIDs: Set<String>
    ) -> Station? {
        guard resolvedQueue.stations.count > 1 else { return nil }

        for offset in 1..<resolvedQueue.stations.count {
            let index = (resolvedQueue.currentIndex + offset) % resolvedQueue.stations.count
            let station = resolvedQueue.stations[index]
            guard !excludedStationIDs.contains(station.id) else { continue }
            return station
        }

        return nil
    }

    static func previousStation(in resolvedQueue: ResolvedQueue) -> Station {
        let previousIndex = resolvedQueue.currentIndex == resolvedQueue.stations.startIndex
            ? resolvedQueue.stations.index(before: resolvedQueue.stations.endIndex)
            : resolvedQueue.stations.index(before: resolvedQueue.currentIndex)
        return resolvedQueue.stations[previousIndex]
    }
}
