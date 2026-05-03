import Foundation

typealias NowPlayingTrack = AVTunesysNowPlayingTrack

actor NowPlayingService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func supports(_ station: Station) -> Bool {
        provider(for: station) != nil
    }

    func fetchTrack(for station: Station) async -> NowPlayingTrack? {
        guard let provider = provider(for: station) else { return nil }

        do {
            return try await provider.fetchTrack(for: station, using: session)
        } catch {
            return nil
        }
    }

    private nonisolated func provider(for station: Station) -> Provider? {
        if AVTunesysEighties80sNowPlaying.supports(station) {
            return .eighties80s
        }

        if URL(string: station.streamURL) != nil {
            return .icyStream
        }

        return nil
    }
}

private extension NowPlayingService {
    enum Provider {
        case eighties80s
        case icyStream

        func fetchTrack(for station: Station, using session: URLSession) async throws -> NowPlayingTrack? {
            switch self {
            case .eighties80s:
                return try await fetch80s80sTrack(for: station, using: session)
            case .icyStream:
                return try await fetchICYTrack(for: station, using: session)
            }
        }

        private func fetchICYTrack(for station: Station, using session: URLSession) async throws -> NowPlayingTrack? {
            guard let streamURL = URL(string: station.streamURL) else { return nil }

            var request = URLRequest(url: streamURL)
            request.timeoutInterval = 5
            request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
            request.setValue("AVTunesys/0.1", forHTTPHeaderField: "User-Agent")

            return try await parseICYTrack(from: request, using: session)
        }

        private func parseICYTrack(from request: URLRequest, using session: URLSession) async throws -> NowPlayingTrack? {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<400 ~= httpResponse.statusCode else {
                return nil
            }

            guard let metadataInterval = AVTunesysNowPlayingMetadata.metadataInterval(from: httpResponse), metadataInterval > 0 else {
                return nil
            }

            var bytesUntilMetadata = metadataInterval
            var totalBytesRead = 0
            let maxBytesToRead = min(metadataInterval + 4096, 262_144)
            var iterator = bytes.makeAsyncIterator()

            while let byte = try await iterator.next() {
                if Task.isCancelled { return nil }

                totalBytesRead += 1
                if totalBytesRead > maxBytesToRead {
                    return nil
                }

                if bytesUntilMetadata > 0 {
                    bytesUntilMetadata -= 1
                    continue
                }

                let metadataLength = Int(byte) * 16
                guard metadataLength > 0 else {
                    bytesUntilMetadata = metadataInterval
                    continue
                }

                var metadataBytes: [UInt8] = []
                metadataBytes.reserveCapacity(metadataLength)

                for _ in 0..<metadataLength {
                    guard let metadataByte = try await iterator.next() else { return nil }
                    metadataBytes.append(metadataByte)
                }

                if let track = AVTunesysNowPlayingMetadata.parseICYMetadata(metadataBytes) {
                    return track
                }

                bytesUntilMetadata = metadataInterval
            }

            return nil
        }

        private func fetch80s80sTrack(for station: Station, using session: URLSession) async throws -> NowPlayingTrack? {
            let requestURL = AVTunesysEighties80sNowPlaying.resolvedURL(for: station) ?? AVTunesysEighties80sNowPlaying.fallbackURL
            var request = URLRequest(url: requestURL)
            request.timeoutInterval = 10
            request.setValue("AVTunesys/0.1", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                return nil
            }

            let html = String(decoding: data, as: UTF8.self)
            return AVTunesysEighties80sNowPlaying.parseTrack(for: station, from: html)
        }
    }
}
