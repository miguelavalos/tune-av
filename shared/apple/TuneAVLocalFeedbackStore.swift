import Foundation

struct TuneAVLocalFeedbackRecord: Codable, Equatable {
    let feedback: TuneAVStationFeedback
    let updatedAt: String
}

struct TuneAVLocalFeedbackLoadResult: Equatable {
    let records: [String: TuneAVLocalFeedbackRecord]
    let needsPersistence: Bool
}

enum TuneAVLocalFeedbackStore {
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
                    $0.trackKey,
                    TuneAVLocalFeedbackRecord(
                        feedback: $0.feedback,
                        updatedAt: $0.updatedAt ?? fallbackTimestamp
                    )
                )
            }
        )
    }
}
