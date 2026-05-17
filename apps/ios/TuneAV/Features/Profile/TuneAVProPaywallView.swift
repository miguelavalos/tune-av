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

                    paywallAviScene

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        paywallBenefit("sparkles", titleKey: "paywall.benefit.avi.title", detailKey: "paywall.benefit.avi")
                        paywallBenefit("heart.text.square", titleKey: "paywall.benefit.library.title", detailKey: "paywall.benefit.library")
                        paywallBenefit("icloud", titleKey: "paywall.benefit.sync.title", detailKey: "paywall.benefit.sync")
                        paywallBenefit("radio", titleKey: "paywall.benefit.discovery.title", detailKey: "paywall.benefit.discovery")
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
                                .accessibilityIdentifier("paywall.terms")
                        }
                        if let privacyURL = AppConfig.privacyURL {
                            Button(L10n.string("paywall.privacy")) { openURL(privacyURL) }
                                .accessibilityIdentifier("paywall.privacy")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.highlight)
                }
                .padding(24)
            }
            .accessibilityIdentifier("paywall.sheet")
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

    private var paywallAviScene: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("AviV2HeadNeutral")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .padding(8)
                .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())
                .overlay {
                    Circle()
                        .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.string("paywall.scene.title"))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(TuneAVTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.string("paywall.scene.detail"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
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

    private func paywallBenefit(_ systemImage: String, titleKey: String, detailKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TuneAVTheme.highlight)
                .frame(width: 34, height: 34)
                .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

            Text(L10n.string(titleKey))
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(L10n.string(detailKey))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(12)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.58), lineWidth: 1)
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
