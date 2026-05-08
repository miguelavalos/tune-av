import Foundation

enum DiscoveryShareTextFormatter {
    static let title = L10n.string("shell.library.discoveries.shareTitle")

    static func text(title trackTitle: String?, artist: String?, stationName: String) -> String {
        TuneAVDiscoveryShareTextFormatter.currentTrackText(
            title: trackTitle,
            artist: artist,
            stationName: stationName
        )
    }

    static func text(for discoveries: [DiscoveredTrack]) -> String {
        TuneAVDiscoveryShareTextFormatter.listText(title: title, discoveries: discoveries)
    }
}
