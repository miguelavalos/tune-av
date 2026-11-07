import AudioToolbox
import AVFoundation
import Foundation
import ShazamKit

/// Identifies the song a radio stream is playing from the stream itself, never the microphone,
/// and never through the player: a second connection reads about twelve seconds of the station's
/// audio, decodes them and asks the ShazamKit catalog with the resulting signature.
///
/// Progressive Icecast/Shoutcast streams (MP3, AAC-LC, HE-AAC) and HLS with ADTS or MPEG-TS
/// segments are supported; fragmented-MP4 segments, Ogg and `http` URLs are reported as
/// unsupported. One identification runs at a time.
actor TuneAVStreamSongIdentifier: TuneAVStreamSongIdentifying {
    private let transport: any TuneAVStreamSongIdentifierTransport
    private let matcher: any TuneAVSongSignatureMatching
    private let userAgent: String
    private let overallTimeout: TimeInterval

    init(
        transport: any TuneAVStreamSongIdentifierTransport = TuneAVURLSessionStreamTransport(),
        matcher: any TuneAVSongSignatureMatching = TuneAVShazamKitSignatureMatcher(),
        userAgent: String = TuneAVStreamSongIdentificationPolicy.userAgent(),
        overallTimeout: TimeInterval = TuneAVStreamSongIdentificationPolicy.overallTimeout
    ) {
        self.transport = transport
        self.matcher = matcher
        self.userAgent = userAgent
        self.overallTimeout = overallTimeout
    }

    func identify(
        streamURL: URL,
        onStreamTitle: @escaping @Sendable (TuneAVTrackMetadata) -> Void
    ) async -> TuneAVStreamSongIdentification {
        let startedAt = Date()
        let capture = Capture()
        let outcome: TuneAVStreamSongIdentificationOutcome

        do {
            outcome = try await withDeadline(overallTimeout) {
                let audio = try await self.captureSignatureAudio(from: streamURL, capture: capture, onStreamTitle: onStreamTitle)
                try Task.checkCancellation()
                let match = await self.matcher.match(audio)
                try Task.checkCancellation()
                return Self.outcome(for: match)
            }
        } catch is CancellationError {
            outcome = .cancelled
        } catch let failure as CaptureFailure {
            outcome = failure.outcome
        } catch {
            outcome = Self.outcome(forTransportError: error)
        }

        return TuneAVStreamSongIdentification(
            outcome: outcome,
            streamTitle: capture.streamTitle,
            elapsed: Date().timeIntervalSince(startedAt)
        )
    }

    // MARK: - Capture

    /// The stream title read on the capture connection, published as it arrives.
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var _streamTitle: TuneAVTrackMetadata?

        var streamTitle: TuneAVTrackMetadata? {
            lock.lock()
            defer { lock.unlock() }
            return _streamTitle
        }

        func noteStreamTitle(_ rawValue: String, onStreamTitle: @Sendable (TuneAVTrackMetadata) -> Void) {
            let parsed = TuneAVTrackMetadataParser.parse(rawValue)
            guard parsed.title != nil || parsed.artist != nil else { return }
            lock.lock()
            let changed = _streamTitle != parsed
            _streamTitle = parsed
            lock.unlock()
            if changed {
                onStreamTitle(parsed)
            }
        }
    }

    private enum CaptureFailure: Error {
        case unsupported(TuneAVStreamSongIdentificationUnsupportedReason)
        case timedOut

        var outcome: TuneAVStreamSongIdentificationOutcome {
            switch self {
            case .unsupported(let reason):
                return .unsupportedStream(reason)
            case .timedOut:
                return .networkFailure
            }
        }
    }

    private func captureSignatureAudio(
        from streamURL: URL,
        capture: Capture,
        onStreamTitle: @escaping @Sendable (TuneAVTrackMetadata) -> Void,
        playlistHops: Int = 0
    ) async throws -> TuneAVSignatureAudio {
        guard TuneAVStreamSongIdentificationPolicy.supports(streamURL: streamURL) else {
            throw CaptureFailure.unsupported(.insecureURL)
        }

        if Self.looksLikePlaylist(streamURL) {
            return try await captureFromPlaylist(at: streamURL, capture: capture, onStreamTitle: onStreamTitle, hops: playlistHops)
        }

        let opened = try await transport.openStream(makeStreamRequest(for: streamURL))
        let response = opened.response
        guard response.statusCode == 200 else {
            opened.close()
            throw CaptureFailure.unsupported(.httpStatus(response.statusCode))
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        if TuneAVStreamContainer.isPlaylistContentType(contentType) || Self.looksLikePlaylist(response.url ?? streamURL) {
            let text = try await Self.readWholeBody(opened.chunks, limit: 256 * 1024)
            opened.close()
            return try await captureFromPlaylistText(
                text,
                base: response.url ?? streamURL,
                capture: capture,
                onStreamTitle: onStreamTitle,
                hops: playlistHops
            )
        }
        if TuneAVStreamContainer.isUnsupportedContentType(contentType) {
            opened.close()
            throw CaptureFailure.unsupported(.container(contentType ?? "unknown"))
        }

        let metadataInterval = response.value(forHTTPHeaderField: "icy-metaint")
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let stripper = metadataInterval.flatMap { $0 > 0 ? TuneAVICYMetadataStripper(metadataInterval: $0) : nil }
        let parser = TuneAVStreamPacketParser(
            typeHint: TuneAVStreamContainer.audioFileTypeHint(contentType: contentType, url: response.url ?? streamURL)
        )

        defer { opened.close() }
        var firstBytesAt: Date?
        var bytesRead = 0
        var prefix = Data()

        for try await chunk in opened.chunks {
            try Task.checkCancellation()
            if firstBytesAt == nil {
                firstBytesAt = Date()
            }
            bytesRead += chunk.count

            let audio = stripper?.strip(chunk) ?? chunk
            if let title = stripper?.takeNewTitle() {
                capture.noteStreamTitle(title, onStreamTitle: onStreamTitle)
            }

            if !parser.isReady, prefix.count < 16 {
                prefix.append(audio.prefix(16 - prefix.count))
                if prefix.count >= 8 {
                    switch TuneAVStreamContainer.sniff(prefix) {
                    case .ogg:
                        throw CaptureFailure.unsupported(.container("ogg"))
                    case .fragmentedMP4:
                        throw CaptureFailure.unsupported(.container("fmp4"))
                    default:
                        break
                    }
                }
            }

            parser.feed(audio)
            if parser.parseError != noErr {
                throw CaptureFailure.unsupported(.undecodable)
            }
            if parser.isReady, parser.secondsGathered >= TuneAVStreamSongIdentificationPolicy.captureSeconds {
                break
            }
            if let firstBytesAt, !parser.isReady,
               Date().timeIntervalSince(firstBytesAt) > TuneAVStreamSongIdentificationPolicy.parserReadyTimeout {
                throw CaptureFailure.unsupported(.undecodable)
            }
            if bytesRead > TuneAVStreamSongIdentificationPolicy.maximumBytes {
                throw CaptureFailure.unsupported(.undecodable)
            }
        }
        try Task.checkCancellation()

        return try Self.signatureAudio(from: parser)
    }

    private func captureFromPlaylist(
        at url: URL,
        capture: Capture,
        onStreamTitle: @escaping @Sendable (TuneAVTrackMetadata) -> Void,
        hops: Int
    ) async throws -> TuneAVSignatureAudio {
        let (data, response) = try await transport.fetch(makeFetchRequest(for: url))
        guard response.statusCode == 200 else {
            throw CaptureFailure.unsupported(.httpStatus(response.statusCode))
        }
        return try await captureFromPlaylistText(
            String(decoding: data, as: UTF8.self),
            base: response.url ?? url,
            capture: capture,
            onStreamTitle: onStreamTitle,
            hops: hops
        )
    }

    private func captureFromPlaylistText(
        _ text: String,
        base: URL,
        capture: Capture,
        onStreamTitle: @escaping @Sendable (TuneAVTrackMetadata) -> Void,
        hops: Int
    ) async throws -> TuneAVSignatureAudio {
        guard hops < 3 else { throw CaptureFailure.unsupported(.emptyPlaylist) }

        switch TuneAVHLSPlaylist.kind(of: text) {
        case .master:
            guard let variant = TuneAVHLSPlaylist.preferredVariant(TuneAVHLSPlaylist.variants(in: text, base: base)) else {
                throw CaptureFailure.unsupported(.emptyPlaylist)
            }
            return try await captureFromPlaylist(at: variant.url, capture: capture, onStreamTitle: onStreamTitle, hops: hops + 1)
        case .media:
            return try await captureSegments(TuneAVHLSPlaylist.segments(in: text, base: base))
        case .simple:
            guard let streamURL = TuneAVHLSPlaylist.firstStreamURL(inSimplePlaylist: text, base: base) else {
                throw CaptureFailure.unsupported(.emptyPlaylist)
            }
            return try await captureSignatureAudio(from: streamURL, capture: capture, onStreamTitle: onStreamTitle, playlistHops: hops + 1)
        case .unknown:
            throw CaptureFailure.unsupported(.emptyPlaylist)
        }
    }

    private func captureSegments(_ segments: [TuneAVHLSSegment]) async throws -> TuneAVSignatureAudio {
        let chosen = TuneAVHLSPlaylist.trailingSegments(segments, targetSeconds: TuneAVStreamSongIdentificationPolicy.captureSeconds)
        guard !chosen.isEmpty else { throw CaptureFailure.unsupported(.emptyPlaylist) }

        var payload = Data()
        for segment in chosen {
            try Task.checkCancellation()
            let (data, response) = try await transport.fetch(makeFetchRequest(for: segment.url))
            guard response.statusCode == 200 else {
                throw CaptureFailure.unsupported(.httpStatus(response.statusCode))
            }
            payload.append(data)
        }

        let container = TuneAVStreamContainer.sniff(payload)
        var hint: AudioFileTypeID = container.audioFileTypeHint
        switch container {
        case .mpegTransportStream:
            payload = TuneAVMPEGTransportStreamDemuxer.demux(payload)
            hint = TuneAVStreamContainer.sniff(payload).audioFileTypeHint
        case .fragmentedMP4:
            throw CaptureFailure.unsupported(.container("fmp4"))
        case .ogg:
            throw CaptureFailure.unsupported(.container("ogg"))
        case .adts, .mp3, .id3, .unknown:
            break
        }

        let parser = TuneAVStreamPacketParser(typeHint: hint)
        parser.feed(payload)
        guard parser.parseError == noErr else { throw CaptureFailure.unsupported(.undecodable) }
        return try Self.signatureAudio(from: parser)
    }

    private static func signatureAudio(from parser: TuneAVStreamPacketParser) throws -> TuneAVSignatureAudio {
        guard parser.hasPackets else { throw CaptureFailure.unsupported(.undecodable) }
        let buffer: AVAudioPCMBuffer
        do {
            buffer = try TuneAVStreamAudioDecoder.signatureBuffer(from: parser)
        } catch {
            throw CaptureFailure.unsupported(.decodeFailed)
        }
        let audio = TuneAVSignatureAudio(buffer: buffer)
        guard audio.seconds >= TuneAVStreamSongIdentificationPolicy.minimumSignatureSeconds else {
            throw CaptureFailure.unsupported(.undecodable)
        }
        return audio
    }

    // MARK: - Requests

    private func makeStreamRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        return request
    }

    private func makeFetchRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }

    private static func looksLikePlaylist(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".m3u8") || path.hasSuffix(".m3u") || path.hasSuffix(".pls")
    }

    private static func readWholeBody(_ chunks: AsyncThrowingStream<Data, Error>, limit: Int) async throws -> String {
        var body = Data()
        for try await chunk in chunks {
            body.append(chunk)
            if body.count > limit {
                break
            }
        }
        return String(decoding: body, as: UTF8.self)
    }

    private func withDeadline<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CaptureFailure.timedOut
            }
            guard let first = try await group.next() else { throw CaptureFailure.timedOut }
            group.cancelAll()
            return first
        }
    }

    // MARK: - Outcomes

    private static func outcome(for match: TuneAVSongMatchOutcome) -> TuneAVStreamSongIdentificationOutcome {
        switch match {
        case .matched(let tracks):
            guard let first = tracks.first else { return .noMatch }
            return .matched(first)
        case .noMatch:
            return .noMatch
        case .failed(let domain, let code):
            return TuneAVStreamSongIdentificationPolicy.outcome(forMatchFailureDomain: domain, code: code)
        }
    }

    private static func outcome(forTransportError error: Error) -> TuneAVStreamSongIdentificationOutcome {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return .unsupportedStream(.insecureURL)
        }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        return .networkFailure
    }
}

