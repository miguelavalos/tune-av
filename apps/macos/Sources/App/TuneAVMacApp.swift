import AccountAV
import AppKit
import AVDiagnosticsFoundation
import AVBrandFoundation
import SwiftUI

@main
struct TuneAVMacApp: App {
    @NSApplicationDelegateAdaptor(TuneAVMacAppDelegate.self) private var appDelegate
    @StateObject private var languageController = AppLanguageController()
    @StateObject private var themeController = AppThemeController()
    @StateObject private var model = TuneAVMacModel()

    init() {
        AVDiagnostics.configure(TuneAVMacConfig.diagnosticsConfiguration)
    }

    var body: some Scene {
        WindowGroup(L10n.string("app.name")) {
            MacRootView()
                .environmentObject(languageController)
                .environmentObject(themeController)
                .environmentObject(model)
                .environment(\.locale, languageController.locale)
                .avBrandPalette(TuneAVTheme.brandPalette)
                .preferredColorScheme(themeController.currentTheme.preferredColorScheme)
                .frame(minWidth: 1360, minHeight: 760)
                .task {
                    await model.startAutomaticLibrarySync()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.prepareForTermination()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    model.prepareForAppInactivity()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.resumeAfterAppActivation()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    model.prepareForSystemSleep()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    model.resumeAfterSystemWake()
                }
        }
        .defaultSize(width: 1360, height: 800)
        .commands {
            CommandMenu(L10n.string("mac.menu.navigation")) {
                Button(L10n.string("tab.home")) {
                    model.selectedSection = .home
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button(L10n.string("tab.library")) {
                    model.selectedSection = .library
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button(L10n.string("tab.music")) {
                    model.selectedSection = .music
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button(L10n.string("tab.search")) {
                    model.selectedSection = .search
                }
                .keyboardShortcut("4", modifiers: [.command])

                Divider()

                Button(L10n.string("profile.settingsScreen.title")) {
                    model.selectedSection = .settings
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button(L10n.string("profile.accountScreen.title")) {
                    model.selectedSection = .profile
                }
                .keyboardShortcut("5", modifiers: [.command])
            }

            CommandMenu(L10n.string("mac.menu.avi")) {
                Button(model.currentDiscoveryIsSaved ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort")) {
                    _ = model.toggleCurrentDiscoverySaved()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!model.hasCurrentDiscovery)

                Button(L10n.string("player.discovery.noSave")) {
                    model.setCurrentDiscoveryFeedback(.notForMe)
                }
                .disabled(!model.hasCurrentDiscovery)

                Divider()

                Button(L10n.string("shell.avi.actions.searchLyrics")) {
                    openCurrentTrack(destination: .web, suffix: "lyrics")
                }
                .disabled(!model.hasCurrentDiscovery)

                Button(L10n.string("shell.avi.actions.searchYouTube")) {
                    openCurrentTrack(destination: .youtube)
                }
                .disabled(!model.hasCurrentDiscovery)

                Button(L10n.string("shell.avi.actions.searchAppleMusic")) {
                    openCurrentTrack(destination: .appleMusic)
                }
                .disabled(!model.hasCurrentDiscovery)

                Button(L10n.string("shell.avi.actions.searchArtist")) {
                    openURL(model.currentArtistSearchURL())
                }
                .disabled(!model.hasCurrentDiscovery)

                Divider()

                Button(currentStationIsSaved ? L10n.string("player.station.unsave") : L10n.string("player.station.save")) {
                    toggleCurrentStationSaved()
                }
                .disabled(model.currentStation == nil)

                Button(L10n.string("shell.avi.recommendation.details")) {
                    openCurrentStationDetail(showsHistory: false)
                }
                .disabled(model.currentStation == nil)

                Button(L10n.string("shell.avi.actions.history")) {
                    openCurrentStationDetail(showsHistory: true)
                }
                .disabled(model.currentStation == nil)

                Button(L10n.string("shell.avi.actions.openWebsite")) {
                    openCurrentStationWebsiteOrSearch()
                }
                .disabled(model.currentStation == nil)

                Button(L10n.string("shell.avi.actions.findRelatedRadios")) {
                    openCurrentStationSearch(suffix: "similar radio stations")
                }
                .disabled(model.currentStation == nil)
            }

            CommandMenu(L10n.string("mac.menu.playback")) {
                Button(model.isPlaying ? L10n.string("player.control.pause") : L10n.string("player.control.play")) {
                    model.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button(L10n.string("player.control.previous")) {
                    model.playPreviousInQueue()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!model.canCyclePlaybackQueue)

                Button(L10n.string("player.control.next")) {
                    model.playNextInQueue()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!model.canCyclePlaybackQueue)
            }
        }
    }

    private var currentStationIsSaved: Bool {
        guard let station = model.currentStation else { return false }
        return model.isFavorite(station)
    }

    private func openURL(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openCurrentTrack(destination: TuneAVExternalSearchURL.Destination, suffix: String? = nil) {
        openURL(model.currentTrackSearchURL(destination: destination, suffix: suffix))
    }

    private func toggleCurrentStationSaved() {
        guard let station = model.currentStation else { return }
        model.toggleFavorite(station)
    }

    private func openCurrentStationDetail(showsHistory: Bool) {
        guard let station = model.currentStation else { return }
        model.openStationDetail(station, queue: model.playbackQueue, showsHistory: showsHistory)
    }

    private func openCurrentStationWebsiteOrSearch() {
        guard let station = model.currentStation else { return }
        if let url = station.resolvedHomepageURL {
            openURL(url)
            return
        }
        openCurrentStationSearch()
    }

    private func openCurrentStationSearch(suffix: String? = nil) {
        guard let station = model.currentStation else { return }
        let query = TuneAVExternalSearchURL.query(parts: [station.name, station.country], suffix: suffix)
        openURL(TuneAVExternalSearchURL.url(for: .web, query: query))
    }
}

@MainActor
final class TuneAVMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        bringMainWindowForward()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringMainWindowForward()
        return true
    }

    private func bringMainWindowForward() {
        NSApp.unhide(nil)
        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.windows
                .filter { $0.canBecomeKey || $0.canBecomeMain }
                .forEach { window in
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                }
        }
    }
}
