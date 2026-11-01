import Foundation

/// A play of one station at one moment, as Avi remembers it on this device.
struct TuneAVRecentPlay: Equatable {
    let station: Station
    let playedAt: Date
}

/// Device-local memory of when each station was played. Avi uses it to notice habits
/// (returns to one radio, the hour of day a radio is usually on) without any backend.
struct TuneAVStationPlayLog: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let stationID: String
        let playedAt: Date
    }

    static let storageKey = "tuneav.stationPlayLog.v1"
    static let retention: TimeInterval = 14 * 24 * 60 * 60
    static let maxEntries = 400
    static let returningWindow: TimeInterval = 7 * 24 * 60 * 60
    static let returningMinimumCount = 3

    var entries: [Entry] = []

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    func recording(_ stationID: String, at date: Date = .now) -> TuneAVStationPlayLog {
        var next = pruned(now: date)
        next.entries.append(Entry(stationID: stationID, playedAt: date))
        if next.entries.count > Self.maxEntries {
            next.entries.removeFirst(next.entries.count - Self.maxEntries)
        }
        return next
    }

    func pruned(now: Date = .now) -> TuneAVStationPlayLog {
        let cutoff = now.addingTimeInterval(-Self.retention)
        return TuneAVStationPlayLog(entries: entries.filter { $0.playedAt >= cutoff && $0.playedAt <= now })
    }

    func plays(for stationID: String) -> [Date] {
        entries.filter { $0.stationID == stationID }.map(\.playedAt)
    }

    /// The station played most often since `since`, when it reached `minimumCount` plays.
    func mostPlayedStation(
        since: Date,
        minimumCount: Int = TuneAVStationPlayLog.returningMinimumCount
    ) -> (stationID: String, count: Int)? {
        var counts: [String: Int] = [:]
        var lastPlayed: [String: Date] = [:]
        for entry in entries where entry.playedAt >= since {
            counts[entry.stationID, default: 0] += 1
            lastPlayed[entry.stationID] = max(lastPlayed[entry.stationID] ?? .distantPast, entry.playedAt)
        }
        guard let best = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (lastPlayed[lhs.key] ?? .distantPast) < (lastPlayed[rhs.key] ?? .distantPast)
        }), best.value >= minimumCount else { return nil }
        return (best.key, best.value)
    }

    /// Expands recent stations into timestamped plays. A station without logged plays falls back
    /// to `lastPlayedByID` so older installs keep a usable "last played" moment.
    func recentPlays(stations: [Station], lastPlayedByID: [String: Date] = [:]) -> [TuneAVRecentPlay] {
        var plays: [TuneAVRecentPlay] = []
        var seen = Set<String>()
        for station in stations where !seen.contains(station.id) {
            seen.insert(station.id)
            let logged = self.plays(for: station.id)
            if logged.isEmpty {
                if let lastPlayed = lastPlayedByID[station.id] {
                    plays.append(TuneAVRecentPlay(station: station, playedAt: lastPlayed))
                }
            } else {
                plays.append(contentsOf: logged.map { TuneAVRecentPlay(station: station, playedAt: $0) })
            }
        }
        return plays
    }

    static func load(from defaults: UserDefaults = .standard, key: String = TuneAVStationPlayLog.storageKey) -> TuneAVStationPlayLog {
        guard let data = defaults.data(forKey: key),
              let log = try? JSONDecoder().decode(TuneAVStationPlayLog.self, from: data) else {
            return TuneAVStationPlayLog()
        }
        return log.pruned()
    }

    func save(to defaults: UserDefaults = .standard, key: String = TuneAVStationPlayLog.storageKey) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }
}
