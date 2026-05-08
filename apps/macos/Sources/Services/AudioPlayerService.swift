@preconcurrency import AVFoundation
import Foundation
import Network

@MainActor
final class AudioPlayerService: ObservableObject {
    struct PlaybackQueue: Equatable {
        typealias Source = TuneAVPlaybackQueueSource

        let source: Source
        let stations: [Station]
    }

    private enum TrackSource {
        case stream
        case fallback
        case cached
    }

    typealias PlaybackState = TuneAVPlaybackState

    @Published private(set) var currentStation: Station?
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var sleepTimerDescription: String?
    @Published private(set) var currentTrackTitle: String?
    @Published private(set) var currentTrackArtist: String?
    @Published private(set) var currentTrackAlbumTitle: String?
    @Published private(set) var currentTrackArtworkURL: URL?
    @Published private(set) var playbackQueue: PlaybackQueue = .init(source: .singleStation, stations: [])

    private var player: AVPlayer?
    private let nowPlayingService = NowPlayingService()
    private let trackArtworkService = TrackArtworkService()
    private var metadataTask: Task<Void, Never>?
    private var artworkResolutionTask: Task<Void, Never>?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: TuneAVStreamMetadataDelegate?
    private var currentTrackSource: TrackSource?
    private var loadingTimeoutTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var userRequestedPlayback = false
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.tuneav.mac.audio-network-monitor")
    private var lastNetworkPathStatus: NWPath.Status?
    private let sleepTimerController = TuneAVSleepTimerController()
    private var cachedNowPlayingByStationID: [String: TuneAVCachedNowPlayingState] = [:]

    var isPlaying: Bool {
        playbackState == .playing
    }

    var isLoading: Bool {
        playbackState == .loading
    }

    var hasFailure: Bool {
        if case .failed = playbackState {
            return true
        }
        return false
    }

    init() {
        observeNetworkChanges()
    }

    func isCurrent(_ station: Station) -> Bool {
        currentStation?.id == station.id
    }

    func applyUITestTrackMetadata(title: String?, artist: String?) {
        guard TuneAVUITestEnvironment.current.isEnabled else { return }
        currentTrackTitle = title
        currentTrackArtist = artist
        currentTrackAlbumTitle = nil
        currentTrackSource = title == nil && artist == nil ? nil : .fallback
        persistCurrentNowPlayingState()
    }

    func play(_ station: Station) {
        play(station: station)
    }

    func play(station: Station, queue: PlaybackQueue? = nil) {
        if case .loading = playbackState, currentStation?.id == station.id {
            return
        }

        if let queue {
            playbackQueue = sanitizedPlaybackQueue(queue, currentStationID: station.id)
        }

        guard let url = URL(string: station.streamURL) else {
            failPlayback(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.invalidURL))
            return
        }

