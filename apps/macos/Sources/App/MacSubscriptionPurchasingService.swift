import AccountAV
import Foundation
import OSLog

#if canImport(RevenueCat)
import RevenueCat
#endif

struct MacTuneAVSubscriptionOffer: Equatable {
    let identifier: String
    let productIdentifier: String
    let localizedTitle: String
    let localizedPrice: String
}

struct MacTuneAVPurchaseOutcome: Equatable {
    let shouldRefreshAccess: Bool
    let customerUserID: String
}

enum MacTuneAVSubscriptionPurchaseError: LocalizedError, Equatable {
    case missingAccountUser
    case missingConfiguration
    case offeringUnavailable
    case monthlyPackageUnavailable
    case purchaseCancelled
    case purchaseNotEntitled
    case restoreNotEntitled
    case purchaseReconciliationDelayed
    case restoreReconciliationDelayed
    case redemptionReconciliationDelayed
    case sdkUnavailable
    case underlying(String)

    var isExpectedStoreOutcome: Bool {
        switch self {
        case .purchaseCancelled, .purchaseNotEntitled, .restoreNotEntitled:
            true
        default:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAccountUser:
            L10n.string("subscription.error.signInRequired")
        case .missingConfiguration:
            L10n.string("subscription.error.configuration")
        case .offeringUnavailable:
            L10n.string("subscription.error.offerUnavailable")
        case .monthlyPackageUnavailable:
            L10n.string("subscription.error.productUnavailable")
        case .purchaseCancelled:
            L10n.string("subscription.error.cancelled")
        case .purchaseNotEntitled:
            L10n.string("subscription.error.purchaseNotEntitled")
        case .restoreNotEntitled:
            L10n.string("subscription.error.restoreNotEntitled")
        case .purchaseReconciliationDelayed:
            L10n.string("subscription.error.purchaseReconciliationDelayed")
        case .restoreReconciliationDelayed:
            L10n.string("subscription.error.restoreReconciliationDelayed")
        case .redemptionReconciliationDelayed:
            L10n.string("subscription.error.redemptionReconciliationDelayed")
        case .sdkUnavailable:
            L10n.string("subscription.error.sdkUnavailable")
        case .underlying(let message):
            message
        }
    }
}

@MainActor
protocol MacTuneAVSubscriptionPurchasing {
    func prepare(for user: AccountAVUser?) async throws
    func loadMonthlyOffer(for user: AccountAVUser?) async throws -> MacTuneAVSubscriptionOffer
    func purchaseMonthlyPro(for user: AccountAVUser?) async throws -> MacTuneAVPurchaseOutcome
    func restorePurchases(for user: AccountAVUser?) async throws -> MacTuneAVPurchaseOutcome
}

@MainActor
final class MacNoopTuneAVSubscriptionPurchasing: MacTuneAVSubscriptionPurchasing {
    func prepare(for user: AccountAVUser?) async throws {
        guard user != nil else {
            throw MacTuneAVSubscriptionPurchaseError.missingAccountUser
        }
        throw MacTuneAVSubscriptionPurchaseError.missingConfiguration
    }

    func loadMonthlyOffer(for user: AccountAVUser?) async throws -> MacTuneAVSubscriptionOffer {
        try await prepare(for: user)
        throw MacTuneAVSubscriptionPurchaseError.missingConfiguration
    }

    func purchaseMonthlyPro(for user: AccountAVUser?) async throws -> MacTuneAVPurchaseOutcome {
        try await prepare(for: user)
        throw MacTuneAVSubscriptionPurchaseError.missingConfiguration
    }

    func restorePurchases(for user: AccountAVUser?) async throws -> MacTuneAVPurchaseOutcome {
        try await prepare(for: user)
        throw MacTuneAVSubscriptionPurchaseError.missingConfiguration
    }
}

@MainActor
final class MacUITestTuneAVSubscriptionPurchasing: MacTuneAVSubscriptionPurchasing {
    func prepare(for user: AccountAVUser?) async throws {
        guard user != nil else {
            throw MacTuneAVSubscriptionPurchaseError.missingAccountUser
        }
    }

    func loadMonthlyOffer(for user: AccountAVUser?) async throws -> MacTuneAVSubscriptionOffer {
        try await prepare(for: user)
        return MacTuneAVSubscriptionOffer(
            identifier: "$rc_monthly",
            productIdentifier: "tuneav_pro_monthly",
            localizedTitle: "Tune AV Pro",
            localizedPrice: "$4.99"
        )
    }

