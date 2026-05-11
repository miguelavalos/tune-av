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
        case notForMeStation
        case dislikedStation
        case directoryMomentum
    }

    let currentStation: Station?
    let recentStations: [Station]
    let favoriteStations: [Station]
    let discoveries: [DiscoveredTrack]
    let stationFeedback: [String: TuneAVStationFeedback]
    let feedContext: HomeFeedContext
    let preferredTag: String

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

        let discoveryScore = discoveries.reduce(0) { partial, discovery in
            guard discovery.stationID == station.id else { return partial }

            if discovery.isMarkedInteresting {
                return partial + 8
            }

            if discovery.isHidden {
                return partial - 6
            }

            return partial + 1
        }

        if discoveryScore > 0 {
            reasons.append(.savedDiscovery)
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
        case .notForMeStation:
            return L10n.string("recommendations.reason.notForMeStation")
        case .dislikedStation:
            return L10n.string("recommendations.reason.dislikedStation")
        case .directoryMomentum:
            return L10n.string("recommendations.reason.directoryMomentum")
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