// MARK: - URLSession transport

/// The real network layer: an ephemeral session per connection, no cache, closed as soon as the
/// capture has enough audio.
final class TuneAVURLSessionStreamTransport: TuneAVStreamSongIdentifierTransport {
    private let fetchSession: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        fetchSession = URLSession(configuration: configuration)
    }

    func openStream(_ request: URLRequest) async throws -> TuneAVOpenedStream {
        let handler = StreamHandler()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = TuneAVStreamSongIdentificationPolicy.overallTimeout + 5
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: handler, delegateQueue: nil)
        let task = session.dataTask(with: request)

        let (chunks, continuation) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .unbounded)
        handler.chunkContinuation = continuation
        let close: @Sendable () -> Void = {
            task.cancel()
            session.invalidateAndCancel()
        }
        continuation.onTermination = { _ in close() }

        do {
            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (responseContinuation: CheckedContinuation<HTTPURLResponse, Error>) in
                    handler.responseContinuation = responseContinuation
                    task.resume()
                }
            } onCancel: {
                close()
            }
            return TuneAVOpenedStream(response: response, chunks: chunks, close: close)
        } catch {
            close()
            throw error
        }
    }

    func fetch(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let (data, response) = try await fetchSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private final class StreamHandler: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var _responseContinuation: CheckedContinuation<HTTPURLResponse, Error>?
        private var _chunkContinuation: AsyncThrowingStream<Data, Error>.Continuation?

        var responseContinuation: CheckedContinuation<HTTPURLResponse, Error>? {
            get { lock.lock(); defer { lock.unlock() }; return _responseContinuation }
            set { lock.lock(); defer { lock.unlock() }; _responseContinuation = newValue }
        }

        var chunkContinuation: AsyncThrowingStream<Data, Error>.Continuation? {
            get { lock.lock(); defer { lock.unlock() }; return _chunkContinuation }
            set { lock.lock(); defer { lock.unlock() }; _chunkContinuation = newValue }
        }

        private func takeResponseContinuation() -> CheckedContinuation<HTTPURLResponse, Error>? {
            lock.lock()
            defer { lock.unlock() }
            let continuation = _responseContinuation
            _responseContinuation = nil
            return continuation
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let http = response as? HTTPURLResponse else {
                takeResponseContinuation()?.resume(throwing: URLError(.badServerResponse))
                completionHandler(.cancel)
                return
            }
            takeResponseContinuation()?.resume(returning: http)
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            chunkContinuation?.yield(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                takeResponseContinuation()?.resume(throwing: error)
                if (error as NSError).code == NSURLErrorCancelled {
                    chunkContinuation?.finish()
                } else {
                    chunkContinuation?.finish(throwing: error)
                }
            } else {
                takeResponseContinuation()?.resume(throwing: URLError(.badServerResponse))
                chunkContinuation?.finish()
            }
            chunkContinuation = nil
        }
    }
}

