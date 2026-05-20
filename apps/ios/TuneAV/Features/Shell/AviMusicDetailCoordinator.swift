import Foundation

struct AviMusicDetailSelection {
    let detail: SelectedMusicAviDetail
    let returnMusicMode: MusicContentMode?
    let returnMusicOverview: Bool
    let clearsStationDetail: Bool
    let isNowPlayingFullPlayer: Bool
    let selectedTab: AppShellTab
}

enum AviMusicDetailCoordinator {
    static func track(
        _ discovery: DiscoveredTrack,
        returnMusicMode: MusicContentMode?
    ) -> AviMusicDetailSelection {
        selection(detail: .track(discovery), returnMusicMode: returnMusicMode)
    }

    static func artist(
        _ summary: DiscoveryArtistSummary,
        returnMusicMode: MusicContentMode?
    ) -> AviMusicDetailSelection {
        selection(detail: .artist(summary), returnMusicMode: returnMusicMode)
    }

    private static func selection(
        detail: SelectedMusicAviDetail,
        returnMusicMode: MusicContentMode?
    ) -> AviMusicDetailSelection {
        AviMusicDetailSelection(
            detail: detail,
            returnMusicMode: returnMusicMode,
            returnMusicOverview: returnMusicMode == nil,
            clearsStationDetail: true,
            isNowPlayingFullPlayer: false,
            selectedTab: .avi
        )
    }
}
