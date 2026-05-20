import Foundation

@MainActor
enum ShellUITestBootstrapSeeder {
    static func seedLibraryIfNeeded(
        launchContext: LaunchContext,
        libraryStore: LibraryStore,
        recentLimit: Int?
    ) {
        guard launchContext.isUITesting else { return }
        guard launchContext.shouldSeedUITestLibrary else { return }
        guard libraryStore.favorites.isEmpty, libraryStore.recents.isEmpty else { return }

        let samples = Array(Station.samples.prefix(3))
        guard !samples.isEmpty else { return }

        seedStations(samples, libraryStore: libraryStore, recentLimit: recentLimit)

        if launchContext.shouldUseLocalUITestDiscovery {
            seedDiscoveries(samples, libraryStore: libraryStore)
        }
    }

    private static func seedStations(
        _ samples: [Station],
        libraryStore: LibraryStore,
        recentLimit: Int?
    ) {
        for station in samples.prefix(2) {
            libraryStore.toggleFavorite(for: station)
        }

        for station in samples {
            libraryStore.recordPlayback(of: station, recentLimit: recentLimit)
        }
    }

    private static func seedDiscoveries(_ samples: [Station], libraryStore: LibraryStore) {
        guard samples.count >= 2 else { return }

        libraryStore.recordDiscoveredTrack(
            title: "Midnight City",
            artist: "M83",
            station: samples[0],
            artworkURL: nil
        )
        libraryStore.markTrackInteresting(
            title: "Sweet Disposition",
            artist: "The Temper Trap",
            station: samples[1],
            artworkURL: nil
        )
    }
}