// MARK: - ShazamKit

/// Builds the signature with `SHSignatureGenerator` and asks the catalog through `SHSession`.
/// Only the signature (a few kilobytes of spectral peaks) leaves the device, never raw audio.
struct TuneAVShazamKitSignatureMatcher: TuneAVSongSignatureMatching {
    func match(_ audio: TuneAVSignatureAudio) async -> TuneAVSongMatchOutcome {
        let generator = SHSignatureGenerator()
        do {
            try generator.append(audio.buffer, at: nil)
        } catch {
            let nsError = error as NSError
            return .failed(domain: nsError.domain, code: nsError.code)
        }

        let signature = generator.signature()
        let session = SHSession()
        let result = await session.result(from: signature)
        switch result {
        case .match(let match):
            return .matched(match.mediaItems.map(TuneAVIdentifiedTrack.init(mediaItem:)))
        case .noMatch:
            return .noMatch
        case .error(let error, _):
            let nsError = error as NSError
            return .failed(domain: nsError.domain, code: nsError.code)
        @unknown default:
            return .failed(domain: "com.apple.ShazamKit", code: -1)
        }
    }
}

extension TuneAVIdentifiedTrack {
    init(mediaItem item: SHMatchedMediaItem) {
        self.init(
            title: item.title ?? "",
            artist: item.artist,
            appleMusicID: item.appleMusicID,
            appleMusicURL: item.appleMusicURL,
            artworkURL: item.artworkURL,
            shazamID: item.shazamID,
            shazamWebURL: item.webURL,
            isrc: item.isrc,
            matchOffset: item.matchOffset
        )
    }
}
