import AppKit
import SwiftUI

@main
struct AvtunesysMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var audioPlayer = AudioPlayerService()
    private let accountTokenProvider: MacAccountTokenProviding = LocalFallbackMacAccountTokenProvider()

    var body: some Scene {
        WindowGroup("AV Tunesys") {
            ContentView()
                .environmentObject(libraryStore)
                .environmentObject(audioPlayer)
                .frame(minWidth: AppWindowDefaults.minimumWidth, minHeight: AppWindowDefaults.minimumHeight)
                .task {
                    await libraryStore.configureBackendClients(tokenProvider: accountTokenProvider.currentToken)
                }
        }
        .defaultSize(width: AppWindowDefaults.defaultWidth, height: AppWindowDefaults.defaultHeight)

        Settings {
            SettingsView()
                .environmentObject(libraryStore)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        resetMainWindowToDefaultWidth()
    }

    private func resetMainWindowToDefaultWidth() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let window = NSApp.windows.first(where: { $0.title == "AV Tunesys" }) ?? NSApp.windows.first else {
                return
            }

            let currentFrame = window.frame
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? currentFrame
            let targetSize = NSSize(
                width: min(AppWindowDefaults.defaultWidth, screenFrame.width * 0.92),
                height: min(AppWindowDefaults.defaultHeight, screenFrame.height * 0.9)
            )
            let origin = NSPoint(
                x: screenFrame.midX - targetSize.width / 2,
                y: screenFrame.midY - targetSize.height / 2
            )

            window.contentMinSize = NSSize(width: AppWindowDefaults.minimumWidth, height: AppWindowDefaults.minimumHeight)
            window.setFrame(NSRect(origin: origin, size: targetSize), display: true, animate: false)
        }
    }
}

private enum AppWindowDefaults {
    static let minimumWidth: CGFloat = 1260
    static let minimumHeight: CGFloat = 720
    static let defaultWidth: CGFloat = 1440
    static let defaultHeight: CGFloat = 820
}
