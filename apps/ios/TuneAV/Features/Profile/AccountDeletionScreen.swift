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
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("accountDeletion.title"))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .accessibilityIdentifier("accountDeletion.title")

            Text(L10n.string("accountDeletion.subtitle"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sharedAccountNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("accountDeletion.shared.title"), systemImage: "person.2.badge.gearshape")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TuneAVTheme.textPrimary)

            Text(L10n.string("accountDeletion.shared.detail"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(cardBackground)
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

    private var eligibleContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard(
                systemImage: "checkmark.shield",
                title: L10n.string("accountDeletion.eligible.title"),
                detail: L10n.string("accountDeletion.eligible.detail")
            )
            .accessibilityIdentifier("accountDeletion.status.eligible")

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

            Button {
                Task { await viewModel.requestDeletion() }
            } label: {
                HStack {
                    Text(viewModel.isSubmitting ? L10n.string("accountDeletion.deleting") : L10n.string("accountDeletion.deleteButton"))
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .foregroundStyle(.white)
                .frame(height: 48)
                .padding(.horizontal, 18)
                .background(Color(red: 0.84, green: 0.16, blue: 0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
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

            if viewModel.canFinalizeDeletion {
                Button {
                    Task { await viewModel.finalizeDeletion() }
                } label: {
                    Text(viewModel.isSubmitting ? L10n.string("accountDeletion.finalizing") : L10n.string("accountDeletion.finalizeButton"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TuneAVTheme.brandBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
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
        }
    }

    private var blockerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.blockers) { blocker in
                VStack(alignment: .leading, spacing: 6) {
                    Text(blocker.label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    if let detail = blocker.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let managementUrl = blocker.managementUrl {
                        Link(L10n.string("accountDeletion.manageLink"), destination: managementUrl)
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("accountDeletion.blocker.\(blocker.type.rawValue)")
            }
        }
    }

    private func statusCard(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(TuneAVTheme.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }
}
