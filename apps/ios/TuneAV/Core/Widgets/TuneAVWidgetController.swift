import Combine
import Foundation
import OSLog
import UIKit
import WidgetKit

@MainActor
final class TuneAVWidgetController {
    typealias ShellPlaybackHandler = @MainActor (Station, TuneAVPlaybackQueueSource, [Station]?) -> Void

    static let shared = TuneAVWidgetController()

    private nonisolated static let logger = Logger(subsystem: "com.avalsys.tuneav", category: "widgets")
    private static let coalescingDelay: Duration = .milliseconds(500)
    private static let launchSettleDelay: Duration = .seconds(2)
    private static let artworkPixelSize = 180
    private static let artworkRetryInterval: TimeInterval = 300
    private static let favoriteCandidateLimit = 12
    private nonisolated static let artworkCompressionQuality: CGFloat = 0.82

    private weak var audioPlayer: AudioPlayerService?
    private weak var libraryStore: LibraryStore?
    private weak var accessController: AccessController?
    private var shellPlaybackHandler: ShellPlaybackHandler?
    private var shellPlaybackToken: UUID?
    private var cancellables: Set<AnyCancellable> = []
    private var directory: URL?
    private var isLaunchSettled = false
    private var launchSettleTask: Task<Void, Never>?
    private var scheduledEvaluation: Task<Void, Never>?
    private var scheduledReload: Task<Void, Never>?
    private var ioTail: Task<Void, Never>?
    private var lastSnapshot: TuneAVWidgetSnapshot?
    private var reloadThrottle = TuneAVLiveActivityUpdateThrottle(minimumInterval: TuneAVWidgetReloadPlanner.minimumInterval)
    private var artworkFileNames: [URL: String] = [:]
    private var artworkInFlight: [URL: String] = [:]
    private var artworkFailures: [URL: Date] = [:]
    private var launchArtworkFileNames: Set<String> = []
    private var pendingReloadKinds: Set<String> = []
    private var pendingRecentStationID: String?

    private init() {}

    func attach(audioPlayer: AudioPlayerService, libraryStore: LibraryStore, accessController: AccessController) {
        guard self.audioPlayer == nil else { return }
        self.audioPlayer = audioPlayer
        self.libraryStore = libraryStore
        self.accessController = accessController

        TuneAVWidgetActionRouter.handler = { [weak self] action in
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
                    guard let self else { return }
                    if self.isLaunchSettled {
                        self.scheduleEvaluation()
                    } else {
                        self.settleAfterLaunch(delay: Self.launchSettleDelay)
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleEvaluation()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.writeStoppedStateBeforeTermination()
                }
            }
            .store(in: &cancellables)
    }

    func registerShellPlayback(_ handler: @escaping ShellPlaybackHandler) -> UUID {
        let token = UUID()
        shellPlaybackHandler = handler
        shellPlaybackToken = token
        return token
    }

    func unregisterShellPlayback(token: UUID?) {
        guard let token, token == shellPlaybackToken else { return }
        shellPlaybackHandler = nil
        shellPlaybackToken = nil
    }

