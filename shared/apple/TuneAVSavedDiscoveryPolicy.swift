import Foundation

enum TuneAVSavedDiscoveryPolicy {
    static func canSaveDiscovery(
        isAlreadySaved: Bool,
        savedCount: Int,
        limit: Int?
    ) -> Bool {
        guard let limit else { return true }
        if isAlreadySaved {
            return true
        }
        return savedCount < limit
    }

    static func overflowSavedIndexes<Discovery: TuneAVMusicLibraryDiscovery>(
        in discoveries: [Discovery],
        limit: Int?
    ) -> [Int] {
        guard let limit else { return [] }

        var remainingSavedTracks = limit
        return discoveries.indices.compactMap { index in
            guard discoveries[index].isMarkedInteresting else { return nil }
            guard remainingSavedTracks > 0 else { return index }
            remainingSavedTracks -= 1
            return nil
        }
    }
}
