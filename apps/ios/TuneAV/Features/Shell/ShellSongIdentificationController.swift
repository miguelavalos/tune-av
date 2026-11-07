import Foundation
import OSLog

/// Drives one "What's playing?" identification at a time for the full player: it runs the
/// identifier off the main actor, publishes the listening state and the result, and forgets the
/// result when the station changes. Metering and the player update stay with the caller.
@MainActor
final class ShellSongIdentificationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening(stationID: String, streamTitle: TuneAVTrackMetadata?)
        case matched(stationID: String, track: TuneAVIdentifiedTrack)
        case noMatch(stationID: String)
        case unsupported(stationID: String)
        case unavailable(stationID: String)
        case networkFailure(stationID: String)

        var stationID: String? {
            switch self {
            case .idle:
                return nil
            case .listening(let stationID, _),
                 .matched(let stationID, _),
                 .noMatch(let stationID),
                 .unsupported(let stationID),
                 .unavailable(let stationID),
                 .networkFailure(let stationID):
                return stationID
            }
        }

        var isListening: Bool {
            if case .listening = self {
                return true
            }
            return false
        }
    }

    @Published private(set) var phase: Phase = .idle

    /// How long the "identified from the stream" confirmation stays under the player.
    static let matchedConfirmationDuration: Duration = .seconds(8)

    private let identifier: any TuneAVStreamSongIdentifying
    private let logger = Logger(subsystem: "com.avalsys.tuneav", category: "identify")
    private var task: Task<Void, Never>?
    private var generation = 0

    init(identifier: any TuneAVStreamSongIdentifying) {
        self.identifier = identifier
    }

    deinit {
        task?.cancel()
    }

    func isListening(stationID: String?) -> Bool {
        guard let stationID else { return false }
        return phase.isListening && phase.stationID == stationID
    }

    func phase(for stationID: String?) -> Phase {
        guard let stationID, phase.stationID == stationID else { return .idle }
        return phase
    }

    /// Starts an identification for `station`. `onResult` runs on the main actor with the final
    /// result unless the run was superseded or cancelled.
    func identify(
        station: Station,
        onResult: @escaping @MainActor (TuneAVStreamSongIdentification) -> Void
    ) {
        guard let streamURL = URL(string: station.streamURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            phase = .unsupported(stationID: station.id)
            return
        }

        task?.cancel()
        generation += 1
        let runGeneration = generation
        let stationID = station.id
        phase = .listening(stationID: stationID, streamTitle: nil)

        let identifier = identifier
        let onStreamTitle: @Sendable (TuneAVTrackMetadata) -> Void = { [weak self] streamTitle in
            Task { @MainActor in
                guard let self, self.generation == runGeneration, case .listening = self.phase else { return }
                self.phase = .listening(stationID: stationID, streamTitle: streamTitle)
            }
        }
        task = Task { [weak self] in
            let result = await identifier.identify(streamURL: streamURL, onStreamTitle: onStreamTitle)
            guard let self, self.generation == runGeneration, !Task.isCancelled else { return }
            self.phase = Self.phase(for: result.outcome, stationID: stationID)
            self.log(result)
            onResult(result)
            if case .matched = self.phase {
                self.scheduleMatchedConfirmationClear(runGeneration: runGeneration)
            }
        }
    }

    private func scheduleMatchedConfirmationClear(runGeneration: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.matchedConfirmationDuration)
            guard let self, self.generation == runGeneration, case .matched = self.phase else { return }
            self.phase = .idle
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        phase = .idle
    }

    /// Drops a finished result (the message under the player) without cancelling a running one.
    func clearResult() {
        guard !phase.isListening else { return }
        phase = .idle
    }

    /// Forgets everything that belongs to another station.
    func resetIfNeeded(currentStationID: String?) {
        guard let activeStationID = phase.stationID, activeStationID != currentStationID else { return }
        cancel()
    }

    private static func phase(for outcome: TuneAVStreamSongIdentificationOutcome, stationID: String) -> Phase {
        switch outcome {
        case .matched(let track):
            return .matched(stationID: stationID, track: track)
        case .noMatch:
            return .noMatch(stationID: stationID)
        case .unsupportedStream:
            return .unsupported(stationID: stationID)
        case .unavailable:
            return .unavailable(stationID: stationID)
        case .networkFailure:
            return .networkFailure(stationID: stationID)
        case .cancelled:
            return .idle
        }
    }

    private func log(_ result: TuneAVStreamSongIdentification) {
        let elapsedMilliseconds = Int(result.elapsed * 1000)
        switch result.outcome {
        case .matched:
            logger.info("Song identification matched elapsedMs=\(elapsedMilliseconds, privacy: .public)")
        case .noMatch:
            logger.info("Song identification found no match elapsedMs=\(elapsedMilliseconds, privacy: .public)")
        case .unsupportedStream(let reason):
            logger.notice("Song identification unsupported reason=\(String(describing: reason), privacy: .public)")
        case .unavailable(let domain, let code):
            logger.error("Song identification unavailable domain=\(domain, privacy: .public) code=\(code, privacy: .public)")
        case .networkFailure:
            logger.notice("Song identification network failure elapsedMs=\(elapsedMilliseconds, privacy: .public)")
        case .cancelled:
            break
        }
    }
}
