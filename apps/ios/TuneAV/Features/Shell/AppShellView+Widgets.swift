import SwiftUI

extension AppShellView {
    func registerWidgetPlayback() {
        widgetPlaybackRegistration = TuneAVWidgetController.shared.registerShellPlayback { station, queueSource, queue in
            playStation(station, queueSource: queueSource, queue: queue)
        }
    }

    func handleWidgetDeepLink(_ url: URL) {
        guard let link = TuneAVWidgetDeepLink(url: url) else { return }

        switch link {
        case .home:
            selectedTab = .home
        case let .player(stationID):
            if let currentStation = audioPlayer.currentStation {
                openNowPlayingFullPlayer(currentStation)
            } else if let station = libraryStore.station(for: stationID) {
                audioPlayer.select(station: station)
                openNowPlayingFullPlayer(station)
            } else {
                selectedTab = .home
            }
        case let .play(stationID, isFavoriteShortcut):
            let currentStation = audioPlayer.currentStation
            guard let station = currentStation?.id == stationID ? currentStation : libraryStore.station(for: stationID) else {
                selectedTab = .home
                return
            }
            let isAlreadyPlaying = currentStation?.id == station.id && (audioPlayer.status == .playing || audioPlayer.status == .loading)
            if !isAlreadyPlaying {
                playStation(
                    station,
                    queueSource: TuneAVWidgetPlaybackPlanner.queueSource(isFavoriteShortcut: isFavoriteShortcut),
                    queue: isFavoriteShortcut ? libraryStore.favoriteStations() : nil
                )
            }
            if pendingCellularPlayback == nil {
                openNowPlayingFullPlayer(station)
            }
        }
    }
}
