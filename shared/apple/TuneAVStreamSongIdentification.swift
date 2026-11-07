import AVFoundation
import Foundation

/// One song recognised from a radio stream by the catalog (ShazamKit). Everything the
/// player and the follow-ups (history, "save to Apple Music") need, nothing platform-bound.
struct TuneAVIdentifiedTrack: Equatable, Sendable {
    let title: String
    let artist: String?
    let appleMusicID: String?
    let appleMusicURL: URL?
    let artworkURL: URL?
    let shazamID: String?
    let shazamWebURL: URL?
    let isrc: String?
    /// Position in the song, in seconds, of the start of the captured window.
    let matchOffset: TimeInterval

    init(
        title: String,
        artist: String?,
        appleMusicID: String? = nil,
        appleMusicURL: URL? = nil,
        artworkURL: URL? = nil,
        shazamID: String? = nil,
        shazamWebURL: URL? = nil,
        isrc: String? = nil,
        matchOffset: TimeInterval = 0
    ) {
        self.title = title
        self.artist = artist
        self.appleMusicID = appleMusicID
        self.appleMusicURL = appleMusicURL
        self.artworkURL = artworkURL
        self.shazamID = shazamID
        self.shazamWebURL = shazamWebURL
        self.isrc = isrc
        self.matchOffset = matchOffset
    }
}

/// Why a stream cannot be identified. Not shown to the person; kept for logs and tests.
enum TuneAVStreamSongIdentificationUnsupportedReason: Equatable, Sendable {
    /// The stream URL is not `https`; App Transport Security blocks the second connection.
    case insecureURL
    /// The station answered with a status other than 200.
    case httpStatus(Int)
    /// The response is not an HTTP response.
    case notHTTP
    /// The container cannot be parsed (Ogg, fragmented MP4 segments, an unknown format).
    case container(String)
    /// The parser could not read any packets within the time budget.
    case undecodable
    /// The playlist has no usable variant or segment.
    case emptyPlaylist
    /// The decoder failed.
    case decodeFailed
}

enum TuneAVStreamSongIdentificationOutcome: Equatable, Sendable {
    case matched(TuneAVIdentifiedTrack)
    case noMatch
    case unsupportedStream(TuneAVStreamSongIdentificationUnsupportedReason)
    /// The catalog refused or failed (for example ShazamKit App Service not enabled, 102/401).
    case unavailable(domain: String, code: Int)
    case networkFailure
    case cancelled
}

struct TuneAVStreamSongIdentification: Equatable, Sendable {
    let outcome: TuneAVStreamSongIdentificationOutcome
    /// The last `StreamTitle` the station sent on the capture connection, parsed as artist/title.
    let streamTitle: TuneAVTrackMetadata?
    let elapsed: TimeInterval

    init(outcome: TuneAVStreamSongIdentificationOutcome, streamTitle: TuneAVTrackMetadata? = nil, elapsed: TimeInterval = 0) {
        self.outcome = outcome
        self.streamTitle = streamTitle
        self.elapsed = elapsed
    }
}

/// The identification service the UI talks to. The real one is `TuneAVStreamSongIdentifier`;
/// UI tests inject a scripted one.
protocol TuneAVStreamSongIdentifying: Sendable {
    /// Captures about twelve seconds of the stream at `streamURL`, never the microphone, and asks
    /// the catalog. `onStreamTitle` fires as soon as the station's own in-band title is read, so
    /// the UI can show it while the catalog answers.
    func identify(
        streamURL: URL,
        onStreamTitle: @escaping @Sendable (TuneAVTrackMetadata) -> Void
    ) async -> TuneAVStreamSongIdentification
}

/// A progressive stream opened by the transport: the HTTP response, the body chunks and a way to
/// close the connection once enough audio has arrived.
struct TuneAVOpenedStream: Sendable {
    let response: HTTPURLResponse
    let chunks: AsyncThrowingStream<Data, Error>
    let close: @Sendable () -> Void
}

/// The network layer of the identifier. Injected so unit tests feed recorded bytes.
protocol TuneAVStreamSongIdentifierTransport: Sendable {
    func openStream(_ request: URLRequest) async throws -> TuneAVOpenedStream
    func fetch(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse)
}

enum TuneAVSongMatchOutcome: Equatable, Sendable {
    case matched([TuneAVIdentifiedTrack])
    case noMatch
    case failed(domain: String, code: Int)
}

/// Decoded PCM ready for the signature generator: Float32, non-interleaved, at 48000, 44100,
/// 32000 or 16000 Hz, between 3 and 12 seconds. One identification creates it and hands it to the
/// matcher once; nothing else keeps the buffer, which is why the wrapper is marked Sendable.
struct TuneAVSignatureAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    var seconds: Double {
        guard buffer.format.sampleRate > 0 else { return 0 }
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    var sampleRate: Double {
        buffer.format.sampleRate
    }
}

/// The catalog call, behind a protocol so tests never reach ShazamKit.
protocol TuneAVSongSignatureMatching: Sendable {
    func match(_ audio: TuneAVSignatureAudio) async -> TuneAVSongMatchOutcome
}

enum TuneAVStreamSongIdentificationPolicy {
    /// Audio gathered before the catalog query. Servers burst their buffer on connect, so this
    /// usually arrives in well under a second.
    static let captureSeconds: Double = 12
    /// The catalog accepts 3.0 to 12.0 s; trim with a margin.
    static let signatureSeconds: Double = 11.9
    static let minimumSignatureSeconds: Double = 3
    /// From the first bytes, how long the parser gets to recognise the format.
    static let parserReadyTimeout: TimeInterval = 5
    /// End-to-end budget: connect, gather, decode and the catalog round trip.
    static let overallTimeout: TimeInterval = 25
    /// Safety cap on bytes read from one connection.
    static let maximumBytes = 6 * 1024 * 1024
    /// Sample rates `SHSignatureGenerator` accepts as they are.
    static let signatureSampleRates: Set<Double> = [48_000, 44_100, 32_000, 16_000]
    static let resampleRate: Double = 44_100

    /// Only `https` streams can be read by the second connection: the ATS media exception the
    /// player uses applies to AVFoundation, not to URLSession.
    static func supports(streamURL: URL) -> Bool {
        guard let scheme = streamURL.scheme?.lowercased() else { return false }
        return scheme == "https"
    }

    static func supports(streamURLString: String) -> Bool {
        guard let url = URL(string: streamURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return supports(streamURL: url)
    }

    /// Classifies a catalog failure for the UI: network trouble, silence (treated as no match) or
    /// a service refusal.
    static func outcome(forMatchFailureDomain domain: String, code: Int) -> TuneAVStreamSongIdentificationOutcome {
        if domain == NSURLErrorDomain {
            return .networkFailure
        }
        // SHErrorCode.signatureInvalid (200): nothing recognisable in the audio, same as no match.
        if domain == "com.apple.ShazamKit", code == 200 {
            return .noMatch
        }
        return .unavailable(domain: domain, code: code)
    }

    static func userAgent(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "TuneAV/\(version) (stream identification; +https://github.com/miguelavalos/tune-av)"
    }
}
