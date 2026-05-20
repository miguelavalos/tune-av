struct AviReturnContext {
    let tab: AppShellTab
    let radioMode: RadioLibraryMode?
    let radioOverview: Bool?
    let musicMode: MusicContentMode?
    let musicOverview: Bool?

    var radioReturnRequest: (mode: RadioLibraryMode?, overview: Bool?)? {
        guard tab == .library else { return nil }

        return (radioMode, radioOverview)
    }

    var musicReturnRequest: (mode: MusicContentMode?, overview: Bool?)? {
        guard tab == .music else { return nil }

        return (musicMode, musicOverview)
    }

    static func captured(
        selectedTab: AppShellTab,
        existingContext: AviReturnContext?,
        radioMode: RadioLibraryMode?,
        radioOverview: Bool?,
        musicMode: MusicContentMode?,
        musicOverview: Bool?
    ) -> AviReturnContext? {
        if selectedTab == .avi {
            return existingContext
        }

        return AviReturnContext(
            tab: selectedTab,
            radioMode: selectedTab == .library ? radioMode : nil,
            radioOverview: selectedTab == .library ? radioOverview : nil,
            musicMode: selectedTab == .music ? musicMode : nil,
            musicOverview: selectedTab == .music ? musicOverview : nil
        )
    }
}

struct AviReturnRestoreRequest {
    let tab: AppShellTab
    let radioMode: RadioLibraryMode?
    let radioOverview: Bool?
    let musicMode: MusicContentMode?
    let musicOverview: Bool?

    var radioReturnRequest: (mode: RadioLibraryMode?, overview: Bool?)? {
        guard tab == .library else { return nil }

        return (radioMode, radioOverview)
    }

    var musicReturnRequest: (mode: MusicContentMode?, overview: Bool?)? {
        guard tab == .music else { return nil }

        return (musicMode, musicOverview)
    }

    init(context: AviReturnContext) {
        tab = context.tab
        radioMode = context.radioMode
        radioOverview = context.radioOverview
        musicMode = context.musicMode
        musicOverview = context.musicOverview
    }
}

struct AviReturnRestoration {
    let tab: AppShellTab
    let radioMode: RadioLibraryMode?
    let radioOverview: Bool?
    let musicMode: MusicContentMode?
    let musicOverview: Bool?
    private let restoresRadioState: Bool
    private let restoresMusicState: Bool

    var radioReturnRequest: (mode: RadioLibraryMode?, overview: Bool?)? {
        guard restoresRadioState else { return nil }

        return (radioMode, radioOverview)
    }

    var musicReturnRequest: (mode: MusicContentMode?, overview: Bool?)? {
        guard restoresMusicState else { return nil }

        return (musicMode, musicOverview)
    }

    init(restoreRequest: AviReturnRestoreRequest) {
        tab = restoreRequest.tab
        radioMode = restoreRequest.radioMode
        radioOverview = restoreRequest.radioOverview
        musicMode = restoreRequest.musicMode
        musicOverview = restoreRequest.musicOverview
        restoresRadioState = restoreRequest.radioReturnRequest != nil
        restoresMusicState = restoreRequest.musicReturnRequest != nil
    }

    init(fallbackTab: AppShellTab) {
        tab = fallbackTab
        radioMode = nil
        radioOverview = nil
        musicMode = nil
        musicOverview = nil
        restoresRadioState = false
        restoresMusicState = false
    }
}

struct AviCloseFocusedDetailPlan {
    let clearsStationDetail: Bool
    let clearsMusicDetail: Bool
    let isNowPlayingFullPlayer: Bool
    let clearsOpenedStationPresentation: Bool
    private let restoration: AviReturnRestoration?

    var selectedTab: AppShellTab? {
        restoration?.tab
    }

    var radioReturnRequest: (mode: RadioLibraryMode?, overview: Bool?)? {
        restoration?.radioReturnRequest
    }

    var musicReturnRequest: (mode: MusicContentMode?, overview: Bool?)? {
        restoration?.musicReturnRequest
    }

    init(restoration: AviReturnRestoration?) {
        clearsStationDetail = true
        clearsMusicDetail = true
        isNowPlayingFullPlayer = false
        clearsOpenedStationPresentation = true
        self.restoration = restoration
    }
}

struct AviReturnCoordinator {
    private(set) var context: AviReturnContext?

    mutating func capture(
        selectedTab: AppShellTab,
        radioMode: RadioLibraryMode?,
        radioOverview: Bool?,
        musicMode: MusicContentMode?,
        musicOverview: Bool?
    ) {
        context = AviReturnContext.captured(
            selectedTab: selectedTab,
            existingContext: context,
            radioMode: radioMode,
            radioOverview: radioOverview,
            musicMode: musicMode,
            musicOverview: musicOverview
        )
    }

    mutating func consumeRestoreRequest() -> AviReturnRestoreRequest? {
        guard let context else { return nil }

        self.context = nil
        return AviReturnRestoreRequest(context: context)
    }

    mutating func consumeRestoration(fallbackTab: AppShellTab?) -> AviReturnRestoration? {
        if let request = consumeRestoreRequest() {
            return AviReturnRestoration(restoreRequest: request)
        }
        guard let fallbackTab else { return nil }

        return AviReturnRestoration(fallbackTab: fallbackTab)
    }

    mutating func closeFocusedDetailPlan(fallbackTab: AppShellTab?) -> AviCloseFocusedDetailPlan {
        AviCloseFocusedDetailPlan(restoration: consumeRestoration(fallbackTab: fallbackTab))
    }
}
