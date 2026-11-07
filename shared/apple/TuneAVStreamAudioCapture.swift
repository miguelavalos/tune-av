import AudioToolbox
import AVFoundation
import Foundation

// The pieces that turn radio stream bytes into PCM for the song signature: the ICY in-band
// metadata stripper, the `AudioFileStream` packet parser, the `AVAudioConverter` decoder, the
// HLS playlist reader and the MPEG-TS demuxer. None of them touches the network or the player.

// MARK: - ICY in-band metadata

/// Removes the metadata blocks an Icecast/Shoutcast server interleaves every `metadataInterval`
/// audio bytes when the request carried `Icy-MetaData: 1`, and keeps the `StreamTitle` values.
final class TuneAVICYMetadataStripper {
    let metadataInterval: Int
    private(set) var titles: [String] = []
    private(set) var metadataBlockCount = 0

    private var audioBytesRemaining: Int
    private var metadataBytesRemaining = -1
    private var metadataBuffer: [UInt8] = []
    private var pendingTitle: String?

    init(metadataInterval: Int) {
        self.metadataInterval = metadataInterval
        audioBytesRemaining = metadataInterval
    }

    var latestTitle: String? {
        titles.last
    }

    /// Returns the audio bytes of `data`; metadata blocks are consumed.
    func strip(_ data: Data) -> Data {
        var audio = Data(capacity: data.count)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var position = 0
            while position < bytes.count {
                if metadataBytesRemaining < 0 {
                    if audioBytesRemaining == 0 {
                        let length = Int(bytes[position]) * 16
                        position += 1
                        metadataBlockCount += 1
                        if length == 0 {
                            audioBytesRemaining = metadataInterval
                        } else {
                            metadataBytesRemaining = length
                            metadataBuffer.removeAll(keepingCapacity: true)
                        }
                        continue
                    }
                    let count = min(audioBytesRemaining, bytes.count - position)
                    audio.append(bytes.baseAddress! + position, count: count)
                    position += count
                    audioBytesRemaining -= count
                } else {
                    let count = min(metadataBytesRemaining, bytes.count - position)
                    metadataBuffer.append(contentsOf: bytes[position ..< position + count])
                    position += count
                    metadataBytesRemaining -= count
                    if metadataBytesRemaining == 0 {
                        consumeMetadataBlock()
                        metadataBytesRemaining = -1
                        audioBytesRemaining = metadataInterval
                    }
                }
            }
        }
        return audio
    }

    /// The title read since the previous call, once.
    func takeNewTitle() -> String? {
        defer { pendingTitle = nil }
        return pendingTitle
    }

    private func consumeMetadataBlock() {
        let text = String(decoding: metadataBuffer.prefix { $0 != 0 }, as: UTF8.self)
        guard let title = TuneAVNowPlayingMetadata.metadataValue(named: "StreamTitle", in: text) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard titles.last != trimmed else { return }
        titles.append(trimmed)
        pendingTitle = trimmed
    }
}

// MARK: - Compressed packet parser

/// Wraps `AudioFileStream`: feeds raw MP3 or AAC (ADTS) bytes and collects packets with their
/// descriptions until enough seconds are gathered. For HE-AAC the format list's first playable
/// entry is chosen so the decoder runs at the full sample rate.
final class TuneAVStreamPacketParser {
    private(set) var dataFormat = AudioStreamBasicDescription()
    private(set) var chosenFormat = AudioStreamBasicDescription()
    private(set) var formatList: [AudioStreamBasicDescription] = []
    private(set) var magicCookie: Data?
    private(set) var isReady = false
    private(set) var compressedData = Data()
    private(set) var packetDescriptions: [AudioStreamPacketDescription] = []
    private(set) var maximumPacketSize: UInt32 = 0
    private(set) var bytesFed = 0
    private(set) var parseError: OSStatus = noErr

    private var stream: AudioFileStreamID?

    init(typeHint: AudioFileTypeID) {
        let client = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioFileStreamOpen(
            client,
            { client, _, propertyID, _ in
                Unmanaged<TuneAVStreamPacketParser>.fromOpaque(client).takeUnretainedValue().handleProperty(propertyID)
            },
            { client, byteCount, packetCount, data, descriptions in
                Unmanaged<TuneAVStreamPacketParser>.fromOpaque(client).takeUnretainedValue()
                    .handlePackets(byteCount: byteCount, packetCount: packetCount, data: data, descriptions: descriptions)
            },
            typeHint,
            &stream
        )
        if status != noErr {
            parseError = status
        }
    }

