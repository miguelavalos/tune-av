import AVExternalLinkFoundation
import Foundation

struct MusicExternalSearchRouter {
    let openSearch: (TuneAVExternalSearchURL.FeatureSearch) -> Void
    let searchEngine: AVExternalSearchEngine

    func openDiscoveryYouTube(_ discovery: DiscoveredTrack) {
        openDiscovery(discovery, suffix: nil, youtube: true)
    }

    func openDiscoveryLyrics(_ discovery: DiscoveredTrack) {
        openDiscovery(discovery, suffix: "lyrics", youtube: false)
    }

    func openDiscoveryAppleMusic(_ discovery: DiscoveredTrack) {
        openDiscovery(discovery, destination: .appleMusic, feature: .appleMusicSearch)
    }

    func openDiscoverySpotify(_ discovery: DiscoveredTrack) {
        openDiscovery(discovery, destination: .spotify, feature: .spotifySearch)
    }

    func openArtistYouTube(_ artistName: String) {
        openArtist(artistName, destination: .youtube, feature: .youtubeSearch)
    }

    func openArtistAppleMusic(_ artistName: String) {
        openArtist(artistName, destination: .appleMusic, feature: .appleMusicSearch)
    }

    func openArtistSpotify(_ artistName: String) {
        openArtist(artistName, destination: .spotify, feature: .spotifySearch)
    }

    private func openDiscovery(_ discovery: DiscoveredTrack, suffix: String?, youtube: Bool) {
        guard let search = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: discovery.searchQuery,
            suffix: suffix,
            youtube: youtube,
            engine: searchEngine
        ) else { return }
        openSearch(search)
    }

    private func openDiscovery(
        _ discovery: DiscoveredTrack,
        destination: TuneAVExternalSearchURL.Destination,
        feature: LimitedFeature
    ) {
        guard let search = TuneAVExternalSearchURL.discoverySearch(
            searchQuery: discovery.searchQuery,
            destination: destination,
            feature: feature,
            engine: searchEngine
        ) else { return }
        openSearch(search)
    }

    private func openArtist(
        _ artistName: String,
        destination: TuneAVExternalSearchURL.Destination,
        feature: LimitedFeature
    ) {
        guard let search = TuneAVExternalSearchURL.artistSearch(
            artist: artistName,
            destination: destination,
            feature: feature,
            engine: searchEngine
        ) else { return }
        openSearch(search)
    }
}
