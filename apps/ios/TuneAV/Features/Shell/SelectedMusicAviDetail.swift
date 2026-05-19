import Foundation

enum SelectedMusicAviDetail: Identifiable {
    case track(DiscoveredTrack)
    case artist(DiscoveryArtistSummary)

    var id: String {
        switch self {
        case .track(let discovery):
            return "track-\(discovery.discoveryID)"
        case .artist(let summary):
            return "artist-\(summary.id)"
        }
    }
}