        teardownObservers()
        clearTrackMetadata()
        currentStation = station
        restoreCachedNowPlaying(for: station)
        lastErrorMessage = nil
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
            pause()
        case .paused:
            resume()
        case .idle, .failed:
            if let currentStation {
                play(station: currentStation)
            } else if let station = Station.samples.first {
                play(station: station)
            }
        case .loading:
            break
        }
    }

    func resume() {
        guard currentStation != nil else {
            if let station = Station.samples.first {
                play(station: station)
            }
            return
        }

        if shouldReloadCurrentStation {
            retry()
            return
        }

        userRequestedPlayback = true
        player?.play()
        playbackState = .loading
        lastErrorMessage = nil
        startLoadingTimeout()
    }

    func pause() {
        userRequestedPlayback = false
        player?.pause()
        if currentStation != nil {
            playbackState = .paused
        }
    }

    func retry() {
        guard let currentStation else { return }
        userRequestedPlayback = true
        play(station: currentStation)
    }

    var canCyclePlaybackQueue: Bool {
        playbackQueueStations.count > 1
    }

    func playNextInQueue() {
        guard let resolvedQueue = resolvedPlaybackQueue() else { return }

        play(station: TuneAVPlaybackQueueLogic.nextStation(in: resolvedQueue), queue: playbackQueue)
    }

    func playPreviousInQueue() {
        guard let resolvedQueue = resolvedPlaybackQueue() else { return }

        play(station: TuneAVPlaybackQueueLogic.previousStation(in: resolvedQueue), queue: playbackQueue)
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerController.setTimer(
            minutes: minutes,
            setDescription: { [weak self] description in self?.sleepTimerDescription = description },
            onFire: { [weak self] in self?.stop() }
        )
    }

    func clearSleepTimerNotice() {
        sleepTimerController.clearNoticeIfIdle(
            isIdle: playbackState == .idle,
            setDescription: { [weak self] description in self?.sleepTimerDescription = description }
        )
    }

    func stop() {
        persistCurrentNowPlayingState()
        player?.pause()
        player = nil
        teardownObservers()
        userRequestedPlayback = false
        lastErrorMessage = nil
        currentStation = nil
        playbackState = .idle
        clearTrackMetadata()
        playbackQueue = .init(source: .singleStation, stations: [])
    }

    private var playbackQueueStations: [Station] {
        guard let currentStation else { return [] }
        return sanitizedPlaybackQueue(playbackQueue, currentStationID: currentStation.id).stations
    }

    private func resolvedPlaybackQueue() -> TuneAVPlaybackQueueLogic.ResolvedQueue? {
        guard let currentStation else { return nil }
        let stations = playbackQueueStations
        return TuneAVPlaybackQueueLogic.resolvedQueue(stations: stations, currentStation: currentStation)
    }

    private func sanitizedPlaybackQueue(_ queue: PlaybackQueue, currentStationID: String) -> PlaybackQueue {
        let stations = TuneAVPlaybackQueueLogic.sanitizedStations(
            queue.stations,
            currentStation: currentStation,
            currentStationID: currentStationID
        )
        return PlaybackQueue(source: queue.source, stations: stations)
    }

    private func attachObservers(to player: AVPlayer, item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }

                switch item.status {
                case .unknown:
                    self.playbackState = .loading
                case .readyToPlay:
                    if player.timeControlStatus != .waitingToPlayAtSpecifiedRate {
                        self.loadingTimeoutTask?.cancel()
                        self.loadingTimeoutTask = nil
                        self.playbackState = .playing
                    }
                case .failed:
                    self.failPlayback(self.playbackErrorMessage(from: item.error))
                @unknown default:
                    self.failPlayback(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamLoadFailed))
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
                    } else {
                        if case .loading = self.playbackState { break }
                        if case .failed = self.playbackState { break }
                        self.playbackState = .paused
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.playbackState = .loading
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
            Task { @MainActor in
                self?.failPlayback(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamInterrupted))
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.userRequestedPlayback {
                    self.playbackState = .loading
                    self.startLoadingTimeout()
                }
            }
        }

        let metadataDelegate = TuneAVStreamMetadataDelegate { [weak self] events in
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
        persistCurrentNowPlayingState()
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        artworkResolutionTask?.cancel()
        artworkResolutionTask = nil
        lastErrorMessage = message
        playbackState = .failed(message)
        player?.pause()
    }

    private var shouldReloadCurrentStation: Bool {
        guard currentStation != nil else { return false }
        guard let player else { return true }
        guard let item = player.currentItem else { return true }

        if item.status == .failed {
            return true
        }

        if case .failed = playbackState {
            return true
        }

        return false
    }

    private func startLoadingTimeout() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: TuneAVAudioPlaybackPolicy.loadingTimeoutSeconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                if case .loading = self.playbackState {
                    self.failPlayback(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamTimeout))
                }
            }
        }
    }

    private func playbackErrorMessage(from error: Error?) -> String {
        L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamLoadFailed)
    }

    private func observeNetworkChanges() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkPathUpdate(path)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func handleNetworkPathUpdate(_ path: NWPath) {
        let previousStatus = lastNetworkPathStatus
        lastNetworkPathStatus = path.status

        let isRecoverablePlaybackState: Bool
        switch playbackState {
        case .failed, .loading, .paused:
            isRecoverablePlaybackState = true
        case .idle, .playing:
            isRecoverablePlaybackState = false
        }

        if TuneAVAudioPlaybackPolicy.shouldRetryAfterNetworkRestored(
            isNetworkSatisfied: path.status == .satisfied,
            hadPreviousNetworkStatus: previousStatus != nil,
            wasPreviouslyUnsatisfied: previousStatus != .satisfied,
            userRequestedPlayback: userRequestedPlayback,
            hasCurrentStation: currentStation != nil,
            isRecoverablePlaybackState: isRecoverablePlaybackState
        ) {
            retry()
        }
    }

    private func teardownObservers() {
        persistCurrentNowPlayingState()
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
            guard let self else { return }
            guard nowPlayingService.supports(station) else { return }

            try? await Task.sleep(for: TuneAVAudioPlaybackPolicy.nowPlayingFallbackInitialDelay)

            while !Task.isCancelled {
                guard self.currentStation?.id == station.id else { return }
                if self.currentTrackSource == .stream { return }

                guard let track = await self.nowPlayingService.fetchTrack(for: station) else {
                    try? await Task.sleep(for: TuneAVAudioPlaybackPolicy.nowPlayingFallbackPollingInterval)
                    continue
                }

                self.applyFallbackTrack(track, for: station)

                try? await Task.sleep(for: TuneAVAudioPlaybackPolicy.nowPlayingFallbackPollingInterval)
            }
        }
    }

    private func updateTrackMetadata(from events: [TuneAVStreamMetadataEvent]) async {
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

        if TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(resolvedTitle, stationName: currentStation?.name) {
            resolvedTitle = nil
            resolvedArtist = nil
        } else if TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(resolvedArtist, stationName: currentStation?.name) {
            resolvedArtist = nil
        }

        applyTrackMetadata(title: resolvedTitle, artist: resolvedArtist)
    }

    private func applyFallbackTrack(_ track: NowPlayingTrack, for station: Station) {
        guard currentStation?.id == station.id else { return }
        guard currentTrackSource != .stream else { return }

        let normalizedArtist = TuneAVTrackMetadataParser.sanitizeArtist(track.artist)
        guard let normalizedTitle = TuneAVTrackMetadataParser.sanitizeTitle(track.title, artist: normalizedArtist) else { return }
        guard !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(normalizedTitle, stationName: station.name) else { return }

        let resolvedArtist = TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(normalizedArtist, stationName: station.name)
            ? nil
            : normalizedArtist

        currentTrackSource = .fallback
        applyTrackMetadata(title: normalizedTitle, artist: resolvedArtist)
    }

    private func applyTrackMetadata(title: String?, artist: String?) {
        guard title != currentTrackTitle || artist != currentTrackArtist else { return }

        currentTrackTitle = title
        currentTrackArtist = artist
        currentTrackAlbumTitle = nil
        persistCurrentNowPlayingState()
        resolveArtworkForCurrentTrack()
    }

    private func resolveArtworkForCurrentTrack() {
        artworkResolutionTask?.cancel()

        guard let artist = currentTrackArtist, let title = currentTrackTitle else {
            currentTrackAlbumTitle = nil
            currentTrackArtworkURL = nil
            return
        }

        currentTrackAlbumTitle = nil
        currentTrackArtworkURL = nil
        artworkResolutionTask = Task { [weak self] in
            guard let self else { return }
            let resolved = await trackArtworkService.resolveArtwork(artist: artist, title: title)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentTrackArtist == artist, self.currentTrackTitle == title else { return }
                self.currentTrackAlbumTitle = resolved?.albumTitle
                self.currentTrackArtworkURL = resolved?.artworkURL
                self.persistCurrentNowPlayingState()
            }
        }
    }

    private func clearTrackMetadata() {
        artworkResolutionTask?.cancel()
        artworkResolutionTask = nil
        currentTrackSource = nil
        currentTrackTitle = nil
        currentTrackArtist = nil
        currentTrackAlbumTitle = nil
        currentTrackArtworkURL = nil
    }

    private func persistCurrentNowPlayingState() {
        guard let stationID = currentStation?.id else { return }

        let hasVisibleMetadata =
            currentTrackTitle != nil ||
            currentTrackArtist != nil ||
            currentTrackAlbumTitle != nil ||
            currentTrackArtworkURL != nil

        guard hasVisibleMetadata else { return }

        cachedNowPlayingByStationID[stationID] = TuneAVCachedNowPlayingState(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            albumTitle: currentTrackAlbumTitle,
            artworkURL: currentTrackArtworkURL
        )
    }

    private func restoreCachedNowPlaying(for station: Station) {
        guard let cachedState = cachedNowPlayingByStationID[station.id] else { return }

        let sanitizedArtist = TuneAVTrackMetadataParser.sanitizeArtist(cachedState.artist)
        let sanitizedTitle = TuneAVTrackMetadataParser.sanitizeTitle(cachedState.title, artist: sanitizedArtist)
        currentTrackTitle = sanitizedTitle
        currentTrackArtist = sanitizedArtist
        currentTrackAlbumTitle = cachedState.albumTitle
        currentTrackArtworkURL = cachedState.artworkURL
        currentTrackSource = sanitizedTitle != nil || sanitizedArtist != nil ? .cached : nil
    }

    deinit {
        networkMonitor.cancel()
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
