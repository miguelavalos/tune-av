import Foundation

enum TuneAVMusicLibraryMode: String, CaseIterable, Identifiable {
    case songs
    case artists
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs:
            return L10n.string("shell.music.mode.songs")
        case .artists:
            return L10n.string("shell.music.mode.artists")
        case .history:
            return L10n.string("shell.music.mode.history")
        }
    }

    var songsTitle: String {
        switch self {
        case .songs, .artists:
            return L10n.string("shell.library.discoveries.songs.savedTitle")
        case .history:
            return L10n.string("shell.library.discoveries.songs.historyTitle")
        }
    }
}

protocol TuneAVMusicLibraryDiscovery: TuneAVDiscoveryShareItem {
    var stationID: String { get }
    var isMarkedInteresting: Bool { get }
    var artistDisplayText: String { get }
    var resolvedArtworkURL: URL? { get }
}

struct TuneAVDiscoveryArtistSummary: Identifiable, Equatable {
    let name: String
    let trackCount: Int
    let artistArtworkURL: URL?
    let fallbackArtworkURL: URL?
    private let locale: Locale

    init(
        name: String,
        trackCount: Int,
        artistArtworkURL: URL?,
        fallbackArtworkURL: URL?,
        locale: Locale = .current
    ) {
        self.name = name
        self.trackCount = trackCount
        self.artistArtworkURL = artistArtworkURL
        self.fallbackArtworkURL = fallbackArtworkURL
        self.locale = locale
    }

    var id: String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .lowercased()
    }

    var displayArtworkURL: URL? {
        artistArtworkURL ?? fallbackArtworkURL
    }
}

enum TuneAVMusicLibraryLogic {
    static func visibleDiscoveries<Discovery: TuneAVMusicLibraryDiscovery>(
        _ discoveries: [Discovery]
    ) -> [Discovery] {
        discoveries.filter { discovery in
            !discovery.isHidden && !looksLikeStationMetadata(discovery)
        }
    }

    static func savedDiscoveries<Discovery: TuneAVMusicLibraryDiscovery>(
        _ discoveries: [Discovery]
    ) -> [Discovery] {
        visibleDiscoveries(discoveries).filter(\.isMarkedInteresting)
    }

    static func filteredDiscoveries<Discovery: TuneAVMusicLibraryDiscovery>(
        _ discoveries: [Discovery],
        mode: TuneAVMusicLibraryMode,
        query: String,
        selectedArtistName: String?,
        historyStationID: String? = nil
    ) -> [Discovery] {
        let baseDiscoveries = visibleDiscoveries(discoveries).filter { discovery in
            switch mode {
            case .songs, .artists:
                return discovery.isMarkedInteresting
            case .history:
                return true
            }
        }

        let artistFilteredDiscoveries: [Discovery]
        if let selectedArtistName {
            artistFilteredDiscoveries = baseDiscoveries.filter {
                $0.artistDisplayText.compare(
                    selectedArtistName,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
        } else {
            artistFilteredDiscoveries = baseDiscoveries
        }

        let stationFilteredDiscoveries: [Discovery]
        if mode == .history, let historyStationID {
            stationFilteredDiscoveries = artistFilteredDiscoveries.filter { $0.stationID == historyStationID }
        } else {
            stationFilteredDiscoveries = artistFilteredDiscoveries
        }

        guard let trimmedQuery = TuneAVText.normalizedValue(query) else { return stationFilteredDiscoveries }

        return stationFilteredDiscoveries.filter { discovery in
            discovery.title.localizedCaseInsensitiveContains(trimmedQuery)
                || discovery.artist?.localizedCaseInsensitiveContains(trimmedQuery) == true
                || discovery.stationName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    static func filteredArtistSummaries<Discovery: TuneAVMusicLibraryDiscovery>(
        _ discoveries: [Discovery],
        mode: TuneAVMusicLibraryMode,
        query: String,
        locale: Locale = .current
    ) -> [TuneAVDiscoveryArtistSummary] {
        let savedDiscoveries = visibleDiscoveries(discoveries).filter { discovery in
            switch mode {
            case .songs, .artists:
                return discovery.isMarkedInteresting
            case .history:
                return false
            }
        }

        let matchingDiscoveries: [Discovery]
        if let trimmedQuery = TuneAVText.normalizedValue(query) {
            matchingDiscoveries = savedDiscoveries.filter { discovery in
                discovery.artist?.localizedCaseInsensitiveContains(trimmedQuery) == true
                    || discovery.title.localizedCaseInsensitiveContains(trimmedQuery)
            }
        } else {
            matchingDiscoveries = savedDiscoveries
        }

        return artistSummaries(for: matchingDiscoveries, locale: locale)
    }

    static func visibleArtistSummaries<Discovery: TuneAVMusicLibraryDiscovery>(
        _ discoveries: [Discovery],
        locale: Locale = .current
    ) -> [TuneAVDiscoveryArtistSummary] {
        artistSummaries(for: savedDiscoveries(discoveries), locale: locale)
    }

    static func normalizedInitialMode<Discovery: TuneAVMusicLibraryDiscovery>(
        _ mode: TuneAVMusicLibraryMode,
        discoveries: [Discovery],
        historyStationID: String? = nil
    ) -> TuneAVMusicLibraryMode {
        if historyStationID != nil {
            return .history
        }

        guard mode == .songs, savedDiscoveries(discoveries).isEmpty, !visibleDiscoveries(discoveries).isEmpty else {
            return mode
        }

        return .history
    }

    private static func artistSummaries<Discovery: TuneAVMusicLibraryDiscovery>(
        for discoveries: [Discovery],
        locale: Locale
    ) -> [TuneAVDiscoveryArtistSummary] {
        let grouped = Dictionary(grouping: discoveries) { discovery in
            discovery.artistDisplayText
        }

        return grouped
            .map { artist, discoveries in
                TuneAVDiscoveryArtistSummary(
                    name: artist,
                    trackCount: discoveries.count,
                    artistArtworkURL: nil,
                    fallbackArtworkURL: discoveries.compactMap(\.resolvedArtworkURL).first,
                    locale: locale
                )
            }
            .sorted { first, second in
                if first.trackCount == second.trackCount {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }

                return first.trackCount > second.trackCount
            }
    }

    private static func looksLikeStationMetadata(_ discovery: any TuneAVMusicLibraryDiscovery) -> Bool {
        TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(discovery.title, stationName: discovery.stationName)
            || TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(discovery.artist, stationName: discovery.stationName)
    }
}