    private func settleAfterLaunch(delay: Duration) {
        guard !isLaunchSettled, launchSettleTask == nil else { return }
        launchSettleTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            let (directory, baseline, artworkFileNames) = await Task.detached(priority: .utility) {
                () -> (URL?, TuneAVWidgetSnapshot?, Set<String>) in
                guard let directory = TuneAVSharedContainer.widgetsDirectoryURL else { return (nil, nil, []) }
                let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
                return (
                    directory,
                    TuneAVWidgetSnapshotStore.read(from: directory),
                    Set(fileNames.filter(TuneAVSharedContainer.isValidArtworkFileName))
                )
            }.value
            guard let self else { return }
            self.directory = directory
            self.lastSnapshot = baseline
            self.launchArtworkFileNames = artworkFileNames
            self.isLaunchSettled = true
            self.launchSettleTask = nil
            self.evaluate(bypassThrottle: false)
        }
    }

    private func waitUntilLaunchSettled() async {
        settleAfterLaunch(delay: .zero)
        launchSettleTask?.cancel()
        await launchSettleTask?.value
    }

    private func handle(_ action: TuneAVWidgetAction) async {
        await waitUntilLaunchSettled()
        guard let audioPlayer, let libraryStore else { return }

        switch action {
        case let .playStation(id, isFavoriteShortcut, expectsActivePlayback):
            switch TuneAVWidgetPlaybackPlanner.command(
                stationID: id,
                isFavoriteShortcut: isFavoriteShortcut,
                expectsActivePlayback: expectsActivePlayback,
                currentStationID: audioPlayer.currentStation?.id,
                status: audioPlayer.status
            ) {
            case .pause:
                audioPlayer.pause()
            case .resume:
                audioPlayer.togglePlayback()
            case .none:
                break
            case .play:
                guard let station = station(for: id) else {
                    Self.logger.debug("Widget station is no longer in the library")
                    break
                }
                let source = TuneAVWidgetPlaybackPlanner.queueSource(isFavoriteShortcut: isFavoriteShortcut)
                let queue = isFavoriteShortcut ? libraryStore.favoriteStations() : nil
                if let shellPlaybackHandler {
                    shellPlaybackHandler(station, source, queue)
                } else if ShellCellularPlaybackGate.decision(
                    warnBeforeCellularPlayback: libraryStore.settings.warnBeforeCellularPlayback,
                    currentNetworkIsExpensive: audioPlayer.currentNetworkIsExpensive
                ) == .requestConfirmation {
                    Self.logger.debug("Widget playback waits for the cellular confirmation in the app")
                } else {
                    audioPlayer.play(
                        station: station,
                        queue: AudioPlayerService.PlaybackQueue(source: source, stations: queue ?? [station])
                    )
                    pendingRecentStationID = station.id
                }
            }
        }

        scheduledEvaluation?.cancel()
        scheduledEvaluation = nil
        evaluate(bypassThrottle: true)
        await ioTail?.value
    }

    private func station(for id: String) -> Station? {
        if let current = audioPlayer?.currentStation, current.id == id {
            return current
        }
        return libraryStore?.station(for: id)
    }

    private func scheduleEvaluation() {
        guard isLaunchSettled, scheduledEvaluation == nil else { return }
        scheduledEvaluation = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescingDelay)
            guard !Task.isCancelled, let self else { return }
            self.scheduledEvaluation = nil
            self.evaluate(bypassThrottle: false)
        }
    }

    private func evaluate(bypassThrottle: Bool) {
        guard isLaunchSettled, let directory, let audioPlayer, let libraryStore else { return }

        recordWidgetStartedPlaybackIfNeeded(audioPlayer: audioPlayer, libraryStore: libraryStore)

        let favorites = libraryStore.favorites
            .prefix(Self.favoriteCandidateLimit)
            .map(Station.init(favorite:))
        var input = TuneAVWidgetSnapshotInput(
            currentStation: audioPlayer.currentStation,
            status: audioPlayer.status,
            trackTitle: audioPlayer.currentTrackTitle,
            trackArtist: audioPlayer.currentTrackArtist,
            lastPlayedStation: libraryStore.station(for: libraryStore.settings.lastPlayedStationID),
            favorites: favorites,
            opensAppToPlay: libraryStore.settings.warnBeforeCellularPlayback,
            artworkFileNames: [:]
        )

        let sources = TuneAVWidgetSnapshotMapper.artworkSources(for: input)
        let wanted = Set(sources)
        artworkFileNames = artworkFileNames.filter { wanted.contains($0.key) }
        for url in sources where artworkFileNames[url] == nil {
            let fileName = TuneAVLiveActivityController.artworkFileName(for: url)
            if launchArtworkFileNames.contains(fileName) {
                artworkFileNames[url] = fileName
            }
        }
        launchArtworkFileNames = []
        input.artworkFileNames = artworkFileNames
        requestArtwork(sources, directory: directory)

        apply(
            TuneAVWidgetSnapshotMapper.snapshot(for: input, strings: .localized),
            directory: directory,
            bypassThrottle: bypassThrottle
        )
    }

    private func recordWidgetStartedPlaybackIfNeeded(audioPlayer: AudioPlayerService, libraryStore: LibraryStore) {
        guard let pendingRecentStationID else { return }
        guard let station = audioPlayer.currentStation, station.id == pendingRecentStationID else {
            self.pendingRecentStationID = nil
            return
        }
        guard audioPlayer.status == .playing else { return }
        self.pendingRecentStationID = nil
        libraryStore.recordPlayback(of: station, recentLimit: accessController?.limits.recentStations)
    }

    private func apply(_ snapshot: TuneAVWidgetSnapshot, directory: URL, bypassThrottle: Bool) {
        let decision = TuneAVWidgetReloadPlanner.decision(
            previous: lastSnapshot,
            next: snapshot,
            throttle: reloadThrottle,
            now: Date()
        )
        guard decision != .none else { return }
        pendingReloadKinds.formUnion(TuneAVWidgetReloadPlanner.kinds(previous: lastSnapshot, next: snapshot))
        lastSnapshot = snapshot

        let keeping = keptFileNames(for: snapshot)
        runIO {
            Self.writeSnapshot(snapshot, directory: directory, keeping: keeping)
        }

        switch decision {
        case .none:
            break
        case .now:
            reloadNow()
        case let .after(delay):
            if bypassThrottle {
                reloadNow()
            } else {
                scheduleReload(after: delay)
            }
        }
    }

    private func keptFileNames(for snapshot: TuneAVWidgetSnapshot) -> Set<String> {
        let referenced = ([snapshot.myRadio] + snapshot.favorites).compactMap { $0?.artworkFileName }
        return Set(referenced)
            .union(artworkFileNames.values)
            .union(artworkInFlight.values)
    }

    private func reloadNow() {
        scheduledReload?.cancel()
        scheduledReload = nil
        reloadThrottle.recordUpdate(at: Date())
        let kinds = TuneAVWidgetKind.all.filter(pendingReloadKinds.contains)
        pendingReloadKinds = []
        guard !kinds.isEmpty else { return }
        let pendingWrites = ioTail
        Task {
            await pendingWrites?.value
            for kind in kinds {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }
    }

    private func scheduleReload(after delay: TimeInterval) {
        guard scheduledReload == nil else { return }
        scheduledReload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.scheduledReload = nil
            self.reloadNow()
        }
    }

    @discardableResult
    private func runIO<T: Sendable>(_ operation: @escaping @Sendable () -> T) -> Task<T, Never> {
        let previous = ioTail
        let task = Task.detached(priority: .utility) { () -> T in
            await previous?.value
            return operation()
        }
        ioTail = Task.detached(priority: .utility) {
            _ = await task.value
        }
        return task
    }

    private func requestArtwork(_ urls: [URL], directory: URL) {
        let now = Date()
        artworkFailures = artworkFailures.filter { now.timeIntervalSince($0.value) < Self.artworkRetryInterval }
        for url in urls where artworkFileNames[url] == nil && artworkInFlight[url] == nil && artworkFailures[url] == nil {
            let fileName = TuneAVLiveActivityController.artworkFileName(for: url)
            let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
            artworkInFlight[url] = fileName

            Task { [weak self] in
                guard let self else { return }
                var didStore = await self.runIO {
                    FileManager.default.fileExists(atPath: fileURL.path)
                }.value

                if !didStore,
                   let image = await TuneAVArtworkImagePipeline.shared.uiImage(from: url, maxPixelSize: Self.artworkPixelSize) {
                    didStore = await self.runIO {
                        Self.writeArtwork(image, to: fileURL)
                    }.value
                }
                self.finishArtwork(url: url, fileName: fileName, didStore: didStore)
            }
        }
    }

    private func finishArtwork(url: URL, fileName: String, didStore: Bool) {
        guard artworkInFlight[url] == fileName else { return }
        artworkInFlight[url] = nil
        guard didStore else {
            artworkFailures[url] = Date()
            return
        }
        artworkFileNames[url] = fileName
        scheduleEvaluation()
    }

    private func writeStoppedStateBeforeTermination() {
        guard let directory, let lastSnapshot, lastSnapshot.playback != .stopped else { return }
        let stopped = TuneAVWidgetSnapshotMapper.stopped(lastSnapshot)
        self.lastSnapshot = stopped
        let keeping = keptFileNames(for: stopped)
        let write = runIO {
            Self.writeSnapshot(stopped, directory: directory, keeping: keeping)
        }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            _ = await write.value
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
        for kind in TuneAVWidgetKind.all {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    private nonisolated static func writeSnapshot(
        _ snapshot: TuneAVWidgetSnapshot,
        directory: URL,
        keeping keptFileNames: Set<String>
    ) {
        do {
            let data = try TuneAVWidgetSnapshotStore.encode(snapshot)
            try TuneAVWidgetSnapshotStore.write(data, to: directory)
            let fileManager = FileManager.default
            for existing in try fileManager.contentsOfDirectory(atPath: directory.path)
            where existing != TuneAVWidgetSnapshotStore.fileName && !keptFileNames.contains(existing) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(existing, isDirectory: false))
            }
        } catch {
            logger.debug("Widget snapshot was not written")
        }
    }

    private nonisolated static func writeArtwork(_ image: UIImage, to fileURL: URL) -> Bool {
        guard let data = image.jpegData(compressionQuality: artworkCompressionQuality) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}