    func purchaseMonthlyPro(for user: AccountAVUser?) async throws -> MacTuneAVPurchaseOutcome {
        try await prepare(for: user)
        return MacTuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: user?.id ?? "")
    }

    func restorePurchases(for user: AccountAVUser?) async throws -> MacTuneAVPurchaseOutcome {
        try await prepare(for: user)
        return MacTuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: user?.id ?? "")
    }
}

#if canImport(RevenueCat)
@MainActor
final class MacRevenueCatTuneAVSubscriptionPurchasing: MacTuneAVSubscriptionPurchasing {
    private let apiKeyProvider: () -> String?
    private let offeringIDProvider: () -> String?
    private let monthlyPackageIDProvider: () -> String?
    private var configuredUserID: String?
    private let purchaseLogger = Logger(subsystem: "com.avalsys.tuneav", category: "subscription")

    init(
        apiKeyProvider: @escaping () -> String? = { TuneAVMacConfig.revenueCatPublicAPIKey },
        offeringIDProvider: @escaping () -> String? = { TuneAVMacConfig.revenueCatOfferingID },
        monthlyPackageIDProvider: @escaping () -> String? = { TuneAVMacConfig.revenueCatMonthlyPackageID }
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.offeringIDProvider = offeringIDProvider
        self.monthlyPackageIDProvider = monthlyPackageIDProvider
    }

    func prepare(for user: AccountAVUser?) async throws {
        let userID = try requireUserID(user)
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw MacTuneAVSubscriptionPurchaseError.missingConfiguration
        }

        if configuredUserID == userID, Purchases.isConfigured {
            return
        }

