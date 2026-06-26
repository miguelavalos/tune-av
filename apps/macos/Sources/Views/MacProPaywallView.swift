import AVAviFoundation
import AVPaywallFoundation
import SwiftUI

struct MacProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var model: TuneAVMacModel

    let startSignInFlow: () -> Void

    init(startSignInFlow: @escaping () -> Void = {}) {
        self.startSignInFlow = startSignInFlow
    }

    var body: some View {
        AVPaywallSheetScaffold(
            navigationTitle: L10n.string("paywall.navigationTitle"),
            closeTitle: L10n.string("paywall.close"),
            backgroundStyle: AnyShapeStyle(TuneAVTheme.shellBackground),
            onClose: { dismiss() }
        ) {
            paywallHeader
            paywallOfferCard
            subscriptionTermsRow

            if model.isWaitingForSubscriptionReconciliation {
                AVPaywallStatusRow(systemImage: "clock.arrow.circlepath", message: reconciliationStatus)
            } else if let error = model.subscriptionError?.errorDescription {
                AVPaywallStatusRow(systemImage: "exclamationmark.triangle", message: error)
            }

            AVPaywallBenefitList(items: benefitItems)
            AVPaywallLegalLinks(links: legalLinkItems)
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 620)
        .task {
            await model.loadMonthlySubscriptionOffer()
        }
        .onChange(of: model.accessMode) { _, mode in
            if mode == .signedInPro {
                dismiss()
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
            primaryAccessibilityIdentifier: "paywall.purchase",
            primaryAction: primaryAction
        ) {
            paywallAviAvatar
        } restoreButton: {
            if model.accountUser != nil {
                AVPaywallRestoreButton(
                    title: restoreTitle,
                    isDisabled: model.isSubscriptionOperationInProgress
                ) {
                    Task { await model.restorePurchases() }
                }
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var subscriptionTermsRow: some View {
        if model.accountUser != nil, let offer = model.subscriptionOffer {
            AVPaywallStatusRow(
                systemImage: "calendar.badge.clock",
                message: L10n.string("paywall.subscriptionTerms", offer.localizedPrice)
            )
            .accessibilityIdentifier("paywall.subscriptionTerms")
        }
    }

    private var paywallAviAvatar: some View {
        AVAviAssetAvatarBadge(
            assetName: "AviV2HeadNeutral",
            imageSize: 54,
            badgeSize: 68,
            padding: 7,
            backgroundStyle: .accentSoft,
            strokeStyle: .accentSoft
        )
    }

    private func primaryAction() {
        if model.accountUser != nil {
            Task { await model.purchaseMonthlyPro() }
        } else {
            dismiss()
            startSignInFlow()
        }
    }

    private var primaryButtonTitle: String {
        guard model.accountUser != nil else {
            return L10n.string("profile.pro.signIn")
        }
        if model.isSubscriptionOperationInProgress {
            return L10n.string("paywall.purchase.loading")
        }
        guard let offer = model.subscriptionOffer else {
            return L10n.string("paywall.purchase.loadingOffer")
        }
        return L10n.string("paywall.purchase.price", offer.localizedPrice)
    }

    private var primaryButtonIsDisabled: Bool {
        if model.accountUser == nil {
            return false
        }
        return model.isSubscriptionOperationInProgress || model.subscriptionOffer == nil
    }

    private var restoreTitle: String {
        model.isSubscriptionOperationInProgress
            ? L10n.string("paywall.restore.loading")
            : L10n.string("paywall.restore")
    }

    private var reconciliationStatus: String {
        switch model.subscriptionReconciliationSource {
        case .restore:
            return L10n.string("paywall.status.restorePending")
        case .purchase, .none:
            return L10n.string("paywall.status.purchasePending")
        }
    }

    private var benefitItems: [AVPaywallBenefitItem] {
        [
            AVPaywallBenefitItem(
                id: "avi",
                systemImage: "sparkles",
                title: L10n.string("paywall.benefit.avi.title"),
                detail: L10n.string("paywall.benefit.avi")
            ),
            AVPaywallBenefitItem(
                id: "library",
                systemImage: "heart.text.square",
                title: L10n.string("paywall.benefit.library.title"),
                detail: L10n.string("paywall.benefit.library")
            ),
            AVPaywallBenefitItem(
                id: "sync",
                systemImage: "icloud",
                title: L10n.string("paywall.benefit.sync.title"),
                detail: L10n.string("paywall.benefit.sync")
            ),
            AVPaywallBenefitItem(
                id: "discovery",
                systemImage: "radio",
                title: L10n.string("paywall.benefit.discovery.title"),
                detail: L10n.string("paywall.benefit.discovery")
            )
        ]
    }

    private var legalLinkItems: [AVPaywallLegalLink] {
        [
            AVPaywallLegalLink(title: L10n.string("paywall.terms"), accessibilityIdentifier: "paywall.terms") {
                openURL(termsURL)
            },
            AVPaywallLegalLink(title: L10n.string("paywall.privacy"), accessibilityIdentifier: "paywall.privacy") {
                openURL(privacyURL)
            }
        ]
    }

    private var privacyURL: URL {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_PRIVACY_URL", requireSupportedAVAccountBaseURL: true)
            ?? URL(string: "https://tune-av.avalsys.com/privacy")!
    }

    private var termsURL: URL {
        TuneAVBundleConfig.urlValue(for: "TUNEAV_TERMS_URL", requireSupportedAVAccountBaseURL: true)
            ?? URL(string: "https://tune-av.avalsys.com/terms")!
    }
}
