import SwiftUI

struct ProfileScreen: View {
    enum Mode {
        case account
        case settings
    }

    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var languageController: AppLanguageController
    @EnvironmentObject private var themeController: AppThemeController
    @EnvironmentObject private var libraryStore: LibraryStore

    let mode: Mode
    let startSignInFlow: (Bool) -> Void
    let bottomContentPadding: CGFloat

    @State private var isClearingLocalData = false
    @State private var isShowingClearLocalDataAlert = false
    @State private var isSigningOut = false
    @State private var signOutErrorMessage = ""
    @State private var isShowingSignOutError = false
    @State private var browserDestination: BrowserDestination?
    @State private var isShowingAccountDeletion = false
    @State private var isShowingProPaywall = false
    private let genreTags = TuneAVMusicGenreCatalog.visibleTags

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShellBrandHeader(statusTitle: statusTitle, activeItem: headerActiveItem)

                VStack(alignment: .leading, spacing: 10) {
                    Text(screenTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(screenSubtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                }

                screenContent
            }
            .shellScreenContentPadding(bottom: bottomContentPadding)
        }
        .shellScreenScrollBehavior()
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .alert(clearLibraryAlertTitle, isPresented: $isShowingClearLocalDataAlert) {
            Button(L10n.string("profile.alert.clearData.cancel"), role: .cancel) {}
            Button(clearLibraryConfirmTitle, role: .destructive) {
                isClearingLocalData = true
                libraryStore.clearLocalData(propagatesToCloud: shouldClearSyncedLibrary)
                if accessController.accessMode == .guest {
                    startSignInFlow(false)
                }
                isClearingLocalData = false
            }
        } message: {
            Text(clearLibraryAlertMessage)
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
            TuneAVProPaywallView()
                .environmentObject(accessController)
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
            localDataCard
            helpAndLegalCard
        }
    }

    private var profileSummaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.string("profile.account.title"),
                subtitle: accountIdentityDetail
            )

            Divider()
                .overlay(TuneAVTheme.borderSubtle)

            VStack(alignment: .leading, spacing: 12) {
                ShellRow(
                    systemImage: "person.crop.circle",
                    title: L10n.string("profile.summary.account.title"),
                    detail: accountSummaryDetail
                )
                if let emailAddress = accessController.accountUser?.emailAddress {
                    ShellRow(
                        systemImage: "envelope",
                        title: L10n.string("profile.account.email.title"),
                        detail: emailAddress
                    )
                }
                ShellRow(
                    systemImage: "sparkles.rectangle.stack",
                    title: L10n.string("profile.summary.plan.title"),
                    detail: planSummaryDetail
                )
            }

            accountActionButton
        }
        .padding(22)
        .background(profileCardBackground)
    }

    private var cloudSyncCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.string("profile.sync.title"),
                subtitle: L10n.string("profile.sync.subtitle")
            )

            VStack(alignment: .leading, spacing: 12) {
                ShellRow(
                    systemImage: cloudSyncIcon,
                    title: L10n.string("profile.sync.status.title"),
                    detail: cloudSyncStatusDetail
                )
                .accessibilityIdentifier("profile.sync.status")

                if let lastSyncedAt = cloudSyncLastSyncedAt {
                    ShellRow(
                        systemImage: "clock.badge.checkmark",
                        title: L10n.string("profile.sync.lastSynced.title"),
                        detail: lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    .accessibilityIdentifier("profile.sync.lastSynced")
                }
            }

            ProfileSecondaryButton(
                title: libraryStore.cloudSyncStatus == .syncing
                    ? L10n.string("profile.sync.retry.syncing")
                    : L10n.string("profile.sync.retry"),
                isLoading: libraryStore.cloudSyncStatus == .syncing,
                action: {
                    Task {
                        await libraryStore.refreshCloudLibraryIfNeeded(force: true)
                    }
                }
            )
            .disabled(libraryStore.cloudSyncStatus == .syncing)
            .accessibilityIdentifier("profile.sync.retry")
        }
        .padding(22)
        .background(profileCardBackground)
        .accessibilityIdentifier("profile.sync.card")
    }

    private var proPlanCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.string("profile.pro.title"),
                subtitle: proPlanSubtitle
            )

            VStack(alignment: .leading, spacing: 12) {
                ShellRow(
                    systemImage: "heart.text.square",
                    title: L10n.string("profile.pro.library.title"),
                    detail: L10n.string("profile.pro.library.detail")
                )
                ShellRow(
                    systemImage: "icloud",
                    title: L10n.string("profile.pro.sync.title"),
                    detail: L10n.string("profile.pro.sync.detail")
                )
                ShellRow(
                    systemImage: "sparkles",
                    title: L10n.string("profile.pro.avi.title"),
                    detail: L10n.string("profile.pro.avi.detail")
                )
            }

            proPlanAction
        }
        .padding(22)
        .background(profileCardBackground)
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
                action: { startSignInFlow(true) }
            )
            .disabled(!accessController.accountIsAvailable)
            .accessibilityIdentifier("profile.pro.signIn")
        case .signedInFree:
            ProfilePrimaryButton(
                title: L10n.string("profile.pro.viewOffer"),
                action: { isShowingProPaywall = true }
            )
            .accessibilityIdentifier("profile.pro.viewOffer")
        case .signedInPro:
            ProfileSecondaryButton(
                title: L10n.string("profile.pro.manage"),
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
                action: { startSignInFlow(true) }
            )
            .disabled(!accessController.accountIsAvailable)
            .accessibilityIdentifier("profile.account.connect")
        } else {
            ProfileSecondaryButton(
                title: isSigningOut
                    ? L10n.string("profile.actions.signingOut")
                    : L10n.string("profile.actions.signOut"),
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
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.string("profile.preferences.title"),
                subtitle: L10n.string("profile.preferences.subtitle")
            )

            ShellRow(
                systemImage: "globe",
                title: L10n.string("profile.preferences.language.title"),
                detail: L10n.string("profile.preferences.language.detail")
            )

            languageSelector

            ShellRow(
                systemImage: "music.note.list",
                title: L10n.string("profile.preferences.preferredGenre.title"),
                detail: L10n.string(
                    "profile.preferences.preferredGenre.detail",
                    preferredGenreLabel
                )
            )

            preferredGenreSelector

            ShellRow(
                systemImage: "circle.lefthalf.filled",
                title: L10n.string("profile.preferences.theme.title"),
                detail: L10n.string("profile.preferences.theme.detail")
            )

            themeSelector
        }
        .padding(22)
        .background(profileCardBackground)
    }

    private var localDataCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.string("profile.local.title"),
                subtitle: L10n.string("profile.local.subtitle")
            )

            VStack(alignment: .leading, spacing: 12) {
                ShellRow(
                    systemImage: "heart.text.square",
                    title: L10n.string("shell.library.favorites.title"),
                    detail: localCountDetail(
                        count: libraryStore.favorites.count,
                        limit: accessController.limits.favoriteStations,
                        singular: "profile.local.favorites.count.one",
                        plural: "profile.local.favorites.count.other"
                    )
                )
                ShellRow(
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    title: L10n.string("shell.home.recents.title"),
                    detail: localCountDetail(
                        count: libraryStore.recents.count,
                        limit: accessController.limits.recentStations,
                        singular: "profile.local.recents.count.one",
                        plural: "profile.local.recents.count.other"
                    )
                )
                ShellRow(
                    systemImage: "music.note.list",
                    title: L10n.string("profile.local.savedMusic.title"),
                    detail: localCountDetail(
                        count: libraryStore.savedDiscoveriesCount,
                        limit: accessController.limits.savedTracks,
                        singular: "profile.local.savedMusic.count.one",
                        plural: "profile.local.savedMusic.count.other"
                    )
                )
                ShellRow(
                    systemImage: "internaldrive",
                    title: L10n.string("profile.local.storagePolicy.title"),
                    detail: accessController.capabilities.isLocalOnly
                        ? L10n.string("profile.local.storagePolicy.local")
                        : L10n.string("profile.local.storagePolicy.remote")
                )
            }

            ProfileDangerButton(
                title: isClearingLocalData
                    ? clearLibraryLoadingTitle
                    : clearLibraryActionTitle,
                action: { isShowingClearLocalDataAlert = true }
            )
            .disabled(isClearingLocalData)
        }
        .padding(22)
        .background(profileCardBackground)
    }

    private func localCountDetail(count: Int, limit: Int?, singular: String, plural: String) -> String {
        let base = L10n.plural(
            singular: singular,
            plural: plural,
            count: count,
            count
        )
        guard let limit else { return base }
        return L10n.string("profile.local.limit.used", base, count, limit)
    }

    private var helpAndLegalCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.string("profile.help.title"),
                subtitle: L10n.string("profile.help.subtitle")
            )

            VStack(spacing: 12) {
                ShellRow(
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    title: L10n.string("profile.help.opensource.title"),
                    detail: L10n.string("profile.help.opensource.detail")
                )

                if let openSourceURL = AppConfig.openSourceURL {
                    ProfileActionRow(
                        systemImage: "book.pages",
                        title: L10n.string("profile.help.sourceCode.title"),
                        detail: L10n.string("profile.help.sourceCode.detail"),
                        action: { open(openSourceURL) }
                    )
                }

                if let supportURL = AppConfig.supportURL {
                    ProfileActionRow(
                        systemImage: "questionmark.bubble",
                        title: L10n.string("profile.help.support.title"),
                        detail: L10n.string("profile.help.support.detail"),
                        action: { open(supportURL) }
                    )
                }
                if let termsURL = AppConfig.termsURL {
                    ProfileActionRow(
                        systemImage: "doc.text",
                        title: L10n.string("profile.help.terms.title"),
                        detail: L10n.string("profile.help.terms.detail"),
                        action: { open(termsURL) }
                    )
                }
                if let privacyURL = AppConfig.privacyURL {
                    ProfileActionRow(
                        systemImage: "hand.raised",
                        title: L10n.string("profile.help.privacy.title"),
                        detail: L10n.string("profile.help.privacy.detail"),
                        action: { open(privacyURL) }
                    )
                }
            }
        }
        .padding(22)
        .background(profileCardBackground)
    }

    private var accountSafetyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: L10n.string("profile.safety.title"),
                subtitle: L10n.string("profile.safety.subtitle")
            )

            ProfileActionRow(
                systemImage: "exclamationmark.shield",
                title: L10n.string("profile.safety.delete.title"),
                detail: L10n.string("profile.safety.delete.detail"),
                action: { isShowingAccountDeletion = true }
            )
            .accessibilityIdentifier("profile.safety.delete")
        }
        .padding(22)
        .background(profileCardBackground)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var profileCardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(TuneAVTheme.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
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
        accessController.capabilities.canUseCloudSync
    }

    private var clearLibraryActionTitle: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.actions.clearSyncedLibrary")
            : L10n.string("profile.actions.clearData")
    }

    private var clearLibraryLoadingTitle: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.actions.clearingSyncedLibrary")
            : L10n.string("profile.actions.clearingData")
    }

    private var clearLibraryAlertTitle: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.alert.clearSyncedLibrary.title")
            : L10n.string("profile.alert.clearData.title")
    }

    private var clearLibraryAlertMessage: String {
        shouldClearSyncedLibrary
            ? L10n.string("profile.alert.clearSyncedLibrary.message")
            : L10n.string("profile.alert.clearData.message")
    }

    private var clearLibraryConfirmTitle: String {
        shouldClearSyncedLibrary
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

    private var cloudSyncStatusDetail: String {
        switch libraryStore.cloudSyncStatus {
        case .idle:
            L10n.string("profile.sync.status.idle")
        case .syncing:
            L10n.string("profile.sync.status.syncing")
        case .synced:
            L10n.string("profile.sync.status.synced")
        case .conflict:
            L10n.string("profile.sync.status.conflict")
        case .failed:
            L10n.string("profile.sync.status.failed")
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
                ThemeOptionButton(
                    title: themeLabel(for: theme),
                    systemImage: themeSymbol(for: theme),
                    isSelected: themeController.currentTheme == theme,
                    action: { themeSelection.wrappedValue = theme }
                )
            }
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

    private func open(_ url: URL?) {
        guard let url else { return }
        browserDestination = BrowserDestination(url: url)
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

private struct ProfilePrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(TuneAVTheme.brandBlack)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    TuneAVTheme.highlight,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileSecondaryButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(TuneAVTheme.textPrimary)
                }
            }
            .foregroundStyle(TuneAVTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .padding(.horizontal, 18)
            .background(
                TuneAVTheme.cardSurface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileDangerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.84, green: 0.16, blue: 0.22))

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .padding(.horizontal, 18)
            .background(
                TuneAVTheme.cardSurface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.84, green: 0.16, blue: 0.22).opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileActionRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TuneAVTheme.mutedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeOptionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.mutedSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? TuneAVTheme.highlight.opacity(0.35) : TuneAVTheme.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
