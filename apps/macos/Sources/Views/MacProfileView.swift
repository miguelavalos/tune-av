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
    @State private var isShowingAccountDeletion = false
    @State private var isShowingProPaywall = false

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
        .sheet(isPresented: $isShowingAccountDeletion) {
            MacAccountDeletionSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $isShowingProPaywall) {
            MacProPaywallView(startSignInFlow: {
                Task { await model.signInWithApple() }
            })
            .environmentObject(model)
        }
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

            AVSettingsActionRow(
                systemImage: "exclamationmark.shield",
                title: L10n.string("profile.safety.delete.title"),
                detail: L10n.string("profile.safety.delete.detail"),
                action: { isShowingAccountDeletion = true }
            )
            .accessibilityIdentifier("profile.safety.delete")
        }
    }

    @ViewBuilder
    private var accountActionButton: some View {
        if model.accountUser == nil {
            HStack(spacing: 10) {
                AVSettingsButton(
                    title: accountActionTitle(L10n.string("auth.provider.apple")),
                    style: .primary,
                    isLoading: model.isAccountOperationInProgress,
                    action: { Task { await model.signInWithApple() } }
                )
                .disabled(model.isAccountOperationInProgress)
                AVSettingsButton(
                    title: accountActionTitle(L10n.string("auth.provider.google")),
                    style: .secondary,
                    isLoading: model.isAccountOperationInProgress,
                    action: { Task { await model.signInWithGoogle() } }
                )
                .disabled(model.isAccountOperationInProgress)
            }
        } else {
            AVSettingsButton(
                title: accountActionTitle(L10n.string("profile.actions.signOut")),
                style: .secondary,
                isLoading: model.isAccountOperationInProgress,
                action: { Task { await model.signOut() } }
            )
            .disabled(model.isAccountOperationInProgress)
        }
    }

    @ViewBuilder
    private var proPlanAction: some View {
        if model.accountUser == nil {
            AVSettingsButton(
                title: accountActionTitle(L10n.string("profile.pro.signIn")),
                style: .primary,
                isLoading: model.isAccountOperationInProgress,
                action: { Task { await model.signInWithApple() } }
            )
            .disabled(model.isAccountOperationInProgress)
        } else if model.accessMode == .signedInFree {
            AVSettingsButton(
                title: L10n.string("profile.pro.viewOffer"),
                style: .primary,
                action: { isShowingProPaywall = true }
            )
            .accessibilityIdentifier("profile.pro.viewOffer")
        } else if let subscriptionManagementURL {
            AVSettingsButton(
                title: L10n.string("profile.pro.manage"),
                style: .secondary,
                action: { openURL(subscriptionManagementURL) }
            )
            .accessibilityIdentifier("profile.pro.manage")
        }
    }

    private var accountSubtitle: String {
        model.accountUser?.emailAddress ?? L10n.string("profile.accountSurface.guest")
    }

    private func accountActionTitle(_ fallback: String) -> String {
        model.isAccountOperationInProgress ? L10n.string("profile.account.signingIn") : fallback
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
        switch model.accessMode {
        case .guest:
            return L10n.string("profile.summary.plan.detail.guest")
        case .signedInFree:
            return L10n.string("profile.summary.plan.detail.free")
        case .signedInPro:
            return L10n.string("profile.summary.plan.detail.pro")
        }
    }

    private var proPlanSubtitle: String {
        switch model.accessMode {
        case .guest:
            return L10n.string("profile.pro.subtitle.guest")
        case .signedInFree:
            return L10n.string("profile.pro.subtitle.free")
        case .signedInPro:
            return L10n.string("profile.pro.subtitle.pro")
        }
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

    private var subscriptionManagementURL: URL? {
        URL(string: "https://apps.apple.com/account/subscriptions")
    }

    private var deleteAccountURL: URL? {
        TuneAVBundleConfig.deleteAccountURL(
            explicitURL: TuneAVBundleConfig.urlValue(for: "TUNEAV_DELETE_ACCOUNT_URL"),
            accountManagementURL: accountManagementURL
        )
    }

}

