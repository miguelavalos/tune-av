import Foundation

struct ShellBrowserRouter {
    let openDestination: (BrowserDestination) -> Void
    let closeAviActions: () -> Void

    func openURL(_ url: URL, closesAviActions: Bool = false) {
        guard let destination = BrowserDestination(url: url) else { return }
        openDestination(destination)
        if closesAviActions {
            closeAviActions()
        }
    }

    func openStationWebsiteOrSearch(_ station: Station, closesAviActions: Bool = false) {
        if let url = station.resolvedHomepageURL {
            openURL(url, closesAviActions: closesAviActions)
        } else {
            openStationSearch(for: station)
        }
    }

    func openTrackSearch(
        for station: Station,
        currentTrackArtist: String?,
        currentTrackTitle: String?,
        destination: TuneAVExternalSearchURL.Destination,
        suffix: String? = nil
    ) {
        guard let url = ShellAviExternalSearchResolver.trackSearchURL(
            station: station,
            currentTrackArtist: currentTrackArtist,
            currentTrackTitle: currentTrackTitle,
            destination: destination,
            suffix: suffix
        ) else { return }
        openURL(url, closesAviActions: true)
    }

    func openArtistSearch(currentTrackArtist: String?) {
        guard let url = ShellAviExternalSearchResolver.artistSearchURL(artist: currentTrackArtist) else { return }
        openURL(url, closesAviActions: true)
    }

    func openStationSearch(for station: Station) {
        guard let url = ShellAviExternalSearchResolver.stationSearchURL(station: station) else { return }
        openURL(url, closesAviActions: true)
    }

    func openExternalSearch(
        query: String,
        destination: TuneAVExternalSearchURL.Destination = .web
    ) {
        guard let url = ShellAviExternalSearchResolver.externalSearchURL(query: query, destination: destination) else { return }
        openURL(url, closesAviActions: true)
    }
}
