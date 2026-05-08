import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("tuneav.mac.appearance") private var appearanceMode = "system"
    @AppStorage("tuneav.mac.launchToSearch") private var launchToSearch = false

    var body: some View {
        Form {
            Section(L10n.string("mac.settings.discovery.title")) {
                Picker(
                    L10n.string("profile.preferences.preferredGenre.title"),
                    selection: Binding(
                        get: { libraryStore.preferredTag },
                        set: { libraryStore.updatePreferredTag($0) }
                    )
                ) {
                    Text(L10n.string("mac.profile.genre.none")).tag("")
                    ForEach(["rock", "pop", "jazz", "news", "electronic", "ambient"], id: \.self) { tag in
                        Text(L10n.genreLabel(for: tag)).tag(tag)
                    }
                }

                Toggle(L10n.string("mac.settings.launchToSearch"), isOn: $launchToSearch)
            }

            Section(L10n.string("audio.sleep.timer")) {
                Picker(L10n.string("audio.sleep.timer"), selection: Binding(
                    get: { libraryStore.sleepTimerMinutes },
                    set: { libraryStore.updateSleepTimerMinutes($0) }
                )) {
                    Text(L10n.string("mac.profile.genre.none")).tag(Int?.none)
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Text(L10n.string("audio.sleep.inMinutes", minutes)).tag(Optional(minutes))
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.string("profile.preferences.theme.title")) {
                Picker(L10n.string("profile.preferences.theme.title"), selection: $appearanceMode) {
                    Text(L10n.string("profile.preferences.theme.system")).tag(AppTheme.system.rawValue)
                    Text(L10n.string("profile.preferences.theme.light")).tag(AppTheme.light.rawValue)
                    Text(L10n.string("profile.preferences.theme.dark")).tag(AppTheme.dark.rawValue)
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.string("mac.settings.access.title")) {
                LabeledContent(L10n.string("mac.settings.mode.title"), value: libraryStore.accessMode.title)
                LabeledContent(L10n.string("mac.settings.source.title"), value: libraryStore.accessModeSourceTitle)

                LabeledContent(L10n.string("profile.sync.title"), value: libraryStore.cloudSyncReadinessTitle)
                LabeledContent(L10n.string("mac.settings.backendAccess"), value: libraryStore.backendConnectionStatus.title)
                if let backendConnectionFailureTitle = libraryStore.backendConnectionFailureTitle {
                    LabeledContent(L10n.string("mac.settings.backendError"), value: backendConnectionFailureTitle)
                }
                LabeledContent(L10n.string("profile.account.title"), value: libraryStore.accountConnectionState.title)
                LabeledContent(L10n.string("shell.library.favorites.title"), value: libraryStore.favoritesUsage.title)
                LabeledContent(L10n.string("shell.library.recents.title"), value: libraryStore.recentsUsage.title)
                LabeledContent(L10n.string("profile.local.savedMusic.title"), value: libraryStore.savedTracksUsage.title)
                LabeledContent("Web", value: libraryStore.dailyUsage(for: .webSearch).title)
                LabeledContent("YouTube", value: libraryStore.dailyUsage(for: .youtubeSearch).title)
                LabeledContent(L10n.string("mac.settings.shares"), value: libraryStore.dailyUsage(for: .discoveryShare).title)

                if let accountManagementURL = MacAppConfig.accountManagementURL {
                    Button(L10n.string("mac.accountDeletion.openManagement")) {
                        openURL(accountManagementURL)
                    }
                }
            }

            Section(L10n.string("profile.sync.title")) {
                LabeledContent(L10n.string("profile.sync.status.title"), value: libraryStore.cloudSyncStatus.title)
                LabeledContent(L10n.string("mac.settings.cloudBackend"), value: libraryStore.cloudSyncReadinessTitle)
                if let cloudSyncBlockerDescription = libraryStore.cloudSyncBlockerDescription {
                    Text(cloudSyncBlockerDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let cloudSyncFailureTitle = libraryStore.cloudSyncFailureTitle,
                   libraryStore.cloudSyncStatus == .failed {
                    LabeledContent("Error", value: cloudSyncFailureTitle)
                }
                Button(primaryCloudSyncActionTitle) {
                    Task {
                        await libraryStore.refreshCloudLibraryIfNeeded()
                    }
                }
                .disabled(!libraryStore.canRunCloudSync || libraryStore.cloudSyncStatus == .syncing)

                if libraryStore.cloudSyncStatus == .conflict {
                    LabeledContent("This Mac", value: localConflictText)
                    LabeledContent("Cloud", value: cloudConflictText)
                }

                if libraryStore.canResolveCloudConflict {
                    Button(L10n.string("mac.sync.useCloud")) {
                        Task {
                            await libraryStore.replaceLocalLibraryWithCloudData()
                        }
                    }

                    Button(L10n.string("mac.sync.keepThisMac")) {
                        Task {
                            await libraryStore.overwriteCloudLibraryWithLocalData()
                        }
                    }
                }

                if libraryStore.canRetryBackendConnection {
                    Button(L10n.string("mac.settings.retryBackend")) {
                        Task {
                            await libraryStore.retryBackendConnection()
                        }
                    }
                }

                if libraryStore.canClearCloudSyncStatus {
                    Button(L10n.string("mac.settings.clearSyncStatus")) {
                        libraryStore.clearCloudSyncStatus()
                    }
                }
            }

            Section(L10n.string("profile.local.title")) {
                LabeledContent(L10n.string("shell.library.discoveries.title"), value: libraryStore.discoveriesUsage.title)
                LabeledContent("Lyrics", value: libraryStore.dailyUsage(for: .lyricsSearch).title)
                LabeledContent("Web", value: libraryStore.dailyUsage(for: .webSearch).title)
                LabeledContent("Apple Music", value: libraryStore.dailyUsage(for: .appleMusicSearch).title)
                LabeledContent("Spotify", value: libraryStore.dailyUsage(for: .spotifySearch).title)
                LabeledContent(L10n.string("mac.settings.shares"), value: libraryStore.dailyUsage(for: .discoveryShare).title)

                Button(L10n.string("mac.settings.clearLocalLibrary"), role: .destructive) {
                    libraryStore.clearLocalData(propagatesToCloud: libraryStore.capabilities.canUseCloudSync)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 440)
    }

    private var primaryCloudSyncActionTitle: String {
        switch libraryStore.cloudSyncStatus {
        case .syncing:
            return L10n.string("profile.sync.retry.syncing")
        case .conflict:
            return L10n.string("shell.search.status.search")
        default:
            return L10n.string("profile.sync.retry")
        }
    }

    private var localConflictText: String {
        guard let summary = libraryStore.cloudSyncConflictSummary else { return L10n.string("mac.sync.changedLocal") }
        return "\(summary.localFavoritesCount) favorites, \(summary.localRecentsCount) recents, \(summary.localDiscoveriesCount) discoveries"
    }

    private var cloudConflictText: String {
        guard let summary = libraryStore.cloudSyncConflictSummary else { return L10n.string("mac.sync.changedRemote") }
        guard summary.hasCloudSnapshot else { return L10n.string("mac.sync.unavailable") }
        return "\(summary.cloudFavoritesCount ?? 0) favorites, \(summary.cloudRecentsCount ?? 0) recents, \(summary.cloudDiscoveriesCount ?? 0) discoveries"
    }
}
