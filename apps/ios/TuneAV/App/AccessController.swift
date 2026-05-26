import Foundation
import OSLog

@MainActor
final class AccessController: ObservableObject {
    enum SubscriptionReconciliationSource: Equatable {
        case purchase
        case restore
    }

    @Published private(set) var accessMode: AccessMode
    @Published private(set) var planTier: PlanTier
    @Published private(set) var capabilities: AccessCapabilities
    @Published private(set) var accountUser: AccountUser?
    @Published private(set) var accountSession: AccountSession?
    @Published private(set) var limits: AccessLimits
    @Published private(set) var subscriptionOffer: TuneAVSubscriptionOffer?
    @Published private(set) var subscriptionError: TuneAVSubscriptionPurchaseError?
    @Published private(set) var isSubscriptionOperationInProgress: Bool
    @Published private(set) var isWaitingForSubscriptionReconciliation: Bool
    @Published private(set) var subscriptionReconciliationSource: SubscriptionReconciliationSource?
    @Published var upgradePrompt: UpgradePrompt?

    let accountService: AVAccountService

    private let entitlementService: EntitlementService
    private let subscriptionPurchasing: TuneAVSubscriptionPurchasing
    private let userDefaults: UserDefaults
    private let guestOnboardingPolicy: GuestOnboardingPolicy
    private let now: () -> Date
    private let dailyUsageLimiter: TuneAVDailyUsageLimiter
    private let authLogger = Logger(subsystem: "com.avalsys.tuneav", category: "auth")
    private let guestOnboardingLastPromptAtKey = "tuneav.guestOnboarding.lastPromptAt"
    private var accessRefreshGeneration = 0

    init(
        accountService: AVAccountService = DefaultAVAccountService(),
        entitlementService: EntitlementService? = nil,
        subscriptionPurchasing: TuneAVSubscriptionPurchasing = RevenueCatTuneAVSubscriptionPurchasing(),
        userDefaults: UserDefaults = .standard,
        guestOnboardingPolicy: GuestOnboardingPolicy = GuestOnboardingPolicy(),
        now: @escaping () -> Date = Date.init
    ) {
        let currentUser = accountService.currentUser

        self.accountService = accountService
        self.entitlementService = entitlementService
            ?? PlatformBackedEntitlementService(
                fallback: LocalEntitlementService(),
                apiClient: AVAccountAPIClient(getToken: { try await accountService.getToken() })
            )
        self.subscriptionPurchasing = subscriptionPurchasing
        self.userDefaults = userDefaults
        self.guestOnboardingPolicy = guestOnboardingPolicy
        self.now = now
        self.dailyUsageLimiter = TuneAVDailyUsageLimiter(
            defaults: userDefaults,
            keyStyle: .dayBucket(prefix: "tuneav.featureUsage."),
            limitedFeatures: LimitedFeature.dailyUsageLimitedFeatures,
            now: now
        )
        self.accountUser = currentUser
        self.planTier = .free
        self.capabilities = AccessCapabilities.forMode(.guest)
        self.accountSession = nil
        self.limits = AccessLimits.forMode(.guest)
        self.subscriptionOffer = nil
        self.subscriptionError = nil
        self.isSubscriptionOperationInProgress = false
        self.isWaitingForSubscriptionReconciliation = false
        self.subscriptionReconciliationSource = nil
        self.upgradePrompt = nil
        self.accessMode = .guest
        resolveAccessState()
    }

    var isSignedIn: Bool {
        accountUser != nil
    }

    var isLocalOnly: Bool {
        capabilities.isLocalOnly
    }

    var accountIsAvailable: Bool {
        accountService.isAvailable
    }

    var shouldAutoShowGuestOnboarding: Bool {
        guard accessMode == .guest else { return false }
        return guestOnboardingPolicy.shouldShowAutomatically(
            lastPromptAt: userDefaults.object(forKey: guestOnboardingLastPromptAtKey) as? Date,
            now: now()
        )
    }

    func syncFromAccountProvider() async {
        accessRefreshGeneration += 1
        let generation = accessRefreshGeneration
        accountUser = accountService.currentUser
        if accountUser == nil {
            do {
                _ = try await accountService.getToken()
                guard generation == accessRefreshGeneration else { return }
                accountUser = accountService.currentUser
            } catch {
                guard generation == accessRefreshGeneration else { return }
                authLogger.debug("No active Account AV session during access refresh error=\(Self.safeErrorCode(error), privacy: .public)")
            }
        }
        if accountUser != nil {
            do {
                guard let token = try await accountService.getToken(), !token.isEmpty else {
                    guard generation == accessRefreshGeneration else { return }
                    await clearUnavailableAccountSession(reason: "missing_token")
                    return
                }
            } catch {
                guard generation == accessRefreshGeneration else { return }
                authLogger.error("Account AV session is unavailable during access refresh error=\(Self.safeErrorCode(error), privacy: .public)")
                await clearUnavailableAccountSession(reason: "token_error")
                return
            }
        }
        resolveAccessState()
        let userForRefresh = accountUser
        let refreshedAccess = await entitlementService.refreshAccess(for: accountUser)
        guard generation == accessRefreshGeneration, accountUser == userForRefresh else { return }
        applyResolvedAccess(refreshedAccess)
    }

    func loadMonthlySubscriptionOffer() async {
        guard accountUser != nil else {
            subscriptionError = .missingAccountUser
            return
        }

        do {
            subscriptionOffer = try await subscriptionPurchasing.loadMonthlyOffer(for: accountUser)
            subscriptionError = nil
        } catch let error as TuneAVSubscriptionPurchaseError {
            subscriptionError = error
        } catch {
            subscriptionError = .underlying(error.localizedDescription)
        }
    }

