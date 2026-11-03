import Foundation

enum TuneAVWidgetKind {
    static let myRadio = "TuneAVMyRadioWidget"
    static let nowPlayingFavorites = "TuneAVNowPlayingFavoritesWidget"
    static let lockScreen = "TuneAVLockScreenRadioWidget"
    static let all = [myRadio, nowPlayingFavorites, lockScreen]
}

struct TuneAVWidgetStation: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var artworkFileName: String?
}

struct TuneAVWidgetStrings: Codable, Hashable, Sendable {
    var myRadio: String
    var live: String
    var loading: String
    var paused: String
    var play: String
    var pause: String
    var playStationFormat: String
    var openPlayer: String
    var emptyTitle: String
    var emptyMessage: String

    func playStation(_ name: String) -> String {
        guard playStationFormat.contains("%@") else { return "\(playStationFormat) \(name)" }
        return playStationFormat.replacingOccurrences(of: "%@", with: name)
    }
}

struct TuneAVWidgetSnapshot: Codable, Hashable, Sendable {
    enum Playback: String, Codable, Hashable, Sendable {
        case playing
        case loading
        case paused
        case stopped
    }

    static let currentVersion = 1
    static let maximumFavorites = 4

    var version: Int
    var myRadio: TuneAVWidgetStation?
    var playback: Playback
    var songTitle: String?
    var songArtist: String?
    var favorites: [TuneAVWidgetStation]
    var opensAppToPlay: Bool
    var strings: TuneAVWidgetStrings

    var isEmpty: Bool {
        myRadio == nil && favorites.isEmpty
    }

    var isPlaybackActive: Bool {
        playback == .playing || playback == .loading
    }

    var statusText: String {
        switch playback {
        case .playing:
            return strings.live
        case .loading:
            return strings.loading
        case .paused:
            return strings.paused
        case .stopped:
            return strings.myRadio
        }
    }

    var playbackActionLabel: String {
        guard let myRadio else { return strings.play }
        return isPlaybackActive ? strings.pause : strings.playStation(myRadio.name)
    }
}

enum TuneAVWidgetSnapshotStore {
    static let fileName = "snapshot.json"
    static let maximumFileSize = 64 * 1024

    static func encode(_ snapshot: TuneAVWidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) -> TuneAVWidgetSnapshot? {
        guard data.count <= maximumFileSize,
              let snapshot = try? JSONDecoder().decode(TuneAVWidgetSnapshot.self, from: data),
              snapshot.version == TuneAVWidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    static func read(from directory: URL) -> TuneAVWidgetSnapshot? {
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func readShared() -> TuneAVWidgetSnapshot? {
        guard let directory = TuneAVSharedContainer.widgetsDirectoryURL else { return nil }
        return read(from: directory)
    }

    static func write(_ data: Data, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(
            to: directory.appendingPathComponent(fileName, isDirectory: false),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

extension TuneAVSharedContainer {
    static let widgetsFolderName = "Widgets"

    static var widgetsDirectoryURL: URL? {
        guard let appGroupIdentifier,
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
              ) else { return nil }
        return containerURL.appendingPathComponent(widgetsFolderName, isDirectory: true)
    }

    static func widgetArtworkURL(fileName: String) -> URL? {
        guard isValidArtworkFileName(fileName) else { return nil }
        return widgetsDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
    }
}

enum TuneAVWidgetDeepLink: Hashable, Sendable {
    case home
    case player(stationID: String?)
    case play(stationID: String, isFavoriteShortcut: Bool)

    static let host = "widget"
    private static let widgetBundleSuffix = ".widgets"

    static var appURLScheme: String? {
        guard var identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty else { return nil }
        if identifier.hasSuffix(widgetBundleSuffix) {
            identifier.removeLast(widgetBundleSuffix.count)
        }
        return identifier.lowercased()
    }

    func url(scheme: String? = TuneAVWidgetDeepLink.appURLScheme) -> URL? {
        guard let scheme else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = Self.host
        switch self {
        case .home:
            components.path = "/home"
        case let .player(stationID):
            components.path = "/player"
            if let stationID {
                components.queryItems = [URLQueryItem(name: "station", value: stationID)]
            }
        case let .play(stationID, isFavoriteShortcut):
            components.path = "/play"
            components.queryItems = [
                URLQueryItem(name: "station", value: stationID),
                URLQueryItem(name: "favorite", value: isFavoriteShortcut ? "1" : "0"),
            ]
        }
        return components.url
    }

    init?(url: URL, scheme: String? = TuneAVWidgetDeepLink.appURLScheme) {
        guard let scheme,
              url.scheme?.lowercased() == scheme.lowercased(),
              url.host?.lowercased() == Self.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        let stationID = items.first { $0.name == "station" }?.value.flatMap { $0.isEmpty ? nil : $0 }

        switch components.path {
        case "/home":
            self = .home
        case "/player":
            self = .player(stationID: stationID)
        case "/play":
            guard let stationID else { return nil }
            self = .play(stationID: stationID, isFavoriteShortcut: items.first { $0.name == "favorite" }?.value == "1")
        default:
            return nil
        }
    }
}
