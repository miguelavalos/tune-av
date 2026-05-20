import SwiftUI

struct AviPlanComparisonSheet: View {
    let accessMode: AccessMode
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("shell.avi.plans.eyebrow"))
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)

                        Text(L10n.string("shell.avi.plans.title"))
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(TuneAVTheme.textPrimary)

                        Text(L10n.string("shell.avi.plans.subtitle"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    planSummaryStrip

                    VStack(spacing: 12) {
                        planCard(
                            title: L10n.string("shell.avi.plans.guest"),
                            subtitle: L10n.string("shell.avi.plans.guest.subtitle"),
                            isCurrent: accessMode == .guest,
                            rows: [
                                L10n.string("shell.avi.plans.guest.radios"),
                                L10n.string("shell.avi.plans.guest.songs"),
                                L10n.string("shell.avi.plans.guest.discoveries"),
                                L10n.string("shell.avi.plans.guest.avi"),
                                L10n.string("shell.avi.plans.localOnly")
                            ]
                        )

                        planCard(
                            title: L10n.string("shell.avi.plans.free"),
                            subtitle: L10n.string("shell.avi.plans.free.subtitle"),
                            isCurrent: accessMode == .signedInFree,
                            rows: [
                                L10n.string("shell.avi.plans.free.radios"),
                                L10n.string("shell.avi.plans.free.songs"),
                                L10n.string("shell.avi.plans.free.discoveries"),
                                L10n.string("shell.avi.plans.free.avi"),
                                L10n.string("shell.avi.plans.localOnly")
                            ]
                        )

                        planCard(
                            title: L10n.string("shell.avi.plans.pro"),
                            subtitle: L10n.string("shell.avi.plans.pro.subtitle"),
                            isCurrent: accessMode == .signedInPro,
                            isHighlighted: true,
                            rows: [
                                L10n.string("shell.avi.plans.pro.avi"),
                                L10n.string("shell.avi.plans.pro.radios"),
                                L10n.string("shell.avi.plans.pro.songs"),
                                L10n.string("shell.avi.plans.pro.discoveries"),
                                L10n.string("shell.avi.plans.pro.requests"),
                                L10n.string("shell.avi.plans.pro.sync")
                            ]
                        )
                    }

                    Button {
                        onDismiss()
                        onPrimaryAction()
                    } label: {
                        Text(accessMode == .guest ? L10n.string("shell.avi.preview.primary.search") : L10n.string("shell.avi.preview.primary.pro"))
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(TuneAVTheme.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityIdentifier("avi.planComparison.primary")
                }
                .padding(22)
            }
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .navigationTitle(L10n.string("shell.avi.plans.eyebrow"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("shell.avi.plans.close"), action: onDismiss)
                }
            }
        }
    }

    private var planSummaryStrip: some View {
        HStack(spacing: 10) {
            PlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.start"),
                detail: L10n.string("shell.avi.plans.summary.start.detail")
            )
            PlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.save"),
                detail: L10n.string("shell.avi.plans.summary.save.detail")
            )
            PlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.pro"),
                detail: L10n.string("shell.avi.plans.summary.pro.detail")
            )
        }
    }

    private func planCard(title: String, subtitle: String, isCurrent: Bool, isHighlighted: Bool = false, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(TuneAVTheme.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isCurrent {
                    Text(L10n.string("shell.avi.plans.current"))
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(TuneAVTheme.textInverse)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(TuneAVTheme.highlight, in: Capsule(style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .frame(width: 18)

                        Text(row)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(isHighlighted ? TuneAVTheme.highlight.opacity(0.08) : TuneAVTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isHighlighted ? TuneAVTheme.highlight.opacity(0.36) : TuneAVTheme.borderSubtle.opacity(0.64), lineWidth: 1)
        }
    }
}

private struct PlanSummaryPill: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(detail)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 66, alignment: .topLeading)
        .padding(10)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.55), lineWidth: 1)
        }
    }
}
