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

    private struct DiscoverySignal {
        var score = 0
        var didMatchRecent = false
    }

    private let currentStationCountryCode: String?
    private let recentCountryCodes: Set<String>
    private let favoriteCountryCodes: Set<String>
    private let recentStationTags: Set<String>
    private let favoriteStationTags: Set<String>
    private let normalizedPreferredTag: String
    private let feedContextPreferredTag: String?
    private let negativeFeedbackTags: Set<String>
    private let frequentTag: String?
    private let sanitizedCurrentCountryCode: String?
    private let isWeekend: Bool
    private let hour: Int
    private let discoverySignalsByStationID: [String: DiscoverySignal]

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

        currentStationCountryCode = Self.sanitizedCountryCode(currentStation)
        recentCountryCodes = Set(recentStations.compactMap(Self.sanitizedCountryCode))
        favoriteCountryCodes = Set(favoriteStations.compactMap(Self.sanitizedCountryCode))
        recentStationTags = Set(recentStations.flatMap(Self.normalizedTags))
        favoriteStationTags = Set(favoriteStations.flatMap(Self.normalizedTags))
        normalizedPreferredTag = preferredTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if case .preferredGenre(let tag) = feedContext {
            feedContextPreferredTag = tag.lowercased()
        } else {
            feedContextPreferredTag = nil
        }
        sanitizedCurrentCountryCode = TuneAVCountry.sanitizedCode(currentCountryCode)

        let sourceStations = Array(recentStations.prefix(8)) + favoriteStations
        let tagCounts = sourceStations
            .flatMap(Self.normalizedTags)
            .reduce(into: [String: Int]()) { counts, tag in
                counts[tag, default: 0] += 1
            }
        let topTag = tagCounts.max { first, second in
            if first.value == second.value {
                return first.key > second.key
            }
            return first.value < second.value
        }
        frequentTag = topTag?.value ?? 0 >= 2 ? topTag?.key : nil

        let negativeStationIDs = Set(stationFeedback.compactMap { stationID, feedback in
            switch feedback {
            case .disliked, .notForMe:
                return stationID
            case .liked:
                return nil
            }
        })
        negativeFeedbackTags = Set(
            (recentStations + favoriteStations + [currentStation].compactMap { $0 })
                .filter { negativeStationIDs.contains($0.id) }
                .flatMap(Self.normalizedTags)
        )

        let calendar = Calendar.current
        hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        isWeekend = weekday == 1 || weekday == 7

        let recentCutoff = date.addingTimeInterval(-48 * 60 * 60)
        discoverySignalsByStationID = discoveries.reduce(into: [String: DiscoverySignal]()) { signals, discovery in
            var signal = signals[discovery.stationID, default: DiscoverySignal()]
            if discovery.isMarkedInteresting {
                signal.score += 8
            } else if discovery.isHidden {
                signal.score -= 6
            } else if discovery.playedAt >= recentCutoff {
                signal.score += 3
                signal.didMatchRecent = true
            } else {
                signal.score += 1
            }
            signals[discovery.stationID] = signal
        }
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

        let candidateCountryCode = Self.sanitizedCountryCode(station)
        let candidateTags = Self.normalizedTags(station)

        if let candidateCountryCode, candidateCountryCode == currentStationCountryCode {
            score += 4
            reasons.append(.currentCountry)
        }

        if let candidateCountryCode, recentCountryCodes.contains(candidateCountryCode) {
            score += 3
            reasons.append(.recentCountry)
        }

        if let candidateCountryCode, favoriteCountryCodes.contains(candidateCountryCode) {
            score += 4
            reasons.append(.favoriteCountry)
        }

        if !candidateTags.isDisjoint(with: recentStationTags) {
            score += 5
            reasons.append(.recentTag)
        }

        if !candidateTags.isDisjoint(with: favoriteStationTags) {
            score += 6
            reasons.append(.favoriteTag)
        }

        if matchesPreferredTag(candidateTags) {
            score += 5
            reasons.append(.preferredTag)
        }

        if !candidateTags.isEmpty, !candidateTags.isDisjoint(with: negativeFeedbackTags) {
            score -= 7
            reasons.append(.negativeTag)
        }

        if let frequentTag, candidateTags.contains(frequentTag) {
            score += 4
            reasons.append(.frequentTag)
        }

        if let candidateCountryCode, candidateCountryCode == sanitizedCurrentCountryCode {
            score += 4
            reasons.append(.currentCountryPreference)
        }

        if matchesTimeOfDay(candidateTags) {
            score += 3
            reasons.append(.timeOfDay)
        }

        let discoverySignal = discoverySignalsByStationID[station.id]
        let discoveryScore = discoverySignal?.score ?? 0

        if discoveryScore > 0 {
            reasons.append(discoverySignal?.didMatchRecent == true ? .recentDiscovery : .savedDiscovery)
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

    private func matchesPreferredTag(_ tags: Set<String>) -> Bool {
        guard !normalizedPreferredTag.isEmpty else {
            if let feedContextPreferredTag {
                return tags.contains(feedContextPreferredTag)
            }
            return false
        }

        return tags.contains { tag in
            tag == normalizedPreferredTag || tag.localizedCaseInsensitiveContains(normalizedPreferredTag)
        }
    }

    private func matchesTimeOfDay(_ tags: Set<String>) -> Bool {
        guard !tags.isEmpty else { return false }

        let morningTags = ["news", "talk", "business", "traffic", "morning"]
        let eveningTags = ["jazz", "soul", "chill", "ambient", "classical", "lounge"]
        let weekendTags = ["sports", "dance", "electronic", "latin", "hits"]

        if isWeekend {
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

    private static func sanitizedCountryCode(_ station: Station?) -> String? {
        TuneAVCountry.sanitizedCode(station?.countryCode)
    }

    private static func normalizedTags(_ station: Station) -> Set<String> {
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