    deinit {
        if let stream {
            AudioFileStreamClose(stream)
        }
    }

    func feed(_ data: Data) {
        guard let stream, parseError == noErr, !data.isEmpty else { return }
        bytesFed += data.count
        let status = data.withUnsafeBytes { raw -> OSStatus in
            AudioFileStreamParseBytes(stream, UInt32(raw.count), raw.baseAddress, [])
        }
        if status != noErr {
            parseError = status
        }
    }

    /// Seconds of audio represented by the packets gathered so far.
    var secondsGathered: Double {
        guard isReady, chosenFormat.mSampleRate > 0 else { return 0 }
        let framesPerPacket = Double(chosenFormat.mFramesPerPacket)
        if framesPerPacket > 0 {
            return Double(packetDescriptions.count) * framesPerPacket / chosenFormat.mSampleRate
        }
        let frames = packetDescriptions.reduce(0.0) { $0 + Double($1.mVariableFramesInPacket) }
        return frames / chosenFormat.mSampleRate
    }

    var hasPackets: Bool {
        isReady && !packetDescriptions.isEmpty
    }

    private func handleProperty(_ propertyID: AudioFileStreamPropertyID) {
        guard let stream, propertyID == kAudioFileStreamProperty_ReadyToProducePackets else { return }

        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &dataFormat)
        chosenFormat = dataFormat

        var listSize: UInt32 = 0
        var writable: DarwinBoolean = false
        if AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_FormatList, &listSize, &writable) == noErr, listSize > 0 {
            let count = Int(listSize) / MemoryLayout<AudioFormatListItem>.size
            var items = [AudioFormatListItem](repeating: AudioFormatListItem(), count: count)
            if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_FormatList, &listSize, &items) == noErr {
                formatList = items.map(\.mASBD)
                var index: UInt32 = 0
                var indexSize = UInt32(MemoryLayout<UInt32>.size)
                let status = AudioFormatGetProperty(kAudioFormatProperty_FirstPlayableFormatFromList, listSize, items, &indexSize, &index)
                if status == noErr, Int(index) < items.count {
                    chosenFormat = items[Int(index)].mASBD
                }
            }
        }

        var cookieSize: UInt32 = 0
        if AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable) == noErr, cookieSize > 0 {
            var cookie = Data(count: Int(cookieSize))
            let status = cookie.withUnsafeMutableBytes { raw -> OSStatus in
                AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, raw.baseAddress!)
            }
            if status == noErr {
                magicCookie = cookie
            }
        }

        isReady = true
    }

    private func handlePackets(
        byteCount: UInt32,
        packetCount: UInt32,
        data: UnsafeRawPointer,
        descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        if let descriptions {
            for index in 0 ..< Int(packetCount) {
                let description = descriptions[index]
                let start = compressedData.count
                compressedData.append(
                    data.advanced(by: Int(description.mStartOffset)).assumingMemoryBound(to: UInt8.self),
                    count: Int(description.mDataByteSize)
                )
                packetDescriptions.append(
                    AudioStreamPacketDescription(
                        mStartOffset: Int64(start),
                        mVariableFramesInPacket: description.mVariableFramesInPacket,
                        mDataByteSize: description.mDataByteSize
                    )
                )
                maximumPacketSize = max(maximumPacketSize, description.mDataByteSize)
            }
            return
        }

        // Constant bit rate without descriptions: one packet per mBytesPerPacket.
        let bytesPerPacket = max(1, Int(chosenFormat.mBytesPerPacket))
        var offset = 0
        while offset + bytesPerPacket <= Int(byteCount) {
            let start = compressedData.count
            compressedData.append(data.advanced(by: offset).assumingMemoryBound(to: UInt8.self), count: bytesPerPacket)
            packetDescriptions.append(
                AudioStreamPacketDescription(mStartOffset: Int64(start), mVariableFramesInPacket: 0, mDataByteSize: UInt32(bytesPerPacket))
            )
            maximumPacketSize = max(maximumPacketSize, UInt32(bytesPerPacket))
            offset += bytesPerPacket
        }
    }
}

// MARK: - Decoder

