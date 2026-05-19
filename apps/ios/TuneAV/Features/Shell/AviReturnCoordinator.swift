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
}
