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
        /// A saved radio never played on this device.
        case unplayedFavorite
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
        case .unplayedFavorite: return "shell.home.surprise.reason.favoriteUnplayed"
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
/// (a) a saved favorite not played in the last 3 days (or never played),
/// (b) a liked recent radio usually played in the current hour band and not played today,
/// (c) a popular radio with one of the listener's most common tags that is not in recents,
/// (d) any popular radio not in recents.
/// The current station and radios with negative feedback are never picked.
enum TuneAVSurpriseStationPicker {
    static let favoriteRestDays = 3
    static let topTagCount = 3

    static func pick(
        favorites: [Station],
        recentPlays: [TuneAVRecentPlay],
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

        var lastPlayedByID: [String: Date] = [:]
        var playsByID: [String: [Date]] = [:]
        var recentStationsByID: [String: Station] = [:]
        for play in recentPlays {
            lastPlayedByID[play.station.id] = max(lastPlayedByID[play.station.id] ?? .distantPast, play.playedAt)
            playsByID[play.station.id, default: []].append(play.playedAt)
            if recentStationsByID[play.station.id] == nil {
                recentStationsByID[play.station.id] = play.station
            }
        }

        // (a) Saved favorites that have rested, oldest first; then favorites never played here.
        let restCutoff = now.addingTimeInterval(-TimeInterval(favoriteRestDays) * 24 * 60 * 60)
        let allowedFavorites = favorites.filter(isAllowed)
        let rested = allowedFavorites
            .compactMap { favorite -> (Station, Date)? in
                guard let lastPlayed = lastPlayedByID[favorite.id], lastPlayed <= restCutoff else { return nil }
                return (favorite, lastPlayed)
            }
            .sorted { $0.1 < $1.1 }
        if let (station, _) = rested.first {
            return TuneAVSurprisePick(station: station, reason: .restedFavorite)
        }
        if let station = allowedFavorites.first(where: { lastPlayedByID[$0.id] == nil }) {
            return TuneAVSurprisePick(station: station, reason: .unplayedFavorite)
        }

        // (b) A liked recent radio usually on in this hour band, not played today.
        let band = TuneAVHourBand.band(for: now, calendar: calendar)
        let bandCandidate = recentStationsByID.values
            .filter { station in
                guard isAllowed(station), feedback[station.id] == .liked else { return false }
                let plays = playsByID[station.id] ?? []
                guard !plays.contains(where: { calendar.isDate($0, inSameDayAs: now) }) else { return false }
                return plays.contains { TuneAVHourBand.band(for: $0, calendar: calendar) == band }
            }
            .map { station -> (Station, Int, Date) in
                let plays = playsByID[station.id] ?? []
                let bandCount = plays.filter { TuneAVHourBand.band(for: $0, calendar: calendar) == band }.count
                return (station, bandCount, lastPlayedByID[station.id] ?? .distantPast)
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

        // (c) A popular radio with one of the listener's most common tags.
        let unheardPopular = popular.filter { isAllowed($0) && recentStationsByID[$0.id] == nil }
        let tasteStations = favorites + Array(recentStationsByID.values)
        var tagCounts: [String: Int] = [:]
        for station in tasteStations {
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

        // (d) Any popular radio not in recents.
        if let station = unheardPopular.first {
            return TuneAVSurprisePick(station: station, reason: .popular)
        }

        return nil
    }

    private static func normalizedTags(of station: Station) -> [String] {
        station.tagsList.map { $0.lowercased() }
    }
}
