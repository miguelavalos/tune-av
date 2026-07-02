import AVAviFoundation
import AVPaywallFoundation
import SwiftUI

struct TuneAVProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var accessController: AccessController

    let startSignInFlow: () -> Void

    @State private var isShowingRedeemCodeSheet = false
    @State private var redeemCode = ""
    @State private var redeemStatusMessage: String?
    @State private var isRedeemingCode = false

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

            AVPaywallFooterActions(actions: footerActionItems)
        }
        .task {
            await accessController.syncFromAccountProvider()
            await accessController.loadMonthlySubscriptionOffer()
        }
        .sheet(isPresented: $isShowingRedeemCodeSheet) {
            redeemCodeSheet
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

    private var redeemCodeSheet: some View {
        NavigationStack {
            ScrollView {
                redeemCodeContent
                    .padding(20)
            }
            .background(TuneAVTheme.shellBackground.ignoresSafeArea())
            .navigationTitle(L10n.string("paywall.promo.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.done")) {
                        isShowingRedeemCodeSheet = false
                    }
                    .accessibilityIdentifier("paywall.redeemCode.done")
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("paywall.redeemCode.sheet")
    }

    private var redeemCodeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("paywall.promo.title"))
                    .font(.headline)
                    .foregroundStyle(TuneAVTheme.textPrimary)
                Text(L10n.string("paywall.promo.detail"))
                    .font(.subheadline)
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)

                TextField(L10n.string("paywall.promo.placeholder"), text: $redeemCode)
                    .keyboardType(.asciiCapable)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: redeemCode) { _, newValue in
                        let sanitized = sanitizedRedeemCodeInput(newValue)
                        if sanitized != newValue {
                            redeemCode = sanitized
                        }
                    }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("paywall.redeemCode.field")

                Button(action: claimRedeemCode) {
                    ZStack {
                        if isRedeemingCode {
                            ProgressView()
                                .tint(TuneAVTheme.textInverse)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(TuneAVTheme.textInverse)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .background(
                        redeemButtonIsDisabled ? TuneAVTheme.neutral300 : TuneAVTheme.highlight,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .disabled(redeemButtonIsDisabled)
                .accessibilityLabel(L10n.string("paywall.promo.claim"))
                .accessibilityIdentifier("paywall.redeemCode.claim")
            }

            Text(L10n.string("paywall.promo.optional"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let redeemStatusMessage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)

                    Text(redeemStatusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("paywall.redeemCode.status")
            }
        }
        .padding(16)
        .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var normalizedRedeemCode: String {
        redeemCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedRedeemCodeInput(_ code: String) -> String {
        var sanitized = ""
        for character in code {
            switch character {
            case " ", "\n", "\t":
                continue
            case "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}", "\u{2018}", "\u{2019}":
                sanitized.append("-")
            case _ where isASCIIAlphanumeric(character) || character == "-" || character == "_":
                sanitized.append(character)
            default:
                continue
            }
        }
        return sanitized.uppercased()
    }

    private func isASCIIAlphanumeric(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value else {
            return false
        }
        return (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }

    private var redeemButtonIsDisabled: Bool {
        normalizedRedeemCode.isEmpty ||
            isRedeemingCode ||
            accessController.isSubscriptionOperationInProgress
    }

    private func showRedeemCodeSheet() {
        guard !accessController.isSubscriptionOperationInProgress else { return }
        if accessController.isSignedIn {
            redeemStatusMessage = nil
            isShowingRedeemCodeSheet = true
        } else {
            dismiss()
            startSignInFlow()
        }
    }

    private func claimRedeemCode() {
        let code = normalizedRedeemCode
        guard !code.isEmpty, !isRedeemingCode else { return }
        isRedeemingCode = true
        redeemStatusMessage = nil

        Task {
            do {
                try await accessController.claimPromotionCode(code)
                redeemStatusMessage = L10n.string("paywall.promo.claimed")
                redeemCode = ""
                isShowingRedeemCodeSheet = false
            } catch {
                redeemStatusMessage = error.localizedDescription
            }
            isRedeemingCode = false
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
        case .redeemCode:
            return L10n.string("paywall.status.redeemingCode")
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

    private var footerActionItems: [AVPaywallFooterAction] {
        var actions = [
            AVPaywallFooterAction(
                title: L10n.string("paywall.redeemCode"),
                accessibilityIdentifier: "paywall.redeemCode",
                action: showRedeemCodeSheet
            )
        ]

        for link in legalLinkItems {
            actions.append(
                AVPaywallFooterAction(
                    title: link.title,
                    accessibilityIdentifier: link.accessibilityIdentifier,
                    action: link.action
                )
            )
        }

        return actions
    }
}
