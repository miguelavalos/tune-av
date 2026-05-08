import Foundation

typealias MusicLibraryMode = TuneAVMusicLibraryMode
typealias DiscoveryArtistSummary = TuneAVDiscoveryArtistSummary

enum AppShellMusicLibrary {
    static func visibleDiscoveries(_ discoveries: [DiscoveredTrack]) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.visibleDiscoveries(discoveries)
    }

    static func savedDiscoveries(_ discoveries: [DiscoveredTrack]) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.savedDiscoveries(discoveries)
    }

    static func filteredDiscoveries(
        _ discoveries: [DiscoveredTrack],
        mode: MusicLibraryMode,
        query: String,
        selectedArtistName: String?,
        historyStationID: String? = nil
    ) -> [DiscoveredTrack] {
        TuneAVMusicLibraryLogic.filteredDiscoveries(
            discoveries,
            mode: mode,
            query: query,
            selectedArtistName: selectedArtistName,
            historyStationID: historyStationID
        )
    }

    static func filteredArtistSummaries(
        _ discoveries: [DiscoveredTrack],
        mode: MusicLibraryMode,
        query: String
    ) -> [DiscoveryArtistSummary] {
        TuneAVMusicLibraryLogic.filteredArtistSummaries(discoveries, mode: mode, query: query, locale: L10n.locale)
    }

    static func visibleArtistSummaries(_ discoveries: [DiscoveredTrack]) -> [DiscoveryArtistSummary] {
        TuneAVMusicLibraryLogic.visibleArtistSummaries(discoveries, locale: L10n.locale)
    }

    static func shareText(title: String, discoveries: [DiscoveredTrack]) -> String {
        TuneAVDiscoveryShareTextFormatter.listText(title: title, discoveries: discoveries)
    }

    static func normalizedInitialMode(
        _ mode: MusicLibraryMode,
        discoveries: [DiscoveredTrack],
        historyStationID: String? = nil
    ) -> MusicLibraryMode {
        TuneAVMusicLibraryLogic.normalizedInitialMode(mode, discoveries: discoveries, historyStationID: historyStationID)
    }
}
