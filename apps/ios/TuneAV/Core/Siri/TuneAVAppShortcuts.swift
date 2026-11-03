import AppIntents

struct TuneAVAppShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TuneAVPlayMyRadioIntent(),
            phrases: [
                "Play my radio on \(.applicationName)",
                "Play my radio in \(.applicationName)",
                "Start my radio on \(.applicationName)",
                "Play \(.applicationName)",
            ],
            shortTitle: "appShortcut.playMyRadio",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: TuneAVPausePlaybackIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Stop \(.applicationName)",
                "Pause my radio on \(.applicationName)",
                "Stop the radio on \(.applicationName)",
            ],
            shortTitle: "appShortcut.pause",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: TuneAVPlayRadioIntent(),
            phrases: [
                "Play \(\.$station) on \(.applicationName)",
                "Listen to \(\.$station) on \(.applicationName)",
            ],
            shortTitle: "appShortcut.playStation",
            systemImageName: "radio"
        )
    }
}
