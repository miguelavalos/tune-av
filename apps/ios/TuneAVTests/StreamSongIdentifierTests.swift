import AudioToolbox
import AVFoundation
import XCTest
@testable import TuneAV

/// The "What's playing?" pipeline on recorded stream bytes: ICY stripping, `AudioFileStream`
/// parsing, decoding, HLS playlists, MPEG-TS demuxing and the identifier's outcomes with a fake
/// transport and a fake catalog. No network and no ShazamKit call runs here.
final class StreamSongIdentifierTests: XCTestCase {
    private static let streamTitle = "Whitney Houston - Didn't We Almost Have It All"
    private static let streamURL = URL(string: "https://radio.example.test/live.mp3")!

    // MARK: - Fixtures

    private func fixture(_ name: String, _ fileExtension: String) throws -> Data {
        let bundle = Bundle(for: StreamSongIdentifierTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: fileExtension), "missing fixture \(name).\(fileExtension)")
        return try Data(contentsOf: url)
    }

    private func mp3Fixture() throws -> Data { try fixture("stream-mp3-3s", "mp3") }
    private func aacFixture() throws -> Data { try fixture("stream-aac-lc-3s", "aac") }
    private func heAACFixture() throws -> Data { try fixture("stream-he-aac-3s", "aac") }

    /// Six seconds of MP3: the three-second fixture twice, so the decoded audio clears the
    /// catalog's three-second minimum after the decoder's priming frames.
    private func sixSecondMP3() throws -> Data {
        let fixture = try mp3Fixture()
        return fixture + fixture
    }

    /// Interleaves ICY metadata blocks every `interval` audio bytes, the way an Icecast server does
    /// for a client that sent `Icy-MetaData: 1`. The first block carries the title.
    private func icyWrapped(_ audio: Data, interval: Int, title: String) -> Data {
        var output = Data()
        var offset = 0
        var isFirstBlock = true
        while offset < audio.count {
            let count = min(interval, audio.count - offset)
            output.append(audio[offset ..< offset + count])
            offset += count
            guard count == interval else { break }
            if isFirstBlock {
                let text = "StreamTitle='\(title)';StreamUrl='';"
                var block = Array(text.utf8)
                let padded = (block.count + 15) / 16 * 16
                block.append(contentsOf: [UInt8](repeating: 0, count: padded - block.count))
                output.append(UInt8(padded / 16))
                output.append(contentsOf: block)
                isFirstBlock = false
            } else {
                output.append(0)
            }
        }
        return output
    }

    private func chunks(_ data: Data, size: Int) -> [Data] {
        stride(from: 0, to: data.count, by: size).map { start in
            data[start ..< min(start + size, data.count)]
        }
    }

    private func parse(_ data: Data, hint: AudioFileTypeID) -> TuneAVStreamPacketParser {
        let parser = TuneAVStreamPacketParser(typeHint: hint)
        for chunk in chunks(data, size: 3000) {
            parser.feed(chunk)
        }
        return parser
    }

    // MARK: - ICY stripper

    func testICYStripperRemovesMetadataAndKeepsTitle() throws {
        let audio = Data((0 ..< 10_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let wrapped = icyWrapped(audio, interval: 1000, title: Self.streamTitle)
        XCTAssertGreaterThan(wrapped.count, audio.count)

        let stripper = TuneAVICYMetadataStripper(metadataInterval: 1000)
        var recovered = Data()
        for chunk in chunks(wrapped, size: 777) {
            recovered.append(stripper.strip(chunk))
        }

        XCTAssertEqual(recovered, audio)
        XCTAssertEqual(stripper.titles, [Self.streamTitle])
        XCTAssertEqual(stripper.metadataBlockCount, 10, "one block after each full interval, the first with the title and the rest empty")
        XCTAssertEqual(stripper.takeNewTitle(), Self.streamTitle)
        XCTAssertNil(stripper.takeNewTitle())
    }

    func testICYStripperReadsBlockSplitAcrossChunks() {
        let audio = Data(repeating: 0xAB, count: 64)
        let wrapped = icyWrapped(audio, interval: 16, title: "Artist - Song")
        let stripper = TuneAVICYMetadataStripper(metadataInterval: 16)
        var recovered = Data()
        for chunk in chunks(wrapped, size: 5) {
            recovered.append(stripper.strip(chunk))
        }
        XCTAssertEqual(recovered, audio)
        XCTAssertEqual(stripper.latestTitle, "Artist - Song")
    }

    // MARK: - Parser and decoder

    func testMP3FixtureParsesAndDecodesAtTheCodecRate() throws {
        let parser = parse(try mp3Fixture(), hint: kAudioFileMP3Type)

        XCTAssertEqual(parser.parseError, noErr)
        XCTAssertTrue(parser.isReady)
        XCTAssertEqual(parser.chosenFormat.mFormatID, kAudioFormatMPEGLayer3)
        XCTAssertEqual(parser.chosenFormat.mSampleRate, 44_100)
        XCTAssertEqual(parser.chosenFormat.mChannelsPerFrame, 2)
        XCTAssertEqual(parser.secondsGathered, 3, accuracy: 0.1)

        let pcm = try TuneAVStreamAudioDecoder.decode(parser)
        XCTAssertEqual(pcm.format.sampleRate, 44_100)
        XCTAssertEqual(pcm.format.channelCount, 2)
        XCTAssertEqual(pcm.format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(TuneAVStreamAudioDecoder.seconds(of: pcm), 3, accuracy: 0.15)
        XCTAssertGreaterThan(peak(of: pcm), 0.05, "decoded audio should not be silent")
    }

    func testADTSFixtureParsesAndDecodes() throws {
        let parser = parse(try aacFixture(), hint: kAudioFileAAC_ADTSType)

        XCTAssertEqual(parser.parseError, noErr)
        XCTAssertEqual(parser.chosenFormat.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(parser.chosenFormat.mSampleRate, 44_100)
        XCTAssertNotNil(parser.magicCookie)
        XCTAssertEqual(parser.secondsGathered, 3, accuracy: 0.1)

        let pcm = try TuneAVStreamAudioDecoder.decode(parser)
        XCTAssertEqual(pcm.format.sampleRate, 44_100)
        XCTAssertEqual(TuneAVStreamAudioDecoder.seconds(of: pcm), 3, accuracy: 0.15)
        XCTAssertGreaterThan(peak(of: pcm), 0.05)
    }

    func testHEAACFixtureDecodesAtTheFullRate() throws {
        let parser = parse(try heAACFixture(), hint: kAudioFileAAC_ADTSType)

        XCTAssertEqual(parser.parseError, noErr)
        XCTAssertEqual(parser.dataFormat.mSampleRate, 22_050, "the core AAC layer runs at half rate")
        XCTAssertEqual(parser.chosenFormat.mFormatID, kAudioFormatMPEG4AAC_HE)
        XCTAssertEqual(parser.chosenFormat.mSampleRate, 44_100, "the first playable format list entry is HE-AAC at 44.1 kHz")
        XCTAssertEqual(parser.secondsGathered, 3, accuracy: 0.1)

        let pcm = try TuneAVStreamAudioDecoder.decode(parser)
        XCTAssertEqual(pcm.format.sampleRate, 44_100)
        XCTAssertEqual(TuneAVStreamAudioDecoder.seconds(of: pcm), 3, accuracy: 0.2)
        XCTAssertGreaterThan(peak(of: pcm), 0.05)
    }

    func testParserRejectsGarbage() {
        let parser = TuneAVStreamPacketParser(typeHint: 0)
        parser.feed(Data((0 ..< 20_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }))
        XCTAssertFalse(parser.hasPackets)
    }

    func testTrimKeepsAtMostTheSignatureLength() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false))
        let long = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100 * 14))
        long.frameLength = 44_100 * 14

        let trimmed = TuneAVStreamAudioDecoder.trimmed(long, seconds: 11.9)
        XCTAssertEqual(TuneAVStreamAudioDecoder.seconds(of: trimmed), 11.9, accuracy: 0.001)

        let short = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100 * 5))
        short.frameLength = 44_100 * 5
        XCTAssertTrue(TuneAVStreamAudioDecoder.trimmed(short, seconds: 11.9) === short)
    }

    func testResampleProducesTheRequestedRate() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22_050, channels: 2, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050 * 4))
        buffer.frameLength = 22_050 * 4
        for channel in 0 ..< 2 {
            for frame in 0 ..< Int(buffer.frameLength) {
                buffer.floatChannelData![channel][frame] = sinf(Float(frame) * 0.05)
            }
        }

        let resampled = try TuneAVStreamAudioDecoder.resample(buffer, to: 44_100)
        XCTAssertEqual(resampled.format.sampleRate, 44_100)
        XCTAssertEqual(TuneAVStreamAudioDecoder.seconds(of: resampled), 4, accuracy: 0.05)
        XCTAssertGreaterThan(peak(of: resampled), 0.5)
    }

    func testSignatureBufferIsTrimmedAndAtAnAcceptedRate() throws {
        let parser = parse(try sixSecondMP3(), hint: kAudioFileMP3Type)
        let buffer = try TuneAVStreamAudioDecoder.signatureBuffer(from: parser)
        XCTAssertTrue(TuneAVStreamSongIdentificationPolicy.signatureSampleRates.contains(buffer.format.sampleRate))
        XCTAssertLessThanOrEqual(TuneAVStreamAudioDecoder.seconds(of: buffer), TuneAVStreamSongIdentificationPolicy.signatureSeconds)
        XCTAssertGreaterThanOrEqual(TuneAVStreamAudioDecoder.seconds(of: buffer), TuneAVStreamSongIdentificationPolicy.minimumSignatureSeconds)
    }

    // MARK: - Containers

    func testContainerSniffing() throws {
        XCTAssertEqual(TuneAVStreamContainer.sniff(try mp3Fixture()), .mp3)
        XCTAssertEqual(TuneAVStreamContainer.sniff(try aacFixture()), .adts)
        XCTAssertEqual(TuneAVStreamContainer.sniff(Data([0x49, 0x44, 0x33, 0x04, 0x00])), .id3)
        XCTAssertEqual(TuneAVStreamContainer.sniff(Data([0, 0, 0, 0x18] + Array("ftypiso5".utf8))), .fragmentedMP4)
        XCTAssertEqual(TuneAVStreamContainer.sniff(Data([0, 0, 0, 0x18] + Array("stypmsdh".utf8))), .fragmentedMP4)
        XCTAssertEqual(TuneAVStreamContainer.sniff(Data(Array("OggS".utf8) + [0, 2])), .ogg)
        XCTAssertEqual(TuneAVStreamContainer.sniff(transportStream(wrapping: Data(repeating: 1, count: 400))), .mpegTransportStream)
        XCTAssertEqual(TuneAVStreamContainer.sniff(Data([1, 2])), .unknown)
        let plainURL = URL(string: "https://radio.example.test/live")!
        XCTAssertEqual(TuneAVStreamContainer.audioFileTypeHint(contentType: "audio/mpeg", url: plainURL), kAudioFileMP3Type)
        XCTAssertEqual(TuneAVStreamContainer.audioFileTypeHint(contentType: "audio/aacp", url: plainURL), kAudioFileAAC_ADTSType)
        XCTAssertEqual(TuneAVStreamContainer.audioFileTypeHint(contentType: "audio/aacp", url: Self.streamURL), kAudioFileMP3Type, "a .mp3 path wins over a wrong content type")
        XCTAssertEqual(TuneAVStreamContainer.audioFileTypeHint(contentType: nil, url: URL(string: "https://x.test/a.aac")!), kAudioFileAAC_ADTSType)
        XCTAssertEqual(TuneAVStreamContainer.audioFileTypeHint(contentType: "application/octet-stream", url: URL(string: "https://x.test/live")!), 0)
        XCTAssertTrue(TuneAVStreamContainer.isPlaylistContentType("application/vnd.apple.mpegurl"))
        XCTAssertTrue(TuneAVStreamContainer.isPlaylistContentType("audio/x-mpegurl"))
        XCTAssertFalse(TuneAVStreamContainer.isPlaylistContentType("audio/mpeg"))
        XCTAssertTrue(TuneAVStreamContainer.isUnsupportedContentType("application/ogg"))
        XCTAssertFalse(TuneAVStreamContainer.isUnsupportedContentType("audio/aac"))
    }

    // MARK: - HLS playlists

    func testHLSMasterPlaylistVariantsPreferAudioOnlyLowestBandwidth() throws {
        let base = URL(string: "https://cdn.example.test/radio/master.m3u8")!
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=640x360
        video/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"
        aac_128/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.5"

        https://other.example.test/aac_64/index.m3u8
        """
        XCTAssertEqual(TuneAVHLSPlaylist.kind(of: text), .master)
        let variants = TuneAVHLSPlaylist.variants(in: text, base: base)
        XCTAssertEqual(variants.count, 3)
        XCTAssertEqual(variants[0].url.absoluteString, "https://cdn.example.test/radio/video/index.m3u8")
        XCTAssertFalse(variants[0].isAudioOnly)
        XCTAssertEqual(variants[1].bandwidth, 128_000)
        XCTAssertEqual(variants[2].url.absoluteString, "https://other.example.test/aac_64/index.m3u8")

        let preferred = try XCTUnwrap(TuneAVHLSPlaylist.preferredVariant(variants))
        XCTAssertEqual(preferred.bandwidth, 64_000)

        let unmarked = [
            TuneAVHLSVariant(url: base, bandwidth: nil, codecs: nil),
            TuneAVHLSVariant(url: base.appendingPathComponent("b"), bandwidth: 1, codecs: nil)
        ]
        XCTAssertEqual(TuneAVHLSPlaylist.preferredVariant(unmarked)?.url, base, "without bandwidth on every variant the first listed wins")
        XCTAssertNil(TuneAVHLSPlaylist.preferredVariant([]))
    }

    func testHLSMediaPlaylistSegmentsAndTrailingSelection() {
        let base = URL(string: "https://cdn.example.test/radio/aac_128/index.m3u8")!
        let text = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:4132
        #EXTINF:5.000,
        seg4132.aac
        #EXTINF:5.000,title="show info"
        seg4133.aac
        #EXTINF:5.000,
        seg4134.aac
        #EXTINF:5.000,
        seg4135.aac
        """
        XCTAssertEqual(TuneAVHLSPlaylist.kind(of: text), .media)
        let segments = TuneAVHLSPlaylist.segments(in: text, base: base)
        XCTAssertEqual(segments.map(\.url.lastPathComponent), ["seg4132.aac", "seg4133.aac", "seg4134.aac", "seg4135.aac"])
        XCTAssertEqual(segments.map(\.duration), [5, 5, 5, 5])
        XCTAssertEqual(segments[0].url.absoluteString, "https://cdn.example.test/radio/aac_128/seg4132.aac")

        let trailing = TuneAVHLSPlaylist.trailingSegments(segments, targetSeconds: 12)
        XCTAssertEqual(trailing.map(\.url.lastPathComponent), ["seg4133.aac", "seg4134.aac", "seg4135.aac"])
        XCTAssertEqual(TuneAVHLSPlaylist.trailingSegments(segments, targetSeconds: 100).count, 4)
        XCTAssertTrue(TuneAVHLSPlaylist.trailingSegments([], targetSeconds: 12).isEmpty)
    }

    func testSimplePlaylistsYieldTheirFirstStreamURL() {
        let base = URL(string: "https://radio.example.test/listen.pls")!
        let pls = """
        [playlist]
        NumberOfEntries=2
        File1=https://ice.example.test/stream.mp3
        Title1=Example Radio
        File2=https://ice2.example.test/stream.mp3
        """
        XCTAssertEqual(TuneAVHLSPlaylist.kind(of: pls), .simple)
        XCTAssertEqual(TuneAVHLSPlaylist.firstStreamURL(inSimplePlaylist: pls, base: base)?.absoluteString, "https://ice.example.test/stream.mp3")

        let m3u = "#EXTM3U\nhttps://ice.example.test/live\n"
        XCTAssertEqual(TuneAVHLSPlaylist.kind(of: m3u), .simple)
        XCTAssertEqual(TuneAVHLSPlaylist.firstStreamURL(inSimplePlaylist: m3u, base: base)?.absoluteString, "https://ice.example.test/live")

        XCTAssertEqual(TuneAVHLSPlaylist.kind(of: "<html>not a playlist</html>"), .unknown)
    }

    // MARK: - MPEG-TS

    func testTransportStreamDemuxRecoversTheElementaryStream() throws {
        let elementary = try aacFixture()
        let transport = transportStream(wrapping: elementary)
        XCTAssertEqual(transport.count % 188, 0)

        let demuxed = TuneAVMPEGTransportStreamDemuxer.demux(transport)
        XCTAssertEqual(demuxed, elementary)

        let parser = parse(demuxed, hint: kAudioFileAAC_ADTSType)
        XCTAssertEqual(parser.secondsGathered, 3, accuracy: 0.1)
    }

    func testTransportStreamDemuxIgnoresStreamsWithoutAudio() {
        XCTAssertTrue(TuneAVMPEGTransportStreamDemuxer.demux(Data(repeating: 0x47, count: 188 * 3)).isEmpty)
        XCTAssertTrue(TuneAVMPEGTransportStreamDemuxer.demux(Data()).isEmpty)
    }

    // MARK: - Policy

    func testPolicySupportsOnlySecureStreamURLs() {
        XCTAssertTrue(TuneAVStreamSongIdentificationPolicy.supports(streamURLString: "https://ice6.somafm.com/indiepop-128-aac"))
        XCTAssertTrue(TuneAVStreamSongIdentificationPolicy.supports(streamURLString: " https://media-ssl.musicradio.com/Heart80sMP3 "))
        XCTAssertFalse(TuneAVStreamSongIdentificationPolicy.supports(streamURLString: "http://stream.example.test/live"))
        XCTAssertFalse(TuneAVStreamSongIdentificationPolicy.supports(streamURLString: ""))
        XCTAssertFalse(TuneAVStreamSongIdentificationPolicy.supports(streamURLString: "not a url"))
    }

    func testMatchFailureClassification() {
        XCTAssertEqual(TuneAVStreamSongIdentificationPolicy.outcome(forMatchFailureDomain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), .networkFailure)
        XCTAssertEqual(TuneAVStreamSongIdentificationPolicy.outcome(forMatchFailureDomain: "com.apple.ShazamKit", code: 200), .noMatch)
        XCTAssertEqual(
            TuneAVStreamSongIdentificationPolicy.outcome(forMatchFailureDomain: "com.apple.ShazamCore", code: 102),
            .unavailable(domain: "com.apple.ShazamCore", code: 102)
        )
        XCTAssertEqual(
            TuneAVStreamSongIdentificationPolicy.outcome(forMatchFailureDomain: "com.apple.ShazamKit", code: 202),
            .unavailable(domain: "com.apple.ShazamKit", code: 202)
        )
    }

    func testUserAgentNamesTheAppWithoutPrivateData() {
        let agent = TuneAVStreamSongIdentificationPolicy.userAgent()
        XCTAssertTrue(agent.hasPrefix("TuneAV/"))
        XCTAssertTrue(agent.contains("github.com/miguelavalos/tune-av"))
    }

    // MARK: - Identifier end to end (fake transport, fake catalog)

    func testIdentifierMatchesAProgressiveMP3StreamAndReadsTheICYTitle() async throws {
        let audio = try sixSecondMP3()
        let transport = FakeTransport(
            stream: .init(
                statusCode: 200,
                headers: ["Content-Type": "audio/mpeg", "icy-metaint": "8000", "icy-name": "Heart 80s"],
                chunks: chunks(icyWrapped(audio, interval: 8000, title: Self.streamTitle), size: 4096)
            )
        )
        let matcher = FakeMatcher(outcome: .matched([Self.sampleTrack]))
        let identifier = TuneAVStreamSongIdentifier(transport: transport, matcher: matcher, userAgent: "TuneAVTests/1")
        let titles = TitleRecorder()

        let result = await identifier.identify(streamURL: Self.streamURL) { titles.record($0) }

        XCTAssertEqual(result.outcome, .matched(Self.sampleTrack))
        XCTAssertEqual(result.streamTitle, TuneAVTrackMetadata(title: "Didn't We Almost Have It All", artist: "Whitney Houston"))
        XCTAssertEqual(titles.values, [TuneAVTrackMetadata(title: "Didn't We Almost Have It All", artist: "Whitney Houston")])
        XCTAssertGreaterThan(result.elapsed, 0)

        let request = try XCTUnwrap(transport.log.streamRequests.first)
        XCTAssertEqual(request.url, Self.streamURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Icy-MetaData"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "TuneAVTests/1")
        XCTAssertEqual(transport.log.closeCount, 1, "the capture connection is closed once the audio is gathered")

        let matched = try XCTUnwrap(matcher.log.audio.first)
        XCTAssertEqual(matched.sampleRate, 44_100)
        XCTAssertGreaterThanOrEqual(matched.seconds, 3)
        XCTAssertLessThanOrEqual(matched.seconds, 11.9)
    }

    func testIdentifierStopsReadingOnceTwelveSecondsAreGathered() async throws {
        // Five copies of the three-second fixture: the capture must stop near twelve seconds and
        // never read the rest.
        let fixture = try mp3Fixture()
        let audio = fixture + fixture + fixture + fixture + fixture
        let transport = FakeTransport(
            stream: .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg"], chunks: chunks(audio, size: 16_000))
        )
        let matcher = FakeMatcher(outcome: .noMatch)
        let identifier = TuneAVStreamSongIdentifier(transport: transport, matcher: matcher, userAgent: "TuneAVTests/1")

        let result = await identifier.identify(streamURL: Self.streamURL) { _ in }

        XCTAssertEqual(result.outcome, .noMatch)
        XCTAssertNil(result.streamTitle)
        let matched = try XCTUnwrap(matcher.log.audio.first)
        XCTAssertEqual(matched.seconds, 11.9, accuracy: 0.01)
        XCTAssertEqual(transport.log.closeCount, 1)
    }

    func testIdentifierMapsCatalogFailures() async throws {
        let audio = try sixSecondMP3()
        func run(_ outcome: TuneAVSongMatchOutcome) async -> TuneAVStreamSongIdentificationOutcome {
            let transport = FakeTransport(stream: .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg"], chunks: chunks(audio, size: 8192)))
            let identifier = TuneAVStreamSongIdentifier(transport: transport, matcher: FakeMatcher(outcome: outcome), userAgent: "TuneAVTests/1")
            return await identifier.identify(streamURL: Self.streamURL) { _ in }.outcome
        }

        let unavailable = await run(.failed(domain: "com.apple.ShazamCore", code: 102))
        XCTAssertEqual(unavailable, .unavailable(domain: "com.apple.ShazamCore", code: 102))
        let network = await run(.failed(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        XCTAssertEqual(network, .networkFailure)
        let silent = await run(.failed(domain: "com.apple.ShazamKit", code: 200))
        XCTAssertEqual(silent, .noMatch)
        let empty = await run(.matched([]))
        XCTAssertEqual(empty, .noMatch)
    }

    func testIdentifierRejectsNon200AndInsecureAndUnsupportedStreams() async throws {
        let audio = try sixSecondMP3()

        let notFound = FakeTransport(stream: .init(statusCode: 404, headers: [:], chunks: []))
        var identifier = TuneAVStreamSongIdentifier(transport: notFound, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        var result = await identifier.identify(streamURL: Self.streamURL) { _ in }
        XCTAssertEqual(result.outcome, .unsupportedStream(.httpStatus(404)))
        XCTAssertEqual(notFound.log.closeCount, 1)

        let insecure = FakeTransport(stream: .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg"], chunks: chunks(audio, size: 8192)))
        identifier = TuneAVStreamSongIdentifier(transport: insecure, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        result = await identifier.identify(streamURL: URL(string: "http://radio.example.test/live.mp3")!) { _ in }
        XCTAssertEqual(result.outcome, .unsupportedStream(.insecureURL))
        XCTAssertTrue(insecure.log.streamRequests.isEmpty, "an http stream is refused before any connection")

        let ogg = FakeTransport(stream: .init(statusCode: 200, headers: ["Content-Type": "application/ogg"], chunks: [Data(repeating: 0, count: 100)]))
        identifier = TuneAVStreamSongIdentifier(transport: ogg, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        result = await identifier.identify(streamURL: Self.streamURL) { _ in }
        XCTAssertEqual(result.outcome, .unsupportedStream(.container("application/ogg")))

        let garbage = FakeTransport(stream: .init(
            statusCode: 200,
            headers: ["Content-Type": "application/octet-stream"],
            chunks: chunks(Data((0 ..< 60_000).map { UInt8(truncatingIfNeeded: $0 &* 13) }), size: 8192)
        ))
        identifier = TuneAVStreamSongIdentifier(transport: garbage, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        result = await identifier.identify(streamURL: Self.streamURL) { _ in }
        XCTAssertEqual(result.outcome, .unsupportedStream(.undecodable))
    }

    func testIdentifierReportsTransportErrorsAsNetworkFailures() async {
        let failing = FakeTransport(stream: .init(statusCode: 200, headers: [:], chunks: [], error: URLError(.cannotConnectToHost)))
        var identifier = TuneAVStreamSongIdentifier(transport: failing, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        var result = await identifier.identify(streamURL: Self.streamURL) { _ in }
        XCTAssertEqual(result.outcome, .networkFailure)

        let blocked = FakeTransport(stream: .init(statusCode: 200, headers: [:], chunks: [], error: URLError(.appTransportSecurityRequiresSecureConnection)))
        identifier = TuneAVStreamSongIdentifier(transport: blocked, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        result = await identifier.identify(streamURL: Self.streamURL) { _ in }
        XCTAssertEqual(result.outcome, .unsupportedStream(.insecureURL))
    }

    func testIdentifierTimesOutWhenTheStreamStalls() async {
        let stalled = FakeTransport(stream: .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg"], chunks: [], stalls: true))
        let identifier = TuneAVStreamSongIdentifier(transport: stalled, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1", overallTimeout: 0.5)
        let result = await identifier.identify(streamURL: Self.streamURL) { _ in }
        XCTAssertEqual(result.outcome, .networkFailure)
        XCTAssertEqual(stalled.log.closeCount, 1)
    }

    func testIdentifierCancels() async throws {
        let stalled = FakeTransport(stream: .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg"], chunks: [], stalls: true))
        let identifier = TuneAVStreamSongIdentifier(transport: stalled, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        // Capture only Sendable values: Swift 6.1 (Xcode 16.4) rejects a Task closure that reaches the test case's `Self`.
        let streamURL = Self.streamURL
        let task = Task { @Sendable [identifier] in
            await identifier.identify(streamURL: streamURL) { _ in }
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.outcome, .cancelled)
    }

    func testIdentifierFollowsHLSMasterAndMediaPlaylistsWithADTSSegments() async throws {
        let segment = try aacFixture()
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"
        aac/index.m3u8
        """
        let media = """
        #EXTM3U
        #EXT-X-TARGETDURATION:3
        #EXT-X-MEDIA-SEQUENCE:10
        #EXTINF:3.0,
        seg10.aac
        #EXTINF:3.0,
        seg11.aac
        #EXTINF:3.0,
        seg12.aac
        #EXTINF:3.0,
        seg13.aac
        #EXTINF:3.0,
        seg14.aac
        """
        let transport = FakeTransport(
            stream: .init(statusCode: 500, headers: [:], chunks: []),
            fetches: [
                "https://hls.example.test/radio/master.m3u8": .init(data: Data(master.utf8), contentType: "application/vnd.apple.mpegurl"),
                "https://hls.example.test/radio/aac/index.m3u8": .init(data: Data(media.utf8), contentType: "application/vnd.apple.mpegurl"),
                "https://hls.example.test/radio/aac/seg11.aac": .init(data: segment, contentType: "audio/aac"),
                "https://hls.example.test/radio/aac/seg12.aac": .init(data: segment, contentType: "audio/aac"),
                "https://hls.example.test/radio/aac/seg13.aac": .init(data: segment, contentType: "audio/aac"),
                "https://hls.example.test/radio/aac/seg14.aac": .init(data: segment, contentType: "audio/aac")
            ]
        )
        let matcher = FakeMatcher(outcome: .matched([Self.sampleTrack]))
        let identifier = TuneAVStreamSongIdentifier(transport: transport, matcher: matcher, userAgent: "TuneAVTests/1")

        let result = await identifier.identify(streamURL: URL(string: "https://hls.example.test/radio/master.m3u8")!) { _ in }

        XCTAssertEqual(result.outcome, .matched(Self.sampleTrack))
        XCTAssertTrue(transport.log.streamRequests.isEmpty, "HLS never opens a progressive connection")
        XCTAssertEqual(
            transport.log.fetchRequests.map(\.url!.lastPathComponent),
            ["master.m3u8", "index.m3u8", "seg11.aac", "seg12.aac", "seg13.aac", "seg14.aac"],
            "the trailing segments summing to twelve seconds are fetched, oldest first"
        )
        let matched = try XCTUnwrap(matcher.log.audio.first)
        XCTAssertEqual(matched.seconds, 11.9, accuracy: 0.01)
    }

    func testIdentifierDemuxesMPEGTransportStreamSegments() async throws {
        let segment = transportStream(wrapping: try aacFixture())
        let media = """
        #EXTM3U
        #EXT-X-TARGETDURATION:3
        #EXTINF:3.0,
        a.ts
        #EXTINF:3.0,
        b.ts
        """
        let transport = FakeTransport(
            stream: .init(statusCode: 500, headers: [:], chunks: []),
            fetches: [
                "https://hls.example.test/live.m3u8": .init(data: Data(media.utf8), contentType: "application/x-mpegurl"),
                "https://hls.example.test/a.ts": .init(data: segment, contentType: "video/MP2T"),
                "https://hls.example.test/b.ts": .init(data: segment, contentType: "video/MP2T")
            ]
        )
        let matcher = FakeMatcher(outcome: .noMatch)
        let identifier = TuneAVStreamSongIdentifier(transport: transport, matcher: matcher, userAgent: "TuneAVTests/1")

        let result = await identifier.identify(streamURL: URL(string: "https://hls.example.test/live.m3u8")!) { _ in }

        XCTAssertEqual(result.outcome, .noMatch)
        let matched = try XCTUnwrap(matcher.log.audio.first)
        XCTAssertEqual(matched.seconds, 6, accuracy: 0.2)
    }

    func testIdentifierRejectsFragmentedMP4Segments() async {
        let fragment = Data([0, 0, 0, 0x18] + Array("stypmsdh".utf8) + [UInt8](repeating: 0, count: 600))
        let media = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:6.0,
        a.m4s
        #EXTINF:6.0,
        b.m4s
        """
        let transport = FakeTransport(
            stream: .init(statusCode: 500, headers: [:], chunks: []),
            fetches: [
                "https://hls.example.test/live.m3u8": .init(data: Data(media.utf8), contentType: "application/vnd.apple.mpegurl"),
                "https://hls.example.test/a.m4s": .init(data: fragment, contentType: "video/mp4"),
                "https://hls.example.test/b.m4s": .init(data: fragment, contentType: "video/mp4")
            ]
        )
        let identifier = TuneAVStreamSongIdentifier(transport: transport, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        let result = await identifier.identify(streamURL: URL(string: "https://hls.example.test/live.m3u8")!) { _ in }
        XCTAssertEqual(result.outcome, .unsupportedStream(.container("fmp4")))
    }

    func testIdentifierFollowsAPlaylistServedOnTheStreamURL() async throws {
        let audio = try sixSecondMP3()
        let playlist = "#EXTM3U\nhttps://ice.example.test/live.mp3\n"
        let transport = FakeTransport(
            stream: .init(statusCode: 200, headers: ["Content-Type": "audio/x-mpegurl"], chunks: [Data(playlist.utf8)]),
            secondStream: .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg"], chunks: chunks(audio, size: 8192))
        )
        let identifier = TuneAVStreamSongIdentifier(transport: transport, matcher: FakeMatcher(outcome: .noMatch), userAgent: "TuneAVTests/1")
        let result = await identifier.identify(streamURL: URL(string: "https://radio.example.test/listen")!) { _ in }
        XCTAssertEqual(result.outcome, .noMatch)
        XCTAssertEqual(transport.log.streamRequests.map(\.url?.absoluteString), ["https://radio.example.test/listen", "https://ice.example.test/live.mp3"])
    }

    // MARK: - Device-local marks and metering

    func testIdentifiedDiscoveryStoreRemembersAndCaps() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StreamSongIdentifierTests.\(UUID().uuidString)"))
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let store = TuneAVIdentifiedDiscoveryStore(defaults: defaults)

        XCTAssertFalse(store.contains("a"))
        store.remember("a")
        store.remember("b")
        store.remember("a")
        XCTAssertTrue(store.contains("a"))
        XCTAssertTrue(store.contains("b"))
        XCTAssertEqual(defaults.stringArray(forKey: TuneAVIdentifiedDiscoveryStore.defaultsKey), ["b", "a"])

        for index in 0 ..< TuneAVIdentifiedDiscoveryStore.maximumCount {
            store.remember("id-\(index)")
        }
        XCTAssertEqual(defaults.stringArray(forKey: TuneAVIdentifiedDiscoveryStore.defaultsKey)?.count, TuneAVIdentifiedDiscoveryStore.maximumCount)
        XCTAssertFalse(store.contains("b"), "the oldest marks fall off")
        XCTAssertTrue(store.contains("id-\(TuneAVIdentifiedDiscoveryStore.maximumCount - 1)"))

        store.forget("id-0")
        XCTAssertFalse(store.contains("id-0"))
        store.removeAll()
        XCTAssertNil(defaults.stringArray(forKey: TuneAVIdentifiedDiscoveryStore.defaultsKey))
    }

    func testMeteringKeySharesATwoMinuteWindowPerStation() {
        let start = Date(timeIntervalSince1970: 8334 * ShellSongIdentificationMetering.retryWindow)
        let key = ShellSongIdentificationMetering.usageKey(stationID: "heart-80s", now: start)
        XCTAssertEqual(key, ShellSongIdentificationMetering.usageKey(stationID: "heart-80s", now: start.addingTimeInterval(110)))
        XCTAssertNotEqual(key, ShellSongIdentificationMetering.usageKey(stationID: "heart-80s", now: start.addingTimeInterval(130)))
        XCTAssertNotEqual(key, ShellSongIdentificationMetering.usageKey(stationID: "somafm", now: start))
        XCTAssertTrue(key.hasPrefix("identify:heart-80s:"))
    }

    // MARK: - Controller

    @MainActor
    func testControllerPublishesListeningThenTheResult() async throws {
        let scripted = ScriptedIdentifier(result: TuneAVStreamSongIdentification(
            outcome: .matched(Self.sampleTrack),
            streamTitle: TuneAVTrackMetadata(title: "Song", artist: "Artist")
        ))
        let controller = ShellSongIdentificationController(identifier: scripted)
        let station = Station.samples[0]
        XCTAssertEqual(controller.phase, .idle)

        var received: TuneAVStreamSongIdentification?
        controller.identify(station: station) { received = $0 }
        XCTAssertEqual(controller.phase, .listening(stationID: station.id, streamTitle: nil))
        XCTAssertTrue(controller.isListening(stationID: station.id))
        XCTAssertFalse(controller.isListening(stationID: "other"))

        try await waitUntil { controller.phase == .matched(stationID: station.id, track: Self.sampleTrack) }
        XCTAssertEqual(received?.outcome, .matched(Self.sampleTrack))
        XCTAssertEqual(controller.phase(for: station.id), .matched(stationID: station.id, track: Self.sampleTrack))
        XCTAssertEqual(controller.phase(for: "other"), .idle)

        controller.resetIfNeeded(currentStationID: station.id)
        XCTAssertNotEqual(controller.phase, .idle, "the result stays while the same station plays")
        controller.resetIfNeeded(currentStationID: "other")
        XCTAssertEqual(controller.phase, .idle)
    }

    @MainActor
    func testControllerMapsOutcomesAndDropsSupersededRuns() async throws {
        let station = Station.samples[0]
        for (outcome, expected) in [
            (TuneAVStreamSongIdentificationOutcome.noMatch, ShellSongIdentificationController.Phase.noMatch(stationID: station.id)),
            (.unsupportedStream(.container("fmp4")), .unsupported(stationID: station.id)),
            (.unavailable(domain: "com.apple.ShazamCore", code: 102), .unavailable(stationID: station.id)),
            (.networkFailure, .networkFailure(stationID: station.id)),
            (.cancelled, .idle)
        ] {
            let controller = ShellSongIdentificationController(identifier: ScriptedIdentifier(result: .init(outcome: outcome)))
            controller.identify(station: station) { _ in }
            try await waitUntil { controller.phase == expected }
        }

        let slow = ScriptedIdentifier(result: .init(outcome: .noMatch), delay: .seconds(2))
        let controller = ShellSongIdentificationController(identifier: slow)
        var results = 0
        controller.identify(station: station) { _ in results += 1 }
        controller.cancel()
        XCTAssertEqual(controller.phase, .idle)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(results, 0, "a cancelled run never reports")

        controller.identify(station: station) { _ in results += 1 }
        controller.clearResult()
        XCTAssertTrue(controller.phase.isListening, "clearing a result never cancels a running identification")
    }

    // MARK: - Helpers

    private static let sampleTrack = TuneAVIdentifiedTrack(
        title: "Didn't We Almost Have It All",
        artist: "Whitney Houston",
        appleMusicID: "840431938",
        appleMusicURL: URL(string: "https://music.apple.com/es/album/didnt-we-almost-have-it-all/840431884?i=840431938"),
        artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/86/b5/25/dj.jpg/800x800bb.jpg"),
        shazamID: "102621931",
        shazamWebURL: URL(string: "https://www.shazam.com/track/102621931/didnt-we-almost-have-it-all"),
        isrc: "USAR18700115",
        matchOffset: 47.14
    )

    private func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for channel in 0 ..< Int(buffer.format.channelCount) {
            for frame in 0 ..< Int(buffer.frameLength) {
                peak = max(peak, abs(channels[channel][frame]))
            }
        }
        return peak
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout) s")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// A minimal MPEG-TS muxer: PAT, PMT with one ADTS audio stream (PID 0x100), then PES packets
    /// carrying `elementary`, the last one padded with an adaptation field.
    private func transportStream(wrapping elementary: Data) -> Data {
        var output = Data()
        var continuity: [Int: UInt8] = [:]

        func header(pid: Int, payloadUnitStart: Bool, adaptation: Bool) -> [UInt8] {
            let counter = continuity[pid, default: 0]
            continuity[pid] = (counter + 1) & 0x0F
            return [
                0x47,
                UInt8(payloadUnitStart ? 0x40 : 0x00) | UInt8((pid >> 8) & 0x1F),
                UInt8(pid & 0xFF),
                (adaptation ? 0x30 : 0x10) | counter
            ]
        }

        func sectionPacket(pid: Int, section: [UInt8]) -> [UInt8] {
            var packet = header(pid: pid, payloadUnitStart: true, adaptation: false)
            packet.append(0) // pointer field
            packet.append(contentsOf: section)
            packet.append(contentsOf: [UInt8](repeating: 0xFF, count: 188 - packet.count))
            return packet
        }

        // PAT: program 1 -> PMT PID 0x1000.
        var pat: [UInt8] = [0x00, 0xB0, 13, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xF0, 0x00]
        pat.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF]) // CRC placeholder
        output.append(contentsOf: sectionPacket(pid: 0, section: pat))

        // PMT: PCR PID 0x100, one ADTS AAC stream (type 0x0F) on PID 0x100.
        var pmt: [UInt8] = [0x02, 0xB0, 18, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0, 0x00]
        pmt.append(contentsOf: [0x0F, 0xE1, 0x00, 0xF0, 0x00])
        pmt.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])
        output.append(contentsOf: sectionPacket(pid: 0x1000, section: pmt))

        // PES: header with a five-byte PTS, then the elementary stream.
        let pesHeader: [UInt8] = [0x00, 0x00, 0x01, 0xC0, 0x00, 0x00, 0x80, 0x80, 0x05, 0x21, 0x00, 0x01, 0x00, 0x01]
        var payload = pesHeader + [UInt8](elementary)
        var isFirst = true
        while !payload.isEmpty {
            let room = 184
            if payload.count >= room {
                var packet = header(pid: 0x100, payloadUnitStart: isFirst, adaptation: false)
                packet.append(contentsOf: payload.prefix(room))
                payload.removeFirst(room)
                output.append(contentsOf: packet)
            } else {
                let stuffing = room - payload.count - 2
                var packet = header(pid: 0x100, payloadUnitStart: isFirst, adaptation: true)
                packet.append(UInt8(stuffing + 1)) // adaptation field length
                packet.append(0x00)                // flags
                packet.append(contentsOf: [UInt8](repeating: 0xFF, count: stuffing))
                packet.append(contentsOf: payload)
                payload.removeAll()
                output.append(contentsOf: packet)
            }
            isFirst = false
        }
        return output
    }
}

// MARK: - Fakes

private final class TransportLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _streamRequests: [URLRequest] = []
    private var _fetchRequests: [URLRequest] = []
    private var _closeCount = 0

    var streamRequests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _streamRequests }
    var fetchRequests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _fetchRequests }
    var closeCount: Int { lock.lock(); defer { lock.unlock() }; return _closeCount }

    func recordStream(_ request: URLRequest) { lock.lock(); _streamRequests.append(request); lock.unlock() }
    func recordFetch(_ request: URLRequest) { lock.lock(); _fetchRequests.append(request); lock.unlock() }
    func recordClose() { lock.lock(); _closeCount += 1; lock.unlock() }
}

private struct FakeTransport: TuneAVStreamSongIdentifierTransport {
    struct StreamScript: Sendable {
        var statusCode: Int
        var headers: [String: String]
        var chunks: [Data]
        var error: Error?
        /// Delivers nothing and never ends, like a server that accepted the connection and stalled.
        var stalls = false
    }

    struct FetchScript: Sendable {
        var data: Data
        var contentType: String
        var statusCode = 200
    }

    let stream: StreamScript
    var secondStream: StreamScript?
    var fetches: [String: FetchScript] = [:]
    let log = TransportLog()

    init(stream: StreamScript, secondStream: StreamScript? = nil, fetches: [String: FetchScript] = [:]) {
        self.stream = stream
        self.secondStream = secondStream
        self.fetches = fetches
    }

    func openStream(_ request: URLRequest) async throws -> TuneAVOpenedStream {
        let script = log.streamRequests.isEmpty ? stream : (secondStream ?? stream)
        log.recordStream(request)
        if let error = script.error {
            throw error
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: script.statusCode, httpVersion: "HTTP/1.1", headerFields: script.headers)!
        let (chunks, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let log = log
        if !script.stalls {
            for chunk in script.chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        return TuneAVOpenedStream(response: response, chunks: chunks, close: {
            log.recordClose()
            continuation.finish()
        })
    }

    func fetch(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        log.recordFetch(request)
        guard let url = request.url, let script = fetches[url.absoluteString] else {
            throw URLError(.fileDoesNotExist)
        }
        let response = HTTPURLResponse(url: url, statusCode: script.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": script.contentType])!
        return (script.data, response)
    }
}

private final class MatcherLog: @unchecked Sendable {
    struct Entry {
        let seconds: Double
        let sampleRate: Double
    }

    private let lock = NSLock()
    private var _audio: [Entry] = []

    var audio: [Entry] { lock.lock(); defer { lock.unlock() }; return _audio }

    func record(_ audio: TuneAVSignatureAudio) {
        lock.lock()
        _audio.append(Entry(seconds: audio.seconds, sampleRate: audio.sampleRate))
        lock.unlock()
    }
}

private struct FakeMatcher: TuneAVSongSignatureMatching {
    let outcome: TuneAVSongMatchOutcome
    let log = MatcherLog()

    init(outcome: TuneAVSongMatchOutcome) {
        self.outcome = outcome
    }

    func match(_ audio: TuneAVSignatureAudio) async -> TuneAVSongMatchOutcome {
        log.record(audio)
        return outcome
    }
}

private final class TitleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [TuneAVTrackMetadata] = []

    var values: [TuneAVTrackMetadata] { lock.lock(); defer { lock.unlock() }; return _values }

    func record(_ value: TuneAVTrackMetadata) {
        lock.lock()
        _values.append(value)
        lock.unlock()
    }
}

private struct ScriptedIdentifier: TuneAVStreamSongIdentifying {
    let result: TuneAVStreamSongIdentification
    var delay: Duration = .milliseconds(30)

    func identify(
        streamURL: URL,
        onStreamTitle: @escaping @Sendable (TuneAVTrackMetadata) -> Void
    ) async -> TuneAVStreamSongIdentification {
        try? await Task.sleep(for: delay)
        if Task.isCancelled {
            return TuneAVStreamSongIdentification(outcome: .cancelled)
        }
        if let streamTitle = result.streamTitle {
            onStreamTitle(streamTitle)
        }
        return result
    }
}
