import Foundation

struct AviMusicDetailSelection {
    let detail: SelectedMusicAviDetail
    let returnMusicMode: MusicContentMode?
    let returnMusicOverview: Bool
    let clearsStationDetail: Bool
    let isNowPlayingFullPlayer: Bool
    let selectedTab: AppShellTab
}

struct AviMusicDetailOpenPlan {
    let detail: SelectedMusicAviDetail
    let returnMusicMode: MusicContentMode?
    let returnMusicOverview: Bool
    let clearsStationDetail: Bool
    let isNowPlayingFullPlayer: Bool
    let selectedTab: AppShellTab

    init(selection: AviMusicDetailSelection) {
        detail = selection.detail
        returnMusicMode = selection.returnMusicMode
        returnMusicOverview = selection.returnMusicOverview
        clearsStationDetail = selection.clearsStationDetail
        isNowPlayingFullPlayer = selection.isNowPlayingFullPlayer
        selectedTab = selection.selectedTab
    }
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

    static func openPlan(for selection: AviMusicDetailSelection) -> AviMusicDetailOpenPlan {
        AviMusicDetailOpenPlan(selection: selection)
    }
}
