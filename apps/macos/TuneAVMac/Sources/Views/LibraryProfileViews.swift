import SwiftUI

struct LibraryView: View {
    private enum SortMode: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case alphabetical = "A-Z"
        case country = "Country"

        var id: String { rawValue }
    }

    @State private var query = ""
    @State private var sortMode: SortMode = .recent

    let favorites: [Station]
    let recents: [Station]
    let limits: AccessLimits
    let playAction: (Station) -> Void
    let toggleFavorite: (Station) -> Void
    let showDetails: (Station) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let compact = width < 840

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Library")
                                .font(.system(size: compact ? 26 : 30, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                            Text("Local favorites and recent playback")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TuneAVTheme.textSecondary)
                        }

                        Spacer()

                        HeaderStatusPill(status: favorites.isEmpty ? "Empty" : "\(favorites.count) saved")
                    }

                    LibrarySummaryRow(
                        favoritesCount: favorites.count,
                        recentsCount: recents.count,
                        latestStationName: recents.first?.name,
                        favoriteLimit: limits.favoriteStations,
                        recentsLimit: limits.recentStations
                    )

                    if compact {
                        VStack(alignment: .leading, spacing: 12) {
                            librarySearchField
                            sortPicker
                        }
                    } else {
                        HStack(alignment: .center, spacing: 16) {
                            librarySearchField
                            sortPicker
                                .frame(width: 220)
                        }
                    }

                    StationSection(title: "Favorites", subtitle: favoritesSubtitle) {
                        if sortedFavorites.isEmpty {
                            EmptyStateCard(
                                title: favorites.isEmpty ? "No favorites yet" : "No favorite matches",
                                detail: favorites.isEmpty ? "Save stations from Home or Search." : "Try another filter query."
                            )
                        } else {
                            LazyVGrid(columns: stationGridColumns, spacing: 12) {
                                ForEach(sortedFavorites) { station in
                                    StationRowCard(
                                        station: station,
                                        isFavorite: true,
                                        toggleFavorite: { toggleFavorite(station) },
                                        playAction: { playAction(station) },
                                        detailsAction: { showDetails(station) }
                                    )
                                }
                            }
                        }
                    }

                    if !sortedRecents.isEmpty {
                        StationSection(title: "Recents", subtitle: recentsSubtitle) {
                            LazyVGrid(columns: stationGridColumns, spacing: 12) {
                                ForEach(sortedRecents) { station in
                                    StationRowCard(
                                        station: station,
                                        isFavorite: favorites.contains(where: { $0.id == station.id }),
                                        toggleFavorite: { toggleFavorite(station) },
                                        playAction: { playAction(station) },
                                        detailsAction: { showDetails(station) }
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: compact ? 760 : 1040, alignment: .leading)
                .padding(.horizontal, compact ? 20 : 28)
                .padding(.top, compact ? 18 : 22)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedFavorites: [Station] {
        sortStations(filterStations(favorites), preserveOrder: false)
    }

    private var stationGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 132, maximum: 170), spacing: 12)
        ]
    }

    private var sortedRecents: [Station] {
        sortStations(filterStations(recents), preserveOrder: sortMode == .recent)
    }

    private func filterStations(_ stations: [Station]) -> [Station] {
        guard !trimmedQuery.isEmpty else { return stations }

        return stations.filter { station in
            station.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            station.country.localizedCaseInsensitiveContains(trimmedQuery) ||
            station.tags.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private func sortStations(_ stations: [Station], preserveOrder: Bool) -> [Station] {
        guard !preserveOrder else { return stations }

        switch sortMode {
        case .recent:
            return stations
        case .alphabetical:
            return stations.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .country:
            return stations.sorted {
                if $0.country.localizedCaseInsensitiveCompare($1.country) == .orderedSame {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.country.localizedCaseInsensitiveCompare($1.country) == .orderedAscending
            }
        }
    }

    private var favoritesSubtitle: String {
        switch sortMode {
        case .recent:
            return "Pinned stations stay here."
        case .alphabetical:
            return "Pinned stations sorted alphabetically."
        case .country:
            return "Pinned stations grouped by country."
        }
    }

    private var recentsSubtitle: String {
        switch sortMode {
        case .recent:
            return "Latest playback sessions."
        case .alphabetical:
            return "Recent stations sorted alphabetically."
        case .country:
            return "Recent stations grouped by country."
        }
    }

    private var librarySearchField: some View {
        TextField("Filter stations in your library", text: $query)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .avCardSurface(cornerRadius: 18)
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sortMode) {
            ForEach(SortMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @Binding var preferredTag: String
    @Binding var accessMode: AccessMode
    let capabilities: AccessCapabilities
    let planTier: PlanTier
    let accountConnectionState: AccountConnectionState
    let limits: AccessLimits
    let favoritesUsage: LimitUsageSummary
    let recentsUsage: LimitUsageSummary
    let discoveriesUsage: LimitUsageSummary
    let savedTracksUsage: LimitUsageSummary
    let lyricsUsage: LimitUsageSummary
    let webUsage: LimitUsageSummary
    let youtubeUsage: LimitUsageSummary
    let appleMusicUsage: LimitUsageSummary
    let spotifyUsage: LimitUsageSummary
    let discoveryShareUsage: LimitUsageSummary
    let cloudSyncStatus: CloudSyncStatus
    let cloudSyncConflictSummary: CloudSyncConflictSummary?
    let cloudSyncFailureTitle: String?
    let backendConnectionStatus: BackendConnectionStatus
    let backendConnectionFailureTitle: String?
    let cloudSyncReadinessTitle: String
    let cloudSyncBlockerDescription: String?
    let accessModeIsBackendManaged: Bool
    let accessModeSourceTitle: String
    let isCloudSyncConfigured: Bool
    let canRunCloudSync: Bool
    let canRetryBackendConnection: Bool
    let canClearCloudSyncStatus: Bool
    let canResolveCloudConflict: Bool
    let accountManagementURL: URL?
    let clearAction: () -> Void
    let retryBackendAction: () -> Void
    let syncAction: () -> Void
    let useCloudAction: () -> Void
    let overwriteCloudAction: () -> Void
    let clearSyncStatusAction: () -> Void
    @AppStorage("tuneav.mac.appearance") private var appearanceMode = "system"
    @AppStorage("tuneav.mac.launchToSearch") private var launchToSearch = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let compact = width < 900

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile")
                                .font(.system(size: compact ? 26 : 30, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                            Text("Preferences and access limits")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TuneAVTheme.textSecondary)
                        }

                        Spacer()

                        HeaderStatusPill(status: "Settings")
                    }

                    ProfileSummaryRow(
                        preferredTag: preferredTag,
                        appearanceMode: appearanceLabel,
                        launchToSearch: launchToSearch,
                        accessMode: accessMode,
                        accountConnectionState: accountConnectionState,
                        accessDetail: cloudSyncReadinessTitle
                    )

                    if compact {
                        VStack(spacing: 16) {
                            discoveryCard
                            accessCard
                            cloudSyncCard
                            appearanceCard
                            localDataCard
                            aboutCard
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                discoveryCard
                                accessCard
                                cloudSyncCard
                                localDataCard
                            }
                            .frame(maxWidth: .infinity, alignment: .top)

                            VStack(spacing: 16) {
                                appearanceCard
                                aboutCard
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: compact ? 760 : 1040, alignment: .leading)
                .padding(.horizontal, compact ? 20 : 28)
                .padding(.top, compact ? 18 : 22)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var discoveryCard: some View {
        SettingsCard(title: "Discovery", subtitle: "Tune what the app prioritizes when you open it.") {
            SettingsFieldRow(
                title: "Preferred discovery tag",
                description: "This drives the default feed when Search opens with no query."
            ) {
                TextField("ambient", text: $preferredTag)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(isOn: $launchToSearch) {
                SettingsLabel(
                    title: "Open in Search",
                    description: "Launch straight into search and browsing instead of Home."
                )
            }
            .toggleStyle(.switch)
        }
    }

    private var accessCard: some View {
        SettingsCard(title: "Access", subtitle: "Matches the Tune AV product model across iOS and macOS.") {
            if accessModeIsBackendManaged {
                SettingsStatsRow(title: "Current mode", value: accessMode.title)
                SettingsStatsRow(title: "Source", value: accessModeSourceTitle)
            } else {
                SettingsFieldRow(
                    title: "Local fallback mode",
                    description: "Used until account-backed access is connected on macOS."
                ) {
                    Picker("Access mode", selection: $accessMode) {
                        ForEach(AccessMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            SettingsStatsRow(title: "Cloud sync", value: cloudSyncReadinessTitle)
            SettingsStatsRow(title: "Backend access", value: backendConnectionStatus.title)
            if let backendConnectionFailureTitle {
                SettingsStatsRow(title: "Backend error", value: backendConnectionFailureTitle)
            }
            SettingsStatsRow(title: "Account", value: accountConnectionState.title)
            SettingsStatsRow(title: "Favorites", value: favoritesUsage.title)
            SettingsStatsRow(title: "Recents", value: recentsUsage.title)
            SettingsStatsRow(title: "Saved tracks", value: savedTracksUsage.title)
            SettingsStatsRow(title: "Daily actions", value: dailyActionsText)
        }
    }

    private var cloudSyncCard: some View {
        SettingsCard(title: "Cloud Sync", subtitle: "Manual sync surface for backend-backed Pro libraries.") {
            SettingsStatsRow(title: "Status", value: cloudSyncStatus.title)
            SettingsStatsRow(title: "Mode", value: cloudSyncModeText)
            if let cloudSyncBlockerDescription {
                SettingsLabel(title: "Sync unavailable", description: cloudSyncBlockerDescription)
            }
            if let cloudSyncFailureTitle, cloudSyncStatus == .failed {
                SettingsStatsRow(title: "Error", value: cloudSyncFailureTitle)
            }

            if cloudSyncStatus == .conflict {
                SettingsLabel(
                    title: "Library conflict",
                    description: cloudConflictDescription
                )
            }

            HStack(spacing: 10) {
                Button(primaryCloudSyncActionTitle, action: syncAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRunCloudSync || cloudSyncStatus == .syncing)

                if canResolveCloudConflict {
                    Button("Use Cloud", action: useCloudAction)
                        .buttonStyle(.borderedProminent)

                    Button("Keep this Mac", action: overwriteCloudAction)
                        .buttonStyle(.bordered)
                }

                if canRetryBackendConnection {
                    Button("Retry backend", action: retryBackendAction)
                        .buttonStyle(.bordered)
                }

                if canClearCloudSyncStatus {
                    Button("Clear status", action: clearSyncStatusAction)
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var cloudSyncModeText: String {
        cloudSyncReadinessTitle
    }

    private var primaryCloudSyncActionTitle: String {
        switch cloudSyncStatus {
        case .syncing:
            return "Syncing..."
        case .conflict:
            return "Refresh"
        default:
            return "Sync now"
        }
    }

    private var cloudConflictDescription: String {
        guard let summary = cloudSyncConflictSummary else {
            return "Cloud and this Mac both changed. Refresh from cloud or keep this Mac when account sync is connected."
        }

        let localText = "This Mac: \(summary.localFavoritesCount) favorites, \(summary.localRecentsCount) recents, \(summary.localDiscoveriesCount) discoveries."
        guard summary.hasCloudSnapshot else {
            return "\(localText) Cloud snapshot was not available after the conflict."
        }

        let cloudText = "Cloud: \(summary.cloudFavoritesCount ?? 0) favorites, \(summary.cloudRecentsCount ?? 0) recents, \(summary.cloudDiscoveriesCount ?? 0) discoveries."
        return "\(localText) \(cloudText)"
    }

    private var appearanceCard: some View {
        SettingsCard(title: "Appearance", subtitle: "Desktop-specific display preferences.") {
            SettingsFieldRow(
                title: "Appearance",
                description: "Choose how the standalone Mac app renders its chrome."
            ) {
                Picker("Appearance", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var localDataCard: some View {
        SettingsCard(title: "Local Data", subtitle: "Current library usage against active limits.") {
            SettingsStatsRow(title: "Favorites", value: favoritesUsage.title)
            SettingsStatsRow(title: "Recents", value: recentsUsage.title)
            SettingsStatsRow(title: "Discoveries", value: discoveriesUsage.title)
            SettingsStatsRow(title: "Saved tracks", value: savedTracksUsage.title)
            SettingsStatsRow(title: "Lyrics", value: lyricsUsage.title)
            SettingsStatsRow(title: "Web", value: webUsage.title)
            SettingsStatsRow(title: "YouTube", value: youtubeUsage.title)
            SettingsStatsRow(title: "Apple Music", value: appleMusicUsage.title)
            SettingsStatsRow(title: "Spotify", value: spotifyUsage.title)
            SettingsStatsRow(title: "Shares", value: discoveryShareUsage.title)

            Button("Clear local library", action: clearAction)
                .buttonStyle(.bordered)
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: "About", subtitle: "Independent macOS edition.") {
            SettingsStatsRow(title: "Edition", value: "macOS standalone")
            SettingsStatsRow(title: "Design", value: "Desktop UX aligned with Tune AV iOS")
            SettingsStatsRow(title: "Backend", value: backendConnectionStatus.title)
            if let backendConnectionFailureTitle {
                SettingsStatsRow(title: "Backend error", value: backendConnectionFailureTitle)
            }
            SettingsStatsRow(title: "Account", value: accountConnectionState.title)

            if let accountManagementURL {
                Button("Manage account") {
                    openURL(accountManagementURL)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var appearanceLabel: String {
        switch appearanceMode {
        case "light":
            return "Light"
        case "dark":
            return "Dark"
        default:
            return "System"
        }
    }

    private var dailyActionsText: String {
        let usages = [lyricsUsage, webUsage, youtubeUsage, appleMusicUsage, spotifyUsage, discoveryShareUsage]
        let limits = usages.compactMap(\.limit)
        guard limits.count == usages.count else {
            return "Practical unlimited"
        }

        if Set(limits).count == 1, let limit = limits.first {
            return "\(usages.map(\.used).max() ?? 0) of \(limit) used today"
        }

        return "Limited daily"
    }
}

extension CloudSyncStatus {
    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
        case .conflict:
            return "Conflict"
        case .failed:
            return "Failed"
        }
    }
}
