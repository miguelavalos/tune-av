import CryptoKit
import Foundation
import StoreKit

enum SubscriptionPurchaseOutcome {
    case purchased
    case pending
    case cancelled
}

enum RestorePurchasesOutcome {
    case restored
    case nothingToRestore
}

enum EntitlementServiceError: LocalizedError {
    case accountRequired
    case subscriptionUnavailable
    case productUnavailable
    case purchaseVerificationFailed

    var errorDescription: String? {
        switch self {
        case .accountRequired:
            L10n.string("subscription.error.accountRequired")
        case .subscriptionUnavailable:
            L10n.string("subscription.error.unavailable")
        case .productUnavailable:
            L10n.string("subscription.error.productUnavailable")
        case .purchaseVerificationFailed:
            L10n.string("subscription.error.verificationFailed")
        }
    }
}

struct SubscriptionProduct: Identifiable, Equatable {
    let id: String
    let displayName: String
    let displayPrice: String
    let billingPeriod: String?
}

@MainActor
protocol EntitlementService {
    var isSubscriptionConfigured: Bool { get }

    func loadSubscriptionProducts() async throws -> [SubscriptionProduct]
    func resolveAccess(for user: AccountUser?) -> ResolvedAccess
    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess
    func purchasePro(for user: AccountUser, productID: String) async throws -> SubscriptionPurchaseOutcome
    func restorePurchases(for user: AccountUser) async throws -> RestorePurchasesOutcome
}

@MainActor
final class StoreKitEntitlementService: EntitlementService {
    private let premiumProductIDs: [String]
    private let userDefaults: UserDefaults
    private let planTierCachePrefix = "tuneav.planTier."

    init(
        premiumProductIDs: [String] = AppConfig.premiumProductIDs,
        userDefaults: UserDefaults = .standard
    ) {
        self.premiumProductIDs = premiumProductIDs
        self.userDefaults = userDefaults
    }

    var isSubscriptionConfigured: Bool {
        !premiumProductIDs.isEmpty
    }

    func loadSubscriptionProducts() async throws -> [SubscriptionProduct] {
        guard isSubscriptionConfigured else { return [] }

        let products = try await Product.products(for: premiumProductIDs)
        let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        return premiumProductIDs.compactMap { productID in
            guard let product = productsByID[productID] else { return nil }

            return SubscriptionProduct(
                id: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                billingPeriod: billingPeriodText(for: product)
            )
        }
    }

    func resolveAccess(for user: AccountUser?) -> ResolvedAccess {
        guard let user else { return .guest }
        if let uiTestAccess = Self.uiTestResolvedAccess() {
            return uiTestAccess
        }
        let cached = userDefaults.string(forKey: cacheKey(for: user.id)) ?? ""
        let planTier = PlanTier(rawValue: cached) ?? .free
        return resolvedAccess(for: user, planTier: planTier)
    }

    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess {
        guard let user else { return .guest }
        if let uiTestAccess = Self.uiTestResolvedAccess() {
            cache(uiTestAccess.planTier, for: user.id)
            return uiTestAccess
        }
        guard isSubscriptionConfigured else {
            cache(.free, for: user.id)
            return resolvedAccess(for: user, planTier: .free)
        }

        let accountToken = Self.appAccountToken(for: user)
        var resolvedTier: PlanTier = .free

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard premiumProductIDs.contains(transaction.productID) else { continue }
            guard transaction.appAccountToken == accountToken else { continue }

            resolvedTier = .pro
            break
        }

