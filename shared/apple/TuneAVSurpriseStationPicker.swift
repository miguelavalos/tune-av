import Foundation

/// Hour-of-day bands Avi uses to notice when a radio is usually on.
enum TuneAVHourBand: String, CaseIterable, Equatable {
    case morning
    case midday
    case afternoon
    case evening
    case night

    static func band(for date: Date, calendar: Calendar = .current) -> TuneAVHourBand {
        switch calendar.component(.hour, from: date) {
        case 6..<11: return .morning
        case 11..<15: return .midday
        case 15..<19: return .afternoon
        case 19..<24: return .evening
        default: return .night
        }
    }

    var reasonKey: String {
        "shell.home.surprise.reason.band.\(rawValue)"
    }
}

/// A station Avi can justify, with the reason it would say out loud.
struct TuneAVSurprisePick: Equatable {
    enum Reason: Equatable {
        /// A saved radio not played for `favoriteRestDays` or more.
        case restedFavorite
        /// A saved radio with no dated play in the device-local log. The log is local, keeps
        /// 14 days and started with 1.1.0, and favorites sync from other devices, so Avi only
        /// says the radio is saved and never claims it was never played.
        case savedFavorite
        /// A liked recent radio the listener usually plays in this hour band.
        case hourBand(TuneAVHourBand)
        /// A popular radio sharing one of the listener's most common tags.
        case tag(String)
        /// A popular radio the listener has not played yet.
        case popular
    }

    let station: Station
    let reason: Reason

    var reasonKey: String {
        switch reason {
        case .restedFavorite: return "shell.home.surprise.reason.favoriteRested"
        case .savedFavorite: return "shell.home.surprise.reason.favoriteSaved"
        case .hourBand(let band): return band.reasonKey
        case .tag: return "shell.home.surprise.reason.tag"
        case .popular: return "shell.home.surprise.reason.popular"
        }
    }

    /// Raw arguments in placeholder order; the tag is the station tag, not yet localized.
    var reasonArguments: [String] {
        switch reason {
        case .tag(let tag): return [station.name, tag]
        default: return [station.name]
        }
    }

    func localizedReason(genreLabel: (String) -> String = { L10n.genreLabel(for: $0) }) -> String {
        switch reason {
        case .tag(let tag):
            return L10n.string(reasonKey, station.name, genreLabel(tag))
        default:
            return L10n.string(reasonKey, station.name)
        }
    }
}

/// Picks a station entirely from device-local signals, in a fixed order of preference:
/// (a) a saved favorite not played in the last 3 days, then a saved favorite with no dated play,
/// (b) a liked recent radio usually played in the current hour band and not played today,
/// (c) a popular radio with one of the listener's most common tags that was never played or saved,
/// (d) any popular radio never played or saved.
/// The current station and radios with negative feedback are never picked.
/// Stations are matched by library identity (stream URL first), not only by `id`, because a
/// synced favorite and a local recent can carry different ids for the same radio.
enum TuneAVSurpriseStationPicker {
    static let favoriteRestDays = 3
    static let topTagCount = 3