        if Purchases.isConfigured {
            _ = try await logInRevenueCat(userID)
        } else {
            Purchases.configure(withAPIKey: apiKey, appUserID: userID)
        }
        configuredUserID = userID
    }

    func loadMonthlyOffer(for user: AccountAVUser?) async throws -> MacTuneAVSubscriptionOffer {
        TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "load_offer")
        do {
            try await prepare(for: user)
            let package = try await loadMonthlyPackage()
            let productIdentifier = package.storeProduct.productIdentifier
            let localizedPrice = package.storeProduct.localizedPriceString
            purchaseLogger.info(
                "Loaded monthly offer product=\(productIdentifier, privacy: .public) displayPrice=\(localizedPrice, privacy: .public) priceSource=revenuecat revenueCatCurrency=\(package.storeProduct.currencyCode ?? "unknown", privacy: .public)"
            )
            return MacTuneAVSubscriptionOffer(
                identifier: package.identifier,
                productIdentifier: productIdentifier,
                localizedTitle: package.storeProduct.localizedTitle,
                localizedPrice: localizedPrice
            )
        } catch {
            TuneAVMacDiagnostics.capture(error, feature: "tune.subscription", operation: "load_offer", step: "revenuecat")
            throw error
        }
    }

    func purchaseMonthlyPro(for user: AccountAVUser?) async throws -> MacTuneAVPurchaseOutcome {
        let userID = try requireUserID(user)
        do {
            try await prepare(for: user)
            let package = try await loadMonthlyPackage()
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "purchase", data: ["product_key": "pro_monthly"])
            purchaseLogger.info(
                "Starting RevenueCat purchase userID=\(userID, privacy: .private) product=\(package.storeProduct.productIdentifier, privacy: .public) price=\(package.storeProduct.localizedPriceString, privacy: .public)"
            )
            let result = try await purchase(package)
            guard !result.userCancelled else {
                TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "purchase_cancelled", data: ["product_key": "pro_monthly"])
                throw MacTuneAVSubscriptionPurchaseError.purchaseCancelled
            }
            guard hasActiveProEntitlement(result.customerInfo) else {
                TuneAVMacDiagnostics.addBreadcrumb(
                    feature: "tune.subscription",
                    operation: "purchase_not_entitled",
                    data: ["product_key": "pro_monthly"]
                )
                throw MacTuneAVSubscriptionPurchaseError.purchaseNotEntitled
            }
            purchaseLogger.info(
                "Finished RevenueCat purchase userID=\(userID, privacy: .private) product=\(package.storeProduct.productIdentifier, privacy: .public)"
            )
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "purchase_completed", data: ["product_key": "pro_monthly"])
            return MacTuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: userID)
        } catch let error as MacTuneAVSubscriptionPurchaseError where error.isExpectedStoreOutcome {
            throw error
        } catch {
            TuneAVMacDiagnostics.capture(error, feature: "tune.subscription", operation: "purchase", step: "revenuecat", data: ["product_key": "pro_monthly"])
            throw error
        }
    }

    func restorePurchases(for user: AccountAVUser?) async throws -> MacTuneAVPurchaseOutcome {
        let userID = try requireUserID(user)
        do {
            try await prepare(for: user)
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "restore")
            purchaseLogger.info("Starting RevenueCat restore userID=\(userID, privacy: .private)")
            let customerInfo = try await restorePurchases()
            guard hasActiveProEntitlement(customerInfo) else {
                TuneAVMacDiagnostics.addBreadcrumb(
                    feature: "tune.subscription",
                    operation: "restore_not_entitled"
                )
                throw MacTuneAVSubscriptionPurchaseError.restoreNotEntitled
            }
            purchaseLogger.info("Finished RevenueCat restore userID=\(userID, privacy: .private)")
            TuneAVMacDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "restore_completed")
            return MacTuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: userID)
        } catch let error as MacTuneAVSubscriptionPurchaseError where error.isExpectedStoreOutcome {
            throw error
        } catch {
            TuneAVMacDiagnostics.capture(error, feature: "tune.subscription", operation: "restore", step: "revenuecat")
            throw error
        }
    }

    private func requireUserID(_ user: AccountAVUser?) throws -> String {
        guard let userID = user?.id, !userID.isEmpty else {
            throw MacTuneAVSubscriptionPurchaseError.missingAccountUser
        }
        return userID
    }

    private func loadMonthlyPackage() async throws -> Package {
        let offerings = try await getOfferings()
        let offering: Offering?
        if let offeringID = offeringIDProvider(), !offeringID.isEmpty {
            offering = offerings.offering(identifier: offeringID)
        } else {
            offering = offerings.current
        }

        guard let offering else {
            throw MacTuneAVSubscriptionPurchaseError.offeringUnavailable
        }

        if let packageID = monthlyPackageIDProvider(), !packageID.isEmpty,
           let package = offering.package(identifier: packageID) {
            return package
        }

        guard let package = offering.monthly else {
            throw MacTuneAVSubscriptionPurchaseError.monthlyPackageUnavailable
        }
        return package
    }

    private func getOfferings() async throws -> Offerings {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getOfferings { offerings, error in
                if let offerings {
                    continuation.resume(returning: offerings)
                } else {
                    continuation.resume(throwing: Self.purchaseError(from: error))
                }
            }
        }
    }

    private func purchase(_ package: Package) async throws -> PurchaseResultData {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.purchase(package: package) { transaction, customerInfo, error, userCancelled in
                if let error {
                    continuation.resume(throwing: Self.purchaseError(from: error))
                } else if let customerInfo {
                    continuation.resume(
                        returning: PurchaseResultData(
                            transaction: transaction,
                            customerInfo: customerInfo,
                            userCancelled: userCancelled
                        )
                    )
                } else {
                    continuation.resume(throwing: Self.purchaseError(from: nil))
                }
            }
        }
    }

    private func restorePurchases() async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.restorePurchases { customerInfo, error in
                if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: Self.purchaseError(from: error))
                }
            }
        }
    }

    private func logInRevenueCat(_ userID: String) async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.logIn(userID) { customerInfo, _, error in
                if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: Self.purchaseError(from: error))
                }
            }
        }
    }

    private func hasActiveProEntitlement(_ customerInfo: CustomerInfo) -> Bool {
        TuneAVSubscriptionEntitlementPolicy.hasActiveProEntitlement(
            Set(customerInfo.entitlements.active.keys)
        )
    }

    private static func purchaseError(from error: Error?) -> MacTuneAVSubscriptionPurchaseError {
        guard let error else {
            return .underlying(L10n.string("subscription.error.unknown"))
        }
        return .underlying(error.localizedDescription)
    }
}
#else
typealias MacRevenueCatTuneAVSubscriptionPurchasing = MacNoopTuneAVSubscriptionPurchasing
#endif