private struct MacAccountDeletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: TuneAVMacModel
    @StateObject private var viewModel = MacAccountDeletionViewModel()

    var body: some View {
        AVSettingsSheetScaffold(
            spacing: 18,
            horizontalPadding: 24,
            topPadding: 24,
            bottomPadding: 24,
            backgroundStyle: AnyShapeStyle(TuneAVTheme.shellBackground),
            closeTitle: L10n.string("common.done"),
            closeAccessibilityIdentifier: "accountDeletion.done",
            onClose: { dismiss() }
        ) {
            AVSettingsScreenHeader(
                title: L10n.string("accountDeletion.title"),
                subtitle: L10n.string("accountDeletion.subtitle"),
                titleAccessibilityIdentifier: "accountDeletion.title"
            )

            if viewModel.isLoading {
                AVSettingsLoadingState(L10n.string("accountDeletion.loading"))
            } else {
                AVSettingsNoticeCard(
                    systemImage: "person.2.badge.gearshape",
                    title: L10n.string("accountDeletion.shared.title"),
                    detail: L10n.string("accountDeletion.shared.detail")
                )

                stateContent
            }
        }
        .frame(minWidth: 520, idealWidth: 620, maxWidth: 720, minHeight: 560)
        .task {
            await viewModel.load(using: model)
        }
        .onChange(of: viewModel.didCompleteDeletion) { _, didComplete in
            guard didComplete else { return }
            dismiss()
        }
        .accessibilityIdentifier("accountDeletion.sheet")
    }

    @ViewBuilder
    private var stateContent: some View {
        if let errorMessage = viewModel.errorMessage {
            AVSettingsStatusCard(
                systemImage: "exclamationmark.triangle",
                title: L10n.string("accountDeletion.error.title"),
                detail: errorMessage
            )
            .accessibilityIdentifier("accountDeletion.status.error")
        }

        switch viewModel.resolvedEligibility?.status {
        case .eligible:
            eligibleContent
        case .inProgress:
            inProgressContent
        case .completed:
            AVSettingsStatusCard(
                systemImage: "checkmark.circle",
                title: L10n.string("accountDeletion.completed.title"),
                detail: L10n.string("accountDeletion.completed.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.completed")
        case .blocked:
            blockedContent
        case .unavailable, .none:
            unavailableContent
        }
    }

    private var eligibleContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            AVSettingsStatusCard(
                systemImage: "checkmark.shield",
                title: L10n.string("accountDeletion.eligible.title"),
                detail: L10n.string("accountDeletion.eligible.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.eligible")

            impactNotice
            warningsList

            Text(L10n.string("accountDeletion.confirm.instructions"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            AVSettingsTextField(
                "DELETE",
                text: $viewModel.confirmationText,
                accessibilityIdentifier: "accountDeletion.confirmation"
            )

            AVSettingsButton(
                title: viewModel.isSubmitting
                    ? L10n.string("accountDeletion.deleting")
                    : L10n.string("accountDeletion.deleteButton"),
                style: .destructivePrimary,
                isLoading: viewModel.isSubmitting
            ) {
                Task { await viewModel.requestDeletion(using: model) }
            }
            .disabled(!viewModel.canRequestDeletion || viewModel.isSubmitting)
            .opacity(viewModel.canRequestDeletion ? 1 : 0.45)
            .accessibilityIdentifier("accountDeletion.deleteButton")
        }
    }

    private var inProgressContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            AVSettingsStatusCard(
                systemImage: "clock.badge.exclamationmark",
                title: L10n.string("accountDeletion.inProgress.title"),
                detail: L10n.string("accountDeletion.inProgress.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.inProgress")

            blockersList
            warningsList

            if viewModel.canFinalizeDeletion {
                AVSettingsButton(
                    title: viewModel.isSubmitting
                        ? L10n.string("accountDeletion.finalizing")
                        : L10n.string("accountDeletion.finalizeButton"),
                    style: .primary,
                    isLoading: viewModel.isSubmitting
                ) {
                    Task { await viewModel.finalizeDeletion(using: model) }
                }
                .disabled(viewModel.isSubmitting)
                .accessibilityIdentifier("accountDeletion.finalizeButton")
            }
        }
    }

    private var blockedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            AVSettingsStatusCard(
                systemImage: "lock.shield",
                title: L10n.string("accountDeletion.blocked.title"),
                detail: L10n.string("accountDeletion.blocked.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.blocked")

            blockersList
            warningsList
            accountWebsiteButton
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            AVSettingsStatusCard(
                systemImage: "safari",
                title: L10n.string("accountDeletion.unavailable.title"),
                detail: L10n.string("accountDeletion.unavailable.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.unavailable")

            warningsList
            accountWebsiteButton
        }
    }

    @ViewBuilder
    private var impactNotice: some View {
        if viewModel.hasHighImpactDeletionWarnings {
            AVSettingsStatusCard(
                systemImage: "exclamationmark.octagon.fill",
                title: L10n.string("accountDeletion.impact.high.title"),
                detail: L10n.string("accountDeletion.impact.high.detail")
            )
            .accessibilityIdentifier("accountDeletion.impact.high")
        } else if viewModel.hasLinkedAppDeletionWarnings {
            AVSettingsStatusCard(
                systemImage: "exclamationmark.triangle.fill",
                title: L10n.string("accountDeletion.impact.linkedApps.title"),
                detail: L10n.string("accountDeletion.impact.linkedApps.detail")
            )
            .accessibilityIdentifier("accountDeletion.impact.linkedApps")
        }
    }

    private var blockersList: some View {
        AVSettingsDetailList(items: viewModel.blockers.map(detailItem(for:)))
    }

    private var warningsList: some View {
        AVSettingsDetailList(items: viewModel.warnings.map(detailItem(for:)))
    }

    private func detailItem(for item: AccountDeletionBlocker) -> AVSettingsDetailListItem {
        AVSettingsDetailListItem(
            id: item.type.rawValue,
            title: item.label,
            detail: item.detail,
            linkTitle: item.managementUrl == nil ? nil : L10n.string("accountDeletion.manageLink"),
            linkDestination: item.managementUrl,
            accessibilityIdentifier: "accountDeletion.\(item.type.rawValue)"
        )
    }

    @ViewBuilder
    private var accountWebsiteButton: some View {
        if let deleteAccountURL {
            AVSettingsLinkButton(
                title: L10n.string("accountDeletion.accountWebsiteLink"),
                systemImage: "safari",
                destination: deleteAccountURL
            )
            .accessibilityIdentifier("accountDeletion.accountWebsiteLink")
        }
    }

    private var deleteAccountURL: URL? {
        TuneAVBundleConfig.deleteAccountURL(
            explicitURL: TuneAVBundleConfig.urlValue(for: "TUNEAV_DELETE_ACCOUNT_URL"),
            accountManagementURL: TuneAVBundleConfig.urlValue(for: "ACCOUNTAV_MANAGEMENT_URL")
        )
    }
}