enum TuneAVStreamAudioDecoderError: Error {
    case invalidFormat
    case converterUnavailable
    case noAudio
}

enum TuneAVStreamAudioDecoder {
    /// Decodes every gathered packet to Float32 non-interleaved PCM at the codec's own rate.
    static func decode(_ parser: TuneAVStreamPacketParser) throws -> AVAudioPCMBuffer {
        guard parser.hasPackets else { throw TuneAVStreamAudioDecoderError.noAudio }
        var sourceDescription = parser.chosenFormat
        guard let sourceFormat = AVAudioFormat(streamDescription: &sourceDescription) else {
            throw TuneAVStreamAudioDecoderError.invalidFormat
        }

        let packetCount = AVAudioPacketCount(parser.packetDescriptions.count)
        let compressed = AVAudioCompressedBuffer(
            format: sourceFormat,
            packetCapacity: packetCount,
            maximumPacketSize: Int(max(parser.maximumPacketSize, 1))
        )
        parser.compressedData.withUnsafeBytes { raw in
            compressed.data.copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        for (index, description) in parser.packetDescriptions.enumerated() {
            compressed.packetDescriptions![index] = description
        }
        compressed.packetCount = packetCount
        compressed.byteLength = UInt32(parser.compressedData.count)

        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceDescription.mSampleRate,
            channels: sourceDescription.mChannelsPerFrame,
            interleaved: false
        ) else {
            throw TuneAVStreamAudioDecoderError.invalidFormat
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: pcmFormat) else {
            throw TuneAVStreamAudioDecoderError.converterUnavailable
        }
        if let cookie = parser.magicCookie {
            converter.magicCookie = cookie
        }

        let framesPerPacket = sourceDescription.mFramesPerPacket > 0 ? Int(sourceDescription.mFramesPerPacket) : 2048
        let estimatedFrames = AVAudioFrameCount(parser.packetDescriptions.count * framesPerPacket)
        return try convertAll(converter, input: compressed, outputFormat: pcmFormat, estimatedFrames: estimatedFrames)
    }

    /// Resamples PCM to `sampleRate`, keeping Float32 non-interleaved and the channel count.
    static func resample(_ buffer: AVAudioPCMBuffer, to sampleRate: Double) throws -> AVAudioPCMBuffer {
        guard buffer.format.sampleRate != sampleRate else { return buffer }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: buffer.format.channelCount,
            interleaved: false
        ) else {
            throw TuneAVStreamAudioDecoderError.invalidFormat
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            throw TuneAVStreamAudioDecoderError.converterUnavailable
        }
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)
        return try convertAll(converter, input: buffer, outputFormat: targetFormat, estimatedFrames: estimatedFrames)
    }

    /// The first `seconds` of `buffer`; the buffer itself when it is already shorter.
    static func trimmed(_ buffer: AVAudioPCMBuffer, seconds: Double) -> AVAudioPCMBuffer {
        let maximumFrames = AVAudioFrameCount(seconds * buffer.format.sampleRate)
        guard buffer.frameLength > maximumFrames,
              let output = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: maximumFrames),
              let source = buffer.floatChannelData,
              let destination = output.floatChannelData else {
            return buffer
        }
        for channel in 0 ..< Int(buffer.format.channelCount) {
            destination[channel].update(from: source[channel], count: Int(maximumFrames))
        }
        output.frameLength = maximumFrames
        return output
    }

    static func seconds(of buffer: AVAudioPCMBuffer) -> Double {
        guard buffer.format.sampleRate > 0 else { return 0 }
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    /// Decodes, resamples to a rate the signature generator accepts and trims to the catalog's
    /// maximum query length.
    static func signatureBuffer(from parser: TuneAVStreamPacketParser) throws -> AVAudioPCMBuffer {
        let decoded = try decode(parser)
        let accepted = TuneAVStreamSongIdentificationPolicy.signatureSampleRates.contains(decoded.format.sampleRate)
        let resampled = accepted ? decoded : try resample(decoded, to: TuneAVStreamSongIdentificationPolicy.resampleRate)
        return trimmed(resampled, seconds: TuneAVStreamSongIdentificationPolicy.signatureSeconds)
    }

    private final class InputFeeder: @unchecked Sendable {
        private let lock = NSLock()
        private var fed = false
        let input: AVAudioBuffer

        init(input: AVAudioBuffer) {
            self.input = input
        }

        func next() -> AVAudioBuffer? {
            lock.lock()
            defer { lock.unlock() }
            guard !fed else { return nil }
            fed = true
            return input
        }
    }

    private static func convertAll(
        _ converter: AVAudioConverter,
        input: AVAudioBuffer,
        outputFormat: AVAudioFormat,
        estimatedFrames: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        let chunk = AVAudioFrameCount(max(estimatedFrames, 4096))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: estimatedFrames + 8192),
              let outputChannels = output.floatChannelData else {
            throw TuneAVStreamAudioDecoderError.invalidFormat
        }
        let feeder = InputFeeder(input: input)

        while true {
            guard let piece = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunk) else {
                throw TuneAVStreamAudioDecoderError.invalidFormat
            }
            var conversionError: NSError?
            let status = converter.convert(to: piece, error: &conversionError) { _, outStatus in
                if let next = feeder.next() {
                    outStatus.pointee = .haveData
                    return next
                }
                outStatus.pointee = .endOfStream
                return nil
            }
            if let conversionError {
                throw conversionError
            }
            if piece.frameLength > 0, let pieceChannels = piece.floatChannelData {
                let free = output.frameCapacity - output.frameLength
                let count = min(piece.frameLength, free)
                for channel in 0 ..< Int(outputFormat.channelCount) {
                    (outputChannels[channel] + Int(output.frameLength)).update(from: pieceChannels[channel], count: Int(count))
                }
                output.frameLength += count
            }
            if status == .endOfStream || status == .error || piece.frameLength == 0 {
                break
            }
        }
        guard output.frameLength > 0 else { throw TuneAVStreamAudioDecoderError.noAudio }
        return output
    }
}