    /// - Parameters:
    ///   - recentPlays: dated plays from the device-local play log.
    ///   - playedStations: every radio known to have been played on this device, with or without a
    ///     dated play (macOS recents carry no date, and the log keeps only 14 days).
    static func pick(
        favorites: [Station],
        recentPlays: [TuneAVRecentPlay],
        playedStations: [Station] = [],
        feedback: [String: TuneAVStationFeedback],
        popular: [Station],
        now: Date,
        currentStationID: String?,
        calendar: Calendar = .current
    ) -> TuneAVSurprisePick? {
        func isAllowed(_ station: Station) -> Bool {
            guard station.id != currentStationID else { return false }
            switch feedback[station.id] {
            case .disliked, .notForMe: return false
            case .liked, .none: return true
            }
        }

        var lastPlayedByKey: [String: Date] = [:]
        var playsByKey: [String: [Date]] = [:]
        var recentStationsByKey: [String: Station] = [:]
        for play in recentPlays {
            let key = identityKey(of: play.station)
            lastPlayedByKey[key] = max(lastPlayedByKey[key] ?? .distantPast, play.playedAt)
            playsByKey[key, default: []].append(play.playedAt)
            if recentStationsByKey[key] == nil {
                recentStationsByKey[key] = play.station
            }
        }
        var playedStationsByKey = recentStationsByKey
        for station in playedStations where playedStationsByKey[identityKey(of: station)] == nil {
            playedStationsByKey[identityKey(of: station)] = station
        }
        let favoriteKeys = Set(favorites.map(identityKey(of:)))

        // (a) Saved favorites that have rested, oldest first; then favorites with no dated play.
        let restCutoff = now.addingTimeInterval(-TimeInterval(favoriteRestDays) * 24 * 60 * 60)
        let allowedFavorites = favorites.filter(isAllowed)
        let rested = allowedFavorites
            .compactMap { favorite -> (Station, Date)? in
                guard let lastPlayed = lastPlayedByKey[identityKey(of: favorite)], lastPlayed <= restCutoff else { return nil }
                return (favorite, lastPlayed)
            }
            .sorted { $0.1 < $1.1 }
        if let (station, _) = rested.first {
            return TuneAVSurprisePick(station: station, reason: .restedFavorite)
        }
        if let station = allowedFavorites.first(where: { lastPlayedByKey[identityKey(of: $0)] == nil }) {
            return TuneAVSurprisePick(station: station, reason: .savedFavorite)
        }

        // (b) A liked recent radio usually on in this hour band, not played today.
        let band = TuneAVHourBand.band(for: now, calendar: calendar)
        let bandCandidate = recentStationsByKey.values
            .filter { station in
                guard isAllowed(station), feedback[station.id] == .liked else { return false }
                let plays = playsByKey[identityKey(of: station)] ?? []
                guard !plays.contains(where: { calendar.isDate($0, inSameDayAs: now) }) else { return false }
                return plays.contains { TuneAVHourBand.band(for: $0, calendar: calendar) == band }
            }
            .map { station -> (Station, Int, Date) in
                let plays = playsByKey[identityKey(of: station)] ?? []
                let bandCount = plays.filter { TuneAVHourBand.band(for: $0, calendar: calendar) == band }.count
                return (station, bandCount, lastPlayedByKey[identityKey(of: station)] ?? .distantPast)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
                return lhs.0.id < rhs.0.id
            }
            .first
        if let (station, _, _) = bandCandidate {
            return TuneAVSurprisePick(station: station, reason: .hourBand(band))
        }

        // (c) A popular radio with one of the listener's most common tags. "New for you" must be
        // true, so radios already played (dated or not) or saved are left out.
        let unheardPopular = popular.filter { station in
            let key = identityKey(of: station)
            return isAllowed(station) && playedStationsByKey[key] == nil && !favoriteKeys.contains(key)
        }
        var tasteStationsByKey = playedStationsByKey
        for favorite in favorites where tasteStationsByKey[identityKey(of: favorite)] == nil {
            tasteStationsByKey[identityKey(of: favorite)] = favorite
        }
        var tagCounts: [String: Int] = [:]
        for station in tasteStationsByKey.values {
            for tag in Set(normalizedTags(of: station)) {
                tagCounts[tag, default: 0] += 1
            }
        }
        let topTags = tagCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(topTagCount)
            .map(\.key)
        for tag in topTags {
            if let station = unheardPopular.first(where: { normalizedTags(of: $0).contains(tag) }) {
                return TuneAVSurprisePick(station: station, reason: .tag(tag))
            }
        }

        // (d) Any popular radio never played or saved.
        if let station = unheardPopular.first {
            return TuneAVSurprisePick(station: station, reason: .popular)
        }

        return nil
    }

    private static func identityKey(of station: Station) -> String {
        TuneAVLibrarySnapshotMerger.stationIdentityKey(station.appDataRecord)
    }

    private static func normalizedTags(of station: Station) -> [String] {
        station.tagsList.map { $0.lowercased() }
    }
}
