import AppKit
import MediaPlayer

@MainActor
final class MacNowPlayingSystemController {
    private var lastSignature: String?

    func configureRemoteCommands(
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        toggle: @escaping @MainActor () -> Void,
        next: @escaping @MainActor () -> Void,
        previous: @escaping @MainActor () -> Void
    ) {
        let commandCenter = MPRemoteCommandCenter.shared()
        removeRemoteCommandTargets()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in play() }
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in toggle() }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor in next() }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor in previous() }
            return .success
        }
    }

    func update(
        station: Station?,
        title: String?,
        artist: String?,
        albumTitle: String?,
        isPlaying: Bool,
        elapsedTime: Double?
    ) {
        guard let station else {
            clear()
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: TuneAVDisplayMetadata.normalized(title) ?? station.name,
            MPMediaItemPropertyArtist: TuneAVDisplayMetadata.normalized(artist) ?? station.country,
            MPMediaItemPropertyAlbumTitle: TuneAVDisplayMetadata.normalized(albumTitle) ?? station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let elapsedTime, elapsedTime.isFinite {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        }

        let signature = [
            station.id,
            info[MPMediaItemPropertyTitle] as? String ?? "",
            info[MPMediaItemPropertyArtist] as? String ?? "",
            info[MPMediaItemPropertyAlbumTitle] as? String ?? "",
            isPlaying ? "playing" : "notPlaying",
            "\(Int((elapsedTime ?? -1).rounded(.down)))"
        ].joined(separator: "\u{1F}")

        guard signature != lastSignature else { return }
        lastSignature = signature
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        lastSignature = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func removeRemoteCommandTargets() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
    }

}