// MARK: - Container sniffing

enum TuneAVStreamContainer: Equatable {
    case mpegTransportStream
    case adts
    case mp3
    case fragmentedMP4
    case id3
    case ogg
    case unknown

    static func sniff(_ data: Data) -> TuneAVStreamContainer {
        let bytes = [UInt8](data.prefix(16))
        if data.count > 188, bytes[0] == 0x47, data[data.startIndex + 188] == 0x47 {
            return .mpegTransportStream
        }
        if bytes.count >= 4, bytes[0] == 0x4F, bytes[1] == 0x67, bytes[2] == 0x67, bytes[3] == 0x53 {
            return .ogg
        }
        if bytes.count >= 8, Array(bytes[4 ..< 8]) == Array("ftyp".utf8) || Array(bytes[4 ..< 8]) == Array("styp".utf8) {
            return .fragmentedMP4
        }
        if bytes.count >= 3, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
            return .id3
        }
        if bytes.count >= 2, bytes[0] == 0xFF, (bytes[1] & 0xF6) == 0xF0 {
            return .adts
        }
        if bytes.count >= 2, bytes[0] == 0xFF, (bytes[1] & 0xE0) == 0xE0 {
            return .mp3
        }
        return .unknown
    }

    /// The `AudioFileStream` hint for this container; `0` lets the parser sniff.
    var audioFileTypeHint: AudioFileTypeID {
        switch self {
        case .adts:
            return kAudioFileAAC_ADTSType
        case .mp3:
            return kAudioFileMP3Type
        case .mpegTransportStream, .fragmentedMP4, .id3, .ogg, .unknown:
            return 0
        }
    }

    static func audioFileTypeHint(contentType: String?, url: URL) -> AudioFileTypeID {
        let type = (contentType ?? "").lowercased()
        let path = url.path.lowercased()
        if type.contains("mpeg") || type.contains("mp3") || path.hasSuffix(".mp3") {
            return kAudioFileMP3Type
        }
        if type.contains("aac") || path.hasSuffix(".aac") {
            return kAudioFileAAC_ADTSType
        }
        return 0
    }

    static func isPlaylistContentType(_ contentType: String?) -> Bool {
        let type = (contentType ?? "").lowercased()
        return type.contains("mpegurl") || type.contains("x-scpls") || type.contains("pls")
    }

    static func isUnsupportedContentType(_ contentType: String?) -> Bool {
        let type = (contentType ?? "").lowercased()
        return type.contains("ogg") || type.contains("opus") || type.contains("webm")
    }
}

// MARK: - HLS playlists

