import Foundation

enum DiscoveryShareTextFormatter {
    static let title = "Tune AV discoveries"
    static let maxSharedDiscoveries = 25

    static func text(title trackTitle: String?, artist: String?, stationName: String) -> String {
        let trackText = [
            TuneAVText.normalizedValue(artist),
            TuneAVText.normalizedValue(trackTitle)
        ]
        .compactMap { $0 }
        .joined(separator: " - ")

        let normalizedStationName = TuneAVText.normalizedValue(stationName) ?? stationName
        return trackText.isEmpty ? normalizedStationName : "\(trackText) · \(normalizedStationName)"
    }

    static func text(for discoveries: [DiscoveredTrack]) -> String {
        let lines = discoveries
            .filter { !$0.isHidden }
            .prefix(maxSharedDiscoveries)
            .map { discovery in
                [
                    TuneAVText.normalizedValue(discovery.artist),
                    TuneAVText.normalizedValue(discovery.title)
                ]
                .compactMap { $0 }
                .joined(separator: " - ")
            }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "" }
        return ([title] + lines).joined(separator: "\n")
    }
}
