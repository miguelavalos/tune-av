import AVPaywallFoundation
import SwiftUI

struct AviPlanComparisonSheet: View {
    let accessMode: AccessMode
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AVPaywallHeader(
                        eyebrow: L10n.string("shell.avi.plans.eyebrow"),
                        title: L10n.string("shell.avi.plans.title"),
                        subtitle: L10n.string("shell.avi.plans.subtitle"),
                        titleFontSize: 28,
                        subtitleFontSize: 14
                    )

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

                    AVPaywallPrimaryButton(
                        title: accessMode == .guest ? L10n.string("shell.avi.preview.primary.search") : L10n.string("shell.avi.preview.primary.pro"),
                        accessibilityIdentifier: "avi.planComparison.primary"
                    ) {
                        onDismiss()
                        onPrimaryAction()
                    }
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
            AVPlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.start"),
                detail: L10n.string("shell.avi.plans.summary.start.detail")
            )
            AVPlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.save"),
                detail: L10n.string("shell.avi.plans.summary.save.detail")
            )
            AVPlanSummaryPill(
                title: L10n.string("shell.avi.plans.summary.pro"),
                detail: L10n.string("shell.avi.plans.summary.pro.detail")
            )
        }
    }

    private func planCard(title: String, subtitle: String, isCurrent: Bool, isHighlighted: Bool = false, rows: [String]) -> some View {
        AVPlanComparisonCard(
            title: title,
            subtitle: subtitle,
            rows: rows,
            currentLabel: isCurrent ? L10n.string("shell.avi.plans.current") : nil,
            isHighlighted: isHighlighted
        )
    }
}
