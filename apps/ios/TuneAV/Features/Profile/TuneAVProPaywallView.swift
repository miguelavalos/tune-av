import AVAviFoundation
import AVPaywallFoundation
import SwiftUI

struct TuneAVProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var accessController: AccessController

    let startSignInFlow: () -> Void

    init(startSignInFlow: @escaping () -> Void = {}) {
        self.startSignInFlow = startSignInFlow
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    paywallHeader
                    paywallOfferCard

                    if accessController.isWaitingForSubscriptionReconciliation {
                        paywallStatus("clock.arrow.circlepath", reconciliationStatus)
                    } else if let error = accessController.subscriptionError?.errorDescription {
                        paywallStatus("exclamationmark.triangle", error)
                    }

                    VStack(spacing: 8) {
                        paywallBenefit("sparkles", titleKey: "paywall.benefit.avi.title", detailKey: "paywall.benefit.avi")
                        paywallBenefit("heart.text.square", titleKey: "paywall.benefit.library.title", detailKey: "paywall.benefit.library")
                        paywallBenefit("icloud", titleKey: "paywall.benefit.sync.title", detailKey: "paywall.benefit.sync")
                        paywallBenefit("radio", titleKey: "paywall.benefit.discovery.title", detailKey: "paywall.benefit.discovery")
                    }

                    legalLinks
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
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

    private var paywallHeader: some View {
        AVPaywallHeader(
            eyebrow: L10n.string("paywall.eyebrow"),
            title: L10n.string("paywall.title"),
            subtitle: L10n.string("paywall.subtitle")
        )
    }

    private var paywallOfferCard: some View {
        AVPaywallOfferCard(
            title: L10n.string("paywall.scene.title"),
            detail: L10n.string("paywall.scene.detail"),
            primaryButtonTitle: primaryButtonTitle,
            primaryButtonIsDisabled: primaryButtonIsDisabled,
            primaryAction: primaryAction
        ) {
            paywallAviAvatar
        } restoreButton: {
            if accessController.isSignedIn {
                AVPaywallRestoreButton(
                    title: restoreTitle,
                    isDisabled: accessController.isSubscriptionOperationInProgress
                ) {
                    Task { await accessController.restorePurchases() }
                }
            } else {
                EmptyView()
            }
        }
    }

    private var paywallAviAvatar: some View {
        AVAviAvatarBadge(
            imageSize: 54,
            badgeSize: 68,
            padding: 7,
            backgroundStyle: .accentSoft,
            strokeStyle: .accentSoft
        ) {
            Image("AviV2HeadNeutral")
                .resizable()
                .scaledToFit()
        }
    }

    private func primaryAction() {
        if accessController.isSignedIn {
            Task { await accessController.purchaseMonthlyPro() }
        } else {
            dismiss()
            startSignInFlow()
        }
    }

    private var primaryButtonTitle: String {
        guard accessController.isSignedIn else {
            return L10n.string("profile.pro.signIn")
        }
        if accessController.isSubscriptionOperationInProgress {
            return L10n.string("paywall.purchase.loading")
        }
        guard let offer = accessController.subscriptionOffer else {
            return L10n.string("paywall.purchase.loadingOffer")
        }
        return L10n.string("paywall.purchase.price", offer.localizedPrice)
    }

    private var primaryButtonIsDisabled: Bool {
        if !accessController.isSignedIn {
            return !accessController.accountIsAvailable
        }
        return accessController.isSubscriptionOperationInProgress || accessController.subscriptionOffer == nil
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
        AVPaywallBenefitRow(
            systemImage: systemImage,
            title: L10n.string(titleKey),
            detail: L10n.string(detailKey)
        )
    }

    private func paywallStatus(_ systemImage: String, _ message: String) -> some View {
        AVPaywallStatusRow(systemImage: systemImage, message: message)
    }

    private var legalLinks: some View {
        AVPaywallLegalLinks(links: legalLinkItems)
    }

    private var legalLinkItems: [AVPaywallLegalLink] {
        var links: [AVPaywallLegalLink] = []
        if let termsURL = AppConfig.termsURL {
            links.append(
                AVPaywallLegalLink(title: L10n.string("paywall.terms"), accessibilityIdentifier: "paywall.terms") {
                    openURL(termsURL)
                }
            )
        }
        if let privacyURL = AppConfig.privacyURL {
            links.append(
                AVPaywallLegalLink(title: L10n.string("paywall.privacy"), accessibilityIdentifier: "paywall.privacy") {
                    openURL(privacyURL)
                }
            )
        }
        return links
    }
}
