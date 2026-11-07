import SwiftUI

/// The order of saved radios as the listener arranges it in Library.
///
/// Each `FavoriteStation` carries a `sortPosition`; rows saved before the order existed have
/// none. The order lives on this device only: it is never part of the Pro sync payload
/// (`docs/pro-sync-scope.md`). A sync pull keeps the position of every station that stays
/// saved and puts the stations it brings in at the end (see `LibraryStore.applyRemoteSnapshot`).
enum FavoriteStationOrder {
    /// Rows with a position first, by position; then rows without one, newest save first, which
    /// was the only order before the listener could set one, so an upgrade keeps what it showed.
    /// Ties fall back to the id so the result is deterministic.
    static func ordered<Item>(
        _ items: [Item],
        position: (Item) -> Int?,
        savedAt: (Item) -> Date,
        id: (Item) -> String
    ) -> [Item] {
        items.sorted { lhs, rhs in
            switch (position(lhs), position(rhs)) {
            case let (lhsPosition?, rhsPosition?):
                if lhsPosition != rhsPosition {
                    return lhsPosition < rhsPosition
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                if savedAt(lhs) != savedAt(rhs) {
                    return savedAt(lhs) > savedAt(rhs)
                }
            }
            return id(lhs) < id(rhs)
        }
    }

    /// The position a station saved now takes: after the last one, so a new save goes to the end.
    static func nextPosition<Item>(after items: [Item], position: (Item) -> Int?) -> Int {
        (items.compactMap(position).max() ?? -1) + 1
    }

    /// The list after a drag, with the offsets `List.onMove` reports.
    static func moved<Item>(_ items: [Item], fromOffsets source: IndexSet, toOffset destination: Int) -> [Item] {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        return reordered
    }
}
