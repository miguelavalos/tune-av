@preconcurrency import AVFoundation
import Foundation
import MediaPlayer
import Network
import UIKit

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    struct PlaybackQueue: Equatable {
        typealias Source = TuneAVPlaybackQueueSource

        let source: Source
        let stations: [Station]
    }

    private struct CurrentTrackMetadata: Equatable {
        var title: String?
        var artist: String?
        var albumTitle: String?
        var artworkURL: URL?
        var artistURL: URL?
    }

    typealias PlaybackStatus = TuneAVPlaybackState

    @Published private(set) var currentStation: Station?
    @Published private(set) var status: PlaybackStatus = .idle
    @Published private(set) var sleepTimerDescription: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private var currentTrackMetadata = CurrentTrackMetadata()
    @Published private(set) var playbackQueue: PlaybackQueue = .init(source: .singleStation, stations: [])

    var currentTrackTitle: String? { currentTrackMetadata.title }
    var currentTrackArtist: String? { currentTrackMetadata.artist }
    var currentTrackAlbumTitle: String? { currentTrackMetadata.albumTitle }
    var currentTrackArtworkURL: URL? { currentTrackMetadata.artworkURL }
    var currentTrackArtistURL: URL? { currentTrackMetadata.artistURL }

    var isPlaying: Bool {
        if case .playing = status {
            return true
        }
        return false
    }

    var isLoading: Bool {
        if case .loading = status {
            return true
        }
        return false
    }

    var hasFailure: Bool {
        if case .failed = status {
            return true
        }
        return false
    }

    private var player: AVPlayer?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var playbackStalledObserver: NSObjectProtocol?
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.tuneav.audio-network-monitor")
    private var lastNetworkPathStatus: NWPath.Status?
    private var userRequestedPlayback = false
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: TuneAVStreamMetadataDelegate?
    private let sleepTimerController = TuneAVSleepTimerController()
    private var loadingTimeoutTask: Task<Void, Never>?
    private var nowPlayingPollingTask: Task<Void, Never>?
    private var artworkResolutionTask: Task<Void, Never>?
    private var nowPlayingArtworkTask: Task<Void, Never>?
    private let nowPlayingService = NowPlayingService()
    private let trackArtworkService = TrackArtworkService()
    private var currentTrackSource: TrackSource?
    private var cachedNowPlayingByStationID: [String: TuneAVCachedNowPlayingState] = [:]
    private var nowPlayingArtworkImage: UIImage?
    private var nowPlayingArtworkSourceURL: URL?
    private static let nowPlayingArtworkImageCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    private enum TrackSource {
        case stream
        case fallback
        case cached
    }

    private func setStatus(_ newStatus: PlaybackStatus) {
        guard status != newStatus else { return }
        status = newStatus
    }

    override init() {
        super.init()
        configureAudioSession()
        configureRemoteCommands()
        observeAudioSessionNotifications()
        observeNetworkChanges()
    }

    deinit {
        networkMonitor.cancel()
    }

    func applyUITestTrackMetadata(title: String?, artist: String?) {
        guard TuneAVUITestEnvironment.current.isEnabled else { return }
        setCurrentTrackIdentity(title: title, artist: artist)
        currentTrackSource = title == nil && artist == nil ? nil : .fallback
        persistCurrentNowPlayingState()
        updateNowPlayingInfo()
    }

    func play(station: Station, queue: PlaybackQueue? = nil) {
        if case .loading = status, currentStation?.id == station.id {
            return
        }

        if let queue {
            playbackQueue = sanitizedPlaybackQueue(queue, currentStationID: station.id)
        }

        guard let url = URL(string: station.streamURL) else {
            setFailure(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.invalidURL))
            return
        }

        resetTransientStateForNewPlayback()
        userRequestedPlayback = true
        currentStation = station
        restoreCachedNowPlaying(for: station)
        setStatus(.loading)

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        attachObservers(to: item)
        observePlayerItemNotifications(for: item)
        startLoadingTimeout()
        startNowPlayingFallback(for: station)
        activateSessionIfNeeded()
        player?.play()
        updateNowPlayingInfo()
    }

    func togglePlayback() {
        switch status {
        case .playing:
            pause()
        case .paused:
            resume()
        case .failed:
            retry()
        case .idle:
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

        activateSessionIfNeeded()
        player?.play()
        setStatus(.loading)
        userRequestedPlayback = true
        lastErrorMessage = nil
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        userRequestedPlayback = false
        if currentStation != nil {
            setStatus(.paused)
        }
        updateNowPlayingInfo()
    }

    func stop() {
        persistCurrentNowPlayingState()
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        nowPlayingPollingTask?.cancel()
        nowPlayingPollingTask = nil
        artworkResolutionTask?.cancel()
        artworkResolutionTask = nil
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        player?.pause()
        userRequestedPlayback = false
        player = nil
        playerItemStatusObserver = nil
        timeControlStatusObserver = nil
        failedToEndObserver = nil
        playbackStalledObserver = nil
        metadataOutput = nil
        metadataDelegate = nil
        currentTrackSource = nil
        setStatus(.idle)
        lastErrorMessage = nil
        setCurrentTrackIdentity(title: nil, artist: nil)
        setCurrentTrackArtworkMetadata(albumTitle: nil, artworkURL: nil, artistURL: nil)
        nowPlayingArtworkImage = nil
        nowPlayingArtworkSourceURL = nil
        playbackQueue = .init(source: .singleStation, stations: [])
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func stopAndClearCurrentStation() {
        stop()
        currentStation = nil
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
            isIdle: status == .idle,
            setDescription: { [weak self] description in self?.sleepTimerDescription = description }
        )
    }

    func isCurrent(_ station: Station) -> Bool {
        currentStation?.id == station.id
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

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            setStatus(.failed(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.sessionUnavailable)))
        }
    }

    private func attachObservers(to item: AVPlayerItem) {
        playerItemStatusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.loadingTimeoutTask?.cancel()
                    self.loadingTimeoutTask = nil
                    if self.player?.timeControlStatus == .playing {
                        self.setStatus(.playing)
                    }
                    self.activateSessionIfNeeded()
                    self.updateNowPlayingInfo()
                case .failed:
                    self.setFailure(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamLoadFailed))
                case .unknown:
                    self.setStatus(.loading)
                @unknown default:
                    self.setStatus(.loading)
                }
            }
        }

        timeControlStatusObserver = player?.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.loadingTimeoutTask?.cancel()
                    self.loadingTimeoutTask = nil
                    self.setStatus(.playing)
                case .paused:
                    if case .loading = self.status { break }
                    if case .failed = self.status { break }
                    self.setStatus(.paused)
                case .waitingToPlayAtSpecifiedRate:
                    self.setStatus(.loading)
                @unknown default:
                    break
                }
                self.updateNowPlayingInfo()
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

    private func observePlayerItemNotifications(for item: AVPlayerItem) {
        let center = NotificationCenter.default
        failedToEndObserver = center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setFailure(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamInterrupted))
            }
        }

        playbackStalledObserver = center.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.userRequestedPlayback {
                    self.setStatus(.loading)
                    self.startLoadingTimeout()
                }
            }
        }
    }

    private func startLoadingTimeout() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: TuneAVAudioPlaybackPolicy.loadingTimeoutSeconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                if case .loading = self.status {
                    self.setFailure(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamTimeout))
                }
            }
        }
    }

    private func setFailure(_ message: String) {
        persistCurrentNowPlayingState()
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        nowPlayingPollingTask?.cancel()
        nowPlayingPollingTask = nil
        artworkResolutionTask?.cancel()
        artworkResolutionTask = nil
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        setStatus(.failed(message))
        lastErrorMessage = message
        player?.pause()
        updateNowPlayingInfo()
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
        switch status {
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

    private func resetTransientStateForNewPlayback() {
        persistCurrentNowPlayingState()
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        nowPlayingPollingTask?.cancel()
        nowPlayingPollingTask = nil
        artworkResolutionTask?.cancel()
        artworkResolutionTask = nil
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = nil
        lastErrorMessage = nil
        player?.pause()
        player = nil
        playerItemStatusObserver = nil
        timeControlStatusObserver = nil
        failedToEndObserver = nil
        playbackStalledObserver = nil
        metadataOutput = nil
        metadataDelegate = nil
        setCurrentTrackIdentity(title: nil, artist: nil)
        setCurrentTrackArtworkMetadata(albumTitle: nil, artworkURL: nil, artistURL: nil)
        currentTrackSource = nil
        nowPlayingArtworkImage = nil
        nowPlayingArtworkSourceURL = nil
    }

    private var shouldReloadCurrentStation: Bool {
        guard currentStation != nil else { return false }
        guard let player else { return true }
        guard let item = player.currentItem else { return true }

        if item.status == .failed {
            return true
        }

        if case .failed = status {
            return true
        }

        return false
    }

    private func activateSessionIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            setStatus(.failed(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.activateAudio)))
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentStation else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrackTitle ?? currentStation.name,
            MPMediaItemPropertyArtist: currentTrackArtist ?? currentStation.country,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        info[MPMediaItemPropertyAlbumTitle] = currentStation.name

        if let artworkImage = resolvedNowPlayingArtworkImage(for: currentStation) {
            info[MPMediaItemPropertyArtwork] = Self.makeNowPlayingArtwork(from: artworkImage)
        }

        if let elapsed = player?.currentTime().seconds, elapsed.isFinite {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        refreshNowPlayingArtworkIfNeeded(for: currentStation)
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

        if resolvedTitle != currentTrackTitle || resolvedArtist != currentTrackArtist {
            setCurrentTrackIdentity(title: resolvedTitle, artist: resolvedArtist)
            persistCurrentNowPlayingState()
            resolveArtworkForCurrentTrack()
            updateNowPlayingInfo()
        }
    }

    private func startNowPlayingFallback(for station: Station) {
        nowPlayingPollingTask?.cancel()
        nowPlayingPollingTask = Task { [weak self] in
            guard let self else { return }
            guard nowPlayingService.supports(station) else { return }

            try? await Task.sleep(for: TuneAVAudioPlaybackPolicy.nowPlayingFallbackInitialDelay)
            guard !Task.isCancelled else { return }

            while !Task.isCancelled {
                guard self.currentStation?.id == station.id else { return }
                if self.currentTrackSource == .stream { return }

                let track = await nowPlayingService.fetchTrack(for: station)
                guard !Task.isCancelled else { return }

                if let track {
                    self.applyFallbackTrack(track, for: station)
                }

                try? await Task.sleep(for: TuneAVAudioPlaybackPolicy.nowPlayingFallbackPollingInterval)
            }
        }
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

        if currentTrackTitle == normalizedTitle && currentTrackArtist == resolvedArtist {
            return
        }

        setCurrentTrackIdentity(title: normalizedTitle, artist: resolvedArtist)
        currentTrackSource = .fallback
        persistCurrentNowPlayingState()
        resolveArtworkForCurrentTrack()
        updateNowPlayingInfo()
    }

    private func resolveArtworkForCurrentTrack() {
        artworkResolutionTask?.cancel()

        guard let artist = currentTrackArtist, let title = currentTrackTitle else {
            setCurrentTrackArtworkMetadata(albumTitle: nil, artworkURL: nil, artistURL: nil)
            return
        }

        setCurrentTrackArtworkMetadata(albumTitle: nil, artworkURL: nil, artistURL: nil)

        artworkResolutionTask = Task { [weak self] in
            guard let self else { return }
            let resolved = await trackArtworkService.resolveArtwork(artist: artist, title: title)
            guard !Task.isCancelled else { return }
            guard self.currentTrackArtist == artist, self.currentTrackTitle == title else { return }

            guard self.setCurrentTrackArtworkMetadata(
                albumTitle: resolved?.albumTitle,
                artworkURL: resolved?.artworkURL,
                artistURL: resolved?.artistURL
            ) else { return }
            self.persistCurrentNowPlayingState()
            self.updateNowPlayingInfo()
        }
    }

    @discardableResult
    private func setCurrentTrackIdentity(title: String?, artist: String?) -> Bool {
        let nextMetadata = CurrentTrackMetadata(
            title: title,
            artist: artist,
            albumTitle: currentTrackAlbumTitle,
            artworkURL: currentTrackArtworkURL,
            artistURL: currentTrackArtistURL
        )
        return setCurrentTrackMetadata(nextMetadata)
    }

    @discardableResult
    private func setCurrentTrackArtworkMetadata(albumTitle: String?, artworkURL: URL?, artistURL: URL?) -> Bool {
        let nextMetadata = CurrentTrackMetadata(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            albumTitle: albumTitle,
            artworkURL: artworkURL,
            artistURL: artistURL
        )
        return setCurrentTrackMetadata(nextMetadata)
    }

    @discardableResult
    private func setCurrentTrackMetadata(_ nextMetadata: CurrentTrackMetadata) -> Bool {
        guard currentTrackMetadata != nextMetadata else { return false }
        currentTrackMetadata = nextMetadata
        return true
    }

    private func resolvedNowPlayingArtworkImage(for station: Station) -> UIImage? {
        if let nowPlayingArtworkImage {
            return nowPlayingArtworkImage
        }

        return UIImage(named: "BrandMark")
    }

    private func refreshNowPlayingArtworkIfNeeded(for station: Station) {
        let artworkURL = currentTrackArtworkURL

        if artworkURL == nowPlayingArtworkSourceURL, nowPlayingArtworkImage != nil {
            return
        }

        if artworkURL == nil, nowPlayingArtworkSourceURL == nil, nowPlayingArtworkImage != nil {
            return
        }

        nowPlayingArtworkTask?.cancel()
        nowPlayingArtworkTask = Task { [weak self] in
            guard let self else { return }
            let resolvedImage = await Self.loadNowPlayingArtworkImage(from: artworkURL)
            guard !Task.isCancelled else { return }
            guard self.currentStation?.id == station.id else { return }

            self.nowPlayingArtworkSourceURL = artworkURL
            self.nowPlayingArtworkImage = resolvedImage ?? UIImage(named: "BrandMark")
            self.updateNowPlayingInfo()
        }
    }

    private static func loadNowPlayingArtworkImage(from url: URL?) async -> UIImage? {
        guard let url else { return UIImage(named: "BrandMark") }

        if let cachedImage = nowPlayingArtworkImageCache.object(forKey: url as NSURL) {
            return cachedImage
        }

        do {
            let (data, _) = try await TuneAVURLSessions.artwork.data(from: url)
            guard !Task.isCancelled else { return nil }
            let image = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
            if let image {
                nowPlayingArtworkImageCache.setObject(image, forKey: url as NSURL, cost: data.count)
            }
            return image
        } catch {
            return UIImage(named: "BrandMark")
        }
    }

    private func persistCurrentNowPlayingState() {
        guard let stationID = currentStation?.id else { return }

        let hasVisibleMetadata =
            currentTrackTitle != nil ||
            currentTrackArtist != nil ||
            currentTrackAlbumTitle != nil ||
            currentTrackArtworkURL != nil ||
            currentTrackArtistURL != nil

        guard hasVisibleMetadata else { return }

        cachedNowPlayingByStationID[stationID] = TuneAVCachedNowPlayingState(
            title: currentTrackTitle,
            artist: currentTrackArtist,
            albumTitle: currentTrackAlbumTitle,
            artworkURL: currentTrackArtworkURL,
            artistURL: currentTrackArtistURL
        )
    }

    private func restoreCachedNowPlaying(for station: Station) {
        guard let cachedState = cachedNowPlayingByStationID[station.id] else { return }

        let sanitizedArtist = TuneAVTrackMetadataParser.sanitizeArtist(cachedState.artist)
        let sanitizedTitle = TuneAVTrackMetadataParser.sanitizeTitle(cachedState.title, artist: sanitizedArtist)

        setCurrentTrackMetadata(CurrentTrackMetadata(
            title: sanitizedTitle,
            artist: sanitizedArtist,
            albumTitle: cachedState.albumTitle,
            artworkURL: cachedState.artworkURL,
            artistURL: cachedState.artistURL
        ))
        currentTrackSource = sanitizedTitle != nil || sanitizedArtist != nil ? .cached : nil
    }

    private nonisolated static func makeNowPlayingArtwork(from image: UIImage) -> MPMediaItemArtwork {
        let boundsSize = image.size
        return MPMediaItemArtwork(boundsSize: boundsSize) { _ in image }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
    }

    private func observeAudioSessionNotifications() {
        let center = NotificationCenter.default

        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt

            Task { @MainActor in
                guard let self else { return }
                guard let typeValue,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                    return
                }

                if type == .began {
                    self.player?.pause()
                    if self.currentStation != nil {
                        self.setStatus(.paused)
                    }
                    self.updateNowPlayingInfo()
                    return
                }

                if let optionsValue {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.resume()
                    }
                }
            }
        }

        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateNowPlayingInfo()
            }
        }
    }
}
