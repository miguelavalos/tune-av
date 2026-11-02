import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AppShellView {
    func enrichedStation(_ station: Station) -> Station {
        let cachedStation = station.enrichmentLookupKeys
            .compactMap { enrichedStationsByID[$0] }
            .max { $0.enrichmentRank < $1.enrichmentRank }

        guard let cachedStation else { return station }
        guard cachedStation.hasBackendEnrichment else { return station }
        if let isStationNewer = station.metadataFreshnessCompared(to: cachedStation) {
            return isStationNewer ? station : cachedStation
        }
        if station.displayArtworkURL != nil, cachedStation.displayArtworkURL == nil {
            return station
        }
        guard !station.hasBackendEnrichment || cachedStation.enrichmentRank >= station.enrichmentRank else { return station }
        return cachedStation
    }

    func enrichedStations(_ stations: [Station]) -> [Station] {
        stations.map(enrichedStation)
    }

    func rememberBackendStations(_ stations: [Station]) {
        guard !stations.isEmpty else { return }

        var nextEnrichedStationsByID = enrichedStationsByID

        for station in stations where station.hasBackendEnrichment {
            for key in station.enrichmentLookupKeys {
                let current = nextEnrichedStationsByID[key]
                guard station.isPreferredEnrichment(over: current) else { continue }
                nextEnrichedStationsByID[key] = station
            }
        }
        if nextEnrichedStationsByID != enrichedStationsByID {
            enrichedStationsByID = nextEnrichedStationsByID
        }

        libraryStore.rememberStationSnapshots(stations)
    }

    func refreshSelectedStationEnrichmentIfNeeded(_ station: Station) {
        guard !launchContext.isUITesting else { return }
        let resolvedStation = enrichedStation(station)
        guard resolvedStation.enrichmentRank < 12 else { return }

        Task {
            await refreshSelectedStationEnrichment(station)
        }
    }

    func refreshSelectedStationEnrichment(_ station: Station) async {
        do {
            let results = try await stationService.searchStations(
                filters: .init(
                    query: station.name,
                    country: station.country,
                    countryCode: station.countryCode ?? "",
                    language: station.language,
                    limit: 5
                )
            )
            guard let enrichedMatch = results.bestBackendMatch(for: station) else { return }
            guard !Task.isCancelled else { return }
            rememberBackendStations([enrichedMatch])
        } catch {
            return
        }
    }

    func refreshLibraryStationEnrichment() async {
        guard !launchContext.isUITesting else { return }

        let candidates = libraryEnrichmentCandidates()
        guard !candidates.isEmpty else { return }
        let candidatesKey = libraryEnrichmentCandidatesKey(candidates)
        guard shouldRefreshLibraryEnrichment(for: candidatesKey) else { return }
        lastLibraryEnrichmentRequestKey = candidatesKey
        lastLibraryEnrichmentRequestAt = .now

        var enrichedMatches: [Station] = []
        for station in candidates {
            if Task.isCancelled { return }

            do {
                let results = try await stationService.searchStations(
                    filters: .init(
                        query: station.name,
                        country: station.country,
                        countryCode: station.countryCode ?? "",
                        language: station.language,
                        limit: 5
                    )
                )
                guard let enrichedMatch = results.bestBackendMatch(for: station) else { continue }
                enrichedMatches.append(enrichedMatch)
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }

        guard !Task.isCancelled else { return }
        guard candidatesKey == libraryEnrichmentCandidatesKey(libraryEnrichmentCandidates()) else { return }
        rememberBackendStations(enrichedMatches)
    }

    func shouldRefreshLibraryEnrichment(for key: String, now: Date = .now) -> Bool {
        guard key == lastLibraryEnrichmentRequestKey, let lastLibraryEnrichmentRequestAt else {
            return true
        }
        return now.timeIntervalSince(lastLibraryEnrichmentRequestAt) >= Self.libraryEnrichmentRefreshInterval
    }

    func libraryEnrichmentCandidates() -> [Station] {
        var seenIDs = Set<String>()
        let stations = [audioPlayer.currentStation].compactMap { $0 } + favoriteStations + recentStations

        return stations.reduce(into: [Station]()) { result, station in
            guard !seenIDs.contains(station.id) else { return }
            seenIDs.insert(station.id)

            let resolvedStation = enrichedStation(station)
            guard resolvedStation.enrichmentRank < 12 else { return }
            result.append(resolvedStation)
        }
        .prefix(12)
        .map { $0 }
    }

    func libraryEnrichmentCandidatesKey(_ candidates: [Station]) -> String {
        candidates
            .map { "\($0.id):\($0.enrichmentRank)" }
            .joined(separator: "|")
    }

    func openDiscoveryStation(_ discovery: DiscoveredTrack) {
        guard let station = libraryStore.station(for: discovery.stationID) else { return }

        playStation(station, queueSource: .libraryRecents, queue: enrichedRecentStations)
    }
}
