import AVSettingsFoundation
import SwiftUI

private enum MacLocalDataClearAction: Identifiable {
    case favorites
    case recents
    case discoveries
    case all

    var id: String {
        switch self {
        case .favorites: "favorites"
        case .recents: "recents"
        case .discoveries: "discoveries"
        case .all: "all"
        }
    }
}

private struct MacSettingsPickerSurface: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }
}

struct MacProfileView: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                profileSummaryCard
                proPlanCard
                syncCard
                if model.accountUser != nil {
                    accountSafetyCard
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
    }

    private var header: some View {
        AVSettingsScreenHeader(
            title: L10n.string("profile.accountScreen.title"),
            subtitle: L10n.string("profile.accountScreen.subtitle")
        )
    }

    private var profileSummaryCard: some View {
        AVSettingsCard {
            AVSettingsSectionHeader(
                title: L10n.string("profile.account.title"),
                subtitle: accountSubtitle
            )

            Divider()
                .overlay(TuneAVTheme.borderSubtle)

            AVSettingsInfoRow(
                systemImage: "person.crop.circle",
                title: L10n.string("profile.summary.account.title"),
                detail: accountSummaryDetail
            )
            if let emailAddress = model.accountUser?.emailAddress {
                AVSettingsInfoRow(
                    systemImage: "envelope",
                    title: L10n.string("profile.account.email.title"),
                    detail: emailAddress
                )
            }
            AVSettingsInfoRow(
                systemImage: "sparkles.rectangle.stack",
                title: L10n.string("profile.summary.plan.title"),
                detail: accountPlanDetail
            )

            accountActionButton
        }
    }

    private var proPlanCard: some View {
        AVSettingsCard {
            AVSettingsSectionHeader(
                title: L10n.string("profile.pro.title"),
                subtitle: proPlanSubtitle
            )

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

            proPlanAction
        }
    }

    private var syncCard: some View {
        AVSettingsCard {
            AVSettingsSectionHeader(
                title: L10n.string("profile.sync.title"),
                subtitle: syncSubtitle
            )

            AVSettingsInfoRow(
                systemImage: syncStatusIcon,
                title: syncHeadline,
                detail: syncDetail
            )
            .accessibilityIdentifier("profile.sync.status")

            if let cloudSyncErrorMessage = model.cloudSyncErrorMessage {
                Label(cloudSyncErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if let lastCloudSyncAt = model.lastCloudSyncAt {
                Text(L10n.string("profile.sync.lastActivity", lastCloudSyncAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            AVSettingsButton(
                title: model.cloudSyncStatus == .syncing ? L10n.string("profile.sync.retry.syncing") : L10n.string("profile.sync.retry"),
                style: .secondary,
                isLoading: model.cloudSyncStatus == .syncing,
                action: { Task { await model.synchronizeLibraryNow() } }
            )
            .disabled(model.cloudSyncStatus == .syncing || model.accountUser == nil)
        }
    }

    private var accountSafetyCard: some View {
        AVSettingsCard {
            AVSettingsSectionHeader(
                title: L10n.string("profile.safety.title"),
                subtitle: L10n.string("profile.safety.subtitle")
            )

            if let deleteAccountURL {
                AVSettingsActionRow(
                    systemImage: "exclamationmark.shield",
                    title: L10n.string("profile.safety.delete.title"),
                    detail: L10n.string("profile.safety.delete.detail"),
                    action: { openURL(deleteAccountURL) }
                )
                .accessibilityIdentifier("profile.safety.delete")
            }
        }
    }

    @ViewBuilder
    private var accountActionButton: some View {
        if model.accountUser == nil {
            HStack(spacing: 10) {
                AVSettingsButton(
                    title: "Sign in with Apple",
                    style: .primary,
                    action: { Task { await model.signInWithApple() } }
                )
                AVSettingsButton(
                    title: "Sign in with Google",
                    style: .secondary,
                    action: { Task { await model.signInWithGoogle() } }
                )
            }
        } else {
            AVSettingsButton(
                title: L10n.string("profile.actions.signOut"),
                style: .secondary,
                action: { Task { await model.signOut() } }
            )
        }
    }

    @ViewBuilder
    private var proPlanAction: some View {
        if model.accountUser == nil {
            AVSettingsButton(
                title: L10n.string("profile.pro.signIn"),
                style: .primary,
                action: { Task { await model.signInWithApple() } }
            )
        } else if let accountURL = accountManagementURL {
            AVSettingsButton(
                title: L10n.string("profile.pro.manage"),
                style: .secondary,
                action: { openURL(accountURL) }
            )
        }
    }

    private var accountSubtitle: String {
        model.accountUser?.emailAddress ?? L10n.string("profile.accountSurface.guest")
    }

    private var accountTitle: String {
        model.accountUser?.displayName ?? L10n.string("profile.account.identity.guest")
    }

    private var accountDetail: String {
        model.accountUser?.emailAddress ?? L10n.string("profile.summary.account.detail.guest")
    }

    private var accountSummaryDetail: String {
        model.accountUser == nil ? L10n.string("profile.summary.account.detail.guest") : accountTitle
    }

    private var accountPlanDetail: String {
        model.accountUser == nil
            ? L10n.string("profile.summary.plan.detail.guest")
            : L10n.string("profile.accountSurface.free")
    }

    private var proPlanSubtitle: String {
        model.accountUser == nil ? L10n.string("profile.pro.subtitle.guest") : L10n.string("profile.pro.subtitle.free")
    }

    private var syncSubtitle: String {
        model.accountUser == nil
            ? L10n.string("profile.accountSurface.guest")
            : L10n.string("profile.sync.subtitle.short")
    }

    private var syncMetricValue: String {
        switch model.cloudSyncStatus {
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

    private var syncSummaryValue: String {
        model.accountUser == nil ? L10n.string("profile.summary.plan.detail.guest") : syncMetricValue
    }

    private var syncHeadline: String {
        syncMetricValue
    }

    private var syncDetail: String {
        guard model.accountUser != nil else {
            return L10n.string("profile.account.identity.guest")
        }

        switch model.cloudSyncStatus {
        case .idle:
            return L10n.string("profile.sync.detail.ready")
        case .syncing:
            return L10n.string("profile.sync.detail.syncing")
        case .synced(let date):
            return L10n.string("profile.sync.lastActivity", date.formatted(date: .abbreviated, time: .shortened))
        case .conflict:
            return L10n.string("profile.sync.detail.needsAttention")
        case .failed:
            return L10n.string("profile.sync.detail.failed")
        }
    }

    private var syncStatusIcon: String {
        guard model.accountUser != nil else {
            return "icloud.slash"
        }

        switch model.cloudSyncStatus {
        case .idle:
            return "icloud"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.icloud"
        case .conflict:
            return "exclamationmark.icloud"
        case .failed:
            return "icloud.slash"
        }
    }

    private var syncStatusColor: Color {
        switch model.cloudSyncStatus {
        case .synced:
            return .green
        case .conflict, .failed:
            return .red
        case .idle, .syncing:
            return TuneAVTheme.highlight
        }
    }

    private var accountManagementURL: URL? {
        TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_MANAGEMENT_URL")
    }

    private var deleteAccountURL: URL? {
        TuneAVBundleConfig.deleteAccountURL(
            explicitURL: TuneAVBundleConfig.urlValue(for: "TUNEAV_DELETE_ACCOUNT_URL"),
            accountManagementURL: accountManagementURL
        )
    }

}

private struct MacProfileCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Divider()

            content()
        }
        .padding(18)
        .background(TuneAVTheme.cardSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct MacProfileMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 34, height: 34)
                .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .frame(minHeight: 82)
        .background(TuneAVTheme.cardSurface.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.68), lineWidth: 1)
        }
    }
}

private struct MacProfileInfoRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(TuneAVTheme.textSecondary)
            }

            Spacer()
        }
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var model: TuneAVMacModel
    @EnvironmentObject private var languageController: AppLanguageController
    @Environment(\.openURL) private var openURL

    @AppStorage("tuneav.mac.openLastStationOnLaunch") private var openLastStationOnLaunch = true
    @AppStorage("tuneav.mac.autoSkipUnstableStreams") private var autoSkipUnstableStreams = true
    @AppStorage("tuneav.mac.keepWindowAwake") private var keepWindowAwake = false
    @AppStorage("tuneav.mac.preferredGenre") private var preferredGenre = ""
    @State private var pendingClearAction: MacLocalDataClearAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                preferencesCard
                localDataCard
                helpCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
    }

    private var header: some View {
        AVSettingsScreenHeader(
            title: L10n.string("shell.header.settings"),
            subtitle: L10n.string("profile.preferences.subtitle")
        )
    }

    private var preferencesCard: some View {
        AVSettingsCard {
            AVSettingsSectionHeader(
                title: L10n.string("profile.preferences.title"),
                subtitle: L10n.string("profile.preferences.subtitle")
            )

            AVSettingsInfoRow(
                systemImage: "globe",
                title: L10n.string("profile.preferences.language.title"),
                detail: L10n.string("profile.preferences.language.detail")
            )

            languageSelector

            AVSettingsInfoRow(
                systemImage: "music.note.list",
                title: L10n.string("profile.preferences.preferredGenre.title"),
                detail: L10n.string("profile.preferences.preferredGenre.detail", preferredGenreLabel)
            )

            preferredGenreSelector

            Divider()
                .overlay(TuneAVTheme.borderSubtle)

            AVSettingsToggleRow(
                systemImage: "clock.arrow.circlepath",
                title: L10n.string("profile.preferences.openLastStation.title"),
                detail: L10n.string("profile.preferences.openLastStation.detail"),
                isOn: $openLastStationOnLaunch
            )

            AVSettingsToggleRow(
                systemImage: "forward.end.fill",
                title: L10n.string("profile.preferences.autoSkipUnstableStreams.title"),
                detail: L10n.string("profile.preferences.autoSkipUnstableStreams.detail"),
                isOn: $autoSkipUnstableStreams
            )

            AVSettingsToggleRow(
                systemImage: "macwindow",
                title: L10n.string("profile.preferences.keepScreenAwake.title"),
                detail: L10n.string("profile.preferences.keepScreenAwake.detail"),
                isOn: $keepWindowAwake
            )
        }
    }

    private var localDataCard: some View {
        AVSettingsCard {
            AVSettingsSectionHeader(
                title: L10n.string("profile.local.title"),
                subtitle: L10n.string("profile.local.subtitle")
            )

            AVSettingsInfoRow(
                systemImage: "heart.text.square",
                title: L10n.string("shell.library.favorites.title"),
                detail: L10n.plural(
                    singular: "profile.local.favorites.count.one",
                    plural: "profile.local.favorites.count.other",
                    count: model.favoriteStations.count,
                    model.favoriteStations.count
                )
            )
            AVSettingsInfoRow(
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                title: L10n.string("shell.home.recents.title"),
                detail: L10n.plural(
                    singular: "profile.local.recents.count.one",
                    plural: "profile.local.recents.count.other",
                    count: model.recentStations.count,
                    model.recentStations.count
                )
            )
            AVSettingsInfoRow(
                systemImage: "music.note.list",
                title: L10n.string("profile.local.savedMusic.title"),
                detail: L10n.plural(
                    singular: "profile.local.savedMusic.count.one",
                    plural: "profile.local.savedMusic.count.other",
                    count: model.savedDiscoveredTracks.count,
                    model.savedDiscoveredTracks.count
                )
            )
            AVSettingsInfoRow(
                systemImage: "internaldrive",
                title: L10n.string("profile.local.storagePolicy.title"),
                detail: model.accountUser == nil ? L10n.string("profile.local.storagePolicy.local") : L10n.string("profile.local.storagePolicy.remote")
            )

            AVSettingsInlineActionRow(
                systemImage: "heart.slash",
                title: L10n.string("profile.actions.clearFavorites"),
                detail: L10n.string("profile.alert.clearFavorites.message"),
                actionTitle: L10n.string("profile.alert.clearData.confirm"),
                action: { pendingClearAction = .favorites }
            )
            .disabled(model.favoriteStations.isEmpty)

            AVSettingsInlineActionRow(
                systemImage: "clock.badge.xmark",
                title: L10n.string("profile.actions.clearRecents"),
                detail: L10n.string("profile.alert.clearRecents.message"),
                actionTitle: L10n.string("profile.alert.clearData.confirm"),
                action: { pendingClearAction = .recents }
            )
            .disabled(model.recentStations.isEmpty)

            AVSettingsInlineActionRow(
                systemImage: "music.note.list",
                title: L10n.string("profile.actions.clearDiscoveries"),
                detail: L10n.string("profile.alert.clearDiscoveries.message"),
                actionTitle: L10n.string("profile.alert.clearData.confirm"),
                action: { pendingClearAction = .discoveries }
            )
            .disabled(model.discoveredTracks.isEmpty)

            AVSettingsInlineActionRow(
                systemImage: "trash",
                title: L10n.string("profile.actions.clearAllLocalData"),
                detail: L10n.string("profile.alert.clearData.message"),
                actionTitle: L10n.string("profile.actions.clearAllLocalData"),
                action: { pendingClearAction = .all }
            )
            .disabled(model.favoriteStations.isEmpty && model.recentStations.isEmpty && model.discoveredTracks.isEmpty)

            if pendingClearAction != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text(clearDialogTitle)
                        .font(.headline)
                        .foregroundStyle(TuneAVTheme.textPrimary)
                    Text(clearDialogMessage)
                        .font(.subheadline)
                        .foregroundStyle(TuneAVTheme.textSecondary)

                    HStack(spacing: 10) {
                        Button(role: .destructive) {
                            performClearAction()
                        } label: {
                            Text(clearDialogConfirmTitle)
                        }

                        Button(L10n.string("profile.alert.clearData.cancel")) {
                            pendingClearAction = nil
                        }
                    }
                }
                .padding(14)
                .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
            }
        }
    }

    private var helpCard: some View {
        AVSettingsCard {
            AVSettingsSectionHeader(
                title: L10n.string("profile.help.title"),
                subtitle: L10n.string("profile.help.subtitle")
            )

            AVSettingsInfoRow(
                systemImage: "chevron.left.forwardslash.chevron.right",
                title: L10n.string("profile.help.opensource.title"),
                detail: L10n.string("profile.help.opensource.detail")
            )

            if let openSourceURL {
                AVSettingsActionRow(
                    systemImage: "book.pages",
                    title: L10n.string("profile.help.sourceCode.title"),
                    detail: L10n.string("profile.help.sourceCode.detail"),
                    action: { openURL(openSourceURL) }
                )
            }

            if let supportURL {
                AVSettingsActionRow(
                    systemImage: "questionmark.bubble",
                    title: L10n.string("profile.help.support.title"),
                    detail: L10n.string("profile.help.support.detail"),
                    action: { openURL(supportURL) }
                )
            }
            AVSettingsActionRow(
                systemImage: "doc.text",
                title: L10n.string("profile.help.terms.title"),
                detail: L10n.string("profile.help.terms.detail"),
                action: { openURL(termsURL) }
            )
            AVSettingsActionRow(
                systemImage: "hand.raised",
                title: L10n.string("profile.help.privacy.title"),
                detail: L10n.string("profile.help.privacy.detail"),
                action: { openURL(privacyURL) }
            )
        }
    }

    private var preferredGenreLabel: String {
        preferredGenre.isEmpty ? L10n.string("profile.preferences.preferredGenre.none") : L10n.genreLabel(for: preferredGenre)
    }

    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { languageController.currentLanguage },
            set: { languageController.select($0) }
        )
    }

    private var languageSelector: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageSelection.wrappedValue = language
                } label: {
                    if languageController.currentLanguage == language {
                        Label("\(language.displayName) (\(language.autonym))", systemImage: "checkmark")
                    } else {
                        Text("\(language.displayName) (\(language.autonym))")
                    }
                }
            }
        } label: {
            MacSettingsPickerSurface(
                systemImage: "globe",
                title: languageController.currentLanguage.displayName,
                subtitle: languageController.currentLanguage.autonym
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preferredGenreSelector: some View {
        Menu {
            Button {
                preferredGenre = ""
            } label: {
                if preferredGenre.isEmpty {
                    Label(L10n.string("profile.preferences.preferredGenre.none"), systemImage: "checkmark")
                } else {
                    Text(L10n.string("profile.preferences.preferredGenre.none"))
                }
            }

            ForEach(TuneAVMusicGenreCatalog.visibleTags, id: \.self) { tag in
                Button {
                    preferredGenre = tag
                } label: {
                    if preferredGenre == tag {
                        Label(L10n.genreLabel(for: tag), systemImage: "checkmark")
                    } else {
                        Text(L10n.genreLabel(for: tag))
                    }
                }
            }
        } label: {
            MacSettingsPickerSurface(
                systemImage: "music.note.list",
                title: preferredGenreLabel,
                subtitle: L10n.string("profile.preferences.preferredGenre.title")
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var supportURL: URL? {
        TuneAVBundleConfig.supportURL(
            explicitURL: TuneAVBundleConfig.urlValue(for: "SUPPORTAV_BASE_URL", requireSupportedAVAccountBaseURL: true)
                ?? URL(string: "https://support-av.avalsys.com/"),
            email: TuneAVBundleConfig.nonEmptyStringValue(for: "TUNEAV_SUPPORT_EMAIL") ?? "support@avalsys.com"
        )
    }

    private var openSourceURL: URL? {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_OPEN_SOURCE_URL", requireSupportedAVAccountBaseURL: true)
            ?? URL(string: "https://github.com/miguelavalos/tune-av")
    }

    private var privacyURL: URL {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_PRIVACY_URL", requireSupportedAVAccountBaseURL: true)
            ?? URL(string: "https://tune-av.avalsys.com/privacy")!
    }

    private var termsURL: URL {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_TERMS_URL", requireSupportedAVAccountBaseURL: true)
            ?? URL(string: "https://tune-av.avalsys.com/terms")!
    }

    private var clearDialogTitle: String {
        switch pendingClearAction {
        case .favorites:
            return L10n.string("profile.alert.clearFavorites.title")
        case .recents:
            return L10n.string("profile.alert.clearRecents.title")
        case .discoveries:
            return L10n.string("profile.alert.clearDiscoveries.title")
        case .all:
            return L10n.string("profile.alert.clearData.title")
        case nil:
            return ""
        }
    }

    private var clearDialogMessage: String {
        switch pendingClearAction {
        case .favorites:
            return L10n.string("profile.alert.clearFavorites.message")
        case .recents:
            return L10n.string("profile.alert.clearRecents.message")
        case .discoveries:
            return L10n.string("profile.alert.clearDiscoveries.message")
        case .all:
            return L10n.string("profile.alert.clearData.message")
        case nil:
            return ""
        }
    }

    private var clearDialogConfirmTitle: String {
        switch pendingClearAction {
        case .all:
            return L10n.string("profile.actions.clearAllLocalData")
        case .favorites, .recents, .discoveries:
            return L10n.string("profile.alert.clearData.confirm")
        case nil:
            return ""
        }
    }

    private func performClearAction() {
        switch pendingClearAction {
        case .favorites:
            model.clearFavorites()
        case .recents:
            model.clearRecents()
        case .discoveries:
            model.clearDiscoveredTracks()
        case .all:
            model.clearLocalLibraryData()
        case nil:
            break
        }
        pendingClearAction = nil
    }
}
