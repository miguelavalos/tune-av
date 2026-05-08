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
                            Text(L10n.string("shell.library.title"))
                                .font(.system(size: compact ? 26 : 30, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                            Text(L10n.string("shell.library.subtitle"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(TuneAVTheme.textSecondary)
                        }

                        Spacer()

                        HeaderStatusPill(status: favorites.isEmpty ? L10n.string("shell.library.status.empty") : L10n.plural(singular: "shell.library.status.saved.one", plural: "shell.library.status.saved.other", count: favorites.count, favorites.count))
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

                    StationSection(title: L10n.string("shell.library.favorites.title"), subtitle: favoritesSubtitle) {
                        if sortedFavorites.isEmpty {
                            EmptyStateCard(
                                title: favorites.isEmpty ? L10n.string("shell.library.favorites.empty") : L10n.string("shell.library.favorites.noMatch"),
                                detail: favorites.isEmpty ? L10n.string("shell.library.favorites.empty.detail") : L10n.string("shell.library.favorites.noMatch.detail")
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
                        StationSection(title: L10n.string("shell.library.recents.title"), subtitle: recentsSubtitle) {
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
            GridItem(.adaptive(minimum: 124, maximum: 150), spacing: 12)
        ]
    }

    private var sortedRecents: [Station] {
        sortStations(filterStations(recents), preserveOrder: sortMode == .recent)
    }

    private func filterStations(_ stations: [Station]) -> [Station] {
        TuneAVLibraryStationLogic.filteredStations(stations, query: trimmedQuery)
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
            return L10n.string("shell.library.favorites.subtitle")
        case .alphabetical:
            return L10n.string("shell.library.favorites.subtitle")
        case .country:
            return L10n.string("shell.library.favorites.subtitle")
        }
    }

    private var recentsSubtitle: String {
        switch sortMode {
        case .recent:
            return L10n.string("shell.library.recents.subtitle")
        case .alphabetical:
            return L10n.string("shell.library.recents.subtitle")
        case .country:
            return L10n.string("shell.library.recents.subtitle")
        }
    }

    private var librarySearchField: some View {
        MacSearchField(prompt: L10n.string("shell.library.searchPrompt"), text: $query)
    }

    private var sortPicker: some View {
        Picker(L10n.string("mac.library.sort"), selection: $sortMode) {
            ForEach(SortMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var languageController: AppLanguageController
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
    let accountUserDisplayName: String?
    let accountUserEmail: String?
    let accountIsAvailable: Bool
    let accountIsSignedIn: Bool
    let accountIsAuthenticating: Bool
    let accountErrorMessage: String?
    let accountManagementURL: URL?
    let isClearingLocalData: Bool
    let clearActionTitle: String
    let clearAction: () -> Void
    let signInWithAppleAction: () -> Void
    let signInWithGoogleAction: () -> Void
    let signOutAction: () -> Void
    let deleteAccountAction: () -> Void
    let retryBackendAction: () -> Void
    let syncAction: () -> Void
    let useCloudAction: () -> Void
    let overwriteCloudAction: () -> Void
    let clearSyncStatusAction: () -> Void
    @AppStorage("tuneav.mac.appearance") private var appearanceMode = "system"
    private let genreTags = ["rock", "pop", "jazz", "news", "electronic", "ambient"]

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 900

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 18) {
                    header(compact: compact)

                    if compact {
                        VStack(spacing: 16) {
                            profileSections
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                accountCard
                                preferencesCard
                                localDataCard
                            }
                            .frame(maxWidth: .infinity, alignment: .top)

                            VStack(spacing: 16) {
                                if capabilities.canUseCloudSync {
                                    cloudSyncCard
                                }
                                helpAndLegalCard
                                if accountIsSignedIn {
                                    accountSafetyCard
                                }
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

    @ViewBuilder
    private var profileSections: some View {
        accountCard
        preferencesCard
        localDataCard
        if capabilities.canUseCloudSync {
            cloudSyncCard
        }
        helpAndLegalCard
        if accountIsSignedIn {
            accountSafetyCard
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("profile.title"))
                    .font(.system(size: compact ? 26 : 30, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                Text(L10n.string("profile.subtitle"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Spacer()
            HeaderStatusPill(status: accountIsSignedIn ? L10n.string("profile.summary.account.detail.signedIn") : L10n.string("profile.status.guest"))
        }
    }

    private var accountCard: some View {
        SettingsCard(title: L10n.string("profile.account.title"), subtitle: accountIdentityDetail) {
            SettingsStatsRow(title: L10n.string("profile.summary.account.title"), value: accountSummaryDetail)
            if let accountUserEmail, !accountUserEmail.isEmpty {
                SettingsStatsRow(title: L10n.string("profile.account.email.title"), value: accountUserEmail)
            }
            SettingsStatsRow(title: L10n.string("profile.summary.plan.title"), value: planSummaryDetail)

            if let accountErrorMessage, !accountErrorMessage.isEmpty {
                SettingsStatsRow(title: L10n.string("mac.profile.accountError"), value: accountErrorMessage)
            }

            if accountIsSignedIn {
                SettingsActionButton(
                    title: accountIsAuthenticating ? L10n.string("profile.actions.signingOut") : L10n.string("profile.actions.signOut"),
                    systemImage: "rectangle.portrait.and.arrow.right",
                    action: signOutAction
                )
                    .disabled(accountIsAuthenticating)
            } else {
                HStack(spacing: 10) {
                    SettingsActionButton(
                        title: accountIsAuthenticating ? L10n.string("mac.profile.openingApple") : "Apple",
                        systemImage: "apple.logo",
                        style: .prominent,
                        action: signInWithAppleAction
                    )
                        .disabled(!accountIsAvailable || accountIsAuthenticating)

                    SettingsActionButton(
                        title: accountIsAuthenticating ? L10n.string("mac.profile.openingGoogle") : "Google",
                        systemImage: "globe",
                        action: signInWithGoogleAction
                    )
                        .disabled(!accountIsAvailable || accountIsAuthenticating)
                }

                if !accountIsAvailable {
                    SettingsLabel(
                        title: L10n.string("mac.profile.accountUnavailable"),
                        description: L10n.string("mac.profile.accountUnavailable.detail")
                    )
                }
            }
        }
    }

    private var preferencesCard: some View {
        SettingsCard(title: L10n.string("profile.preferences.title"), subtitle: L10n.string("profile.preferences.subtitle")) {
            SettingsFieldRow(
                title: L10n.string("profile.preferences.language.title"),
                description: L10n.string("profile.preferences.language.detail")
            ) {
                languageSelector
            }

            if accountIsSignedIn {
                SettingsFieldRow(
                    title: L10n.string("profile.preferences.preferredGenre.title"),
                    description: L10n.string("profile.preferences.preferredGenre.detail", normalizedPreferredTag.isEmpty ? L10n.string("profile.preferences.preferredGenre.none") : genreLabel(for: normalizedPreferredTag))
                ) {
                    genreSelector
                }
            } else {
                SettingsLabel(
                    title: L10n.string("profile.preferences.accountPerk.title"),
                    description: L10n.string("profile.preferences.accountPerk.detail")
                )
            }

            SettingsFieldRow(
                title: L10n.string("profile.preferences.theme.title"),
                description: L10n.string("profile.preferences.theme.detail")
            ) {
                HStack(spacing: 10) {
                    SettingsOptionButton(
                        title: L10n.string("profile.preferences.theme.system"),
                        systemImage: "circle.lefthalf.filled",
                        isSelected: appearanceMode == AppTheme.system.rawValue
                    ) {
                        appearanceMode = AppTheme.system.rawValue
                    }
                    SettingsOptionButton(
                        title: L10n.string("profile.preferences.theme.light"),
                        systemImage: "sun.max",
                        isSelected: appearanceMode == AppTheme.light.rawValue
                    ) {
                        appearanceMode = AppTheme.light.rawValue
                    }
                    SettingsOptionButton(
                        title: L10n.string("profile.preferences.theme.dark"),
                        systemImage: "moon.fill",
                        isSelected: appearanceMode == AppTheme.dark.rawValue
                    ) {
                        appearanceMode = AppTheme.dark.rawValue
                    }
                }
            }
        }
    }

    private var localDataCard: some View {
        SettingsCard(title: L10n.string("profile.local.title"), subtitle: L10n.string("profile.local.subtitle")) {
            SettingsStatsRow(title: L10n.string("shell.library.favorites.title"), value: favoritesUsage.title)
            SettingsStatsRow(title: L10n.string("shell.library.recents.title"), value: recentsUsage.title)
            SettingsStatsRow(title: L10n.string("profile.local.savedMusic.title"), value: savedTracksUsage.title)
            SettingsStatsRow(title: L10n.string("profile.local.storagePolicy.title"), value: capabilities.isLocalOnly ? L10n.string("profile.local.storagePolicy.local") : L10n.string("profile.local.storagePolicy.remote"))

            SettingsActionButton(
                title: clearActionTitle,
                systemImage: "trash",
                style: .destructive,
                action: clearAction
            )
                .disabled(isClearingLocalData)
        }
    }

    private var cloudSyncCard: some View {
        SettingsCard(title: L10n.string("profile.sync.title"), subtitle: L10n.string("profile.sync.subtitle")) {
            SettingsStatsRow(title: L10n.string("profile.sync.status.title"), value: cloudSyncStatus.title)
            if let cloudSyncBlockerDescription {
                SettingsLabel(title: L10n.string("mac.profile.syncUnavailable"), description: cloudSyncBlockerDescription)
            }
            if let cloudSyncFailureTitle, cloudSyncStatus == .failed {
                SettingsStatsRow(title: L10n.string("mac.player.status.error"), value: cloudSyncFailureTitle)
            }

            if cloudSyncStatus == .conflict {
                SettingsLabel(
                    title: L10n.string("mac.profile.libraryConflict"),
                    description: cloudConflictDescription
                )
            }

            HStack(spacing: 10) {
                SettingsActionButton(
                    title: primaryCloudSyncActionTitle,
                    systemImage: cloudSyncStatus == .syncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                    style: .prominent,
                    action: syncAction
                )
                    .disabled(!canRunCloudSync || cloudSyncStatus == .syncing)

                if canResolveCloudConflict {
                    SettingsActionButton(
                        title: L10n.string("mac.sync.useCloud"),
                        systemImage: "icloud.and.arrow.down",
                        style: .prominent,
                        action: useCloudAction
                    )

                    SettingsActionButton(
                        title: L10n.string("mac.sync.keepThisMac"),
                        systemImage: "desktopcomputer",
                        action: overwriteCloudAction
                    )
                }
            }
        }
    }

    private var genreSelector: some View {
        Menu {
            Button {
                preferredTag = ""
            } label: {
                if normalizedPreferredTag.isEmpty {
                    Label(L10n.string("mac.profile.genre.none"), systemImage: "checkmark")
                } else {
                    Text(L10n.string("mac.profile.genre.none"))
                }
            }

            ForEach(genreTags, id: \.self) { tag in
                Button {
                    preferredTag = tag
                } label: {
                    if normalizedPreferredTag == tag {
                        Label(genreLabel(for: tag), systemImage: "checkmark")
                    } else {
                        Text(genreLabel(for: tag))
                    }
                }
            }
        } label: {
            SettingsMenuButtonLabel(
                title: normalizedPreferredTag.isEmpty ? L10n.string("mac.profile.genre.none") : genreLabel(for: normalizedPreferredTag),
                subtitle: L10n.string("mac.profile.summary.launchGenre"),
                systemImage: normalizedPreferredTag.isEmpty ? "line.3.horizontal.decrease.circle" : genreSymbol(for: normalizedPreferredTag)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var languageSelector: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageController.select(language)
                } label: {
                    if languageController.currentLanguage == language {
                        Label("\(language.displayName) (\(language.autonym))", systemImage: "checkmark")
                    } else {
                        Text("\(language.displayName) (\(language.autonym))")
                    }
                }
            }
        } label: {
            SettingsMenuButtonLabel(
                title: languageController.currentLanguage.displayName,
                subtitle: languageController.currentLanguage.autonym,
                systemImage: "globe"
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var helpAndLegalCard: some View {
        SettingsCard(title: L10n.string("profile.help.title"), subtitle: L10n.string("profile.help.subtitle")) {
            SettingsLabel(
                title: L10n.string("profile.help.opensource.title"),
                description: L10n.string("profile.help.opensource.detail")
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 120), spacing: 10),
                    GridItem(.flexible(minimum: 120), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                if let openSourceURL = MacAppConfig.openSourceURL {
                    SettingsLinkButton(title: L10n.string("profile.help.sourceCode.title"), systemImage: "chevron.left.forwardslash.chevron.right") {
                        openURL(openSourceURL)
                    }
                }
                if let supportURL = MacAppConfig.supportURL {
                    SettingsLinkButton(title: L10n.string("profile.help.support.title"), systemImage: "questionmark.circle") {
                        openURL(supportURL)
                    }
                }
                if let termsURL = MacAppConfig.termsURL {
                    SettingsLinkButton(title: L10n.string("profile.help.terms.title"), systemImage: "doc.text") {
                        openURL(termsURL)
                    }
                }
                if let privacyURL = MacAppConfig.privacyURL {
                    SettingsLinkButton(title: L10n.string("profile.help.privacy.title"), systemImage: "hand.raised") {
                        openURL(privacyURL)
                    }
                }
            }
        }
    }

    private var accountSafetyCard: some View {
        SettingsCard(title: L10n.string("profile.safety.title"), subtitle: L10n.string("profile.safety.subtitle")) {
            SettingsLabel(
                title: L10n.string("profile.safety.delete.title"),
                description: L10n.string("profile.safety.delete.detail")
            )

            Button(action: deleteAccountAction) {
                HStack(spacing: 9) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))

                    Text(L10n.string("profile.safety.delete.title"))
                        .font(.system(size: 13, weight: .semibold))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var accountIdentityDetail: String {
        accountIsSignedIn ? (accountUserDisplayName ?? L10n.string("profile.summary.account.detail.signedIn")) : L10n.string("profile.status.guest")
    }

    private var accountSummaryDetail: String {
        accountIsSignedIn ? L10n.string("mac.profile.signedInAs", accountUserDisplayName ?? "Account AV") : L10n.string("profile.account.identity.guest")
    }

    private var planSummaryDetail: String {
        switch accessMode {
        case .guest:
            return L10n.string("mac.profile.freeLocalAccess")
        case .signedInFree:
            return L10n.string("profile.status.free")
        case .signedInPro:
            return L10n.string("profile.status.pro")
        }
    }

    private var primaryCloudSyncActionTitle: String {
        switch cloudSyncStatus {
        case .syncing:
            return L10n.string("profile.sync.retry.syncing")
        case .conflict:
            return L10n.string("sync.conflict.refresh")
        default:
            return L10n.string("profile.sync.retry")
        }
    }

    private var cloudConflictDescription: String {
        guard let summary = cloudSyncConflictSummary else {
            return L10n.string("mac.profile.conflict.default")
        }

        let localText = L10n.string("mac.profile.conflict.local", summary.localFavoritesCount, summary.localRecentsCount, summary.localDiscoveriesCount)
        guard summary.hasCloudSnapshot else {
            return "\(localText) \(L10n.string("mac.profile.conflict.noCloudSnapshot"))"
        }

        let cloudText = L10n.string("mac.profile.conflict.cloud", summary.cloudFavoritesCount ?? 0, summary.cloudRecentsCount ?? 0, summary.cloudDiscoveriesCount ?? 0)
        return "\(localText) \(cloudText)"
    }

    private func genreLabel(for tag: String) -> String {
        L10n.genreLabel(for: tag)
    }

    private func genreSymbol(for tag: String) -> String {
        switch tag {
        case "rock":
            return "guitars"
        case "pop":
            return "music.note"
        case "jazz":
            return "music.mic"
        case "news":
            return "newspaper"
        case "electronic":
            return "waveform"
        case "ambient":
            return "sparkles"
        default:
            return "music.note.list"
        }
    }

    private var normalizedPreferredTag: String {
        preferredTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CloudSyncStatus {
    var title: String {
        switch self {
        case .idle:
            return L10n.string("profile.sync.status.idle")
        case .syncing:
            return L10n.string("profile.sync.status.syncing")
        case .synced:
            return L10n.string("profile.sync.status.synced")
        case .conflict:
            return L10n.string("profile.sync.status.conflict")
        case .failed:
            return L10n.string("profile.sync.status.failed")
        }
    }
}
