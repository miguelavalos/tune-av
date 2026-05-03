import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("avtunesys.mac.appearance") private var appearanceMode = "system"
    @AppStorage("avtunesys.mac.launchToSearch") private var launchToSearch = false

    var body: some View {
        Form {
            Section("Discovery") {
                TextField(
                    "Preferred discovery tag",
                    text: Binding(
                        get: { libraryStore.preferredTag },
                        set: { libraryStore.updatePreferredTag($0) }
                    )
                )

                Toggle("Open directly in Search", isOn: $launchToSearch)
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Access") {
                if libraryStore.accessModeIsBackendManaged {
                    LabeledContent("Mode", value: libraryStore.accessMode.title)
                    LabeledContent("Source", value: libraryStore.accessModeSourceTitle)
                } else {
                    Picker("Local fallback mode", selection: Binding(
                        get: { libraryStore.accessMode },
                        set: { libraryStore.updateAccessMode($0) }
                    )) {
                        ForEach(AccessMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                LabeledContent("Cloud sync", value: libraryStore.cloudSyncReadinessTitle)
                LabeledContent("Backend access", value: libraryStore.backendConnectionStatus.title)
                if let backendConnectionFailureTitle = libraryStore.backendConnectionFailureTitle {
                    LabeledContent("Backend error", value: backendConnectionFailureTitle)
                }
                LabeledContent("Account", value: libraryStore.accountConnectionState.title)
                LabeledContent("Favorites", value: libraryStore.favoritesUsage.title)
                LabeledContent("Recents", value: libraryStore.recentsUsage.title)
                LabeledContent("Saved tracks", value: libraryStore.savedTracksUsage.title)
                LabeledContent("Web", value: libraryStore.dailyUsage(for: .webSearch).title)
                LabeledContent("YouTube", value: libraryStore.dailyUsage(for: .youtubeSearch).title)
                LabeledContent("Shares", value: libraryStore.dailyUsage(for: .discoveryShare).title)

                if let accountManagementURL = MacAppConfig.accountManagementURL {
                    Button("Manage account") {
                        openURL(accountManagementURL)
                    }
                }
            }

            Section("Cloud Sync") {
                LabeledContent("Status", value: libraryStore.cloudSyncStatus.title)
                LabeledContent("Backend", value: libraryStore.cloudSyncReadinessTitle)
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
                    Button("Use Cloud") {
                        Task {
                            await libraryStore.replaceLocalLibraryWithCloudData()
                        }
                    }

                    Button("Keep this Mac") {
                        Task {
                            await libraryStore.overwriteCloudLibraryWithLocalData()
                        }
                    }
                }

                if libraryStore.canRetryBackendConnection {
                    Button("Retry backend") {
                        Task {
                            await libraryStore.retryBackendConnection()
                        }
                    }
                }

                if libraryStore.canClearCloudSyncStatus {
                    Button("Clear sync status") {
                        libraryStore.clearCloudSyncStatus()
                    }
                }
            }

            Section("Local Data") {
                LabeledContent("Discoveries", value: libraryStore.discoveriesUsage.title)
                LabeledContent("Lyrics", value: libraryStore.dailyUsage(for: .lyricsSearch).title)
                LabeledContent("Web", value: libraryStore.dailyUsage(for: .webSearch).title)
                LabeledContent("Apple Music", value: libraryStore.dailyUsage(for: .appleMusicSearch).title)
                LabeledContent("Spotify", value: libraryStore.dailyUsage(for: .spotifySearch).title)
                LabeledContent("Shares", value: libraryStore.dailyUsage(for: .discoveryShare).title)

                Button("Clear local library", role: .destructive) {
                    libraryStore.clearLocalState()
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
            return "Syncing..."
        case .conflict:
            return "Refresh"
        default:
            return "Sync now"
        }
    }

    private var localConflictText: String {
        guard let summary = libraryStore.cloudSyncConflictSummary else { return "Changed locally" }
        return "\(summary.localFavoritesCount) favorites, \(summary.localRecentsCount) recents, \(summary.localDiscoveriesCount) discoveries"
    }

    private var cloudConflictText: String {
        guard let summary = libraryStore.cloudSyncConflictSummary else { return "Changed remotely" }
        guard summary.hasCloudSnapshot else { return "Unavailable" }
        return "\(summary.cloudFavoritesCount ?? 0) favorites, \(summary.cloudRecentsCount ?? 0) recents, \(summary.cloudDiscoveriesCount ?? 0) discoveries"
    }
}
