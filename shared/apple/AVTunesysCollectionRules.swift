import Foundation

enum AVTunesysCollectionRules {
    static func trimmed<T>(_ values: [T], limit: Int?) -> [T] {
        guard let limit else { return values }
        return Array(values.prefix(limit))
    }

    static func overflow<T>(
        in values: [T],
        limit: Int,
        sortedBy areInIncreasingOrder: (T, T) -> Bool
    ) -> [T] {
        guard values.count > limit else { return [] }
        return Array(values.sorted(by: areInIncreasingOrder).dropFirst(limit))
    }

    static func movingToFront<T: Identifiable>(_ item: T, in values: [T], limit: Int?) -> [T] where T.ID: Equatable {
        let reordered = [item] + values.filter { $0.id != item.id }
        return trimmed(reordered, limit: limit)
    }
}
