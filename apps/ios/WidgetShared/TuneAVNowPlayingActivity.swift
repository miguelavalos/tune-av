import ActivityKit
import Foundation

struct TuneAVNowPlayingAttributes: ActivityAttributes {
    typealias ContentState = TuneAVNowPlayingContentState
}

struct TuneAVNowPlayingContentState: Codable, Hashable, Sendable {
    enum Playback: String, Codable, Hashable, Sendable {
        case playing
        case loading
        case paused
    }

    enum HeartTarget: String, Codable, Hashable, Sendable {
        case song
        case station
    }

    var stationName: String
    var songTitle: String?
    var songArtist: String?
    var playback: Playback
    var heartTarget: HeartTarget
    var isSaved: Bool
    var artworkFileName: String?
    var statusText: String
    var playbackActionLabel: String
    var heartActionLabel: String

    var hasSong: Bool {
        songTitle != nil
    }

    var primaryText: String {
        songTitle ?? stationName
    }

    var secondaryText: String {
        guard hasSong else { return statusText }
        return songArtist ?? stationName
    }

    var isLive: Bool {
        playback == .playing
    }
}

enum TuneAVSharedContainer {
    static let appGroupInfoKey = "TuneAVAppGroupIdentifier"
    static let liveActivityFolderName = "LiveActivity"

    static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    static var liveActivityDirectoryURL: URL? {
        guard let appGroupIdentifier,
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
              ) else { return nil }
        return containerURL.appendingPathComponent(liveActivityFolderName, isDirectory: true)
    }

    static func liveActivityArtworkURL(fileName: String) -> URL? {
        guard isValidArtworkFileName(fileName) else { return nil }
        return liveActivityDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func isValidArtworkFileName(_ fileName: String) -> Bool {
        guard fileName.hasPrefix("artwork-"), fileName.hasSuffix(".jpg"), fileName.count <= 64 else { return false }
        return fileName.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
    }
}
