@preconcurrency import AVFoundation
import Foundation
import ImageIO
import MediaPlayer
import Network
import OSLog
import UIKit

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "com.avalsys.tuneav", category: "audio")

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
    @Published private(set) var activeSleepTimerMinutes: Int?
    @Published private(set) var activeSleepTimerRemainingMinutes: Int?
    @Published private(set) var autoSkipNotice: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var consecutiveFailureCount = 0
    @Published private(set) var temporarilyUnstableStationIDs: Set<String> = []
    @Published private(set) var currentNetworkIsExpensive = false
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

    var shouldSuggestFailureRecovery: Bool {
        hasFailure && consecutiveFailureCount >= 2
    }

    private var player: AVPlayer?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var memoryWarningObserver: NSObjectProtocol?
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
    private var sleepTimerRemainingTask: Task<Void, Never>?
    private var autoSkipNoticeTask: Task<Void, Never>?
    private var nowPlayingPollingTask: Task<Void, Never>?
    private var artworkResolutionTask: Task<Void, Never>?
    private var nowPlayingArtworkTask: Task<Void, Never>?
    private let nowPlayingService = NowPlayingService()
    private let trackArtworkService = TrackArtworkService()
    private var currentTrackSource: TrackSource?
    private var cachedNowPlayingByStationID: [String: TuneAVCachedNowPlayingState] = [:]
    private var cachedNowPlayingStationIDs: [String] = []
    private var nowPlayingArtworkImage: UIImage?
    private var nowPlayingArtworkSourceURL: URL?
    private var lastNowPlayingInfoSignature: String?
    private static let maxCachedNowPlayingStations = 80
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

    private func setCurrentStation(_ station: Station?) {
        guard currentStation != station else { return }
        currentStation = station
    }

    private func setPlaybackQueue(_ queue: PlaybackQueue) {
        guard playbackQueue != queue else { return }
        playbackQueue = queue
    }

    private func setSleepTimerDescription(_ description: String?) {
        guard sleepTimerDescription != description else { return }
        sleepTimerDescription = description
    }

    private func setAutoSkipNotice(_ notice: String?) {
        guard autoSkipNotice != notice else { return }
        autoSkipNotice = notice
    }

    private func setLastErrorMessage(_ message: String?) {
        guard lastErrorMessage != message else { return }
        lastErrorMessage = message
    }

    private func setConsecutiveFailureCount(_ count: Int) {
        guard consecutiveFailureCount != count else { return }
        consecutiveFailureCount = count
    }

    override init() {
        super.init()
        configureAudioSession()
        configureRemoteCommands()
        observeAudioSessionNotifications()
        observeMemoryWarnings()
        observeNetworkChanges()
    }

    deinit {
        networkMonitor.cancel()
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func applyUITestTrackMetadata(title: String?, artist: String?) {
        guard TuneAVUITestEnvironment.current.isEnabled else { return }
        setCurrentTrackIdentity(title: title, artist: artist)
        currentTrackSource = title == nil && artist == nil ? nil : .fallback
        persistCurrentNowPlayingState()
        updateNowPlayingInfo()
    }

    func play(station: Station, queue: PlaybackQueue? = nil) {
        if case .loading = status,
           currentStation?.id == station.id,
           currentStation?.streamURL == station.streamURL {
            return
        }

        if let queue {
            setPlaybackQueue(sanitizedPlaybackQueue(queue, currentStationID: station.id))
        }

        guard let url = URL(string: station.streamURL) else {
            setFailure(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.invalidURL))
            return
        }

        if currentStation?.id != station.id {
            setConsecutiveFailureCount(0)
        }
        resetTransientStateForNewPlayback()
        userRequestedPlayback = true
        setCurrentStation(station)
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

    func select(station: Station, queue: PlaybackQueue? = nil) {
        if case .playing = status {
            stop()
        } else if case .loading = status {
            stop()
        }

        if currentStation?.id != station.id {
            setConsecutiveFailureCount(0)
        }

        setCurrentStation(station)
        restoreCachedNowPlaying(for: station)
        setPlaybackQueue(sanitizedPlaybackQueue(
            queue ?? PlaybackQueue(source: .singleStation, stations: [station]),
            currentStationID: station.id
        ))
        userRequestedPlayback = false
        setStatus(.paused)
        setLastErrorMessage(nil)
        setAutoSkipNotice(nil)
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
        setLastErrorMessage(nil)
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
        stop(preservingPlaybackContext: false)
    }

    private func stopForSleepTimer() {
        stop(preservingPlaybackContext: true)
    }

    private func stop(preservingPlaybackContext: Bool) {
        persistCurrentNowPlayingState()
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        autoSkipNoticeTask?.cancel()
        autoSkipNoticeTask = nil
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
        removePlayerItemObservers()
        metadataOutput = nil
        metadataDelegate = nil
        currentTrackSource = nil
        setStatus(.idle)
        setLastErrorMessage(nil)
        setAutoSkipNotice(nil)
        setConsecutiveFailureCount(0)
        setCurrentTrackIdentity(title: nil, artist: nil)
        setCurrentTrackArtworkMetadata(albumTitle: nil, artworkURL: nil, artistURL: nil)
        nowPlayingArtworkImage = nil
        nowPlayingArtworkSourceURL = nil
        if !preservingPlaybackContext {
            setPlaybackQueue(.init(source: .singleStation, stations: []))
        }
        lastNowPlayingInfoSignature = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func stopAndClearCurrentStation() {
        stop()
        setCurrentStation(nil)
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

    @discardableResult
    func playNextStableInQueue() -> Bool {
        guard let resolvedQueue = resolvedPlaybackQueue() else { return false }
        guard let station = TuneAVPlaybackQueueLogic.nextStation(
            in: resolvedQueue,
            excluding: temporarilyUnstableStationIDs
        ) else { return false }

        play(station: station, queue: playbackQueue)
        return true
    }

    func playPreviousInQueue() {
        guard let resolvedQueue = resolvedPlaybackQueue() else { return }

        play(station: TuneAVPlaybackQueueLogic.previousStation(in: resolvedQueue), queue: playbackQueue)
    }

    func setSleepTimer(minutes: Int?) {
        activeSleepTimerMinutes = minutes
        sleepTimerRemainingTask?.cancel()
        sleepTimerRemainingTask = nil
        activeSleepTimerRemainingMinutes = minutes
        sleepTimerController.setTimer(
            minutes: minutes,
            setDescription: { [weak self] description in self?.setSleepTimerDescription(description) },
            onFire: { [weak self] in
                self?.activeSleepTimerMinutes = nil
                self?.activeSleepTimerRemainingMinutes = nil
                self?.sleepTimerRemainingTask?.cancel()
                self?.sleepTimerRemainingTask = nil
                self?.stopForSleepTimer()
            }
        )
        startSleepTimerRemainingUpdatesIfNeeded()
    }

    func clearSleepTimerNotice() {
        sleepTimerController.clearNoticeIfIdle(
            isIdle: status == .idle,
            setDescription: { [weak self] description in self?.setSleepTimerDescription(description) }
        )
    }

    private func startSleepTimerRemainingUpdatesIfNeeded() {
        guard activeSleepTimerMinutes != nil else {
            activeSleepTimerRemainingMinutes = nil
            return
        }

        updateSleepTimerRemainingMinutes()
        sleepTimerRemainingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.updateSleepTimerRemainingMinutes()
                }
            }
        }
    }

    private func updateSleepTimerRemainingMinutes() {
        guard activeSleepTimerMinutes != nil else {
            activeSleepTimerRemainingMinutes = nil
            return
        }

        activeSleepTimerRemainingMinutes = sleepTimerController.remainingMinutes()
    }

    func showAutoSkipNotice(for station: Station) {
        setAutoSkipNotice(L10n.string("audio.autoSkip.skipped", station.name))
        scheduleAutoSkipNoticeDismissal()
    }

    func showAutoSkipBlockedNotice() {
        setAutoSkipNotice(L10n.string("audio.autoSkip.noStableStation"))
        scheduleAutoSkipNoticeDismissal()
    }

    func clearAutoSkipNotice() {
        autoSkipNoticeTask?.cancel()
        autoSkipNoticeTask = nil
        setAutoSkipNotice(nil)
    }

    private func scheduleAutoSkipNoticeDismissal() {
        autoSkipNoticeTask?.cancel()
        autoSkipNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.clearAutoSkipNotice()
            }
        }
    }

    func isCurrent(_ station: Station) -> Bool {
        currentStation?.id == station.id
    }

    func isTemporarilyUnstable(_ station: Station) -> Bool {
        temporarilyUnstableStationIDs.contains(station.id)
    }

    func dismissTemporaryInstabilityWarning(for station: Station) {
        temporarilyUnstableStationIDs.remove(station.id)
    }

    func clearTemporaryInstabilityWarnings() {
        temporarilyUnstableStationIDs.removeAll()
        clearAutoSkipNotice()
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

    private func markCurrentStationTemporarilyUnstableIfNeeded() {
        guard consecutiveFailureCount >= 2, let stationID = currentStation?.id else { return }
        temporarilyUnstableStationIDs.insert(stationID)
    }

    private func clearTemporaryInstability(for station: Station?) {
        guard let station else { return }
        temporarilyUnstableStationIDs.remove(station.id)
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
                    self.setConsecutiveFailureCount(0)
                    self.clearTemporaryInstability(for: self.currentStation)
                    if self.player?.timeControlStatus == .playing {
                        self.setStatus(.playing)
                    }
                    self.activateSessionIfNeeded()
                    self.updateNowPlayingInfo()
                case .failed:
                    self.logPlayerItemFailure(item, context: "status_failed")
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
                    self.setConsecutiveFailureCount(0)
                    self.clearTemporaryInstability(for: self.currentStation)
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
                guard let self else { return }
                self.logPlayerItemFailure(item, context: "failed_to_end")
                self.setFailure(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamInterrupted))
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
                    self.logPlayerItemFailure(self.player?.currentItem, context: "loading_timeout")
                    self.setFailure(L10n.string(TuneAVAudioPlaybackPolicy.ErrorKey.streamTimeout))
                }
            }
        }
    }

    private func logPlayerItemFailure(_ item: AVPlayerItem?, context: String) {
        let stationID = currentStation?.id ?? "unknown"
        let streamURL = currentStation?.streamURL ?? "unknown"
        let itemError = item?.error?.localizedDescription ?? "none"
        let errorEvents = playerItemErrorLogSummary(item)

        Self.logger.error(
            "Playback failure context=\(context, privacy: .private) station_id=\(stationID, privacy: .private) stream_url=\(streamURL, privacy: .private) item_error=\(itemError, privacy: .private) error_events=\(errorEvents, privacy: .private)"
        )
    }

    private func playerItemErrorLogSummary(_ item: AVPlayerItem?) -> String {
        guard let events = item?.errorLog()?.events, !events.isEmpty else { return "none" }
        return events.map(playerItemErrorEventSummary(_:)).joined(separator: " || ")
    }

    private func playerItemErrorEventSummary(_ event: AVPlayerItemErrorLogEvent) -> String {
        let statusCode = event.errorStatusCode == 0 ? "no_status" : String(event.errorStatusCode)
        let domain = event.errorDomain
        let comment = event.errorComment ?? "no_comment"
        let uri = event.uri ?? "no_uri"
        return [statusCode, domain, comment, uri].joined(separator: "|")
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
        setConsecutiveFailureCount(consecutiveFailureCount + 1)
        markCurrentStationTemporarilyUnstableIfNeeded()
        setStatus(.failed(message))
        setLastErrorMessage(message)
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
        currentNetworkIsExpensive = path.isExpensive

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
        setLastErrorMessage(nil)
        player?.pause()
        player = nil
        playerItemStatusObserver = nil
        timeControlStatusObserver = nil
        removePlayerItemObservers()
        metadataOutput = nil
        metadataDelegate = nil
        setCurrentTrackIdentity(title: nil, artist: nil)
        setCurrentTrackArtworkMetadata(albumTitle: nil, artworkURL: nil, artistURL: nil)
        currentTrackSource = nil
        nowPlayingArtworkImage = nil
        nowPlayingArtworkSourceURL = nil
        lastNowPlayingInfoSignature = nil
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
            lastNowPlayingInfoSignature = nil
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

        let signature = nowPlayingInfoSignature(station: currentStation, elapsed: info[MPNowPlayingInfoPropertyElapsedPlaybackTime])
        guard signature != lastNowPlayingInfoSignature else {
            refreshNowPlayingArtworkIfNeeded(for: currentStation)
            return
        }
        lastNowPlayingInfoSignature = signature
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        refreshNowPlayingArtworkIfNeeded(for: currentStation)
    }

    private func nowPlayingInfoSignature(station: Station, elapsed: Any?) -> String {
        let elapsedBucket: Int
        if let elapsed = elapsed as? Double, elapsed.isFinite {
            elapsedBucket = Int(elapsed.rounded(.down))
        } else {
            elapsedBucket = -1
        }

        return [
            station.id,
            currentTrackTitle ?? "",
            currentTrackArtist ?? "",
            currentTrackAlbumTitle ?? "",
            currentTrackArtworkURL?.absoluteString ?? "",
            isPlaying ? "playing" : "notPlaying",
            "\(elapsedBucket)",
            nowPlayingArtworkSourceURL?.absoluteString ?? "",
            nowPlayingArtworkImage == nil ? "noImage" : "image"
        ].joined(separator: "\u{1F}")
    }

    private func updateTrackMetadata(from events: [TuneAVStreamMetadataEvent]) async {
        guard !events.isEmpty else { return }
        guard !shouldPreserveUITestTrackMetadata else { return }

        var resolvedTitle = currentTrackTitle
        var resolvedArtist = currentTrackArtist
        var resolvedFromStream = false

        for event in events {
            let value = event.value
            let commonKey = event.commonKey
            let identifier = event.identifier

            if commonKey == "title" || identifier.contains("title") || identifier.contains("streamtitle") {
                let parsed = TuneAVTrackMetadataParser.parse(value)
                guard !TuneAVTrackMetadataParser.titleLooksLikeTruncatedContraction(parsed.title) else {
                    continue
                }
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
        } else if TuneAVTrackMetadataParser.titleLooksLikeTruncatedContraction(resolvedTitle) {
            resolvedTitle = nil
            resolvedArtist = nil
            resolvedFromStream = false
        } else if TuneAVTrackMetadataParser.artistLooksLikeBroadcastMetadata(resolvedArtist, stationName: currentStation?.name) {
            resolvedArtist = nil
        }

        if resolvedTitle != currentTrackTitle || resolvedArtist != currentTrackArtist {
            setCurrentTrackIdentity(title: resolvedTitle, artist: resolvedArtist)
            persistCurrentNowPlayingState()
            resolveArtworkForCurrentTrack()
            updateNowPlayingInfo()
        }

        if !resolvedFromStream, currentTrackSource == .stream {
            currentTrackSource = nil
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
        guard !shouldPreserveUITestTrackMetadata else { return }
        guard currentTrackSource != .stream else { return }

        let normalizedArtist = TuneAVTrackMetadataParser.sanitizeArtist(track.artist)
        guard let normalizedTitle = TuneAVTrackMetadataParser.sanitizeTitle(track.title, artist: normalizedArtist) else { return }
        guard !TuneAVTrackMetadataParser.valueLooksLikeBroadcastMetadata(normalizedTitle, stationName: station.name) else { return }
        guard !TuneAVTrackMetadataParser.titleLooksLikeTruncatedContraction(normalizedTitle) else { return }

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

    private var shouldPreserveUITestTrackMetadata: Bool {
        TuneAVUITestEnvironment.current.isEnabled &&
            (
                TuneAVLaunchContext.current.uiTestTrackTitle != nil ||
                TuneAVLaunchContext.current.uiTestTrackArtist != nil
            )
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
                tuneAVDownsampleNowPlayingArtwork(data, maxPixelSize: 512) ?? UIImage(data: data)
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
            artistURL: currentTrackArtistURL,
            cachedAt: Date()
        )
        rememberCachedNowPlayingStationID(stationID)
    }

    private func restoreCachedNowPlaying(for station: Station) {
        guard let cachedState = cachedNowPlayingByStationID[station.id] else { return }
        guard TuneAVAudioPlaybackPolicy.isCachedNowPlayingFresh(cachedState) else {
            cachedNowPlayingByStationID[station.id] = nil
            cachedNowPlayingStationIDs.removeAll { $0 == station.id }
            return
        }
        rememberCachedNowPlayingStationID(station.id)

        let sanitizedArtist = TuneAVTrackMetadataParser.sanitizeArtist(cachedState.artist)
        let sanitizedTitle = TuneAVTrackMetadataParser.sanitizeTitle(cachedState.title, artist: sanitizedArtist)

        setCurrentTrackMetadata(CurrentTrackMetadata(
            title: sanitizedTitle,
            artist: sanitizedArtist,
            albumTitle: cachedState.albumTitle,
            artworkURL: cachedState.artworkURL,
            artistURL: cachedState.artistURL
        ))
        restoreCachedNowPlayingArtworkImage(for: cachedState.artworkURL)
        currentTrackSource = sanitizedTitle != nil || sanitizedArtist != nil ? .cached : nil
    }

    private func restoreCachedNowPlayingArtworkImage(for artworkURL: URL?) {
        guard let artworkURL else { return }
        guard let cachedImage = Self.nowPlayingArtworkImageCache.object(forKey: artworkURL as NSURL) else { return }

        nowPlayingArtworkSourceURL = artworkURL
        nowPlayingArtworkImage = cachedImage
    }

    private func rememberCachedNowPlayingStationID(_ stationID: String) {
        cachedNowPlayingStationIDs.removeAll { $0 == stationID }
        cachedNowPlayingStationIDs.append(stationID)

        while cachedNowPlayingStationIDs.count > Self.maxCachedNowPlayingStations {
            let removedStationID = cachedNowPlayingStationIDs.removeFirst()
            cachedNowPlayingByStationID[removedStationID] = nil
        }
    }

    private nonisolated static func makeNowPlayingArtwork(from image: UIImage) -> MPMediaItemArtwork {
        let boundsSize = image.size
        return MPMediaItemArtwork(boundsSize: boundsSize) { _ in image }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        removeRemoteCommandTargets()
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
        removeAudioSessionObservers()

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

    private func observeMemoryWarnings() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
    }

    private func handleMemoryWarning() {
        cachedNowPlayingByStationID.removeAll(keepingCapacity: false)
        cachedNowPlayingStationIDs.removeAll(keepingCapacity: false)
        Self.nowPlayingArtworkImageCache.removeAllObjects()
        HomeFeedCache.shared.clearMemoryCache()
        Task {
            await TuneAVArtworkImagePipeline.shared.clearMemoryCache()
            await TuneAVStationResponseCache.shared.clearMemoryCache()
            await TuneAVAlternateMetadataStreamCache.shared.clearMemoryCache()
        }
    }

    private func removeRemoteCommandTargets() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
    }

    private func removeAudioSessionObservers() {
        let center = NotificationCenter.default
        if let interruptionObserver {
            center.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeChangeObserver {
            center.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }

    private func removePlayerItemObservers() {
        let center = NotificationCenter.default
        if let failedToEndObserver {
            center.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        if let playbackStalledObserver {
            center.removeObserver(playbackStalledObserver)
            self.playbackStalledObserver = nil
        }
    }
}

private func tuneAVDownsampleNowPlayingArtwork(_ data: Data, maxPixelSize: Int) -> UIImage? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }

    let thumbnailOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
        return nil
    }

    return UIImage(cgImage: cgImage)
}
