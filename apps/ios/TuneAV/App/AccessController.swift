import Foundation
import OSLog

@MainActor
protocol AccountProfileResolving {
    func resolveCurrentAccountUser() async throws -> AccountUser
}

enum AccountProfileResolverError: Error, Equatable {
    case missingInternalUserId
}

@MainActor
final class PlatformAccountProfileResolver: AccountProfileResolving {
    private let apiClient: AVAccountAPIClient

    init(apiClient: AVAccountAPIClient) {
        self.apiClient = apiClient
    }

    func resolveCurrentAccountUser() async throws -> AccountUser {
        let summary = try await apiClient.fetchAccountSummary()
        guard let id = summary.id, !id.isEmpty else {
            throw AccountProfileResolverError.missingInternalUserId
        }
        let displayName = summary.displayName.flatMap { value -> String? in
            value.isEmpty ? nil : value
        } ?? L10n.string("app.name")
        return AccountUser(
            id: id,
            displayName: displayName,
            emailAddress: summary.emailAddress
        )
    }
}

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
    @Published private(set) var platformUserId: String?
    @Published private(set) var subscriptionOffer: TuneAVSubscriptionOffer?
    @Published private(set) var subscriptionError: TuneAVSubscriptionPurchaseError?
    @Published private(set) var isAccountSessionTemporarilyUnavailable: Bool
    @Published private(set) var isSubscriptionOperationInProgress: Bool
    @Published private(set) var isWaitingForSubscriptionReconciliation: Bool
    @Published private(set) var subscriptionReconciliationSource: SubscriptionReconciliationSource?
    @Published var upgradePrompt: UpgradePrompt?

    let accountService: AVAccountService

    private let entitlementService: EntitlementService
    private let accountProfileResolver: AccountProfileResolving
    private let subscriptionPurchasing: TuneAVSubscriptionPurchasing
    private let userDefaults: UserDefaults
    private let guestOnboardingPolicy: GuestOnboardingPolicy
    private let now: () -> Date
    private let subscriptionReconciliationRetryDelaysNanoseconds: [UInt64]
    private let sleepNanoseconds: (UInt64) async -> Void
    private let dailyUsageLimiter: TuneAVDailyUsageLimiter
    private let authLogger = Logger(subsystem: "com.avalsys.tuneav", category: "auth")
    private let guestOnboardingLastPromptAtKey = "tuneav.guestOnboarding.lastPromptAt"
    private let lastKnownAccountUserKey = "tuneav.account.lastKnownUser"
    private var accessRefreshGeneration = 0

    init(
        accountService: AVAccountService = DefaultAVAccountService(),
        accountProfileResolver: AccountProfileResolving? = nil,
        entitlementService: EntitlementService? = nil,
        subscriptionPurchasing: TuneAVSubscriptionPurchasing = RevenueCatTuneAVSubscriptionPurchasing(),
        userDefaults: UserDefaults = .standard,
        guestOnboardingPolicy: GuestOnboardingPolicy = GuestOnboardingPolicy(),
        now: @escaping () -> Date = Date.init,
        subscriptionReconciliationRetryDelaysNanoseconds: [UInt64] = [
            1_000_000_000,
            2_000_000_000,
            3_000_000_000,
            5_000_000_000
        ],
        sleepNanoseconds: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        let currentUser = Self.lastKnownAccountUser(from: userDefaults)

        self.accountService = accountService
        self.accountProfileResolver = accountProfileResolver
            ?? PlatformAccountProfileResolver(
                apiClient: AVAccountAPIClient(getToken: { try await accountService.getToken() })
            )
        self.entitlementService = entitlementService
            ?? PlatformBackedEntitlementService(
                fallback: LocalEntitlementService(),
                apiClient: AVAccountAPIClient(getToken: { try await accountService.getToken() })
            )
        self.subscriptionPurchasing = subscriptionPurchasing
        self.userDefaults = userDefaults
        self.guestOnboardingPolicy = guestOnboardingPolicy
        self.now = now
        self.subscriptionReconciliationRetryDelaysNanoseconds = subscriptionReconciliationRetryDelaysNanoseconds
        self.sleepNanoseconds = sleepNanoseconds
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
        self.platformUserId = nil
        self.subscriptionOffer = nil
        self.subscriptionError = nil
        self.isAccountSessionTemporarilyUnavailable = false
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

        switch await accountService.restoreSession() {
        case .active(let providerUser):
            guard generation == accessRefreshGeneration else { return }
            guard let resolvedUser = await resolveInternalAccountUser(providerUser: providerUser) else {
                isAccountSessionTemporarilyUnavailable = true
                if accountUser == nil {
                    accountSession = nil
                    platformUserId = nil
                    subscriptionOffer = nil
                    subscriptionError = nil
                    isWaitingForSubscriptionReconciliation = false
                    subscriptionReconciliationSource = nil
                    clearLastKnownAccountUser()
                    resolveAccessState()
                }
                return
            }
            accountUser = resolvedUser
            persistLastKnownAccountUser(resolvedUser)
            isAccountSessionTemporarilyUnavailable = false
        case .temporarilyUnavailable:
            guard generation == accessRefreshGeneration else { return }
            isAccountSessionTemporarilyUnavailable = true
            authLogger.error("Account AV session is temporarily unavailable during access refresh")
            resolveAccessState()
            return
        case .signedOut, .invalidated:
            guard generation == accessRefreshGeneration else { return }
            clearSignedOutAccountState()
            resolveAccessState()
            return
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
            subscriptionOffer = try await subscriptionPurchasing.loadMonthlyOffer(for: subscriptionAccountUser)
            subscriptionError = nil
        } catch let error as TuneAVSubscriptionPurchaseError {
            subscriptionError = error
        } catch {
            subscriptionError = .underlying(error.localizedDescription)
        }
    }

    func purchaseMonthlyPro() async {
        await runSubscriptionOperation(source: .purchase) {
            try await subscriptionPurchasing.purchaseMonthlyPro(for: subscriptionAccountUser)
        }
    }

    func restorePurchases() async {
        await runSubscriptionOperation(source: .restore) {
            try await subscriptionPurchasing.restorePurchases(for: subscriptionAccountUser)
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
        platformUserId = nil
        subscriptionOffer = nil
        subscriptionError = nil
        isAccountSessionTemporarilyUnavailable = false
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
        resolveAccessState()
        clearLastKnownAccountUser()
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
            await retrySubscriptionReconciliationIfNeeded()
        } catch let error as TuneAVSubscriptionPurchaseError {
            if error != .purchaseCancelled {
                subscriptionError = error
            }
        } catch {
            subscriptionError = .underlying(error.localizedDescription)
        }
    }

    private func retrySubscriptionReconciliationIfNeeded() async {
        guard accessMode != .signedInPro else {
            clearSubscriptionReconciliationState()
            return
        }

        let reconciliationAccountUser = accountUser
        for delay in subscriptionReconciliationRetryDelaysNanoseconds {
            guard isWaitingForSubscriptionReconciliation else { return }
            guard accountUser == reconciliationAccountUser else { return }

            await sleepNanoseconds(delay)
            guard isWaitingForSubscriptionReconciliation else { return }
            guard accountUser == reconciliationAccountUser else { return }

            await syncFromAccountProvider()
            if accessMode == .signedInPro {
                clearSubscriptionReconciliationState()
                return
            }
        }
    }

    private func clearSubscriptionReconciliationState() {
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
        upgradePrompt = nil
    }

    private func resolveAccessState() {
        applyResolvedAccess(entitlementService.resolveAccess(for: accountUser))
    }

    private func resolveInternalAccountUser(providerUser: AccountUser) async -> AccountUser? {
        if TuneAVUITestEnvironment.current.hasAccountOverride {
            return providerUser
        }

        do {
            return try await accountProfileResolver.resolveCurrentAccountUser()
        } catch {
            authLogger.error("Unable to resolve internal Account AV user error=\(Self.safeErrorCode(error), privacy: .public)")
            return nil
        }
    }

    private func clearSignedOutAccountState() {
        accountUser = nil
        platformUserId = nil
        subscriptionOffer = nil
        subscriptionError = nil
        isAccountSessionTemporarilyUnavailable = false
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
        clearLastKnownAccountUser()
    }

    private func applyResolvedAccess(_ resolvedAccess: ResolvedAccess) {
        guard let accountUser, resolvedAccess.accessMode != .guest else {
            planTier = .free
            accessMode = .guest
            capabilities = AccessCapabilities.forMode(.guest)
            limits = TuneAVAccessLimitPolicy.resolvedLimits(.forMode(.guest), accessMode: .guest)
            platformUserId = nil
            accountSession = nil
            return
        }

        if let resolvedPlatformUserId = resolvedAccess.platformUserId, !resolvedPlatformUserId.isEmpty {
            platformUserId = resolvedPlatformUserId
        }
        planTier = resolvedAccess.planTier
        accessMode = resolvedAccess.accessMode
        capabilities = resolvedAccess.capabilities
        limits = TuneAVAccessLimitPolicy.resolvedLimits(resolvedAccess.limits, accessMode: resolvedAccess.accessMode)
        if resolvedAccess.accessMode == .signedInPro {
            clearSubscriptionReconciliationState()
        }
        accountSession = AccountSession(
            user: accountUser,
            planTier: planTier,
            accessMode: accessMode,
            capabilities: capabilities
        )
        persistLastKnownAccountUser(accountUser)
    }

    private var subscriptionAccountUser: AccountUser? {
        guard let accountUser else { return nil }
        guard let platformUserId, !platformUserId.isEmpty else { return accountUser }
        return AccountUser(
            id: platformUserId,
            displayName: accountUser.displayName,
            emailAddress: accountUser.emailAddress
        )
    }

    private static func safeErrorCode(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain):\(nsError.code)"
    }

    private static func lastKnownAccountUser(from userDefaults: UserDefaults) -> AccountUser? {
        guard let data = userDefaults.data(forKey: "tuneav.account.lastKnownUser") else { return nil }
        return try? JSONDecoder().decode(AccountUser.self, from: data)
    }

    private func persistLastKnownAccountUser(_ user: AccountUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        userDefaults.set(data, forKey: lastKnownAccountUserKey)
    }

    private func clearLastKnownAccountUser() {
        userDefaults.removeObject(forKey: lastKnownAccountUserKey)
    }
}
