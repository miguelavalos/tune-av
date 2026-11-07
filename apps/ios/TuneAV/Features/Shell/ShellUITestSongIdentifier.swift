import Foundation

/// The identifier UI tests inject: no network, no ShazamKit, a scripted outcome after a short
/// listening pause so the listening state renders. The scenario comes from the launch context
/// (`TUNEAV_UI_TEST_SONG_IDENTIFICATION`).
struct ShellUITestSongIdentifier: TuneAVStreamSongIdentifying {
    enum Scenario: String {
        case match
        case noMatch
        case unsupported
        case unavailable
        case network
    }

    static let matchedTitle = "Midnight City"
    static let matchedArtist = "M83"

    let scenario: Scenario
    var listeningDelay: Duration = .milliseconds(900)

    init(scenario rawValue: String?) {
        scenario = rawValue.flatMap(Scenario.init(rawValue:)) ?? .unsupported
    }

    func identify(
        streamURL: URL,
        onStreamTitle: @escaping @Sendable (TuneAVTrackMetadata) -> Void
    ) async -> TuneAVStreamSongIdentification {
        try? await Task.sleep(for: listeningDelay)
        guard !Task.isCancelled else {
            return TuneAVStreamSongIdentification(outcome: .cancelled)
        }
        switch scenario {
        case .match:
            return TuneAVStreamSongIdentification(
                outcome: .matched(
                    TuneAVIdentifiedTrack(
                        title: Self.matchedTitle,
                        artist: Self.matchedArtist,
                        appleMusicID: "1440801220",
                        appleMusicURL: URL(string: "https://music.apple.com/album/midnight-city/1440801106?i=1440801220"),
                        artworkURL: nil,
                        shazamID: "53894392",
                        shazamWebURL: URL(string: "https://www.shazam.com/track/53894392/midnight-city"),
                        isrc: "GBAHT1100125",
                        matchOffset: 42
                    )
                ),
                elapsed: 0.9
            )
        case .noMatch:
            return TuneAVStreamSongIdentification(outcome: .noMatch, elapsed: 0.9)
        case .unsupported:
            return TuneAVStreamSongIdentification(outcome: .unsupportedStream(.container("fmp4")), elapsed: 0.9)
        case .unavailable:
            return TuneAVStreamSongIdentification(outcome: .unavailable(domain: "com.apple.ShazamCore", code: 102), elapsed: 0.9)
        case .network:
            return TuneAVStreamSongIdentification(outcome: .networkFailure, elapsed: 0.9)
        }
    }
}
