import Foundation
import OSLog

#if canImport(RevenueCat)
import RevenueCat
#endif

struct TuneAVSubscriptionOffer: Equatable {
    let identifier: String
    let productIdentifier: String
    let localizedTitle: String
    let localizedPrice: String
}

struct TuneAVPurchaseOutcome: Equatable {
    let shouldRefreshAccess: Bool
    let customerUserID: String
}

enum TuneAVSubscriptionPurchaseError: LocalizedError, Equatable {
    case missingAccountUser
    case missingConfiguration
    case offeringUnavailable
    case monthlyPackageUnavailable
    case purchaseCancelled
    case sdkUnavailable
    case underlying(String)

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
        case .sdkUnavailable:
            L10n.string("subscription.error.sdkUnavailable")
        case .underlying(let message):
            message
        }
    }
}

@MainActor
protocol TuneAVSubscriptionPurchasing {
    func prepare(for user: AccountUser?) async throws
    func loadMonthlyOffer(for user: AccountUser?) async throws -> TuneAVSubscriptionOffer
    func purchaseMonthlyPro(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome
    func restorePurchases(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome
}

@MainActor
final class NoopTuneAVSubscriptionPurchasing: TuneAVSubscriptionPurchasing {
    func prepare(for user: AccountUser?) async throws {
        guard user != nil else {
            throw TuneAVSubscriptionPurchaseError.missingAccountUser
        }
        throw TuneAVSubscriptionPurchaseError.missingConfiguration
    }

    func loadMonthlyOffer(for user: AccountUser?) async throws -> TuneAVSubscriptionOffer {
        try await prepare(for: user)
        throw TuneAVSubscriptionPurchaseError.missingConfiguration
    }

    func purchaseMonthlyPro(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        try await prepare(for: user)
        throw TuneAVSubscriptionPurchaseError.missingConfiguration
    }

    func restorePurchases(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        try await prepare(for: user)
        throw TuneAVSubscriptionPurchaseError.missingConfiguration
    }
}

@MainActor
final class UITestTuneAVSubscriptionPurchasing: TuneAVSubscriptionPurchasing {
    func prepare(for user: AccountUser?) async throws {
        guard user != nil else {
            throw TuneAVSubscriptionPurchaseError.missingAccountUser
        }
    }

    func loadMonthlyOffer(for user: AccountUser?) async throws -> TuneAVSubscriptionOffer {
        try await prepare(for: user)
        return TuneAVSubscriptionOffer(
            identifier: "$rc_monthly",
            productIdentifier: "tuneav_pro_monthly",
            localizedTitle: "Tune AV Pro",
            localizedPrice: "$4.99"
        )
    }

    func purchaseMonthlyPro(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        try await prepare(for: user)
        return TuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: user?.id ?? "")
    }

    func restorePurchases(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        try await prepare(for: user)
        return TuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: user?.id ?? "")
    }
}

#if canImport(RevenueCat)
@MainActor
final class RevenueCatTuneAVSubscriptionPurchasing: TuneAVSubscriptionPurchasing {
    private let apiKeyProvider: () -> String?
    private let offeringIDProvider: () -> String?
    private let monthlyPackageIDProvider: () -> String?
    private var configuredUserID: String?
    private let purchaseLogger = Logger(subsystem: "com.avalsys.tuneav", category: "subscription")

    init(
        apiKeyProvider: @escaping () -> String? = { AppConfig.revenueCatPublicAPIKey },
        offeringIDProvider: @escaping () -> String? = { AppConfig.revenueCatOfferingID },
        monthlyPackageIDProvider: @escaping () -> String? = { AppConfig.revenueCatMonthlyPackageID }
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.offeringIDProvider = offeringIDProvider
        self.monthlyPackageIDProvider = monthlyPackageIDProvider
    }