@MainActor
private final class MacAccountDeletionViewModel: ObservableObject {
    @Published private(set) var resolvedEligibility: AccountDeletionEligibility?
    @Published private(set) var summary: AccountSummary?
    @Published private(set) var isLoading = true
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published var confirmationText = ""
    @Published private(set) var didCompleteDeletion = false

    var canRequestDeletion: Bool {
        TuneAVAccountDeletionPolicy.canRequestDeletion(
            eligibility: resolvedEligibility,
            confirmationText: confirmationText
        )
    }

    var canFinalizeDeletion: Bool {
        TuneAVAccountDeletionPolicy.canFinalizeDeletion(eligibility: resolvedEligibility, summary: summary)
    }

    var blockers: [AccountDeletionBlocker] {
        resolvedEligibility?.blockers ?? []
    }

    var warnings: [AccountDeletionBlocker] {
        resolvedEligibility?.warnings ?? []
    }

    var hasHighImpactDeletionWarnings: Bool {
        warnings.contains { warning in
            switch warning.type {
            case .activeAiCredits, .activeProAccess, .activeBillingSubscription:
                return true
            case .linkedApp, .identityProvider, .deletionInProgress, .eligibilityUnavailable:
                return false
            }
        }
    }

    var hasLinkedAppDeletionWarnings: Bool {
        warnings.contains { $0.type == .linkedApp }
    }

    func load(using model: TuneAVMacModel) async {
        isLoading = true
        errorMessage = nil

        do {
            let accountSummary = try await model.fetchAccountDeletionSummary()
            summary = accountSummary
            resolvedEligibility = TuneAVAccountDeletionPolicy.resolvedEligibility(
                from: accountSummary,
                copy: Self.deletionCopy
            )
        } catch {
            errorMessage = L10n.string("accountDeletion.statusUpdateFailed.detail")
            resolvedEligibility = TuneAVAccountDeletionPolicy.unavailableEligibility(copy: Self.deletionCopy)
        }

        isLoading = false
    }

