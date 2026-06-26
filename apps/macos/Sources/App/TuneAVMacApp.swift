import AccountAV
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

                Button("Avi") {
                    model.selectedSection = .avi
                }
                .keyboardShortcut("5", modifiers: [.command])

                Divider()

                Button(L10n.string("profile.settingsScreen.title")) {
                    model.selectedSection = .settings
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button(L10n.string("profile.accountScreen.title")) {
                    model.selectedSection = .profile
                }
                .keyboardShortcut("6", modifiers: [.command])
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