    func purchaseMonthlyPro() async {
        await runSubscriptionOperation(source: .purchase) {
            try await subscriptionPurchasing.purchaseMonthlyPro(for: accountUser)
        }
    }

    func restorePurchases() async {
        await runSubscriptionOperation(source: .restore) {
            try await subscriptionPurchasing.restorePurchases(for: accountUser)
        }
    }

    func skipForNow() {
        markGuestOnboardingPromptShown()
    }

    func signOut() async throws {
        accessRefreshGeneration += 1
        try await accountService.signOut()
        accessRefreshGeneration += 1
        accountUser = nil
        subscriptionOffer = nil
        subscriptionError = nil
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
        resolveAccessState()
    }

    func markGuestOnboardingPromptShown() {
        userDefaults.set(now(), forKey: guestOnboardingLastPromptAtKey)
    }

    func limitState(for feature: LimitedFeature, currentUsage: Int) -> FeatureLimitState {
        FeatureLimitState(feature: feature, currentUsage: currentUsage, limit: limits.limit(for: feature))
    }

    func dailyLimitState(for feature: LimitedFeature) -> FeatureLimitState {
        dailyUsageLimiter.limitState(for: dailyUsageFeature(for: feature), limit: limits.limit(for: feature))
    }

    func canUseDailyFeature(_ feature: LimitedFeature) -> Bool {
        dailyUsageLimiter.canUse(dailyUsageFeature(for: feature), limit: limits.limit(for: feature))
    }

    func canUseDailyFeature(_ feature: LimitedFeature, usageKey: String) -> Bool {
        dailyUsageLimiter.canUse(
            dailyUsageFeature(for: feature),
            limit: limits.limit(for: feature),
            usageKey: dailyUsageKey(for: feature, usageKey: usageKey)
        )
    }

    func recordDailyFeatureUse(_ feature: LimitedFeature) {
        dailyUsageLimiter.recordUse(dailyUsageFeature(for: feature))
    }

    func recordDailyFeatureUse(_ feature: LimitedFeature, usageKey: String) {
        dailyUsageLimiter.recordUse(dailyUsageFeature(for: feature), usageKey: dailyUsageKey(for: feature, usageKey: usageKey))
    }

    func presentUpgradePrompt(for feature: LimitedFeature, currentUsage: Int? = nil) {
        let state = FeatureLimitState(
            feature: feature,
            currentUsage: currentUsage ?? dailyUsageLimiter.usageCount(for: dailyUsageFeature(for: feature)),
            limit: limits.limit(for: feature)
        )

        upgradePrompt = UpgradePrompt.forLimitState(state)
    }

    private func dailyUsageFeature(for feature: LimitedFeature) -> LimitedFeature {
        LimitedFeature.dailyUsageLimitedFeatures.contains(feature) ? .aviAction : feature
    }

    private func dailyUsageKey(for feature: LimitedFeature, usageKey: String) -> String {
        "\(feature.rawValue):\(TuneAVDailyUsageLimiter.normalizedUsageKey(usageKey))"
    }

    private func runSubscriptionOperation(
        source: SubscriptionReconciliationSource,
        _ operation: () async throws -> TuneAVPurchaseOutcome
    ) async {
        guard accountUser != nil else {
            subscriptionError = .missingAccountUser
            return
        }

        isSubscriptionOperationInProgress = true
        subscriptionError = nil
        defer {
            isSubscriptionOperationInProgress = false
        }

        do {
            let outcome = try await operation()
            guard outcome.shouldRefreshAccess else { return }
            isWaitingForSubscriptionReconciliation = true
            subscriptionReconciliationSource = source
            await syncFromAccountProvider()
            if accessMode == .signedInPro {
                isWaitingForSubscriptionReconciliation = false
                subscriptionReconciliationSource = nil
                upgradePrompt = nil
            }
        } catch let error as TuneAVSubscriptionPurchaseError {
            if error != .purchaseCancelled {
                subscriptionError = error
            }
        } catch {
            subscriptionError = .underlying(error.localizedDescription)
        }
    }

    private func resolveAccessState() {
        applyResolvedAccess(entitlementService.resolveAccess(for: accountUser))
    }

    private func clearUnavailableAccountSession(reason: String) async {
        authLogger.error("Clearing unavailable Account AV session reason=\(reason, privacy: .public)")
        try? await accountService.signOut()
        accessRefreshGeneration += 1
        accountUser = nil
        subscriptionOffer = nil
        subscriptionError = nil
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
        resolveAccessState()
    }

    private func applyResolvedAccess(_ resolvedAccess: ResolvedAccess) {
        guard let accountUser, resolvedAccess.accessMode != .guest else {
            planTier = .free
            accessMode = .guest
            capabilities = AccessCapabilities.forMode(.guest)
            limits = TuneAVAccessLimitPolicy.resolvedLimits(.forMode(.guest), accessMode: .guest)
            accountSession = nil
            return
        }

        planTier = resolvedAccess.planTier
        accessMode = resolvedAccess.accessMode
        capabilities = resolvedAccess.capabilities
        limits = TuneAVAccessLimitPolicy.resolvedLimits(resolvedAccess.limits, accessMode: resolvedAccess.accessMode)
        if resolvedAccess.accessMode == .signedInPro {
            isWaitingForSubscriptionReconciliation = false
            subscriptionReconciliationSource = nil
        }
        accountSession = AccountSession(
            user: accountUser,
            planTier: planTier,
            accessMode: accessMode,
            capabilities: capabilities
        )
    }

    private static func safeErrorCode(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain):\(nsError.code)"
    }
}
