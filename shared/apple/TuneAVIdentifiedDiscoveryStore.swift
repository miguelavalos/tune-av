import Foundation

/// Remembers, on this device only, which discoveries came from a stream identification rather
/// than from the station's metadata, so the history can show it. Keyed by the discovery ID the
/// library builds for the track; the list stays short and never syncs (see `docs/pro-sync-scope.md`).
struct TuneAVIdentifiedDiscoveryStore {
    static let defaultsKey = "tuneav.identifiedDiscoveries"
    static let maximumCount = 200

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contains(_ discoveryID: String) -> Bool {
        identifiers.contains(discoveryID)
    }

    func remember(_ discoveryID: String) {
        var current = identifiers
        current.removeAll { $0 == discoveryID }
        current.append(discoveryID)
        if current.count > Self.maximumCount {
            current.removeFirst(current.count - Self.maximumCount)
        }
        defaults.set(current, forKey: Self.defaultsKey)
    }

    func forget(_ discoveryID: String) {
        var current = identifiers
        current.removeAll { $0 == discoveryID }
        defaults.set(current, forKey: Self.defaultsKey)
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private var identifiers: [String] {
        defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }
}
