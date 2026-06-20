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
        AVPaywallSheetScaffold(
            navigationTitle: L10n.string("paywall.navigationTitle"),
            closeTitle: L10n.string("paywall.close"),
            backgroundStyle: AnyShapeStyle(TuneAVTheme.shellBackground),
            onClose: { dismiss() }
        ) {
            paywallHeader
            paywallOfferCard
            subscriptionTermsRow

            if accessController.isWaitingForSubscriptionReconciliation {
                AVPaywallStatusRow(systemImage: "clock.arrow.circlepath", message: reconciliationStatus)
            } else if accessController.isRefreshingAccountAccess {
                AVPaywallStatusRow(systemImage: "arrow.triangle.2.circlepath", message: L10n.string("paywall.status.refreshingAccess"))
            } else if let error = accessController.subscriptionError?.errorDescription {
                AVPaywallStatusRow(systemImage: "exclamationmark.triangle", message: error)
            }

            AVPaywallBenefitList(items: benefitItems)

            AVPaywallLegalLinks(links: legalLinkItems)
        }
        .task {
            await accessController.syncFromAccountProvider()
            await accessController.loadMonthlySubscriptionOffer()
        }
        .onChange(of: accessController.accessMode) { _, mode in
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

    @ViewBuilder
    private var subscriptionTermsRow: some View {
        if accessController.isSignedIn, let offer = accessController.subscriptionOffer {
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
        if accessController.isRefreshingAccountAccess {
            return L10n.string("paywall.purchase.refreshingAccess")
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
        return accessController.isRefreshingAccountAccess ||
            accessController.isSubscriptionOperationInProgress ||
            accessController.subscriptionOffer == nil
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
