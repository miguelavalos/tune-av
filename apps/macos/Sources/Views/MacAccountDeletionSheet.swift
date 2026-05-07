import SwiftUI

struct MacAccountDeletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MacAccountDeletionViewModel

    init(viewModel: MacAccountDeletionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if viewModel.isLoading {
                ProgressView(L10n.string("mac.accountDeletion.loading"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 36)
            } else {
                sharedAccountNotice
                stateContent
            }

            HStack {
                Button(L10n.string("profile.alert.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 560)
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.didCompleteDeletion) { _, didComplete in
            guard didComplete else { return }
            dismiss()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("profile.safety.delete.title"))
                .font(.title2.weight(.bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(L10n.string("mac.accountDeletion.headerDetail"))
                .font(.callout)
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sharedAccountNotice: some View {
        StatusPanel(
            systemImage: "person.2.badge.gearshape",
            title: L10n.string("mac.accountDeletion.shared.title"),
            detail: L10n.string("mac.accountDeletion.shared.detail")
        )
    }

    @ViewBuilder
    private var stateContent: some View {
        if let errorMessage = viewModel.errorMessage {
            StatusPanel(systemImage: "exclamationmark.triangle", title: L10n.string("mac.accountDeletion.unable"), detail: errorMessage)
        }

        if viewModel.didUnlinkCurrentApp {
            StatusPanel(
                systemImage: "link.badge.minus",
                title: L10n.string("mac.accountDeletion.unlinked.title"),
                detail: viewModel.unlinkMessage ?? L10n.string("mac.accountDeletion.unlinked.detail")
            )
        } else {
            switch viewModel.resolvedEligibility?.status {
            case .eligible:
                eligibleContent
            case .blocked:
                blockedContent(title: L10n.string("mac.accountDeletion.blocked"))
            case .inProgress:
                inProgressContent
            case .completed:
                StatusPanel(
                    systemImage: "checkmark.circle",
                    title: L10n.string("mac.accountDeletion.completed.title"),
                    detail: L10n.string("mac.accountDeletion.completed.detail")
                )
            case .unavailable, .none:
                blockedContent(title: L10n.string("mac.accountDeletion.unavailable"))
            }
        }
    }

    private var eligibleContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusPanel(
                systemImage: "checkmark.shield",
                title: L10n.string("mac.accountDeletion.eligible.title"),
                detail: L10n.string("mac.accountDeletion.eligible.detail")
            )

            TextField("DELETE", text: $viewModel.confirmationText)
                .textFieldStyle(.roundedBorder)

            Button(viewModel.isSubmitting ? L10n.string("mac.accountDeletion.requesting") : L10n.string("profile.safety.delete.title")) {
                Task { await viewModel.requestDeletion() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!viewModel.canRequestDeletion || viewModel.isSubmitting)
        }
    }

    private var inProgressContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusPanel(
                systemImage: "clock.badge.exclamationmark",
                title: L10n.string("mac.accountDeletion.inProgress.title"),
                detail: L10n.string("mac.accountDeletion.inProgress.detail")
            )
            blockerList

            if viewModel.canFinalizeDeletion {
                Button(viewModel.isSubmitting ? L10n.string("mac.accountDeletion.finalizing") : L10n.string("mac.accountDeletion.finalize")) {
                    Task { await viewModel.finalizeDeletion() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSubmitting)
            }
        }
    }

    private func blockedContent(title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusPanel(
                systemImage: "lock.shield",
                title: title,
                detail: L10n.string("mac.accountDeletion.blockers.detail")
            )
            blockerList

            HStack(spacing: 10) {
                if viewModel.canUnlinkCurrentApp {
                    Button(viewModel.isSubmitting ? L10n.string("mac.accountDeletion.unlinking") : L10n.string("mac.accountDeletion.unlink")) {
                        Task { await viewModel.unlinkCurrentApp() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canUnlinkCurrentApp)
                }

                if let deleteAccountURL = MacAppConfig.deleteAccountURL {
                    Link(destination: deleteAccountURL) {
                        Label(L10n.string("mac.accountDeletion.openManagement"), systemImage: "safari")
                    }
                }
            }
        }
    }

    private var blockerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.blockers) { blocker in
                VStack(alignment: .leading, spacing: 6) {
                    Text(blocker.label)
                        .font(.headline)
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    if let detail = blocker.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let managementUrl = blocker.managementUrl {
                        Link(L10n.string("mac.accountDeletion.manage"), destination: managementUrl)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct StatusPanel: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
    }
}