        cache(resolvedTier, for: user.id)
        return resolvedAccess(for: user, planTier: resolvedTier)
    }

    func purchasePro(for user: AccountUser, productID: String) async throws -> SubscriptionPurchaseOutcome {
        guard isSubscriptionConfigured else {
            throw EntitlementServiceError.subscriptionUnavailable
        }

        let product = try await loadProduct(id: productID)
        let result = try await product.purchase(options: [.appAccountToken(Self.appAccountToken(for: user))])

        switch result {
        case .success(let verification):
            let transaction = try verifiedTransaction(from: verification)
            await transaction.finish()
            _ = await refreshAccess(for: user)
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restorePurchases(for user: AccountUser) async throws -> RestorePurchasesOutcome {
        guard isSubscriptionConfigured else {
            throw EntitlementServiceError.subscriptionUnavailable
        }

        try await AppStore.sync()
        let refreshedAccess = await refreshAccess(for: user)
        return refreshedAccess.planTier == .pro ? .restored : .nothingToRestore
    }

    private func resolvedAccess(for user: AccountUser, planTier: PlanTier) -> ResolvedAccess {
        let accessMode: AccessMode = planTier == .pro ? .signedInPro : .signedInFree
        return ResolvedAccess(
            planTier: planTier,
            accessMode: accessMode,
            capabilities: AccessCapabilities.forMode(accessMode),
            limits: AccessLimits.forMode(accessMode)
        )
    }

    private static func uiTestResolvedAccess() -> ResolvedAccess? {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["TUNEAV_UI_TESTS"] == "1"
        guard isUITesting, let mode = environment["TUNEAV_UI_TESTS_ACCOUNT_MODE"] else { return nil }

        let accessMode: AccessMode = mode == "pro" ? .signedInPro : .signedInFree
        return ResolvedAccess(
            planTier: accessMode == .signedInPro ? .pro : .free,
            accessMode: accessMode,
            capabilities: .forMode(accessMode),
            limits: .forMode(accessMode)
        )
    }

    private func loadProduct(id: String) async throws -> Product {
        let products = try await Product.products(for: premiumProductIDs)
        guard let product = products.first(where: { $0.id == id }) else {
            throw EntitlementServiceError.productUnavailable
        }

        return product
    }

    private func verifiedTransaction(from verification: VerificationResult<Transaction>) throws -> Transaction {
        switch verification {
        case .verified(let transaction):
            transaction
        case .unverified:
            throw EntitlementServiceError.purchaseVerificationFailed
        }
    }

    private func cache(_ planTier: PlanTier, for userID: String) {
        userDefaults.set(planTier.rawValue, forKey: cacheKey(for: userID))
    }

    private func cacheKey(for userID: String) -> String {
        planTierCachePrefix + userID
    }

    static func appAccountToken(for user: AccountUser) -> UUID {
        let digest = SHA256.hash(data: Data(user.id.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func billingPeriodText(for product: Product) -> String? {
        guard let subscription = product.subscription else { return nil }
        let period = subscription.subscriptionPeriod
        return L10n.string("subscription.period.format", period.value, period.unit.localizedLabel)
    }
}

@MainActor
final class PlatformBackedEntitlementService: EntitlementService {
    private let fallback: StoreKitEntitlementService
    private let apiClient: AVAccountAPIClient

    init(
        fallback: StoreKitEntitlementService = StoreKitEntitlementService(),
        apiClient: AVAccountAPIClient
    ) {
        self.fallback = fallback
        self.apiClient = apiClient
    }

    var isSubscriptionConfigured: Bool {
        fallback.isSubscriptionConfigured
    }

    func loadSubscriptionProducts() async throws -> [SubscriptionProduct] {
        try await fallback.loadSubscriptionProducts()
    }

    func resolveAccess(for user: AccountUser?) -> ResolvedAccess {
        fallback.resolveAccess(for: user)
    }

    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess {
        guard let user else { return .guest }

        let fallbackAccess = await fallback.refreshAccess(for: user)
        if Self.shouldUseUITestAccessOverride {
            return fallbackAccess
        }
        guard apiClient.isConfigured() else {
            return fallbackAccess
        }

        do {
            try await apiClient.registerAppleSubscriptionAccountToken(
                StoreKitEntitlementService.appAccountToken(for: user)
            )
            let payload = try await apiClient.fetchMeAccess()
            guard let avTunesysAccess = payload.apps.first(where: { $0.appId == "tuneav" }) else {
                return fallbackAccess
            }

            return mergeBackendAccess(
                ResolvedAccess(
                    planTier: avTunesysAccess.planTier,
                    accessMode: avTunesysAccess.accessMode,
                    capabilities: avTunesysAccess.capabilities,
                    limits: avTunesysAccess.limits
                ),
                fallbackAccess: fallbackAccess
            )
        } catch {
            return fallbackAccess
        }
    }

    func purchasePro(for user: AccountUser, productID: String) async throws -> SubscriptionPurchaseOutcome {
        try await fallback.purchasePro(for: user, productID: productID)
    }

    func restorePurchases(for user: AccountUser) async throws -> RestorePurchasesOutcome {
        try await fallback.restorePurchases(for: user)
    }

    private func mergeBackendAccess(_ backendAccess: ResolvedAccess, fallbackAccess: ResolvedAccess) -> ResolvedAccess {
        // Preserve existing StoreKit-backed Pro during the transition until backend reconciliation is complete.
        if fallbackAccess.planTier == .pro, backendAccess.planTier != .pro {
            return fallbackAccess
        }

        return backendAccess
    }

    private static var shouldUseUITestAccessOverride: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["TUNEAV_UI_TESTS"] == "1" &&
            environment["TUNEAV_UI_TESTS_ACCOUNT_MODE"] != nil
    }
}

private extension Product.SubscriptionPeriod.Unit {
    var localizedLabel: String {
        switch self {
        case .day:
            L10n.string("subscription.period.unit.day")
        case .week:
            L10n.string("subscription.period.unit.week")
        case .month:
            L10n.string("subscription.period.unit.month")
        case .year:
            L10n.string("subscription.period.unit.year")
        @unknown default:
            L10n.string("subscription.period.unit.month")
        }
    }
}
