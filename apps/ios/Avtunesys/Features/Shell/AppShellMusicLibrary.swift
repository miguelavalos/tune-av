import Foundation

enum MusicLibraryMode: String, CaseIterable, Identifiable {
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

struct DiscoveryArtistSummary: Identifiable, Equatable {
    let name: String
    let trackCount: Int
    let artistArtworkURL: URL?
    let fallbackArtworkURL: URL?

    var id: String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: L10n.locale)
            .lowercased()
    }

    var displayArtworkURL: URL? {
        artistArtworkURL ?? fallbackArtworkURL
    }
}

enum AppShellMusicLibrary {
    static func visibleDiscoveries(_ discoveries: [DiscoveredTrack]) -> [DiscoveredTrack] {
        discoveries.filter { discovery in
            !discovery.isHidden && !looksLikeStationMetadata(discovery)
        }
    }

    static func savedDiscoveries(_ discoveries: [DiscoveredTrack]) -> [DiscoveredTrack] {
        visibleDiscoveries(discoveries).filter(\.isMarkedInteresting)
    }

    static func filteredDiscoveries(
        _ discoveries: [DiscoveredTrack],
        mode: MusicLibraryMode,
        query: String,
        selectedArtistName: String?
    ) -> [DiscoveredTrack] {
        let visible = visibleDiscoveries(discoveries)
        let baseDiscoveries = visible.filter { discovery in
            switch mode {
            case .songs, .artists:
                return discovery.isMarkedInteresting
            case .history:
                return true
            }
        }

        let artistFilteredDiscoveries: [DiscoveredTrack]
        if let selectedArtistName {
            artistFilteredDiscoveries = baseDiscoveries.filter {
                $0.artistDisplayText.compare(selectedArtistName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        } else {
            artistFilteredDiscoveries = baseDiscoveries
        }

        guard let trimmedQuery = AVTunesysText.normalizedValue(query) else { return baseDiscoveries }

        return artistFilteredDiscoveries.filter { discovery in
            discovery.title.localizedCaseInsensitiveContains(trimmedQuery) ||
            discovery.artist?.localizedCaseInsensitiveContains(trimmedQuery) == true ||
            discovery.stationName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    static func filteredArtistSummaries(
        _ discoveries: [DiscoveredTrack],
        mode: MusicLibraryMode,
        query: String
    ) -> [DiscoveryArtistSummary] {
        let savedDiscoveries = visibleDiscoveries(discoveries).filter { discovery in
            switch mode {
            case .songs, .artists:
                return discovery.isMarkedInteresting
            case .history:
                return false
            }
        }
        let matchingDiscoveries: [DiscoveredTrack]
        if let trimmedQuery = AVTunesysText.normalizedValue(query) {
            matchingDiscoveries = savedDiscoveries.filter { discovery in
                discovery.artist?.localizedCaseInsensitiveContains(trimmedQuery) == true ||
                discovery.title.localizedCaseInsensitiveContains(trimmedQuery)
            }
        } else {
            matchingDiscoveries = savedDiscoveries
        }

        return artistSummaries(for: matchingDiscoveries)
    }

    static func visibleArtistSummaries(_ discoveries: [DiscoveredTrack]) -> [DiscoveryArtistSummary] {
        artistSummaries(for: visibleDiscoveries(discoveries).filter(\.isMarkedInteresting))
    }

    static func shareText(title: String, discoveries: [DiscoveredTrack]) -> String {
        let lines = discoveries.map { discovery in
            [
                discovery.artistDisplayText,
                discovery.title,
                discovery.stationName
            ]
            .compactMap(AVTunesysText.normalizedValue)
            .joined(separator: " - ")
        }

        return ([title] + lines).joined(separator: "\n")
    }

    static func normalizedInitialMode(
        _ mode: MusicLibraryMode,
        discoveries: [DiscoveredTrack]
    ) -> MusicLibraryMode {
        guard mode == .songs, savedDiscoveries(discoveries).isEmpty, !visibleDiscoveries(discoveries).isEmpty else {
            return mode
        }

        return .history
    }

    private static func artistSummaries(for discoveries: [DiscoveredTrack]) -> [DiscoveryArtistSummary] {
        let grouped = Dictionary(grouping: discoveries) { discovery in
            discovery.artistDisplayText
        }

        return grouped
            .map { artist, discoveries in
                DiscoveryArtistSummary(
                    name: artist,
                    trackCount: discoveries.count,
                    artistArtworkURL: nil,
                    fallbackArtworkURL: discoveries.compactMap(\.resolvedArtworkURL).first
                )
            }
            .sorted { first, second in
                if first.trackCount == second.trackCount {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }

                return first.trackCount > second.trackCount
            }
    }

    private static func looksLikeStationMetadata(_ discovery: DiscoveredTrack) -> Bool {
        AVTunesysTrackMetadataParser.valueLooksLikeBroadcastMetadata(discovery.title, stationName: discovery.stationName)
            || AVTunesysTrackMetadataParser.artistLooksLikeBroadcastMetadata(discovery.artist, stationName: discovery.stationName)
    }
}
