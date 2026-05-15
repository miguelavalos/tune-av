import SwiftUI

struct TuneAVProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var accessController: AccessController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("paywall.eyebrow"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(TuneAVTheme.highlight)
                            .textCase(.uppercase)

                        Text(L10n.string("paywall.title"))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(TuneAVTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string("paywall.subtitle"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(TuneAVTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        paywallBenefit("heart.text.square", "paywall.benefit.library")
                        paywallBenefit("icloud", "paywall.benefit.sync")
                        paywallBenefit("sparkles", "paywall.benefit.avi")
                        paywallBenefit("radio", "paywall.benefit.discovery")
                    }

                    VStack(spacing: 12) {
                        Button {
                            Task { await accessController.purchaseMonthlyPro() }
                        } label: {
                            Text(primaryButtonTitle)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textInverse)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(accessController.isSubscriptionOperationInProgress || accessController.subscriptionOffer == nil)
                        .accessibilityIdentifier("paywall.purchase")

                        Button {
                            Task { await accessController.restorePurchases() }
                        } label: {
                            Text(restoreTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(TuneAVTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(accessController.isSubscriptionOperationInProgress)
                        .accessibilityIdentifier("paywall.restore")
                    }

                    if accessController.isWaitingForSubscriptionReconciliation {
                        paywallStatus("clock.arrow.circlepath", reconciliationStatus)
                    } else if let error = accessController.subscriptionError?.errorDescription {
                        paywallStatus("exclamationmark.triangle", error)
                    }

                    HStack(spacing: 18) {
                        if let termsURL = AppConfig.termsURL {
                            Button(L10n.string("paywall.terms")) { openURL(termsURL) }
                        }
                        if let privacyURL = AppConfig.privacyURL {
                            Button(L10n.string("paywall.privacy")) { openURL(privacyURL) }
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                }
                .padding(24)
            }
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .navigationTitle(L10n.string("paywall.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("paywall.close")) { dismiss() }
                }
            }
            .task {
                await accessController.loadMonthlySubscriptionOffer()
            }
            .onChange(of: accessController.accessMode) { _, mode in
                if mode == .signedInPro {
                    dismiss()
                }
            }
        }
    }

    private var primaryButtonTitle: String {
        if accessController.isSubscriptionOperationInProgress {
            return L10n.string("paywall.purchase.loading")
        }
        guard let offer = accessController.subscriptionOffer else {
            return L10n.string("paywall.purchase.loadingOffer")
        }
        return L10n.string("paywall.purchase.price", offer.localizedPrice)
    }

    private var restoreTitle: String {
        accessController.isSubscriptionOperationInProgress
            ? L10n.string("paywall.restore.loading")
            : L10n.string("paywall.restore")
    }

    private var reconciliationStatus: String {
        switch accessController.subscriptionReconciliationSource {
        case .restore:
            return L10n.string("paywall.status.restorePending")
        case .purchase, .none:
            return L10n.string("paywall.status.purchasePending")
        }
    }

    private func paywallBenefit(_ systemImage: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 28)

            Text(L10n.string(key))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func paywallStatus(_ systemImage: String, _ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(TuneAVTheme.textSecondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
