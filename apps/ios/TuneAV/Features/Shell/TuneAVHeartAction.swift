import AVHaptics
import Foundation

@MainActor
enum TuneAVHeartAction {
    enum Outcome: Equatable {
        case saved
        case removed
        case blocked
    }

    static func target(title: String?, artist: String?, station: Station) -> TuneAVNowPlayingContentState.HeartTarget {
        let hasSong = TuneAVDisplayMetadata.plausibleTitle(title, stationName: station.name) != nil &&
            TuneAVDisplayMetadata.plausibleArtist(artist, stationName: station.name) != nil
        return hasSong ? .song : .station
    }

    static func isSaved(
        target: TuneAVNowPlayingContentState.HeartTarget,
        title: String?,
        artist: String?,
        station: Station,
        libraryStore: LibraryStore
    ) -> Bool {
        switch target {
        case .song:
            return libraryStore.isSavedDiscoveredTrack(title: title, artist: artist, station: station)
        case .station:
            return libraryStore.isFavorite(station)
        }
    }

    @discardableResult
    static func toggleStationFavorite(
        _ station: Station,
        libraryStore: LibraryStore,
        accessController: AccessController
    ) -> Outcome {
        if libraryStore.isFavorite(station) {
            AVHaptics.perform(.undo)
            libraryStore.toggleFavorite(for: station)
            return .removed
        }

        let state = accessController.limitState(
            for: .favoriteStations,
            currentUsage: libraryStore.favorites.count
        )
        guard state.isAllowed else {
            accessController.presentUpgradePrompt(for: .favoriteStations, currentUsage: state.currentUsage)
            return .blocked
        }

        AVHaptics.perform(.affirm)
        libraryStore.toggleFavorite(for: station)
        return .saved
    }

    @discardableResult
    static func toggleCurrentSong(
        title: String?,
        artist: String?,
        artworkURL: URL?,
        station: Station,
        libraryStore: LibraryStore,
        accessController: AccessController
    ) -> Outcome {
        let state = accessController.limitState(
            for: .savedTracks,
            currentUsage: libraryStore.savedDiscoveriesCount
        )

        let isAlreadySaved = libraryStore.isSavedDiscoveredTrack(title: title, artist: artist, station: station)
        guard ShellCurrentDiscoveryCoordinator.canToggleTrack(
            isAlreadySaved: isAlreadySaved,
            canMarkInteresting: libraryStore.canMarkTrackInteresting(
                title: title,
                artist: artist,
                station: station,
                limit: state.limit
            )
        ) else {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return .blocked
        }

        let didToggle = libraryStore.toggleDiscoveredTrackSaved(
            title: title,
            artist: artist,
            station: station,
            artworkURL: artworkURL,
            savedLimit: state.limit,
            discoveryLimit: accessController.limits.discoveredTracks
        )
        guard didToggle else {
            accessController.presentUpgradePrompt(for: .savedTracks, currentUsage: state.currentUsage)
            return .blocked
        }

        return libraryStore.isSavedDiscoveredTrack(title: title, artist: artist, station: station) ? .saved : .removed
    }
}
