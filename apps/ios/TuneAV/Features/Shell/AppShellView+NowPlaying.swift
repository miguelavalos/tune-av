import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AppShellView {
    var stationNowPlayingRequestKey: String {
        let ids = stationNowPlayingCandidates.map(\.id).joined(separator: "|")
        return "\(selectedTab)|\(isProNowPlayingEnabled)|\(ids)"
    }

    var summaryRefreshRequestKey: String {
        switch selectedTab {
        case .library, .music:
            return "\(selectedTab)|\(accessController.accessMode)|\(accessController.accountUser?.id ?? "guest")"
        case .home, .search, .avi, .profile:
            return ""
        }
    }

    func refreshUserSummaryForVisibleTab() async {
        guard selectedTab == .library || selectedTab == .music else { return }
        guard !launchContext.isUITesting else { return }
        await libraryStore.refreshUserSummary()
    }

    var currentTrackDiscoveryKey: String {
        guard
            let station = audioPlayer.currentStation,
            let trackTitle = TuneAVDisplayMetadata.plausibleTitle(
                audioPlayer.currentTrackTitle,
                stationName: station.name
            ),
            let trackArtist = TuneAVDisplayMetadata.plausibleArtist(
                audioPlayer.currentTrackArtist,
                stationName: station.name
            )
        else {
            return ""
        }

        return [
            station.id,
            TuneAVText.normalizedValue(trackArtist) ?? trackArtist.lowercased(),
            TuneAVText.normalizedValue(trackTitle) ?? trackTitle.lowercased(),
            audioPlayer.currentTrackArtworkURL?.absoluteString ?? ""
        ].joined(separator: "|")
    }

    var stationNowPlayingCandidates: [Station] {
        AppShellNowPlayingPreviews.candidateStations(
            selectedTab: selectedTab,
            homeSnapshot: homeSnapshot,
            searchResults: enrichedStations(searchPresentation.results),
            favoriteStations: enrichedFavoriteStations,
            recentStations: enrichedRecentStations,
            isEnabled: isProNowPlayingEnabled
        )
    }

    func loadStationNowPlayingPreviews() async {
        guard isProNowPlayingEnabled else {
            clearStationNowPlayingPreviews()
            return
        }
        guard !launchContext.isUITesting else {
            clearStationNowPlayingPreviews()
            return
        }

        let supportedStations = stationNowPlayingCandidates
            .filter { stationNowPlayingService.supports($0) }
            .prefix(6)
        let supportedStationIDs = Set(supportedStations.map(\.id))

        guard !supportedStations.isEmpty else {
            clearVisibleStationNowPlayingPreviews()
            return
        }

        var nextTracks = stationNowPlayingTracks.filter { supportedStationIDs.contains($0.key) }

        for station in supportedStations {
            if Task.isCancelled { return }

            if let cached = stationNowPlayingCache[station.id], cached.isFresh {
                nextTracks[station.id] = cached.track
                continue
            }
            if let failedAt = stationNowPlayingFailureCache[station.id], Date().timeIntervalSince(failedAt) < 180 {
                continue
            }

            let track = await stationNowPlayingService.fetchTrack(for: station)
            guard !Task.isCancelled else { return }

            guard let track else {
                stationNowPlayingFailureCache[station.id] = Date()
                continue
            }
            nextTracks[station.id] = track
            stationNowPlayingCache[station.id] = CachedStationNowPlaying(track: track, fetchedAt: Date())
            stationNowPlayingFailureCache[station.id] = nil
        }

        guard stationNowPlayingTracks != nextTracks else { return }
        stationNowPlayingTracks = nextTracks
    }

    func clearVisibleStationNowPlayingPreviews() {
        if !stationNowPlayingTracks.isEmpty {
            stationNowPlayingTracks.removeAll(keepingCapacity: true)
        }
    }

    func clearStationNowPlayingPreviews() {
        if !stationNowPlayingTracks.isEmpty {
            stationNowPlayingTracks.removeAll(keepingCapacity: true)
        }
        if !stationNowPlayingCache.isEmpty {
            stationNowPlayingCache.removeAll(keepingCapacity: true)
        }
        if !stationNowPlayingFailureCache.isEmpty {
            stationNowPlayingFailureCache.removeAll(keepingCapacity: true)
        }
    }

    var isProNowPlayingEnabled: Bool {
        accessController.capabilities.canAccessPremiumFeatures
    }

    func recordCurrentTrackDiscovery() {
        guard
            let station = audioPlayer.currentStation,
            let trackTitle = TuneAVDisplayMetadata.plausibleTitle(
                audioPlayer.currentTrackTitle,
                stationName: station.name
            ),
            let trackArtist = TuneAVDisplayMetadata.plausibleArtist(
                audioPlayer.currentTrackArtist,
                stationName: station.name
            )
        else {
            return
        }

        libraryStore.recordDiscoveredTrack(
            title: trackTitle,
            artist: trackArtist,
            station: station,
            artworkURL: audioPlayer.currentTrackArtworkURL,
            discoveryLimit: accessController.limits.discoveredTracks
        )
        rememberTrackForListeningSession(title: trackTitle, artist: trackArtist)
        accessController.noteDiscoveredTrackForUpgradeMoment(key: "\(station.id)|\(trackTitle)|\(trackArtist)")
    }

    func rememberTrackForListeningSession(title: String, artist: String?) {
        ShellListeningSessionCoordinator.rememberTrack(
            session: &listeningSession,
            title: title,
            artist: artist
        )
    }

    func applyUITestTrackMetadataIfNeeded() {
        guard let metadata = ShellUITestBootstrapOverrides.trackMetadata(from: launchContext) else { return }
        audioPlayer.applyUITestTrackMetadata(
            title: metadata.title,
            artist: metadata.artist
        )
    }
}
