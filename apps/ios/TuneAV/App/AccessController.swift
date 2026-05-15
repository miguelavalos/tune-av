import Foundation
import OSLog

@MainActor
final class AccessController: ObservableObject {
    @Published private(set) var accessMode: AccessMode
    @Published private(set) var planTier: PlanTier
    @Published private(set) var capabilities: AccessCapabilities
    @Published private(set) var accountUser: AccountUser?
    @Published private(set) var accountSession: AccountSession?
    @Published private(set) var limits: AccessLimits
    @Published var upgradePrompt: UpgradePrompt?

    let accountService: AVAccountService

    private let entitlementService: EntitlementService
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
                authLogger.debug("No active Account AV session during access refresh: \(String(reflecting: error), privacy: .public)")
            }
        }
        resolveAccessState()
        let userForRefresh = accountUser
        let refreshedAccess = await entitlementService.refreshAccess(for: accountUser)
        guard generation == accessRefreshGeneration, accountUser == userForRefresh else { return }
        applyResolvedAccess(refreshedAccess)
    }

    func skipForNow() {
        markGuestOnboardingPromptShown()
    }

    func signOut() async throws {
        accessRefreshGeneration += 1
        try await accountService.signOut()
        accessRefreshGeneration += 1
        accountUser = nil
        resolveAccessState()
    }

    func markGuestOnboardingPromptShown() {
        userDefaults.set(now(), forKey: guestOnboardingLastPromptAtKey)
    }

    func limitState(for feature: LimitedFeature, currentUsage: Int) -> FeatureLimitState {
        FeatureLimitState(feature: feature, currentUsage: currentUsage, limit: limits.limit(for: feature))
    }

    func dailyLimitState(for feature: LimitedFeature) -> FeatureLimitState {
        dailyUsageLimiter.limitState(for: feature, limit: limits.limit(for: feature))
    }

    func canUseDailyFeature(_ feature: LimitedFeature) -> Bool {
        dailyUsageLimiter.canUse(feature, limit: limits.limit(for: feature))
    }

    func canUseDailyFeature(_ feature: LimitedFeature, usageKey: String) -> Bool {
        dailyUsageLimiter.canUse(feature, limit: limits.limit(for: feature), usageKey: usageKey)
    }

    func recordDailyFeatureUse(_ feature: LimitedFeature) {
        dailyUsageLimiter.recordUse(feature)
    }

    func recordDailyFeatureUse(_ feature: LimitedFeature, usageKey: String) {
        dailyUsageLimiter.recordUse(feature, usageKey: usageKey)
    }

    func presentUpgradePrompt(for feature: LimitedFeature, currentUsage: Int? = nil) {
        let state = FeatureLimitState(
            feature: feature,
            currentUsage: currentUsage ?? dailyUsageLimiter.usageCount(for: feature),
            limit: limits.limit(for: feature)
        )

        upgradePrompt = UpgradePrompt.forLimitState(state)
    }

    private func resolveAccessState() {
        applyResolvedAccess(entitlementService.resolveAccess(for: accountUser))
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
        accountSession = AccountSession(
            user: accountUser,
            planTier: planTier,
            accessMode: accessMode,
            capabilities: capabilities
        )
    }

}
