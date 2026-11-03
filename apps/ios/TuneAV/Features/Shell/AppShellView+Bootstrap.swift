import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AppShellView {
    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        seedUITestDataIfNeeded()
        applyLaunchBootstrapActions()

        applyDemoStationBootstrapActions()

        if let feature = ShellUITestBootstrapOverrides.upgradePromptFeature(from: launchContext) {
            accessController.presentUpgradePrompt(for: feature)
        }
    }

    func applyDemoStationBootstrapActions() {
        guard let demoStation = launchContext.demoStation else { return }

        let actions = ShellDemoStationBootstrapPlanner.actions(
            hasDemoStation: true,
            seedFavorite: launchContext.seedFavorite,
            currentStationID: audioPlayer.currentStation?.id,
            demoStationID: demoStation.id
        )

        for action in actions {
            applyDemoStationBootstrapAction(action, demoStation: demoStation)
        }
        applyUITestTrackMetadataIfNeeded()
    }

    func applyDemoStationBootstrapAction(
        _ action: ShellDemoStationBootstrapAction,
        demoStation: Station
    ) {
        switch action {
        case let .seed(favorite):
            libraryStore.ensureSeededStation(demoStation, favorite: favorite)
        case .play:
            playStation(demoStation)
        }
    }

    func applyLaunchBootstrapActions() {
        let lastPlayedStation = libraryStore.station(for: libraryStore.settings.lastPlayedStationID)
        let actions = ShellLaunchBootstrapPlanner.actions(
            preferredTab: launchContext.preferredTab,
            hasPreferredSearchQuery: launchContext.preferredSearchQuery != nil,
            shouldRestoreLastOpenedStation: libraryStore.settings.openLastStationOnLaunch && audioPlayer.currentStation == nil,
            hasLastPlayedStation: lastPlayedStation != nil,
            hasDemoStation: launchContext.demoStation != nil
        )

        let routes = ShellLaunchBootstrapRouter.routes(
            for: actions,
            lastPlayedStation: lastPlayedStation,
            demoStation: launchContext.demoStation
        )

        for route in routes {
            applyLaunchBootstrapRoute(route)
        }
    }

    func applyLaunchBootstrapRoute(_ route: ShellLaunchBootstrapRoute) {
        switch route {
        case let .selectTab(tab):
            selectedTab = tab
        case let .openPlayer(station):
            playStation(station)
            showStationDetails(station, queueSource: .singleStation, queue: [station])
        case .restoreLastOpenedStation:
            restoreLastOpenedStationOnLaunch()
        }
    }

    func restoreLastOpenedStationOnLaunch() {
        ShellLaunchRestoreExecutor.restore(
            selection: restoredLaunchSelection(),
            selectStation: { station, queue in
                audioPlayer.select(station: station, queue: queue)
            },
            openPlayer: openNowPlayingFullPlayer(_:)
        )
    }

    func restoredLaunchSelection() -> ShellRestoredLaunchSelection? {
        ShellPlaybackQueueBuilder.restoredLaunchSelection(
            lastPlayedStationID: libraryStore.settings.lastPlayedStationID,
            lastOpenedStationID: libraryStore.settings.lastOpenedStationID,
            stationForID: libraryStore.station(for:),
            enrichStation: enrichedStation(_:),
            favorites: enrichedFavoriteStations,
            recents: enrichedRecentStations,
            homeStations: enrichedStations(homeSnapshot.stations)
        )
    }

    func seedUITestDataIfNeeded() {
        ShellUITestBootstrapSeeder.seedLibraryIfNeeded(
            launchContext: launchContext,
            libraryStore: libraryStore,
            recentLimit: accessController.limits.recentStations
        )
    }
}
