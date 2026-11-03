@preconcurrency import ActivityKit
import Combine
import CryptoKit
import Foundation
import OSLog
import UIKit

@MainActor
final class TuneAVLiveActivityController {
    static let shared = TuneAVLiveActivityController()

    private typealias NowPlayingActivity = Activity<TuneAVNowPlayingAttributes>

    private static let logger = Logger(subsystem: "com.avalsys.tuneav", category: "live-activity")
    private static let coalescingDelay: Duration = .milliseconds(250)
    private static let minimumUpdateInterval: TimeInterval = 1
    private static let artworkPixelSize = 168
    private static let artworkCompressionQuality: CGFloat = 0.82

    private weak var audioPlayer: AudioPlayerService?
    private weak var libraryStore: LibraryStore?
    private weak var accessController: AccessController?
    private var cancellables: Set<AnyCancellable> = []
    private var activity: NowPlayingActivity?
    private var activityStateTask: Task<Void, Never>?
    private var lastPushedState: TuneAVNowPlayingContentState?
    private var throttle = TuneAVLiveActivityUpdateThrottle(minimumInterval: TuneAVLiveActivityController.minimumUpdateInterval)
    private var scheduledEvaluation: Task<Void, Never>?
    private var throttledEvaluation: Task<Void, Never>?
    private var operationTail: Task<Void, Never>?
    private var isSuppressedUntilNextStart = false
    private var isStartBlockedUntilActive = false
    private var artworkSourceURL: URL?
    private var artworkFileName: String?
    private var lastWrittenArtworkFileName: String?
    private var artworkTask: Task<Void, Never>?

    private init() {}

    func attach(audioPlayer: AudioPlayerService, libraryStore: LibraryStore, accessController: AccessController) {
        guard self.audioPlayer == nil else { return }
        self.audioPlayer = audioPlayer
        self.libraryStore = libraryStore
        self.accessController = accessController

        TuneAVLiveActivityActionRouter.handler = { [weak self] action in
            await self?.handle(action)
        }

        audioPlayer.objectWillChange
            .merge(with: libraryStore.objectWillChange)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleEvaluation()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isStartBlockedUntilActive = false
                    self?.scheduleEvaluation()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { _ in
                MainActor.assumeIsolated {
                    Self.endAllActivitiesBeforeTermination()
                }
            }
            .store(in: &cancellables)

        endActivitiesLeftByPreviousLaunch()
    }

    private func handle(_ action: TuneAVLiveActivityAction) async {
        guard let audioPlayer else { return }

        switch action {
        case .togglePlayback:
            if audioPlayer.isPlaying || audioPlayer.isLoading {
                audioPlayer.pause()
            } else {
                audioPlayer.togglePlayback()
            }
        case .toggleHeart:
            guard let libraryStore, let accessController, let station = audioPlayer.currentStation else { break }
            switch TuneAVHeartAction.target(
                title: audioPlayer.currentTrackTitle,
                artist: audioPlayer.currentTrackArtist,
                station: station
            ) {
            case .song:
                TuneAVHeartAction.toggleCurrentSong(
                    title: audioPlayer.currentTrackTitle,
                    artist: audioPlayer.currentTrackArtist,
                    artworkURL: audioPlayer.currentTrackArtworkURL,
                    station: station,
                    libraryStore: libraryStore,
                    accessController: accessController
                )
            case .station:
                TuneAVHeartAction.toggleStationFavorite(
                    station,
                    libraryStore: libraryStore,
                    accessController: accessController
                )
            }
        }

        scheduledEvaluation?.cancel()
        scheduledEvaluation = nil
        evaluate(bypassThrottle: true)
        await operationTail?.value
    }

