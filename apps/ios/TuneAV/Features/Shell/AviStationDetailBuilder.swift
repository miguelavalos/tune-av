struct SelectedStationDetail: Identifiable {
    let station: Station
    let queueSource: AudioPlayerService.PlaybackQueue.Source
    let queueStations: [Station]

    var id: String {
        station.id
    }
}

struct AviStationDetailSelection {
    let resolvedStation: Station
    let detail: SelectedStationDetail
}

struct AviStationOpenSelection {
    let resolvedStation: Station
    let detail: SelectedStationDetail
    let presentation: String
    let isFullPlayer: Bool
    let selectedTab: AppShellTab
}

struct ShellStationDetailOpenPlan {
    let returnRadioMode: RadioLibraryMode?
    let returnRadioOverview: Bool?
    let clearsMusicDetail: Bool
    let selection: AviStationOpenSelection
}

struct ShellContextualAviOpenPlan {
    let capturesReturnContext: Bool
    let clearsStationDetail: Bool
    let clearsMusicDetail: Bool
    let isFullPlayer: Bool
    let selection: AviStationOpenSelection?
    let selectedTab: AppShellTab
}

enum ShellStationDetailOpenPlanner {
    static func detailPlan(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: [Station]?,
        returnRadioMode: RadioLibraryMode?,
        returnRadioOverview: Bool?,
        presentation: String,
        builder: AviStationDetailBuilder
    ) -> ShellStationDetailOpenPlan {
        ShellStationDetailOpenPlan(
            returnRadioMode: returnRadioMode,
            returnRadioOverview: returnRadioOverview,
            clearsMusicDetail: true,
            selection: builder.openDetailSelection(
                station: station,
                queueSource: queueSource,
                queue: { resolvedStation in queue ?? [resolvedStation] },
                presentation: presentation
            )
        )
    }

    static func fullPlayerPlan(
        station: Station,
        presentation: String,
        builder: AviStationDetailBuilder
    ) -> ShellStationDetailOpenPlan {
        ShellStationDetailOpenPlan(
            returnRadioMode: nil,
            returnRadioOverview: nil,
            clearsMusicDetail: true,
            selection: builder.openFullPlayerSelection(
                station: station,
                queueSource: .singleStation,
                queue: { [$0] },
                presentation: presentation
            )
        )
    }

    static func contextualAviPlan(
        currentStation: Station?,
        currentQueueSource: AudioPlayerService.PlaybackQueue.Source,
        currentQueue: @escaping (Station) -> [Station],
        presentation: String,
        builder: AviStationDetailBuilder
    ) -> ShellContextualAviOpenPlan {
        ShellContextualAviOpenPlan(
            capturesReturnContext: true,
            clearsStationDetail: true,
            clearsMusicDetail: true,
            isFullPlayer: false,
            selection: currentStation.map { station in
                builder.openFullPlayerSelection(
                    station: station,
                    queueSource: currentQueueSource,
                    queue: currentQueue,
                    presentation: presentation
                )
            },
            selectedTab: .avi
        )
    }
}

struct AviStationDetailBuilder {
    let enrichStation: (Station) -> Station
    let enrichStations: ([Station]) -> [Station]

    func detail(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: [Station]
    ) -> SelectedStationDetail {
        SelectedStationDetail(
            station: enrichStation(station),
            queueSource: queueSource,
            queueStations: enrichStations(queue)
        )
    }

    func playbackQueue(
        stations: [Station],
        fallbackStation: Station
    ) -> [Station] {
        stations.isEmpty ? [fallbackStation] : stations
    }

    func shouldSyncActiveSignal(
        selectedTab: AppShellTab,
        isFullPlayer: Bool,
        previousStationID: String?,
        selectedDetailStationID: String?
    ) -> Bool {
        guard selectedTab == .avi else { return false }
        if isFullPlayer {
            return true
        }
        guard let previousStationID else { return false }

        return selectedDetailStationID == previousStationID
    }

    func selection(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station]
    ) -> AviStationDetailSelection {
        let resolvedStation = enrichStation(station)
        let detail = SelectedStationDetail(
            station: resolvedStation,
            queueSource: queueSource,
            queueStations: enrichStations(queue(resolvedStation))
        )

        return AviStationDetailSelection(
            resolvedStation: resolvedStation,
            detail: detail
        )
    }

    func openDetailSelection(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station],
        presentation: String
    ) -> AviStationOpenSelection {
        openSelection(
            station: station,
            queueSource: queueSource,
            queue: queue,
            presentation: presentation,
            isFullPlayer: false
        )
    }

    func openFullPlayerSelection(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station],
        presentation: String
    ) -> AviStationOpenSelection {
        openSelection(
            station: station,
            queueSource: queueSource,
            queue: queue,
            presentation: presentation,
            isFullPlayer: true
        )
    }

    private func openSelection(
        station: Station,
        queueSource: AudioPlayerService.PlaybackQueue.Source,
        queue: (Station) -> [Station],
        presentation: String,
        isFullPlayer: Bool
    ) -> AviStationOpenSelection {
        let selection = selection(
            station: station,
            queueSource: queueSource,
            queue: queue
        )

        return AviStationOpenSelection(
            resolvedStation: selection.resolvedStation,
            detail: selection.detail,
            presentation: presentation,
            isFullPlayer: isFullPlayer,
            selectedTab: .avi
        )
    }
}
