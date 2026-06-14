import Foundation

struct TuneAVLocalFeedbackRecord: Codable, Equatable {
    let feedback: TuneAVStationFeedback
    let updatedAt: String
    let title: String?
    let artist: String?
    let stationID: String?

    init(
        feedback: TuneAVStationFeedback,
        updatedAt: String,
        title: String? = nil,
        artist: String? = nil,
        stationID: String? = nil
    ) {
        self.feedback = feedback
        self.updatedAt = updatedAt
        self.title = TuneAVText.normalizedValue(title)
        self.artist = TuneAVText.normalizedValue(artist)
        self.stationID = TuneAVText.normalizedValue(stationID)
    }
}

struct TuneAVLocalFeedbackLoadResult: Equatable {
    let records: [String: TuneAVLocalFeedbackRecord]
    let needsPersistence: Bool
}

enum TuneAVLocalFeedbackStore {
    static func canonicalTrackFeedbackKey(_ key: String) -> String {
        let decodedKey = key.removingPercentEncoding ?? key
        return decodedKey
            .split(separator: "::", omittingEmptySubsequences: false)
            .map { component in
                component
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .lowercased()
            }
            .joined(separator: "::")
    }

    static func canonicalizedTrackRecords(
        _ records: [String: TuneAVLocalFeedbackRecord]
    ) -> [String: TuneAVLocalFeedbackRecord] {
        records.reduce(into: [String: TuneAVLocalFeedbackRecord]()) { result, entry in
            let key = canonicalTrackFeedbackKey(entry.key)
            guard let current = result[key] else {
                result[key] = entry.value
                return
            }

            if TuneAVDateCoding.date(from: entry.value.updatedAt) >= TuneAVDateCoding.date(from: current.updatedAt) {
                result[key] = entry.value
            }
        }
    }

    static func bounded(
        _ records: [String: TuneAVLocalFeedbackRecord],
        maxCount: Int
    ) -> [String: TuneAVLocalFeedbackRecord] {
        guard maxCount > 0 else { return [:] }
        guard records.count > maxCount else { return records }

        let retainedKeys = Set(
            records
                .sorted {
                    if $0.value.updatedAt == $1.value.updatedAt {
                        return $0.key > $1.key
                    }
                    return TuneAVDateCoding.date(from: $0.value.updatedAt) > TuneAVDateCoding.date(from: $1.value.updatedAt)
                }
                .prefix(maxCount)
                .map(\.key)
        )
        return records.filter { retainedKeys.contains($0.key) }
    }

    static func records(
        fromLegacy feedback: [String: TuneAVStationFeedback],
        updatedAt: Date
    ) -> [String: TuneAVLocalFeedbackRecord] {
        let timestamp = TuneAVDateCoding.string(from: updatedAt)
        return feedback.mapValues { TuneAVLocalFeedbackRecord(feedback: $0, updatedAt: timestamp) }
    }
}

enum TuneAVRealtimeFeedbackProjection {
    static func stationFeedback(
        from records: [TuneAVStationFeedbackRecord]
    ) -> [String: TuneAVStationFeedback] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.stationID, $0.feedback) })
    }

    static func stationFeedbackRecords(
        from records: [TuneAVStationFeedbackRecord],
        fallbackUpdatedAt: Date = .now
    ) -> [String: TuneAVLocalFeedbackRecord] {
        let fallbackTimestamp = TuneAVDateCoding.string(from: fallbackUpdatedAt)
        return Dictionary(
            uniqueKeysWithValues: records.map {
                (
                    $0.stationID,
                    TuneAVLocalFeedbackRecord(
                        feedback: $0.feedback,
                        updatedAt: $0.updatedAt ?? fallbackTimestamp
                    )
                )
            }
        )
    }

    static func trackFeedbackRecords(
        from records: [TuneAVTrackFeedbackRecord],
        fallbackUpdatedAt: Date = .now
    ) -> [String: TuneAVLocalFeedbackRecord] {
        let fallbackTimestamp = TuneAVDateCoding.string(from: fallbackUpdatedAt)
        return Dictionary(
            uniqueKeysWithValues: records.map {
                (
                    TuneAVLocalFeedbackStore.canonicalTrackFeedbackKey($0.trackKey),
                    TuneAVLocalFeedbackRecord(
                        feedback: $0.feedback,
                        updatedAt: $0.updatedAt ?? fallbackTimestamp,
                        title: $0.title,
                        artist: $0.artist,
                        stationID: $0.stationID
                    )
                )
            }
        )
    }
}
