import Foundation
import SwiftUI

extension AppShellView {
    /// A song "What's playing?" recognised from the stream becomes the current track: the player
    /// shows it with the catalog artwork, the discovery flow records it like a station title, and
    /// the history remembers it came from the stream audio.
    func applyIdentifiedTrack(_ track: TuneAVIdentifiedTrack, for station: Station) {
        guard audioPlayer.currentStation?.id == station.id else { return }
        audioPlayer.applyIdentifiedTrack(track, for: station)

        let artist = TuneAVDiscoveredTrackSupport.normalizedValue(track.artist)
        let title = TuneAVDiscoveredTrackSupport.normalizedValue(track.title) ?? track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        TuneAVIdentifiedDiscoveryStore().remember(
            DiscoveredTrack.makeID(title: title, artist: artist, stationID: station.id)
        )
    }
}