    private func scheduleEvaluation() {
        guard scheduledEvaluation == nil else { return }
        scheduledEvaluation = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescingDelay)
            guard !Task.isCancelled, let self else { return }
            self.scheduledEvaluation = nil
            self.evaluate(bypassThrottle: false)
        }
    }

    private func scheduleThrottledEvaluation(after delay: TimeInterval) {
        guard throttledEvaluation == nil else { return }
        throttledEvaluation = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.throttledEvaluation = nil
            self.evaluate(bypassThrottle: false)
        }
    }

    private func evaluate(bypassThrottle: Bool) {
        guard let audioPlayer, let libraryStore else { return }

        let status = audioPlayer.status
        if !TuneAVLiveActivityStateMapper.isPlaybackStarting(status) {
            isSuppressedUntilNextStart = false
        }

        guard let station = audioPlayer.currentStation,
              TuneAVLiveActivityStateMapper.playback(for: status) != nil else {
            endActivity()
            return
        }

        guard activity != nil || ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        updateArtworkSource(audioPlayer.currentTrackArtworkURL ?? station.displayArtworkURL)

        let heartTarget = TuneAVHeartAction.target(
            title: audioPlayer.currentTrackTitle,
            artist: audioPlayer.currentTrackArtist,
            station: station
        )
        let input = TuneAVLiveActivityInput(
            station: station,
            status: status,
            trackTitle: audioPlayer.currentTrackTitle,
            trackArtist: audioPlayer.currentTrackArtist,
            isSaved: TuneAVHeartAction.isSaved(
                target: heartTarget,
                title: audioPlayer.currentTrackTitle,
                artist: audioPlayer.currentTrackArtist,
                station: station,
                libraryStore: libraryStore
            ),
            heartTarget: heartTarget,
            artworkFileName: artworkFileName
        )
        guard let state = TuneAVLiveActivityStateMapper.contentState(
            for: input,
            strings: .localized
        ) else {
            endActivity()
            return
        }

        guard let activity else {
            startActivityIfNeeded(with: state, status: status)
            return
        }

        guard state != lastPushedState else { return }

        let delay = bypassThrottle ? 0 : throttle.delay(now: Date())
        guard delay <= 0 else {
            scheduleThrottledEvaluation(after: delay)
            return
        }

        throttledEvaluation?.cancel()
        throttledEvaluation = nil
        lastPushedState = state
        throttle.recordUpdate(at: Date())
        enqueue {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func startActivityIfNeeded(with state: TuneAVNowPlayingContentState, status: TuneAVPlaybackState) {
        guard TuneAVLiveActivityStateMapper.isPlaybackStarting(status),
              !isSuppressedUntilNextStart,
              !isStartBlockedUntilActive,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        do {
            let newActivity = try NowPlayingActivity.request(
                attributes: TuneAVNowPlayingAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            activity = newActivity
            lastPushedState = state
            throttle.recordUpdate(at: Date())
            observeState(of: newActivity)
            endActivities(except: newActivity.id)
        } catch {
            isStartBlockedUntilActive = true
            Self.logger.debug("Live Activity request was not started")
        }
    }

    private func observeState(of activity: NowPlayingActivity) {
        activityStateTask?.cancel()
        let activityID = activity.id
        activityStateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                switch state {
                case .dismissed, .ended:
                    self?.handleActivityFinished(id: activityID)
                    return
                default:
                    continue
                }
            }
        }
    }

    private func handleActivityFinished(id: String) {
        guard activity?.id == id else { return }
        resetActivityReference()
        if let status = audioPlayer?.status, TuneAVLiveActivityStateMapper.isPlaybackStarting(status) {
            isSuppressedUntilNextStart = true
        }
    }

    private func endActivity() {
        throttledEvaluation?.cancel()
        throttledEvaluation = nil
        artworkTask?.cancel()
        artworkTask = nil
        artworkSourceURL = nil
        artworkFileName = nil

        guard let activity else { return }
        resetActivityReference()
        enqueue {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func resetActivityReference() {
        activityStateTask?.cancel()
        activityStateTask = nil
        activity = nil
        lastPushedState = nil
        throttle.reset()
    }

    private func endActivities(except activityID: String) {
        let others = NowPlayingActivity.activities.filter { $0.id != activityID }
        guard !others.isEmpty else { return }
        enqueue {
            for other in others {
                await other.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func endActivitiesLeftByPreviousLaunch() {
        let leftovers = NowPlayingActivity.activities
        guard !leftovers.isEmpty else { return }
        enqueue {
            for leftover in leftovers {
                await leftover.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = operationTail
        operationTail = Task {
            await previous?.value
            await operation()
        }
    }

    private static func endAllActivitiesBeforeTermination() {
        let activities = NowPlayingActivity.activities
        guard !activities.isEmpty else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
    }

    private func updateArtworkSource(_ url: URL?) {
        guard url != artworkSourceURL else { return }
        artworkSourceURL = url
        artworkFileName = nil
        artworkTask?.cancel()
        artworkTask = nil

        guard let url, let directory = TuneAVSharedContainer.liveActivityDirectoryURL else { return }
        let previousFileName = lastWrittenArtworkFileName

        artworkTask = Task { [weak self] in
            guard let image = await TuneAVArtworkImagePipeline.shared.uiImage(
                from: url,
                maxPixelSize: Self.artworkPixelSize
            ) else { return }
            guard !Task.isCancelled,
                  let data = image.jpegData(compressionQuality: Self.artworkCompressionQuality) else { return }

            let fileName = Self.artworkFileName(for: url)
            let didWrite = await Task.detached(priority: .utility) {
                Self.writeArtwork(data, fileName: fileName, directory: directory, keeping: previousFileName)
            }.value

            guard didWrite, !Task.isCancelled, let self, self.artworkSourceURL == url else { return }
            self.lastWrittenArtworkFileName = fileName
            self.artworkFileName = fileName
            self.scheduleEvaluation()
        }
    }

    nonisolated static func artworkFileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "artwork-\(hex.prefix(24)).jpg"
    }

    private nonisolated static func writeArtwork(
        _ data: Data,
        fileName: String,
        directory: URL,
        keeping previousFileName: String?
    ) -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
            if !fileManager.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }

            let keep: Set<String> = [fileName, previousFileName].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
            for existing in try fileManager.contentsOfDirectory(atPath: directory.path) where !keep.contains(existing) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(existing, isDirectory: false))
            }
            return true
        } catch {
            return false
        }
    }
}
