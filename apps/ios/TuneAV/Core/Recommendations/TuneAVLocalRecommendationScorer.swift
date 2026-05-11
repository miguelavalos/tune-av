import Foundation

struct TuneAVLocalRecommendationScorer {
    struct Rank {
        let score: Int
        let reasons: [Reason]

        var primaryReason: Reason? {
            reasons.first
        }
    }

    enum Reason: Equatable {
        case likedStation
        case currentCountry
        case recentCountry
        case favoriteCountry
        case recentTag
        case favoriteTag
        case preferredTag
        case savedDiscovery
        case hiddenDiscovery
        case recentDiscovery
        case notForMeStation
        case dislikedStation
        case negativeTag
        case frequentTag
        case timeOfDay
        case currentCountryPreference
        case directoryMomentum
    }

    let currentStation: Station?
    let recentStations: [Station]
    let favoriteStations: [Station]
    let discoveries: [DiscoveredTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let feedContext: HomeFeedContext
    let preferredTag: String
    let currentCountryCode: String?
    let date: Date

    init(
        currentStation: Station?,
        recentStations: [Station],
        favoriteStations: [Station],
        discoveries: [DiscoveredTrack],
        stationFeedback: [String: TuneAVStationFeedback],
        feedContext: HomeFeedContext,
        preferredTag: String,
        currentCountryCode: String? = nil,
        date: Date = .now
    ) {
        self.currentStation = currentStation
        self.recentStations = recentStations
        self.favoriteStations = favoriteStations
        self.discoveries = discoveries
        self.stationFeedback = stationFeedback
        self.feedContext = feedContext
        self.preferredTag = preferredTag
        self.currentCountryCode = currentCountryCode
        self.date = date
    }

    func rank(_ station: Station) -> Rank {
        var score = 0
        var reasons: [Reason] = []

        switch stationFeedback[station.id] {
        case .liked:
            score += 10
            reasons.append(.likedStation)
        case .notForMe:
            score -= 10
            reasons.append(.notForMeStation)
        case .disliked:
            score -= 16
            reasons.append(.dislikedStation)
        case .none:
            break
        }

        if matchesCountry(station, currentStation) {
            score += 4
            reasons.append(.currentCountry)
        }

        if recentStations.contains(where: { matchesCountry(station, $0) }) {
            score += 3
            reasons.append(.recentCountry)
        }

        if favoriteStations.contains(where: { matchesCountry(station, $0) }) {
            score += 4
            reasons.append(.favoriteCountry)
        }

        if recentStations.contains(where: { sharesTag(station, $0) }) {
            score += 5
            reasons.append(.recentTag)
        }

        if favoriteStations.contains(where: { sharesTag(station, $0) }) {
            score += 6
            reasons.append(.favoriteTag)
        }

        if matchesPreferredTag(station) {
            score += 5
            reasons.append(.preferredTag)
        }

        if matchesNegativeFeedbackTag(station) {
            score -= 7
            reasons.append(.negativeTag)
        }

        if matchesFrequentTag(station) {
            score += 4
            reasons.append(.frequentTag)
        }

        if matchesCurrentCountryPreference(station) {
            score += 4
            reasons.append(.currentCountryPreference)
        }

        if matchesTimeOfDay(station) {
            score += 3
            reasons.append(.timeOfDay)
        }

        var didMatchRecentDiscovery = false
        let discoveryScore = discoveries.reduce(0) { partial, discovery in
            guard discovery.stationID == station.id else { return partial }

            if discovery.isMarkedInteresting {
                return partial + 8
            }

            if discovery.isHidden {
                return partial - 6
            }

            if isRecentDiscovery(discovery) {
                didMatchRecentDiscovery = true
                return partial + 3
            }

            return partial + 1
        }

        if discoveryScore > 0 {
            reasons.append(didMatchRecentDiscovery ? .recentDiscovery : .savedDiscovery)
        } else if discoveryScore < 0 {
            reasons.append(.hiddenDiscovery)
        }
        score += discoveryScore

        let momentum = min((station.votes ?? 0) / 100, 4) + min((station.clickCount ?? 0) / 1000, 3) + min(max(station.clickTrend ?? 0, 0) / 100, 3)
        if momentum > 0 {
            score += momentum
            reasons.append(.directoryMomentum)
        }

        return Rank(score: score, reasons: uniqueReasons(reasons))
    }

    func rankedStations(_ stations: [Station]) -> [(station: Station, rank: Rank)] {
        stations
            .filter { !isSuppressedByFeedback($0) }
            .map { station in
                (station: station, rank: rank(station))
            }
            .sorted { first, second in
                if first.rank.score == second.rank.score {
                    if first.station.id != second.station.id {
                        return first.station.id.localizedStandardCompare(second.station.id) == .orderedAscending
                    }
                    return first.station.name.localizedCaseInsensitiveCompare(second.station.name) == .orderedAscending
                }

                return first.rank.score > second.rank.score
            }
    }

    static func localizedSummary(for reason: Reason?) -> String? {
        guard let reason else { return nil }

        switch reason {
        case .likedStation:
            return L10n.string("recommendations.reason.likedStation")
        case .currentCountry:
            return L10n.string("recommendations.reason.currentCountry")
        case .recentCountry:
            return L10n.string("recommendations.reason.recentCountry")
        case .favoriteCountry:
            return L10n.string("recommendations.reason.favoriteCountry")
        case .recentTag:
            return L10n.string("recommendations.reason.recentTag")
        case .favoriteTag:
            return L10n.string("recommendations.reason.favoriteTag")
        case .preferredTag:
            return L10n.string("recommendations.reason.preferredTag")
        case .savedDiscovery:
            return L10n.string("recommendations.reason.savedDiscovery")
        case .hiddenDiscovery:
            return L10n.string("recommendations.reason.hiddenDiscovery")
        case .recentDiscovery:
            return L10n.string("recommendations.reason.recentDiscovery")
        case .notForMeStation:
            return L10n.string("recommendations.reason.notForMeStation")
        case .dislikedStation:
            return L10n.string("recommendations.reason.dislikedStation")
        case .negativeTag:
            return L10n.string("recommendations.reason.negativeTag")
        case .frequentTag:
            return L10n.string("recommendations.reason.frequentTag")
        case .timeOfDay:
            return L10n.string("recommendations.reason.timeOfDay")
        case .currentCountryPreference:
            return L10n.string("recommendations.reason.currentCountryPreference")
        case .directoryMomentum:
            return L10n.string("recommendations.reason.directoryMomentum")
        }
    }

    private func isSuppressedByFeedback(_ station: Station) -> Bool {
        switch stationFeedback[station.id] {
        case .disliked, .notForMe:
            return true
        case .liked, .none:
            return false
        }
    }

    private func matchesCountry(_ station: Station, _ other: Station?) -> Bool {
        guard
            let lhs = TuneAVCountry.sanitizedCode(station.countryCode),
            let rhs = TuneAVCountry.sanitizedCode(other?.countryCode)
        else {
            return false
        }

        return lhs == rhs
    }

    private func sharesTag(_ station: Station, _ other: Station) -> Bool {
        !normalizedTags(station).isDisjoint(with: normalizedTags(other))
    }

    private func matchesPreferredTag(_ station: Station) -> Bool {
        let normalizedPreferredTag = preferredTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPreferredTag.isEmpty else {
            if case .preferredGenre(let tag) = feedContext {
                return normalizedTags(station).contains(tag.lowercased())
            }
            return false
        }

        return normalizedTags(station).contains { tag in
            tag == normalizedPreferredTag || tag.localizedCaseInsensitiveContains(normalizedPreferredTag)
        }
    }

    private func matchesFrequentTag(_ station: Station) -> Bool {
        let candidateTags = normalizedTags(station)
        guard !candidateTags.isEmpty else { return false }

        let sourceStations = Array(recentStations.prefix(8)) + favoriteStations
        let tagCounts = sourceStations
            .flatMap { normalizedTags($0) }
            .reduce(into: [String: Int]()) { counts, tag in
                counts[tag, default: 0] += 1
            }

        guard let topTag = tagCounts.max(by: { first, second in
            if first.value == second.value {
                return first.key > second.key
            }
            return first.value < second.value
        }) else { return false }

        return topTag.value >= 2 && candidateTags.contains(topTag.key)
    }

    private func matchesNegativeFeedbackTag(_ station: Station) -> Bool {
        let candidateTags = normalizedTags(station)
        guard !candidateTags.isEmpty else { return false }

        let negativeStationIDs = stationFeedback.compactMap { stationID, feedback in
            switch feedback {
            case .disliked, .notForMe:
                return stationID
            case .liked:
                return nil
            }
        }

        guard !negativeStationIDs.isEmpty else { return false }

        let signalStations = (recentStations + favoriteStations + [currentStation].compactMap { $0 })
            .filter { negativeStationIDs.contains($0.id) }

        return signalStations.contains { signalStation in
            !candidateTags.isDisjoint(with: normalizedTags(signalStation))
        }
    }

    private func matchesCurrentCountryPreference(_ station: Station) -> Bool {
        guard
            let preferredCountry = TuneAVCountry.sanitizedCode(currentCountryCode),
            let stationCountry = TuneAVCountry.sanitizedCode(station.countryCode)
        else { return false }

        return stationCountry == preferredCountry
    }

    private func matchesTimeOfDay(_ station: Station) -> Bool {
        let tags = normalizedTags(station)
        guard !tags.isEmpty else { return false }

        let hour = Calendar.current.component(.hour, from: date)
        let morningTags = ["news", "talk", "business", "traffic", "morning"]
        let eveningTags = ["jazz", "soul", "chill", "ambient", "classical", "lounge"]
        let weekendTags = ["sports", "dance", "electronic", "latin", "hits"]
        let weekday = Calendar.current.component(.weekday, from: date)

        if weekday == 1 || weekday == 7 {
            return tags.contains { tag in weekendTags.contains { tag.localizedCaseInsensitiveContains($0) } }
        }

        if hour < 11 {
            return tags.contains { tag in morningTags.contains { tag.localizedCaseInsensitiveContains($0) } }
        }

        if hour >= 18 {
            return tags.contains { tag in eveningTags.contains { tag.localizedCaseInsensitiveContains($0) } }
        }

        return false
    }

    private func isRecentDiscovery(_ discovery: DiscoveredTrack) -> Bool {
        let recentCutoff = date.addingTimeInterval(-48 * 60 * 60)
        return discovery.playedAt >= recentCutoff
    }

    private func normalizedTags(_ station: Station) -> Set<String> {
        Set(
            station.tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private func uniqueReasons(_ reasons: [Reason]) -> [Reason] {
        var seen = Set<String>()
        return reasons.filter { reason in
            seen.insert(String(describing: reason)).inserted
        }
    }
}
