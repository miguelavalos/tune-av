@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioPlayerService: ObservableObject {
    struct StreamMetadataEvent: Sendable {
        let value: String
        let commonKey: String
        let identifier: String
    }

    private enum TrackSource {
        case stream
        case fallback
    }

    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    @Published private(set) var currentStation: Station?
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var currentTrackTitle: String?
    @Published private(set) var currentTrackArtist: String?
    @Published private(set) var currentTrackArtworkURL: URL?

    private var player: AVPlayer?
    private let nowPlayingService = NowPlayingService()
    private let trackArtworkService = TrackArtworkService()
    private var metadataTask: Task<Void, Never>?
    private var artworkResolutionTask: Task<Void, Never>?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: StreamMetadataDelegate?
    private var currentTrackSource: TrackSource?
    private var loadingTimeoutTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var isUserPaused = false
    private var userRequestedPlayback = false

    var isPlaying: Bool {
        playbackState == .playing
    }

    func isCurrent(_ station: Station) -> Bool {
        currentStation?.id == station.id
    }

    func play(_ station: Station) {
        guard let url = URL(string: station.streamURL) else {
            failPlayback("Invalid stream URL.")
            return
        }

        teardownObservers()
        clearTrackMetadata()
        currentStation = station
        lastErrorMessage = nil
        isUserPaused = false
        userRequestedPlayback = true
        playbackState = .loading
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "User-Agent": "TuneAV/0.1",
                    "Icy-MetaData": "1"
                ]
            ]
        )
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        attachObservers(to: player, item: item)
        startLoadingTimeout()
        player.play()
        startMetadataPolling(for: station)
    }

    func togglePlayback() {
        switch playbackState {
        case .playing:
            isUserPaused = true
            userRequestedPlayback = false
            player?.pause()
            playbackState = .paused
        case .paused:
            isUserPaused = false
            userRequestedPlayback = true
            player?.play()
            playbackState = .loading
            startLoadingTimeout()
        case .idle, .failed:
            if let currentStation {
                play(currentStation)
            }
        case .loading:
            isUserPaused = true
            userRequestedPlayback = false
            player?.pause()
            playbackState = .paused
        }
    }

    func stop() {
        player?.pause()
        player = nil
        teardownObservers()
        isUserPaused = false
        userRequestedPlayback = false
        lastErrorMessage = nil
        currentStation = nil
        playbackState = .idle
        clearTrackMetadata()
    }

    private func attachObservers(to player: AVPlayer, item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }

                switch item.status {
                case .unknown:
                    if !self.isUserPaused {
                        self.playbackState = .loading
                    }
                case .readyToPlay:
                    if !self.isUserPaused && player.timeControlStatus != .waitingToPlayAtSpecifiedRate {
                        self.loadingTimeoutTask?.cancel()
                        self.loadingTimeoutTask = nil
                        self.playbackState = .playing
                    }
                case .failed:
                    self.failPlayback(self.playbackErrorMessage(from: item.error))
                @unknown default:
                    self.failPlayback("The stream entered an unknown playback state.")
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }

                switch player.timeControlStatus {
                case .paused:
                    if self.currentStation == nil {
                        self.playbackState = .idle
                    } else if self.isUserPaused {
                        self.playbackState = .paused
                    }
                case .waitingToPlayAtSpecifiedRate:
                    if !self.isUserPaused {
                        self.playbackState = .loading
                    }
                case .playing:
                    self.loadingTimeoutTask?.cancel()
                    self.loadingTimeoutTask = nil
                    self.lastErrorMessage = nil
                    self.playbackState = .playing
                @unknown default:
                    break
                }
            }
        }

        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.localizedDescription
            Task { @MainActor in
                self?.failPlayback(error ?? "Playback stopped unexpectedly.")
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isUserPaused else { return }
                self.playbackState = .loading
                self.startLoadingTimeout()
            }
        }

        let metadataDelegate = StreamMetadataDelegate { [weak self] events in
            Task { @MainActor in
                await self?.updateTrackMetadata(from: events)
            }
        }
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(metadataDelegate, queue: .main)
        item.add(metadataOutput)
        self.metadataOutput = metadataOutput
        self.metadataDelegate = metadataDelegate
    }

    private func failPlayback(_ message: String) {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        lastErrorMessage = message
        playbackState = .failed(message)
        player?.pause()
    }

    private func startLoadingTimeout() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(14))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.userRequestedPlayback else { return }
                if case .loading = self.playbackState {
                    self.failPlayback("The station did not start in time. Try again or choose another stream.")
                }
            }
        }
    }

    private func playbackErrorMessage(from error: Error?) -> String {
        let nsError = error as NSError?
        if nsError?.domain == NSURLErrorDomain, nsError?.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return "This station uses an insecure stream. Tune AV now allows these streams; try again."
        }
        return error?.localizedDescription ?? "The stream failed to start."
    }

    private func teardownObservers() {
        metadataTask?.cancel()
        metadataTask = nil
        artworkResolutionTask?.cancel()
        artworkResolutionTask = nil
        metadataOutput = nil
        metadataDelegate = nil
        currentTrackSource = nil
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil

        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }

        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
    }

    private func startMetadataPolling(for station: Station) {
        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))

            while !Task.isCancelled {
                guard self?.currentStation?.id == station.id else { return }
                if self?.currentTrackSource == .stream { return }

                guard let track = await self?.nowPlayingService.fetchTrack(for: station) else {
                    try? await Task.sleep(for: .seconds(20))
                    continue
                }

                await MainActor.run {
                    self?.applyFallbackTrack(track, for: station)
                }

                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func updateTrackMetadata(from events: [StreamMetadataEvent]) async {
        guard !events.isEmpty else { return }

        var resolvedTitle = currentTrackTitle
        var resolvedArtist = currentTrackArtist
        var resolvedFromStream = false

        for event in events {
            let value = event.value
            let commonKey = event.commonKey
            let identifier = event.identifier

            if commonKey == "title" || identifier.contains("title") || identifier.contains("streamtitle") {
                let parsed = TuneAVTrackMetadataParser.parse(value)
                resolvedTitle = parsed.title ?? resolvedTitle
                resolvedArtist = parsed.artist ?? resolvedArtist
                if parsed.title != nil || parsed.artist != nil {
                    resolvedFromStream = true
                }
                continue
            }

            if commonKey == "artist" || identifier.contains("artist") {
                if let sanitizedArtist = TuneAVTrackMetadataParser.sanitizeArtist(value) {
                    resolvedArtist = sanitizedArtist
                    resolvedFromStream = true
                }
            }
        }

        if resolvedFromStream {
            currentTrackSource = .stream
        }

        applyTrackMetadata(title: resolvedTitle, artist: resolvedArtist)
    }

    private func applyFallbackTrack(_ track: NowPlayingTrack, for station: Station) {
        guard currentStation?.id == station.id else { return }
        guard currentTrackSource != .stream else { return }

        let normalizedArtist = TuneAVTrackMetadataParser.sanitizeArtist(track.artist)
        guard let normalizedTitle = TuneAVTrackMetadataParser.sanitizeTitle(track.title, artist: normalizedArtist) else { return }

        currentTrackSource = .fallback
        applyTrackMetadata(title: normalizedTitle, artist: normalizedArtist)
    }

    private func applyTrackMetadata(title: String?, artist: String?) {
        guard title != currentTrackTitle || artist != currentTrackArtist else { return }

        currentTrackTitle = title
        currentTrackArtist = artist
        resolveArtworkForCurrentTrack()
    }

    private func resolveArtworkForCurrentTrack() {
        artworkResolutionTask?.cancel()

        guard let artist = currentTrackArtist, let title = currentTrackTitle else {
            currentTrackArtworkURL = nil
            return
        }

        currentTrackArtworkURL = nil
        artworkResolutionTask = Task { [weak self] in
            guard let self else { return }
            let resolved = await trackArtworkService.resolveArtwork(artist: artist, title: title)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentTrackArtist == artist, self.currentTrackTitle == title else { return }
                self.currentTrackArtworkURL = resolved?.artworkURL
            }
        }
    }

    private func clearTrackMetadata() {
        artworkResolutionTask?.cancel()
        artworkResolutionTask = nil
        currentTrackSource = nil
        currentTrackTitle = nil
        currentTrackArtist = nil
        currentTrackArtworkURL = nil
    }

    deinit {
        statusObservation?.invalidate()
        timeControlObservation?.invalidate()
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }
    }
}

private final class StreamMetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let handler: @Sendable ([AudioPlayerService.StreamMetadataEvent]) async -> Void

    init(handler: @escaping @Sendable ([AudioPlayerService.StreamMetadataEvent]) async -> Void) {
        self.handler = handler
    }

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        let metadataItems = MetadataItemsBox(groups.flatMap(\.items))
        guard !metadataItems.items.isEmpty else { return }

        Task { [handler, metadataItems] in
            var events: [AudioPlayerService.StreamMetadataEvent] = []
            events.reserveCapacity(metadataItems.items.count)

            for item in metadataItems.items {
                let value = try? await item.load(.stringValue)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value, !value.isEmpty else { continue }

                events.append(
                    AudioPlayerService.StreamMetadataEvent(
                        value: value,
                        commonKey: item.commonKey?.rawValue.lowercased() ?? "",
                        identifier: item.identifier?.rawValue.lowercased() ?? ""
                    )
                )
            }

            guard !events.isEmpty else { return }
            await handler(events)
        }
    }
}

private final class MetadataItemsBox: @unchecked Sendable {
    let items: [AVMetadataItem]

    init(_ items: [AVMetadataItem]) {
        self.items = items
    }
}
