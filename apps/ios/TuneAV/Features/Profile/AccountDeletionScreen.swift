import AVSettingsFoundation
import SwiftUI

struct AccountDeletionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AccountDeletionViewModel

    init(viewModel: AccountDeletionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if viewModel.isLoading {
                        ProgressView(L10n.string("accountDeletion.loading"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        sharedAccountNotice
                        stateContent
                    }
                }
                .padding(24)
            }
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .navigationTitle(L10n.string("accountDeletion.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.done")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("accountDeletion.done")
                }
            }
            .task {
                await viewModel.load()
            }
            .onChange(of: viewModel.didCompleteDeletion) { _, didComplete in
                guard didComplete else { return }
                dismiss()
            }
        }
        .accessibilityIdentifier("accountDeletion.sheet")
    }

    private var header: some View {
        AVSettingsScreenHeader(
            title: L10n.string("accountDeletion.title"),
            subtitle: L10n.string("accountDeletion.subtitle"),
            titleAccessibilityIdentifier: "accountDeletion.title"
        )
    }

    private var sharedAccountNotice: some View {
        AVSettingsNoticeCard(
            systemImage: "person.2.badge.gearshape",
            title: L10n.string("accountDeletion.shared.title"),
            detail: L10n.string("accountDeletion.shared.detail")
        )
    }

    @ViewBuilder
    private var stateContent: some View {
        if let errorMessage = viewModel.errorMessage {
            statusCard(
                systemImage: "exclamationmark.triangle",
                title: L10n.string("accountDeletion.error.title"),
                detail: errorMessage
            )
            .accessibilityIdentifier("accountDeletion.status.error")
        }

        if viewModel.didUnlinkCurrentApp {
            statusCard(
                systemImage: "link.badge.minus",
                title: L10n.string("accountDeletion.unlinked.title"),
                detail: viewModel.unlinkMessage ?? L10n.string("accountDeletion.unlinked.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.unlinked")
        } else {
            switch viewModel.resolvedEligibility?.status {
            case .eligible:
                eligibleContent
            case .blocked:
                blockedContent(title: L10n.string("accountDeletion.blocked.title"))
            case .inProgress:
                inProgressContent
            case .completed:
                statusCard(
                    systemImage: "checkmark.circle",
                    title: L10n.string("accountDeletion.completed.title"),
                    detail: L10n.string("accountDeletion.completed.detail")
                )
                .accessibilityIdentifier("accountDeletion.status.completed")
            case .unavailable, .none:
                blockedContent(title: L10n.string("accountDeletion.unavailable.title"))
            }
        }
    }

    private var eligibleContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard(
                systemImage: "checkmark.shield",
                title: L10n.string("accountDeletion.eligible.title"),
                detail: L10n.string("accountDeletion.eligible.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.eligible")

            warningList

            Text(L10n.string("accountDeletion.confirm.instructions"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            TextField("DELETE", text: $viewModel.confirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(14)
                .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                }
                .accessibilityIdentifier("accountDeletion.confirmation")

            AVSettingsButton(
                title: viewModel.isSubmitting
                    ? L10n.string("accountDeletion.deleting")
                    : L10n.string("accountDeletion.deleteButton"),
                style: .destructivePrimary,
                isLoading: viewModel.isSubmitting
            ) {
                Task { await viewModel.requestDeletion() }
            }
            .disabled(!viewModel.canRequestDeletion || viewModel.isSubmitting)
            .opacity(viewModel.canRequestDeletion ? 1 : 0.45)
            .accessibilityIdentifier("accountDeletion.deleteButton")
        }
    }

    private var inProgressContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard(
                systemImage: "clock.badge.exclamationmark",
                title: L10n.string("accountDeletion.inProgress.title"),
                detail: L10n.string("accountDeletion.inProgress.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.inProgress")
            blockerList
            warningList

            if viewModel.canFinalizeDeletion {
                AVSettingsButton(
                    title: viewModel.isSubmitting
                        ? L10n.string("accountDeletion.finalizing")
                        : L10n.string("accountDeletion.finalizeButton"),
                    style: .primary,
                    isLoading: viewModel.isSubmitting
                ) {
                    Task { await viewModel.finalizeDeletion() }
                }
                .disabled(viewModel.isSubmitting)
                .accessibilityIdentifier("accountDeletion.finalizeButton")
            }
        }
    }

    private func blockedContent(title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard(
                systemImage: "lock.shield",
                title: title,
                detail: L10n.string("accountDeletion.blocked.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.blocked")
            blockerList
            warningList

            if viewModel.canUnlinkCurrentApp {
                AVSettingsButton(
                    title: viewModel.isSubmitting
                        ? L10n.string("accountDeletion.unlinking")
                        : L10n.string("accountDeletion.unlinkButton"),
                    style: .secondary,
                    isLoading: viewModel.isSubmitting
                ) {
                    Task { await viewModel.unlinkCurrentApp() }
                }
                .disabled(!viewModel.canUnlinkCurrentApp)
                .accessibilityIdentifier("accountDeletion.unlinkButton")
            }

            if let accountURL = AppConfig.deleteAccountURL {
                AVSettingsLinkButton(
                    title: L10n.string("accountDeletion.accountWebsiteLink"),
                    systemImage: "safari",
                    destination: accountURL
                )
                .accessibilityIdentifier("accountDeletion.accountWebsiteLink")
            }
        }
    }

    private var blockerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.blockers) { blocker in
                AVSettingsDetailCard(
                    title: blocker.label,
                    detail: blocker.detail,
                    linkTitle: blocker.managementUrl == nil ? nil : L10n.string("accountDeletion.manageLink"),
                    linkDestination: blocker.managementUrl
                )
                .accessibilityIdentifier("accountDeletion.blocker.\(blocker.type.rawValue)")
            }
        }
    }

    private var warningList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.warnings) { warning in
                AVSettingsDetailCard(
                    title: warning.label,
                    detail: warning.detail,
                    linkTitle: warning.managementUrl == nil ? nil : L10n.string("accountDeletion.manageLink"),
                    linkDestination: warning.managementUrl
                )
                .accessibilityIdentifier("accountDeletion.warning.\(warning.type.rawValue)")
            }
        }
    }

    private func statusCard(systemImage: String, title: String, detail: String) -> some View {
        AVSettingsStatusCard(systemImage: systemImage, title: title, detail: detail)
    }
}
