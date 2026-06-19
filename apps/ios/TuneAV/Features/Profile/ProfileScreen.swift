import AVSettingsFoundation
import AVExternalLinkFoundation
import SwiftUI

struct ProfileScreen: View {
    enum Mode {
        case account
        case settings
    }

    fileprivate enum LocalDataClearTarget: Identifiable {
        case favorites
        case recents
        case discoveries
        case settings
        case all

        var id: String {
            switch self {
            case .favorites: "favorites"
            case .recents: "recents"
            case .discoveries: "discoveries"
            case .settings: "settings"
            case .all: "all"
            }
        }
    }

    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var languageController: AppLanguageController
    @EnvironmentObject private var themeController: AppThemeController
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.avCommonAppExperience) private var appExperience
    @Environment(\.openURL) private var openExternalURL

    let mode: Mode
    let startSignInFlow: (Bool) -> Void
    let synchronizeLibraryNow: () async -> Void
    let bottomContentPadding: CGFloat

    @State private var isClearingLocalData = false
    @State private var isShowingLocalDataActions = false
    @State private var isSigningOut = false
    @State private var signOutErrorMessage = ""
    @State private var isShowingSignOutError = false
    @State private var browserDestination: BrowserDestination?
    @State private var isShowingAccountDeletion = false
    @State private var isShowingProPaywall = false
    @State private var accountSummary: AccountSummary?
    private let genreTags = TuneAVMusicGenreCatalog.visibleTags

    var body: some View {
        AVSettingsProfileScreenScaffold(
            title: screenTitle,
            subtitle: screenSubtitle,
            bottomContentPadding: bottomContentPadding,
            backgroundStyle: AnyShapeStyle(TuneAVTheme.shellBackground),
            showsTopSafeAreaShield: true
        ) {
            ShellBrandHeader(statusTitle: statusTitle, activeItem: headerActiveItem)
        } content: {
            screenContent
        }
        .alert(L10n.string("profile.alert.signOutFailed.title"), isPresented: $isShowingSignOutError) {
            Button(L10n.string("profile.alert.close"), role: .cancel) {}
        } message: {
            Text(signOutErrorMessage)
        }
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .sheet(isPresented: $isShowingAccountDeletion) {
            AccountDeletionScreen(viewModel: accountDeletionViewModel)
        }
        .sheet(isPresented: $isShowingProPaywall) {
            TuneAVProPaywallView {
                startSignInFlow(true)
            }
                .environmentObject(accessController)
        }
        .sheet(isPresented: $isShowingLocalDataActions) {
            AVSettingsMaintenanceSheet(
                title: L10n.string("profile.localDataSheet.title"),
                subtitle: L10n.string("profile.localDataSheet.subtitle"),
                closeTitle: L10n.string("profile.alert.clearData.cancel"),
                groupTitle: L10n.string("profile.localDataSheet.partialTitle"),
                actions: localDataMaintenanceActions,
                destructiveSectionTitle: L10n.string("profile.localDataSheet.dangerTitle"),
                destructiveTitle: localDataClearAllActionTitle,
                destructiveDetail: L10n.string("profile.alert.clearData.message"),
                destructiveTarget: LocalDataClearTarget.all,
                backgroundStyle: AnyShapeStyle(TuneAVTheme.shellBackground),
                alertTitle: clearLibraryAlertTitle(for:),
                alertMessage: clearLibraryAlertMessage(for:),
                confirmTitle: clearLibraryConfirmTitle(for:),
                onConfirmTarget: performClearLocalData
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task(id: accessController.accessMode) {
            await refreshAccountSummaryIfNeeded()
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch mode {
        case .account:
            profileSummaryCard
            proPlanCard
            if accessController.capabilities.canUseCloudSync {
                cloudSyncCard
            }
            if accessController.accessMode != .guest {
                accountSafetyCard
            }
        case .settings:
            appPreferencesCard
            tunePreferencesCard
            localDataCard
            helpAndLegalCard
        }
    }

    private var profileSummaryCard: some View {
        AVSettingsSectionCard(
            title: L10n.string("profile.account.title"),
            subtitle: accountIdentityDetail
        ) {
            Divider()
                .overlay(TuneAVTheme.borderSubtle)

            VStack(alignment: .leading, spacing: 12) {
                AVSettingsInfoRow(
                    systemImage: "person.crop.circle",
                    title: L10n.string("profile.summary.account.title"),
                    detail: accountSummaryDetail
                )
                if let emailAddress = accessController.accountUser?.emailAddress {
                    AVSettingsInfoRow(
                        systemImage: "envelope",
                        title: L10n.string("profile.account.email.title"),
                        detail: emailAddress
                    )
                }
                AVSettingsInfoRow(
                    systemImage: "sparkles.rectangle.stack",
                    title: L10n.string("profile.summary.plan.title"),
                    detail: planSummaryDetail
                )
            }

            accountActionButton
        }
    }

    private var cloudSyncCard: some View {
        AVSettingsSectionCard(
            title: L10n.string("profile.sync.title"),
            subtitle: L10n.string("profile.sync.subtitle.short")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                AVSettingsInfoRow(
                    systemImage: cloudSyncIcon,
                    title: cloudSyncHeadline,
                    detail: cloudSyncCompactDetail
                )
                .accessibilityIdentifier("profile.sync.status")

                if let pendingDetail = cloudSyncPendingDetail {
                    AVSettingsInfoRow(
                        systemImage: "tray.and.arrow.up",
                        title: L10n.string("profile.sync.pending.title"),
                        detail: pendingDetail
                    )
                    .accessibilityIdentifier("profile.sync.pending")
                }

            }

            if let lastActivity = cloudSyncLastActivity {
                Text(L10n.string("profile.sync.lastActivity", lastActivity.formatted(date: .abbreviated, time: .shortened)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .accessibilityIdentifier("profile.sync.lastActivity")
            }

            cloudSyncRetryButton
        }
        .accessibilityIdentifier("profile.sync.card")
    }

    private var cloudSyncPendingDetail: String? {
        let sessions = libraryStore.syncDiagnostics.pendingListeningSessionCount
        let feedback = libraryStore.syncDiagnostics.pendingFeedbackUploadCount
        let pending = sessions + feedback
        guard pending > 0 else { return nil }
        return L10n.plural(
            singular: "profile.sync.pending.one",
            plural: "profile.sync.pending.other",
            count: pending,
            pending
        )
    }

    private var cloudSyncLastActivity: Date? {
        [
            cloudSyncLastSyncedAt,
            libraryStore.syncDiagnostics.lastCloudPullAt,
            libraryStore.syncDiagnostics.lastCloudPushAt,
            libraryStore.syncDiagnostics.lastSummaryFetchAt
        ]
        .compactMap { $0 }
        .max()
    }

    private var cloudSyncHeadline: String {
        if cloudSyncPendingDetail != nil {
            return L10n.string("profile.sync.headline.pending")
        }
        if libraryStore.syncDiagnostics.isSummaryStale {
            return L10n.string("profile.sync.headline.updating")
        }
        switch libraryStore.cloudSyncStatus {
        case .idle:
            return L10n.string("profile.sync.headline.ready")
        case .syncing:
            return L10n.string("profile.sync.headline.syncing")
        case .synced:
            return L10n.string("profile.sync.headline.synced")
        case .conflict:
            return L10n.string("profile.sync.headline.needsAttention")
        case .failed:
            return L10n.string("profile.sync.headline.failed")
        }
    }

    private var cloudSyncCompactDetail: String {
        if cloudSyncPendingDetail != nil {
            return L10n.string("profile.sync.detail.pending")
        }
        if libraryStore.syncDiagnostics.isSummaryStale {
            return L10n.string("profile.sync.detail.updating")
        }
        switch libraryStore.cloudSyncStatus {
        case .idle:
            return L10n.string("profile.sync.detail.ready")
        case .syncing:
            return L10n.string("profile.sync.detail.syncing")
        case .synced:
            return L10n.string("profile.sync.detail.synced")
        case .conflict:
            return L10n.string("profile.sync.detail.needsAttention")
        case .failed:
            return L10n.string("profile.sync.detail.failed")
        }
    }

    private var cloudSyncRetryButton: some View {
        AVSettingsButton(
            title: libraryStore.cloudSyncStatus == .syncing
                ? L10n.string("profile.sync.retry.syncing")
                : L10n.string("profile.sync.retry"),
            style: .secondary,
            isLoading: libraryStore.cloudSyncStatus == .syncing,
            action: {
                Task {
                    await synchronizeLibraryNow()
                }
            }
        )
        .disabled(libraryStore.cloudSyncStatus == .syncing)
        .accessibilityIdentifier("profile.sync.retry")
    }

    private var proPlanCard: some View {
        AVSettingsSectionCard(
            title: L10n.string("profile.pro.title"),
            subtitle: proPlanSubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                AVSettingsInfoRow(
                    systemImage: "heart.text.square",
                    title: L10n.string("profile.pro.library.title"),
                    detail: L10n.string("profile.pro.library.detail")
                )
                AVSettingsInfoRow(
                    systemImage: "icloud",
                    title: L10n.string("profile.pro.sync.title"),
                    detail: L10n.string("profile.pro.sync.detail")
                )
                AVSettingsInfoRow(
                    systemImage: "sparkles",
                    title: L10n.string("profile.pro.avi.title"),
                    detail: L10n.string("profile.pro.avi.detail")
                )
                if let subscriptionStatusDetail {
                    AVSettingsInfoRow(
                        systemImage: "calendar.badge.clock",
                        title: L10n.string("profile.pro.subscription.title"),
                        detail: subscriptionStatusDetail
                    )
                    .accessibilityIdentifier("profile.pro.subscriptionStatus")
                }
            }

            proPlanAction
        }
        .accessibilityIdentifier("profile.pro.card")
    }

    @ViewBuilder
    private var proPlanAction: some View {
        switch accessController.accessMode {
        case .guest:
            ProfilePrimaryButton(
                title: accessController.accountIsAvailable
                    ? L10n.string("profile.pro.signIn")
                    : L10n.string("profile.account.connectUnavailable"),
                accessibilityID: "profile.pro.signIn",
                action: { startSignInFlow(true) }
            )
            .disabled(!accessController.accountIsAvailable)
        case .signedInFree:
            ProfilePrimaryButton(
                title: L10n.string("profile.pro.viewOffer"),
                accessibilityID: "profile.pro.viewOffer",
                action: { isShowingProPaywall = true }
            )
        case .signedInPro:
            AVSettingsButton(
                title: L10n.string("profile.pro.manage"),
                style: .secondary,
                action: { open(URL(string: "https://apps.apple.com/account/subscriptions")) }
            )
            .accessibilityIdentifier("profile.pro.manage")
        }
    }

    @ViewBuilder
    private var accountActionButton: some View {
        if accessController.accessMode == .guest {
            ProfilePrimaryButton(
                title: accessController.accountIsAvailable
                    ? L10n.string("profile.account.connect")
                    : L10n.string("profile.account.connectUnavailable"),
                accessibilityID: "profile.account.connect",
                action: { startSignInFlow(true) }
            )
            .disabled(!accessController.accountIsAvailable)
        } else {
            AVSettingsButton(
                title: isSigningOut
                    ? L10n.string("profile.actions.signingOut")
                    : L10n.string("profile.actions.signOut"),
                style: .secondary,
                isLoading: isSigningOut,
                action: {
                    Task { await signOut() }
                }
            )
            .disabled(isSigningOut)
            .accessibilityIdentifier("profile.account.signOut")
        }
    }

    private var appPreferencesCard: some View {
        AVSettingsSectionCard(
            title: L10n.string("profile.preferences.title"),
            subtitle: L10n.string("profile.preferences.subtitle")
        ) {
            AVSettingsInfoRow(
                systemImage: "globe",
                title: L10n.string("profile.preferences.language.title"),
                detail: L10n.string("profile.preferences.language.detail")
            )

            languageSelector

            AVSettingsInfoRow(
                systemImage: "circle.lefthalf.filled",
                title: L10n.string("profile.preferences.theme.title"),
                detail: L10n.string("profile.preferences.theme.detail")
            )

            themeSelector
        }
    }

    private var tunePreferencesCard: some View {
        AVSettingsSectionCard(
            title: L10n.string("profile.productPreferences.title"),
            subtitle: L10n.string("profile.productPreferences.subtitle")
        ) {
            AVSettingsInfoRow(
                systemImage: "music.note.list",
                title: L10n.string("profile.preferences.preferredGenre.title"),
                detail: L10n.string(
                    "profile.preferences.preferredGenre.detail",
                    preferredGenreLabel
                )
            )

            preferredGenreSelector

            Divider()
                .overlay(TuneAVTheme.borderSubtle)

            AVSettingsToggleRow(
                systemImage: "iphone.gen3.radiowaves.left.and.right",
                title: L10n.string("profile.preferences.keepScreenAwake.title"),
                detail: L10n.string("profile.preferences.keepScreenAwake.detail"),
                isOn: keepScreenAwakeSelection
            )

            AVSettingsToggleRow(
                systemImage: "antenna.radiowaves.left.and.right",
                title: L10n.string("profile.preferences.cellularWarning.title"),
                detail: L10n.string("profile.preferences.cellularWarning.detail"),
                isOn: cellularWarningSelection
            )

            AVSettingsToggleRow(
                systemImage: "clock.arrow.circlepath",
                title: L10n.string("profile.preferences.openLastStation.title"),
                detail: L10n.string("profile.preferences.openLastStation.detail"),
                isOn: openLastStationSelection
            )

            AVSettingsToggleRow(
                systemImage: "forward.end.fill",
                title: L10n.string("profile.preferences.autoSkipUnstableStreams.title"),
                detail: L10n.string("profile.preferences.autoSkipUnstableStreams.detail"),
                isOn: autoSkipUnstableStreamsSelection
            )

            Divider()
                .overlay(TuneAVTheme.borderSubtle)

            AVSettingsInfoRow(
                systemImage: "magnifyingglass.circle",
                title: L10n.string("profile.preferences.externalSearchEngine.title"),
                detail: L10n.string("profile.preferences.externalSearchEngine.detail")
            )

            externalSearchEngineSelector

            AVSettingsInfoRow(
                systemImage: "safari",
                title: L10n.string("profile.preferences.webOpenMode.title"),
                detail: L10n.string("profile.preferences.webOpenMode.detail")
            )

            webOpenModeSelector

            if !audioPlayer.temporarilyUnstableStationIDs.isEmpty {
                AVSettingsInlineActionRow(
                    systemImage: "checkmark.circle",
                    title: L10n.string("profile.preferences.clearUnstableWarnings.title"),
                    detail: L10n.string("profile.preferences.clearUnstableWarnings.detail", audioPlayer.temporarilyUnstableStationIDs.count),
                    actionTitle: L10n.string("profile.preferences.clearUnstableWarnings.action"),
                    action: audioPlayer.clearTemporaryInstabilityWarnings
                )
            }
        }
    }

    private var localDataCard: some View {
        AVSettingsSectionCard(
            title: L10n.string("profile.local.title"),
            subtitle: L10n.string("profile.local.subtitle")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                AVSettingsInfoRow(
                    systemImage: "heart.text.square",
                    title: L10n.string("shell.library.favorites.title"),
                    detail: localCountDetail(
                        count: libraryStore.favorites.count,
                        limit: accessController.limits.favoriteStations,
                        singular: "profile.local.favorites.count.one",
                        plural: "profile.local.favorites.count.other"
                    )
                )
                AVSettingsInfoRow(
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    title: L10n.string("shell.home.recents.title"),
                    detail: localCountDetail(
                        count: libraryStore.recents.count,
                        limit: accessController.limits.recentStations,
                        singular: "profile.local.recents.count.one",
                        plural: "profile.local.recents.count.other"
                    )
                )
                AVSettingsInfoRow(
                    systemImage: "music.note.list",
                    title: L10n.string("profile.local.savedMusic.title"),
                    detail: localCountDetail(
                        count: libraryStore.savedDiscoveriesCount,
                        limit: accessController.limits.savedTracks,
                        singular: "profile.local.savedMusic.count.one",
                        plural: "profile.local.savedMusic.count.other"
                    )
                )
                AVSettingsInfoRow(
                    systemImage: "internaldrive",
                    title: L10n.string("profile.local.storagePolicy.title"),
                    detail: accessController.capabilities.isLocalOnly
                        ? L10n.string("profile.local.storagePolicy.local")
                        : L10n.string("profile.local.storagePolicy.remote")
                )
            }

            AVSettingsButton(
                title: isClearingLocalData
                    ? clearLibraryLoadingTitle
                    : L10n.string("profile.actions.manageLocalData"),
                style: .destructive,
                action: { isShowingLocalDataActions = true }
            )
            .disabled(isClearingLocalData)
        }
    }

    private func localCountDetail(count: Int, limit: Int?, singular: String, plural: String) -> String {
        let base = L10n.plural(
            singular: singular,
            plural: plural,
            count: count,
            count
        )
        guard let limit, count <= limit else { return base }
        return L10n.string("profile.local.limit.used", base, count, limit)
    }

    private var helpAndLegalCard: some View {
        AVSettingsHelpLegalSection(
            title: L10n.string("profile.help.title"),
            subtitle: L10n.string("profile.help.subtitle"),
            openSourceTitle: L10n.string("profile.help.opensource.title"),
            openSourceDetail: L10n.string("profile.help.opensource.detail"),
            sourceCodeURL: AppConfig.openSourceURL,
            sourceCodeTitle: L10n.string("profile.help.sourceCode.title"),
            sourceCodeDetail: L10n.string("profile.help.sourceCode.detail"),
            legalLinks: appExperience.legalLinks,
            supportTitle: L10n.string("profile.help.support.title"),
            supportDetail: L10n.string("profile.help.support.detail"),
            privacyTitle: L10n.string("profile.help.privacy.title"),
            privacyDetail: L10n.string("profile.help.privacy.detail"),
            termsTitle: L10n.string("profile.help.terms.title"),
            termsDetail: L10n.string("profile.help.terms.detail"),
            accountDeletionTitle: L10n.string("profile.safety.delete.title"),
            accountDeletionDetail: L10n.string("profile.safety.delete.detail"),
            openURL: open
        )
    }

    private var accountSafetyCard: some View {
        AVSettingsSectionCard(
            title: L10n.string("profile.safety.title"),
            subtitle: L10n.string("profile.safety.subtitle"),
            spacing: 12
        ) {
            AVSettingsActionRow(
                systemImage: "exclamationmark.shield",
                title: L10n.string("profile.safety.delete.title"),
                detail: L10n.string("profile.safety.delete.detail"),
                action: { isShowingAccountDeletion = true }
            )
            .accessibilityIdentifier("profile.safety.delete")
        }
    }

    private var displayName: String {
        accessController.accountUser?.displayName ?? L10n.string("profile.displayName.local")
    }

    private var subtitle: String {
        switch accessController.accessMode {
        case .guest:
            L10n.string("profile.subtitle.guest")
        case .signedInFree, .signedInPro:
            accessController.accountUser?.emailAddress
                ?? accessController.accountUser?.id
                ?? L10n.string("profile.subtitle.accountFallback")
        }
    }

    private var statusTitle: String {
        switch mode {
        case .account:
            L10n.string("profile.statusTitle.account")
        case .settings:
            L10n.string("profile.statusTitle.settings")
        }
    }

    private var headerActiveItem: ShellBrandHeaderActiveItem {
        switch mode {
        case .account:
            .account
        case .settings:
            .settings
        }
    }

    private var screenTitle: String {
        switch mode {
        case .account:
            L10n.string("profile.accountScreen.title")
        case .settings:
            L10n.string("profile.settingsScreen.title")
        }
    }

    private var screenSubtitle: String {
        switch mode {
        case .account:
            L10n.string("profile.accountScreen.subtitle")
        case .settings:
            L10n.string("profile.settingsScreen.subtitle")
        }
    }

    private var accountIdentityDetail: String {
        switch accessController.accessMode {
        case .guest:
            L10n.string("profile.account.identity.guest")
        case .signedInFree, .signedInPro:
            displayName
        }
    }

    private var shouldClearSyncedLibrary: Bool {
        false
    }

    private var clearLibraryActionTitle: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.actions.clearSyncedLibrary")
            : L10n.string("profile.actions.clearData")
    }

    private var localDataClearAllActionTitle: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.actions.clearAllSyncedLibrary")
            : L10n.string("profile.actions.clearAllLocalData")
    }

    private var clearLibraryLoadingTitle: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.actions.clearingSyncedLibrary")
            : L10n.string("profile.actions.clearingData")
    }

    private func clearLibraryAlertTitle(for target: LocalDataClearTarget) -> String {
        switch target {
        case .favorites:
            return L10n.string("profile.alert.clearFavorites.title")
        case .recents:
            return L10n.string("profile.alert.clearRecents.title")
        case .discoveries:
            return L10n.string("profile.alert.clearDiscoveries.title")
        case .settings:
            return L10n.string("profile.alert.resetSettings.title")
        case .all:
            break
        }

        return shouldClearSyncedLibrary
            ? L10n.string("profile.alert.clearSyncedLibrary.title")
            : L10n.string("profile.alert.clearData.title")
    }

    private func clearLibraryAlertMessage(for target: LocalDataClearTarget) -> String {
        switch target {
        case .favorites:
            return L10n.string("profile.alert.clearFavorites.message")
        case .recents:
            return L10n.string("profile.alert.clearRecents.message")
        case .discoveries:
            return L10n.string("profile.alert.clearDiscoveries.message")
        case .settings:
            return L10n.string("profile.alert.resetSettings.message")
        case .all:
            break
        }

        return shouldClearSyncedLibrary
            ? L10n.string("profile.alert.clearSyncedLibrary.message")
            : L10n.string("profile.alert.clearData.message")
    }

    private func clearLibraryConfirmTitle(for target: LocalDataClearTarget) -> String {
        switch target {
        case .favorites, .recents, .discoveries:
            return L10n.string("profile.alert.clearData.confirm")
        case .settings:
            return L10n.string("profile.alert.resetSettings.confirm")
        case .all:
            break
        }

        return shouldClearSyncedLibrary
            ? L10n.string("profile.alert.clearSyncedLibrary.confirm")
            : L10n.string("profile.alert.clearData.confirm")
    }

    private var accountSummaryDetail: String {
        switch accessController.accessMode {
        case .guest:
            L10n.string("profile.summary.account.detail.guest")
        case .signedInFree, .signedInPro:
            L10n.string("profile.summary.account.detail.signedIn", displayName)
        }
    }

    private var planSummaryDetail: String {
        switch accessController.accessMode {
        case .guest:
            L10n.string("profile.summary.plan.detail.guest")
        case .signedInFree:
            L10n.string("profile.summary.plan.detail.free")
        case .signedInPro:
            L10n.string("profile.summary.plan.detail.pro")
        }
    }

    private var proPlanSubtitle: String {
        switch accessController.accessMode {
        case .guest:
            L10n.string("profile.pro.subtitle.guest")
        case .signedInFree:
            L10n.string("profile.pro.subtitle.free")
        case .signedInPro:
            L10n.string("profile.pro.subtitle.pro")
        }
    }

    private var subscriptionStatusDetail: String? {
        guard accessController.accessMode == .signedInPro else { return nil }
        guard let subscription = accountSummary?.billing?.subscriptions.first(where: { subscription in
            subscription.appId == "tuneav" && subscription.planTier == .pro
        }) else {
            return nil
        }

        if subscription.status == "pastDue" {
            return L10n.string("profile.pro.subscription.billingIssue")
        }

        if let expiresAt = subscription.expiresAt ?? subscription.renewsAt,
           let formattedDate = Self.subscriptionDateFormatter.string(fromISO8601: expiresAt) {
            return L10n.string("profile.pro.subscription.activeThrough", formattedDate)
        }

        return nil
    }

    private static let subscriptionDateFormatter = TuneAVSubscriptionDateFormatter()

    private var cloudSyncIcon: String {
        switch libraryStore.cloudSyncStatus {
        case .idle:
            "icloud"
        case .syncing:
            "arrow.triangle.2.circlepath.icloud"
        case .synced:
            "checkmark.icloud"
        case .conflict:
            "exclamationmark.icloud"
        case .failed:
            "xmark.icloud"
        }
    }

    private var cloudSyncLastSyncedAt: Date? {
        if case .synced(let date) = libraryStore.cloudSyncStatus {
            return date
        }
        return nil
    }

    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { languageController.currentLanguage },
            set: { languageController.select($0) }
        )
    }

    private var preferredGenreSelection: Binding<String> {
        Binding(
            get: { libraryStore.settings.preferredTag },
            set: { libraryStore.setPreferredTag($0.isEmpty ? nil : $0) }
        )
    }

    private var themeSelection: Binding<AppTheme> {
        Binding(
            get: { themeController.currentTheme },
            set: { themeController.select($0) }
        )
    }

    private var keepScreenAwakeSelection: Binding<Bool> {
        Binding(
            get: { libraryStore.settings.keepScreenAwake },
            set: { libraryStore.setKeepScreenAwake($0) }
        )
    }

    private var cellularWarningSelection: Binding<Bool> {
        Binding(
            get: { libraryStore.settings.warnBeforeCellularPlayback },
            set: { libraryStore.setWarnBeforeCellularPlayback($0) }
        )
    }

    private var openLastStationSelection: Binding<Bool> {
        Binding(
            get: { libraryStore.settings.openLastStationOnLaunch },
            set: { libraryStore.setOpenLastStationOnLaunch($0) }
        )
    }

    private var autoSkipUnstableStreamsSelection: Binding<Bool> {
        Binding(
            get: { libraryStore.settings.autoSkipUnstableStreams },
            set: { libraryStore.setAutoSkipUnstableStreams($0) }
        )
    }

    private var externalSearchEngineSelection: Binding<AVExternalSearchEngine> {
        Binding(
            get: { AVExternalSearchEngine.resolved(from: libraryStore.settings.externalSearchEngine) },
            set: { libraryStore.setExternalSearchEngine($0) }
        )
    }

    private var webOpenModeSelection: Binding<AVExternalWebOpenMode> {
        Binding(
            get: { AVExternalWebOpenMode.resolved(from: libraryStore.settings.externalWebOpenMode) },
            set: { libraryStore.setExternalWebOpenMode($0) }
        )
    }

    private var languageSelector: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageSelection.wrappedValue = language
                } label: {
                    if languageController.currentLanguage == language {
                        Label {
                            Text("\(language.displayName) (\(language.autonym))")
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text("\(language.displayName) (\(language.autonym))")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(languageController.currentLanguage.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(languageController.currentLanguage.autonym)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TuneAVTheme.mutedSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        }
    }

    private var preferredGenreSelector: some View {
        Menu {
            Button {
                preferredGenreSelection.wrappedValue = ""
            } label: {
                if libraryStore.settings.preferredTag.isEmpty {
                    Label {
                        Text(L10n.string("profile.preferences.preferredGenre.none"))
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                } else {
                    Text(L10n.string("profile.preferences.preferredGenre.none"))
                }
            }

            ForEach(genreTags, id: \.self) { tag in
                Button {
                    preferredGenreSelection.wrappedValue = tag
                } label: {
                    if libraryStore.settings.preferredTag == tag {
                        Label {
                            Text(L10n.genreLabel(for: tag))
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(L10n.genreLabel(for: tag))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preferredGenreIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preferredGenreLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(L10n.string("profile.preferences.preferredGenre.title"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TuneAVTheme.mutedSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        }
    }

    private var themeSelector: some View {
        HStack(spacing: 10) {
            ForEach(AppTheme.allCases) { theme in
                AVSettingsOptionButton(
                    title: themeLabel(for: theme),
                    systemImage: themeSymbol(for: theme),
                    isSelected: themeController.currentTheme == theme,
                    action: { themeSelection.wrappedValue = theme }
                )
            }
        }
    }

    private var externalSearchEngineSelector: some View {
        HStack(spacing: 10) {
            ForEach(AVExternalSearchEngine.allCases) { engine in
                AVSettingsOptionButton(
                    title: externalSearchEngineLabel(for: engine),
                    systemImage: "magnifyingglass",
                    isSelected: externalSearchEngineSelection.wrappedValue == engine,
                    action: { externalSearchEngineSelection.wrappedValue = engine }
                )
            }
        }
    }

    private var webOpenModeSelector: some View {
        HStack(spacing: 10) {
            ForEach(AVExternalWebOpenMode.allCases) { mode in
                AVSettingsOptionButton(
                    title: webOpenModeLabel(for: mode),
                    systemImage: webOpenModeSymbol(for: mode),
                    isSelected: webOpenModeSelection.wrappedValue == mode,
                    action: { webOpenModeSelection.wrappedValue = mode }
                )
            }
        }
    }

    private func performClearLocalData(_ target: LocalDataClearTarget) {
        guard isClearingLocalData == false else { return }
        isClearingLocalData = true
        clearLocalData(target)
        if accessController.accessMode == .guest && target == .all {
            startSignInFlow(false)
        }
        isClearingLocalData = false
    }

    private func clearLocalData(_ target: LocalDataClearTarget) {
        switch target {
        case .favorites:
            libraryStore.clearFavorites(propagatesToCloud: shouldClearSyncedLibrary)
        case .recents:
            libraryStore.clearRecents(propagatesToCloud: shouldClearSyncedLibrary)
        case .discoveries:
            libraryStore.clearDiscoveries(propagatesToCloud: shouldClearSyncedLibrary)
        case .settings:
            libraryStore.resetSettings()
        case .all:
            libraryStore.clearLocalData(propagatesToCloud: shouldClearSyncedLibrary)
        }
    }

    private var preferredGenreLabel: String {
        let preferredTag = libraryStore.settings.preferredTag
        guard !preferredTag.isEmpty else {
            return L10n.string("profile.preferences.preferredGenre.none")
        }

        return L10n.genreLabel(for: preferredTag)
    }

    private var preferredGenreIcon: String {
        genreSymbol(for: libraryStore.settings.preferredTag)
    }

    private func genreSymbol(for tag: String) -> String {
        switch tag {
        case "rock":
            "guitars"
        case "pop":
            "music.note"
        case "jazz":
            "music.mic"
        case "electronic":
            "waveform"
        case "ambient":
            "sparkles"
        case "latin":
            "globe.americas"
        case "oldies":
            "clock.arrow.circlepath"
        case "classical":
            "pianokeys"
        case "country":
            "guitars"
        default:
            "music.note.list"
        }
    }

    private func themeLabel(for theme: AppTheme) -> String {
        switch theme {
        case .system:
            L10n.string("profile.preferences.theme.system")
        case .light:
            L10n.string("profile.preferences.theme.light")
        case .dark:
            L10n.string("profile.preferences.theme.dark")
        }
    }

    private func themeSymbol(for theme: AppTheme) -> String {
        switch theme {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max"
        case .dark:
            "moon.fill"
        }
    }

    private func externalSearchEngineLabel(for engine: AVExternalSearchEngine) -> String {
        switch engine {
        case .google:
            L10n.string("profile.preferences.externalSearchEngine.google")
        case .duckDuckGo:
            L10n.string("profile.preferences.externalSearchEngine.duckDuckGo")
        case .bing:
            L10n.string("profile.preferences.externalSearchEngine.bing")
        }
    }

    private func webOpenModeLabel(for mode: AVExternalWebOpenMode) -> String {
        switch mode {
        case .inApp:
            L10n.string("profile.preferences.webOpenMode.inApp")
        case .system:
            L10n.string("profile.preferences.webOpenMode.system")
        }
    }

    private func webOpenModeSymbol(for mode: AVExternalWebOpenMode) -> String {
        switch mode {
        case .inApp:
            "rectangle.inset.filled"
        case .system:
            "arrow.up.forward.app"
        }
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        if url.isTuneAVWebURL && AVExternalWebOpenMode.resolved(from: libraryStore.settings.externalWebOpenMode) == .inApp {
            browserDestination = BrowserDestination(url: url)
        } else {
            openExternalURL(url)
        }
    }

    private var localDataMaintenanceActions: [AVSettingsMaintenanceAction<LocalDataClearTarget>] {
        [
            AVSettingsMaintenanceAction(
                systemImage: "heart.text.square",
                title: L10n.string("profile.actions.clearFavorites"),
                detail: L10n.string("profile.alert.clearFavorites.message"),
                target: .favorites
            ),
            AVSettingsMaintenanceAction(
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                title: L10n.string("profile.actions.clearRecents"),
                detail: L10n.string("profile.alert.clearRecents.message"),
                target: .recents
            ),
            AVSettingsMaintenanceAction(
                systemImage: "music.note.list",
                title: L10n.string("profile.actions.clearDiscoveries"),
                detail: L10n.string("profile.alert.clearDiscoveries.message"),
                target: .discoveries
            ),
            AVSettingsMaintenanceAction(
                systemImage: "slider.horizontal.3",
                title: L10n.string("profile.actions.resetSettings"),
                detail: L10n.string("profile.alert.resetSettings.message"),
                target: .settings
            )
        ]
    }

    private var accountDeletionViewModel: AccountDeletionViewModel {
        AccountDeletionViewModel(
            api: accountDeletionAPI,
            signOut: { try await accessController.signOut() }
        )
    }

    private var accountDeletionAPI: AccountDeletionAPI {
        if let uiTestAPI = UITestAccountDeletionAPI.fromEnvironment() {
            return uiTestAPI
        }
        return AVAccountAPIClient(getToken: { try await accessController.accountService.getToken() })
    }

    private func refreshAccountSummaryIfNeeded() async {
        guard accessController.accessMode != .guest else {
            accountSummary = nil
            return
        }

        do {
            accountSummary = try await accountDeletionAPI.fetchAccountSummary()
        } catch {
            accountSummary = nil
        }
    }

    private func signOut() async {
        guard isSigningOut == false else { return }
        isSigningOut = true

        do {
            try await accessController.signOut()
        } catch {
            signOutErrorMessage = error.localizedDescription
            isShowingSignOutError = true
        }

        isSigningOut = false
    }
}

private struct TuneAVSubscriptionDateFormatter {
    private let isoFormatter = ISO8601DateFormatter()
    private let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    func string(fromISO8601 value: String) -> String? {
        guard let date = isoFormatter.date(from: value) else { return nil }
        return displayFormatter.string(from: date)
    }
}

private extension URL {
    var isTuneAVWebURL: Bool {
        isSupportedTuneAVBrowserURL
    }
}

private struct ProfilePrimaryButton: View {
    let title: String
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        AVSettingsButton(title: title, style: .primary, action: action)
        .accessibilityIdentifier(accessibilityID)
    }
}
