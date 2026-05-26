import AccountAV
import AVBrandFoundation
import SwiftUI

@main
struct TuneAVMacApp: App {
    @NSApplicationDelegateAdaptor(TuneAVMacAppDelegate.self) private var appDelegate
    @StateObject private var languageController = AppLanguageController()
    @StateObject private var themeController = AppThemeController()
    @StateObject private var model = TuneAVMacModel()

    init() {
        AccountAVClerk.configureIfPossible(
            publishableKey: TuneAVBundleConfig.stringValue(for: "ACCOUNTAV_PUBLISHABLE_KEY"),
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    var body: some Scene {
        WindowGroup("Tune AV") {
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
        }
        .defaultSize(width: 1360, height: 800)
        .commands {
            CommandMenu("Navigation") {
                Button(L10n.string("tab.home")) {
                    model.selectedSection = .home
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button(L10n.string("tab.search")) {
                    model.selectedSection = .search
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button(L10n.string("tab.library")) {
                    model.selectedSection = .library
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button(L10n.string("tab.music")) {
                    model.selectedSection = .music
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button(L10n.string("tab.profile")) {
                    model.selectedSection = .profile
                }
                .keyboardShortcut("5", modifiers: [.command])

                Button(L10n.string("shell.header.settings")) {
                    model.selectedSection = .settings
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Playback") {
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

                Divider()

                Button(model.currentDiscoveryIsSaved ? L10n.string("player.discovery.unsaveShort") : L10n.string("player.discovery.saveShort")) {
                    _ = model.toggleCurrentDiscoverySaved()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!model.hasCurrentDiscovery)
            }
        }
    }
}

final class TuneAVMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