struct TuneAVHLSVariant: Equatable {
    let url: URL
    let bandwidth: Int?
    let codecs: String?

    var isAudioOnly: Bool {
        guard let codecs = codecs?.lowercased() else { return true }
        return !codecs.contains("avc") && !codecs.contains("hvc") && !codecs.contains("hev") && !codecs.contains("vp0") && !codecs.contains("av01")
    }
}

struct TuneAVHLSSegment: Equatable {
    let url: URL
    let duration: Double
}

enum TuneAVHLSPlaylist {
    enum Kind: Equatable {
        case master
        case media
        /// A plain `.m3u` or `.pls` list of stream URLs, not HLS.
        case simple
        case unknown
    }

    static func kind(of text: String) -> Kind {
        if text.contains("#EXT-X-STREAM-INF") {
            return .master
        }
        if text.contains("#EXTINF") || text.contains("#EXT-X-TARGETDURATION") || text.contains("#EXT-X-MEDIA-SEQUENCE") {
            return .media
        }
        let hasURL = lines(text).contains { line in
            let value = line.hasPrefix("File") ? line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? "" : line
            return !value.hasPrefix("#") && (value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://"))
        }
        return hasURL ? .simple : .unknown
    }

    static func variants(in text: String, base: URL) -> [TuneAVHLSVariant] {
        let lines = lines(text)
        var variants: [TuneAVHLSVariant] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                let attributes = attributes(of: line)
                var next = index + 1
                while next < lines.count, lines[next].hasPrefix("#") || lines[next].isEmpty {
                    next += 1
                }
                if next < lines.count, let url = URL(string: lines[next], relativeTo: base)?.absoluteURL {
                    variants.append(
                        TuneAVHLSVariant(
                            url: url,
                            bandwidth: attributes["BANDWIDTH"].flatMap { Int($0) },
                            codecs: attributes["CODECS"]
                        )
                    )
                }
                index = next + 1
                continue
            }
            index += 1
        }
        return variants
    }

    /// The variant to capture: an audio-only rendition with the lowest bandwidth, so the capture
    /// stays small; the first listed variant when nothing is marked.
    static func preferredVariant(_ variants: [TuneAVHLSVariant]) -> TuneAVHLSVariant? {
        let audioOnly = variants.filter(\.isAudioOnly)
        let candidates = audioOnly.isEmpty ? variants : audioOnly
        if candidates.allSatisfy({ $0.bandwidth != nil }) {
            return candidates.min { ($0.bandwidth ?? .max) < ($1.bandwidth ?? .max) }
        }
        return candidates.first
    }

    static func segments(in text: String, base: URL) -> [TuneAVHLSSegment] {
        var segments: [TuneAVHLSSegment] = []
        var duration = 0.0
        for line in lines(text) {
            if line.hasPrefix("#EXTINF:") {
                let value = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first.map(String.init) ?? "0"
                duration = Double(value.trimmingCharacters(in: .whitespaces)) ?? 0
            } else if !line.hasPrefix("#"), !line.isEmpty, let url = URL(string: line, relativeTo: base)?.absoluteURL {
                segments.append(TuneAVHLSSegment(url: url, duration: duration))
                duration = 0
            }
        }
        return segments
    }

    /// The trailing segments (live edge) whose durations sum to at least `targetSeconds`.
    static func trailingSegments(_ segments: [TuneAVHLSSegment], targetSeconds: Double) -> [TuneAVHLSSegment] {
        var chosen: [TuneAVHLSSegment] = []
        var total = 0.0
        for segment in segments.reversed() {
            chosen.insert(segment, at: 0)
            total += segment.duration > 0 ? segment.duration : 1
            if total >= targetSeconds {
                break
            }
        }
        return chosen
    }

    /// The first stream URL of a plain `.m3u` or `.pls` list.
    static func firstStreamURL(inSimplePlaylist text: String, base: URL) -> URL? {
        for line in lines(text) {
            var value = line
            if line.lowercased().hasPrefix("file"), let separator = line.firstIndex(of: "=") {
                value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            }
            guard !value.hasPrefix("#"), !value.isEmpty else { continue }
            let lowercased = value.lowercased()
            guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") else { continue }
            if let url = URL(string: value, relativeTo: base)?.absoluteURL {
                return url
            }
        }
        return nil
    }

    private static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func attributes(of line: String) -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { return [:] }
        let body = line[line.index(after: colon)...]
        var attributes: [String: String] = [:]
        var current = ""
        var inQuotes = false
        var parts: [String] = []
        for character in body {
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character == ",", !inQuotes {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            attributes[String(pair[0]).trimmingCharacters(in: .whitespaces).uppercased()] = String(pair[1]).trimmingCharacters(in: .whitespaces)
        }
        return attributes
    }
}

