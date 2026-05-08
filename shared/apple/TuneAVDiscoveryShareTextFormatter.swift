import Foundation

protocol TuneAVDiscoveryShareItem {
    var title: String { get }
    var artist: String? { get }
    var stationName: String { get }
    var isHidden: Bool { get }
}

enum TuneAVDiscoveryShareTextFormatter {
    static let maxSharedDiscoveries = 25

    static func currentTrackText(title trackTitle: String?, artist: String?, stationName: String) -> String {
        let trackText = [
            TuneAVText.normalizedValue(artist),
            TuneAVText.normalizedValue(trackTitle)
        ]
        .compactMap { $0 }
        .joined(separator: " - ")

        let normalizedStationName = TuneAVText.normalizedValue(stationName) ?? stationName
        return trackText.isEmpty ? normalizedStationName : "\(trackText) · \(normalizedStationName)"
    }

    static func listText(title: String, discoveries: [any TuneAVDiscoveryShareItem]) -> String {
        let lines = discoveries
            .filter { !$0.isHidden }
            .prefix(maxSharedDiscoveries)
            .map(lineText(for:))
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "" }
        return ([title] + lines).joined(separator: "\n")
    }

    private static func lineText(for discovery: any TuneAVDiscoveryShareItem) -> String {
        [
            TuneAVText.normalizedValue(discovery.artist),
            TuneAVText.normalizedValue(discovery.title),
            TuneAVText.normalizedValue(discovery.stationName)
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }
}