    func requestDeletion(using model: TuneAVMacModel) async {
        guard canRequestDeletion, isSubmitting == false else { return }
        isSubmitting = true
        errorMessage = nil

        do {
            let response = try await model.requestAccountDeletion()
            if TuneAVAccountDeletionPolicy.didCompleteDeletion(eligibility: response.deleteAccountEligibility, job: response.job) {
                didCompleteDeletion = true
                await model.signOutAfterAccountDeletion()
            } else {
                resolvedEligibility = response.deleteAccountEligibility ?? resolvedEligibility
            }
        } catch {
            errorMessage = L10n.string("accountDeletion.error.request")
        }

        isSubmitting = false
    }

    func finalizeDeletion(using model: TuneAVMacModel) async {
        guard isSubmitting == false else { return }
        isSubmitting = true
        errorMessage = nil

        do {
            let response = try await model.finalizeAccountDeletion()
            if TuneAVAccountDeletionPolicy.didCompleteDeletion(eligibility: response.deleteAccountEligibility, job: response.job) {
                didCompleteDeletion = true
                await model.signOutAfterAccountDeletion()
            } else {
                resolvedEligibility = response.deleteAccountEligibility ?? resolvedEligibility
            }
        } catch {
            errorMessage = L10n.string("accountDeletion.error.finalize")
        }

        isSubmitting = false
    }

    private static var deletionCopy: TuneAVAccountDeletionPolicy.Copy {
        TuneAVAccountDeletionPolicy.Copy(
            linkedAppTitle: L10n.string("accountDeletion.blocker.linkedApp.title"),
            linkedAppDetail: L10n.string("accountDeletion.blocker.linkedApp.detail"),
            proTitle: L10n.string("accountDeletion.blocker.pro.title"),
            proDetail: L10n.string("accountDeletion.blocker.pro.detail"),
            subscriptionTitle: L10n.string("accountDeletion.blocker.subscription.title"),
            subscriptionDetail: L10n.string("accountDeletion.blocker.subscription.detail"),
            jobTitle: L10n.string("accountDeletion.blocker.job.title"),
            unavailableTitle: L10n.string("accountDeletion.unavailable.title"),
            unavailableDetail: L10n.string("accountDeletion.unavailable.detail"),
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
    @EnvironmentObject private var themeController: AppThemeController
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
                appPreferencesCard
                tunePreferencesCard
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

    private var appPreferencesCard: some View {
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
                systemImage: "circle.lefthalf.filled",
                title: L10n.string("profile.preferences.theme.title"),
                detail: L10n.string("profile.preferences.theme.detail")
            )

            themeSelector
        }
    }

    private var tunePreferencesCard: some View {
        AVSettingsCard {
            AVSettingsSectionHeader(
                title: L10n.string("profile.productPreferences.title"),
                subtitle: L10n.string("profile.productPreferences.subtitle")
            )

            AVSettingsInfoRow(
                systemImage: "music.note.list",
                title: L10n.string("profile.preferences.preferredGenre.title"),
                detail: L10n.string("profile.preferences.preferredGenre.detail", preferredGenreLabel)
            )

            preferredGenreSelector

            Divider()
                .overlay(TuneAVTheme.borderSubtle)

            AVSettingsToggleRow(
                systemImage: "macwindow",
                title: L10n.string("profile.preferences.keepScreenAwake.title"),
                detail: L10n.string("profile.preferences.keepScreenAwake.detail"),
                isOn: $keepWindowAwake
            )

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
            "moon"
        }
    }

    private var supportURL: URL? {
        TuneAVBundleConfig.supportURL(
            explicitURL: TuneAVBundleConfig.urlValue(for: "SUPPORTAV_BASE_URL", requireSupportedAVAccountBaseURL: true)
                ?? URL(string: "https://support-av.avalsys.com/"),
            email: TuneAVBundleConfig.nonEmptyStringValue(for: "SUPPORT_EMAIL_TO") ?? "support@avalsys.com"
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