// MARK: - MPEG-TS demux

/// Pulls the audio elementary stream (ADTS or MP3 frames) out of MPEG-TS segments:
/// PAT, then PMT, then the PES payloads of the first audio PID.
enum TuneAVMPEGTransportStreamDemuxer {
    static let packetSize = 188

    static func demux(_ transportStream: Data) -> Data {
        let bytes = [UInt8](transportStream)
        var programMapPID = -1
        var audioPID = -1
        var elementaryStream = Data()
        var position = 0

        while position + packetSize <= bytes.count {
            guard bytes[position] == 0x47 else {
                position += 1
                continue
            }
            let payloadUnitStart = (bytes[position + 1] & 0x40) != 0
            let pid = (Int(bytes[position + 1] & 0x1F) << 8) | Int(bytes[position + 2])
            let adaptationControl = (bytes[position + 3] >> 4) & 0x3
            var payload = position + 4
            if adaptationControl == 2 || adaptationControl == 3 {
                payload += 1 + Int(bytes[position + 4])
            }
            let end = position + packetSize
            if adaptationControl == 2 || payload >= end {
                position += packetSize
                continue
            }

            if pid == 0, payloadUnitStart, programMapPID < 0 {
                programMapPID = parseProgramMapPID(inPAT: bytes, payload: payload, end: end)
            } else if pid == programMapPID, payloadUnitStart, audioPID < 0 {
                audioPID = parseAudioPID(inPMT: bytes, payload: payload, end: end)
            } else if pid == audioPID {
                var start = payload
                if payloadUnitStart, start + 9 <= end, bytes[start] == 0, bytes[start + 1] == 0, bytes[start + 2] == 1 {
                    let headerLength = Int(bytes[start + 8])
                    start += 9 + headerLength
                }
                if start < end {
                    elementaryStream.append(contentsOf: bytes[start ..< end])
                }
            }
            position += packetSize
        }
        return elementaryStream
    }

    private static func parseProgramMapPID(inPAT bytes: [UInt8], payload: Int, end: Int) -> Int {
        let section = payload + 1 + Int(bytes[payload])
        guard section + 3 <= end else { return -1 }
        let sectionLength = (Int(bytes[section + 1] & 0x0F) << 8) | Int(bytes[section + 2])
        var index = section + 8
        let sectionEnd = min(section + 3 + sectionLength - 4, end)
        while index + 4 <= sectionEnd {
            let program = (Int(bytes[index]) << 8) | Int(bytes[index + 1])
            let pid = (Int(bytes[index + 2] & 0x1F) << 8) | Int(bytes[index + 3])
            if program != 0 {
                return pid
            }
            index += 4
        }
        return -1
    }

    private static func parseAudioPID(inPMT bytes: [UInt8], payload: Int, end: Int) -> Int {
        let section = payload + 1 + Int(bytes[payload])
        guard section + 12 <= end else { return -1 }
        let sectionLength = (Int(bytes[section + 1] & 0x0F) << 8) | Int(bytes[section + 2])
        let programInfoLength = (Int(bytes[section + 10] & 0x0F) << 8) | Int(bytes[section + 11])
        var index = section + 12 + programInfoLength
        let sectionEnd = min(section + 3 + sectionLength - 4, end)
        while index + 5 <= sectionEnd {
            let streamType = bytes[index]
            let pid = (Int(bytes[index + 1] & 0x1F) << 8) | Int(bytes[index + 2])
            let infoLength = (Int(bytes[index + 3] & 0x0F) << 8) | Int(bytes[index + 4])
            // 0x0F ADTS AAC, 0x11 LATM AAC, 0x03/0x04 MPEG audio.
            if streamType == 0x0F || streamType == 0x11 || streamType == 0x03 || streamType == 0x04 {
                return pid
            }
            index += 5 + infoLength
        }
        return -1
    }
}
