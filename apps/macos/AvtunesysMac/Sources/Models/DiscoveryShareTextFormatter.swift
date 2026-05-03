import Foundation

enum DiscoveryShareTextFormatter {
    static let title = "AV Tunesys discoveries"
    static let maxSharedDiscoveries = 25

    static func text(title trackTitle: String?, artist: String?, stationName: String) -> String {
        let trackText = [
            AVTunesysText.normalizedValue(artist),
            AVTunesysText.normalizedValue(trackTitle)
        ]
        .compactMap { $0 }
        .joined(separator: " - ")

        let normalizedStationName = AVTunesysText.normalizedValue(stationName) ?? stationName
        return trackText.isEmpty ? normalizedStationName : "\(trackText) · \(normalizedStationName)"
    }

    static func text(for discoveries: [DiscoveredTrack]) -> String {
        let lines = discoveries
            .filter { !$0.isHidden }
            .prefix(maxSharedDiscoveries)
            .map { discovery in
                [
                    AVTunesysText.normalizedValue(discovery.artist),
                    AVTunesysText.normalizedValue(discovery.title)
                ]
                .compactMap { $0 }
                .joined(separator: " - ")
            }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "" }
        return ([title] + lines).joined(separator: "\n")
    }
}