    func prepare(for user: AccountUser?) async throws {
        let userID = try requireUserID(user)
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw TuneAVSubscriptionPurchaseError.missingConfiguration
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

    func loadMonthlyOffer(for user: AccountUser?) async throws -> TuneAVSubscriptionOffer {
        TuneAVDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "load_offer")
        do {
            try await prepare(for: user)
            let package = try await loadMonthlyPackage()
            let productIdentifier = package.storeProduct.productIdentifier
            let localizedPrice = package.storeProduct.localizedPriceString
            purchaseLogger.info(
                "Loaded monthly offer product=\(productIdentifier, privacy: .public) displayPrice=\(localizedPrice, privacy: .public) priceSource=revenuecat revenueCatCurrency=\(package.storeProduct.currencyCode ?? "unknown", privacy: .public)"
            )
            return TuneAVSubscriptionOffer(
                identifier: package.identifier,
                productIdentifier: productIdentifier,
                localizedTitle: package.storeProduct.localizedTitle,
                localizedPrice: localizedPrice
            )
        } catch {
            TuneAVDiagnostics.capture(error, feature: "tune.subscription", operation: "load_offer", step: "revenuecat")
            throw error
        }
    }

    func purchaseMonthlyPro(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        let userID = try requireUserID(user)
        do {
            try await prepare(for: user)
            let package = try await loadMonthlyPackage()
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "purchase", data: ["product_key": "pro_monthly"])
            purchaseLogger.info(
                "Starting RevenueCat purchase userID=\(userID, privacy: .private) product=\(package.storeProduct.productIdentifier, privacy: .public) price=\(package.storeProduct.localizedPriceString, privacy: .public)"
            )
            let result = try await purchase(package)
            guard !result.userCancelled else {
                TuneAVDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "purchase_cancelled", data: ["product_key": "pro_monthly"])
                throw TuneAVSubscriptionPurchaseError.purchaseCancelled
            }
            purchaseLogger.info(
                "Finished RevenueCat purchase userID=\(userID, privacy: .private) product=\(package.storeProduct.productIdentifier, privacy: .public)"
            )
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "purchase_completed", data: ["product_key": "pro_monthly"])
            return TuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: userID)
        } catch {
            if let purchaseError = error as? TuneAVSubscriptionPurchaseError, purchaseError == .purchaseCancelled {
                throw error
            }
            TuneAVDiagnostics.capture(error, feature: "tune.subscription", operation: "purchase", step: "revenuecat", data: ["product_key": "pro_monthly"])
            throw error
        }
    }

    func restorePurchases(for user: AccountUser?) async throws -> TuneAVPurchaseOutcome {
        let userID = try requireUserID(user)
        do {
            try await prepare(for: user)
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "restore")
            purchaseLogger.info("Starting RevenueCat restore userID=\(userID, privacy: .private)")
            _ = try await restorePurchases()
            purchaseLogger.info("Finished RevenueCat restore userID=\(userID, privacy: .private)")
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: "restore_completed")
            return TuneAVPurchaseOutcome(shouldRefreshAccess: true, customerUserID: userID)
        } catch {
            TuneAVDiagnostics.capture(error, feature: "tune.subscription", operation: "restore", step: "revenuecat")
            throw error
        }
    }

    private func requireUserID(_ user: AccountUser?) throws -> String {
        guard let userID = user?.id, !userID.isEmpty else {
            throw TuneAVSubscriptionPurchaseError.missingAccountUser
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
            throw TuneAVSubscriptionPurchaseError.offeringUnavailable
        }

        if let packageID = monthlyPackageIDProvider(), !packageID.isEmpty,
           let package = offering.package(identifier: packageID) {
            return package
        }

        guard let package = offering.monthly else {
            throw TuneAVSubscriptionPurchaseError.monthlyPackageUnavailable
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

    private static func purchaseError(from error: Error?) -> TuneAVSubscriptionPurchaseError {
        guard let error else {
            return .underlying(L10n.string("subscription.error.unknown"))
        }
        return .underlying(error.localizedDescription)
    }
}
#else
typealias RevenueCatTuneAVSubscriptionPurchasing = NoopTuneAVSubscriptionPurchasing
#endif
