struct ShellAviActionsRouter {
    let changeActionsPage: (Int) -> Void
    let closeAviActions: () -> Void
    let showReaction: (AviScreenReaction) -> Void
    let openTrackSearch: (Station, TuneAVExternalSearchURL.Destination, String?) -> Void
    let openArtistSearch: () -> Void
    let openStationSearch: (Station) -> Void
    let showStationDetails: (Station, [Station], StationDetailSection) -> Void
    let openStationWebsiteOrSearch: (Station) -> Void
    let showRelatedStations: (Station) -> Void
    let stopPlayback: () -> Void

    func previousPage(from state: ShellAviActionsPanelState) {
        changeActionsPage(state.previousPage)
    }

    func nextPage(from state: ShellAviActionsPanelState) {
        changeActionsPage(state.nextPage)
    }

    func searchLyrics(for station: Station) {
        showReaction(.curious)
        openTrackSearch(station, .web, "lyrics")
    }

    func searchYouTube(for station: Station) {
        showReaction(.curious)
        openTrackSearch(station, .youtube, nil)
    }

    func searchAppleMusic(for station: Station) {
        showReaction(.curious)
        openTrackSearch(station, .appleMusic, nil)
    }

    func searchArtist() {
        showReaction(.curious)
        openArtistSearch()
    }

    func searchPublicInfo(for station: Station) {
        showReaction(.curious)
        openStationSearch(station)
    }

    func showRadioDetails(for station: Station) {
        showStationDetails(station, [station], .about)
        closeAviActions()
    }

    func showHistory(for station: Station) {
        showStationDetails(station, [station], .history)
        closeAviActions()
    }

    func openWebsite(for station: Station) {
        showReaction(.curious)
        openStationWebsiteOrSearch(station)
    }

    func findRelatedRadios(for station: Station) {
        showReaction(.curious)
        showRelatedStations(station)
        closeAviActions()
    }

    func closeSignal() {
        closeAviActions()
        stopPlayback()
    }
}
