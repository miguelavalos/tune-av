import Foundation

@MainActor
final class AccessController: ObservableObject {
    @Published private(set) var accessMode: AccessMode
    @Published private(set) var planTier: PlanTier
    @Published private(set) var capabilities: AccessCapabilities
    @Published private(set) var accountUser: AccountUser?
    @Published private(set) var accountSession: AccountSession?
    @Published private(set) var subscriptionProducts: [SubscriptionProduct]
    @Published private(set) var subscriptionProductsAreLoading: Bool
    @Published private(set) var limits: AccessLimits
    @Published var upgradePrompt: UpgradePrompt?

    let accountService: AVAccountService

    private let entitlementService: EntitlementService
    private let userDefaults: UserDefaults
    private let guestOnboardingPolicy: GuestOnboardingPolicy
    private let now: () -> Date
    private let guestOnboardingLastPromptAtKey = "tuneav.guestOnboarding.lastPromptAt"
    private let dailyUsagePrefix = "tuneav.featureUsage."

    init(
        accountService: AVAccountService = DefaultAVAccountService(),
        entitlementService: EntitlementService? = nil,
        userDefaults: UserDefaults = .standard,
        guestOnboardingPolicy: GuestOnboardingPolicy = GuestOnboardingPolicy(),
        now: @escaping () -> Date = Date.init
    ) {
        let currentUser = accountService.currentUser
        let fallbackEntitlementService = StoreKitEntitlementService(userDefaults: userDefaults)

        self.accountService = accountService
        self.entitlementService = entitlementService
            ?? PlatformBackedEntitlementService(
                fallback: fallbackEntitlementService,
                apiClient: AVAccountAPIClient(getToken: { try await accountService.getToken() })
            )
        self.userDefaults = userDefaults
        self.guestOnboardingPolicy = guestOnboardingPolicy
        self.now = now
        self.accountUser = currentUser
        self.planTier = .free
        self.capabilities = AccessCapabilities.forMode(.guest)
        self.accountSession = nil
        self.subscriptionProducts = []
        self.subscriptionProductsAreLoading = false
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

    var subscriptionIsAvailable: Bool {
        entitlementService.isSubscriptionConfigured
    }

    var shouldAutoShowGuestOnboarding: Bool {
        guard accessMode == .guest else { return false }
        return guestOnboardingPolicy.shouldShowAutomatically(
            lastPromptAt: userDefaults.object(forKey: guestOnboardingLastPromptAtKey) as? Date,
            now: now()
        )
    }

    func syncFromAccountProvider() async {
        accountUser = accountService.currentUser
        resolveAccessState()
        let refreshedAccess = await entitlementService.refreshAccess(for: accountUser)
        applyResolvedAccess(refreshedAccess)
        await refreshSubscriptionProducts()
    }

    func skipForNow() {
        markGuestOnboardingPromptShown()
    }

    func purchasePro(productID: String) async throws -> SubscriptionPurchaseOutcome {
        guard let accountUser else {
            throw EntitlementServiceError.accountRequired
        }

        let outcome = try await entitlementService.purchasePro(for: accountUser, productID: productID)
        resolveAccessState()
        return outcome
    }

    func restorePurchases() async throws -> RestorePurchasesOutcome {
        guard let accountUser else {
            throw EntitlementServiceError.accountRequired
        }

        let outcome = try await entitlementService.restorePurchases(for: accountUser)
        resolveAccessState()
        return outcome
    }

    func signOut() async throws {
        try await accountService.signOut()
        accountUser = nil
        resolveAccessState()
    }

    func markGuestOnboardingPromptShown() {
        userDefaults.set(now(), forKey: guestOnboardingLastPromptAtKey)
    }

    func refreshSubscriptionProducts() async {
        guard subscriptionIsAvailable else {
            subscriptionProducts = []
            subscriptionProductsAreLoading = false
            return
        }

        subscriptionProductsAreLoading = true
        defer { subscriptionProductsAreLoading = false }

        do {
            subscriptionProducts = try await entitlementService.loadSubscriptionProducts()
        } catch {
            subscriptionProducts = []
        }
    }

    func limitState(for feature: LimitedFeature, currentUsage: Int) -> FeatureLimitState {
        FeatureLimitState(feature: feature, currentUsage: currentUsage, limit: limits.limit(for: feature))
    }

    func dailyLimitState(for feature: LimitedFeature) -> FeatureLimitState {
        limitState(for: feature, currentUsage: dailyUsageCount(for: feature))
    }

    func canUseDailyFeature(_ feature: LimitedFeature) -> Bool {
        return dailyLimitState(for: feature).isAllowed
    }

    func canUseDailyFeature(_ feature: LimitedFeature, usageKey: String) -> Bool {
        let bucket = dailyUsageBucket(for: feature)
        if bucket.usageKeys.contains(Self.normalizedUsageKey(usageKey)) {
            return true
        }

        return limitState(for: feature, currentUsage: bucket.count).isAllowed
    }

    func recordDailyFeatureUse(_ feature: LimitedFeature) {
        let bucket = dailyUsageBucket(for: feature)
        userDefaults.set(bucket.dayIdentifier, forKey: dailyUsageDayKey(for: feature))
        userDefaults.set(bucket.count + 1, forKey: dailyUsageCountKey(for: feature))
    }

    func recordDailyFeatureUse(_ feature: LimitedFeature, usageKey: String) {
        let normalizedUsageKey = Self.normalizedUsageKey(usageKey)
        guard !normalizedUsageKey.isEmpty else {
            recordDailyFeatureUse(feature)
            return
        }

        var bucket = dailyUsageBucket(for: feature)
        userDefaults.set(bucket.dayIdentifier, forKey: dailyUsageDayKey(for: feature))
        guard !bucket.usageKeys.contains(normalizedUsageKey) else { return }

        bucket.usageKeys.insert(normalizedUsageKey)
        let sortedUsageKeys = bucket.usageKeys.sorted()
        userDefaults.set(sortedUsageKeys, forKey: dailyUsageKeysKey(for: feature))
        userDefaults.set(max(bucket.count + 1, sortedUsageKeys.count), forKey: dailyUsageCountKey(for: feature))
    }

    func presentUpgradePrompt(for feature: LimitedFeature, currentUsage: Int? = nil) {
        let state = FeatureLimitState(
            feature: feature,
            currentUsage: currentUsage ?? dailyUsageCount(for: feature),
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
            limits = limitsWithUITestOverrides(.forMode(.guest))
            accountSession = nil
            return
        }

        planTier = resolvedAccess.planTier
        accessMode = resolvedAccess.accessMode
        capabilities = resolvedAccess.capabilities
        limits = limitsWithUITestOverrides(
            dailyActionsUnlimitedForPro(resolvedAccess.limits, accessMode: resolvedAccess.accessMode)
        )
        accountSession = AccountSession(
            user: accountUser,
            planTier: planTier,
            accessMode: accessMode,
            capabilities: capabilities
        )
    }

    private func limitsWithUITestOverrides(_ resolvedLimits: AccessLimits) -> AccessLimits {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TUNEAV_UI_TESTS"] == "1" else {
            return resolvedLimits
        }

        let favoriteStations = environment["TUNEAV_UI_TEST_FAVORITE_LIMIT"]
            .flatMap(Int.init)
            ?? resolvedLimits.favoriteStations
        let lyricsSearchesPerDay = environment["TUNEAV_UI_TEST_LYRICS_LIMIT"]
            .flatMap(Int.init)
            ?? resolvedLimits.lyricsSearchesPerDay
        let webSearchesPerDay = environment["TUNEAV_UI_TEST_WEB_LIMIT"]
            .flatMap(Int.init)
            ?? resolvedLimits.webSearchesPerDay
        let youtubeSearchesPerDay = environment["TUNEAV_UI_TEST_YOUTUBE_LIMIT"]
            .flatMap(Int.init)
            ?? resolvedLimits.youtubeSearchesPerDay
        let appleMusicSearchesPerDay = environment["TUNEAV_UI_TEST_APPLE_MUSIC_LIMIT"]
            .flatMap(Int.init)
            ?? resolvedLimits.appleMusicSearchesPerDay
        let spotifySearchesPerDay = environment["TUNEAV_UI_TEST_SPOTIFY_LIMIT"]
            .flatMap(Int.init)
            ?? resolvedLimits.spotifySearchesPerDay
        let discoverySharesPerDay = environment["TUNEAV_UI_TEST_DISCOVERY_SHARE_LIMIT"]
            .flatMap(Int.init)
            ?? resolvedLimits.discoverySharesPerDay

        return AccessLimits(
            favoriteStations: favoriteStations,
            recentStations: resolvedLimits.recentStations,
            discoveredTracks: resolvedLimits.discoveredTracks,
            savedTracks: resolvedLimits.savedTracks,
            lyricsSearchesPerDay: lyricsSearchesPerDay,
            webSearchesPerDay: webSearchesPerDay,
            youtubeSearchesPerDay: youtubeSearchesPerDay,
            appleMusicSearchesPerDay: appleMusicSearchesPerDay,
            spotifySearchesPerDay: spotifySearchesPerDay,
            discoverySharesPerDay: discoverySharesPerDay
        )
    }

    private func dailyActionsUnlimitedForPro(_ resolvedLimits: AccessLimits, accessMode: AccessMode) -> AccessLimits {
        guard accessMode == .signedInPro else { return resolvedLimits }

        return AccessLimits(
            favoriteStations: resolvedLimits.favoriteStations,
            recentStations: resolvedLimits.recentStations,
            discoveredTracks: resolvedLimits.discoveredTracks,
            savedTracks: resolvedLimits.savedTracks,
            lyricsSearchesPerDay: nil,
            webSearchesPerDay: nil,
            youtubeSearchesPerDay: nil,
            appleMusicSearchesPerDay: nil,
            spotifySearchesPerDay: nil,
            discoverySharesPerDay: nil
        )
    }

    private func dailyUsageCount(for feature: LimitedFeature) -> Int {
        let bucket = dailyUsageBucket(for: feature)
        return bucket.count
    }

    private func dailyUsageBucket(for feature: LimitedFeature) -> (dayIdentifier: String, count: Int, usageKeys: Set<String>) {
        let dayIdentifier = Self.dayIdentifier(for: now())
        let storedDay = userDefaults.string(forKey: dailyUsageDayKey(for: feature))
        guard storedDay == dayIdentifier else {
            return (dayIdentifier, 0, [])
        }

        let usageKeys = Set(
            userDefaults.stringArray(forKey: dailyUsageKeysKey(for: feature))?
                .map(Self.normalizedUsageKey)
                .filter { !$0.isEmpty } ?? []
        )
        return (dayIdentifier, max(userDefaults.integer(forKey: dailyUsageCountKey(for: feature)), usageKeys.count), usageKeys)
    }

    private func dailyUsageDayKey(for feature: LimitedFeature) -> String {
        "\(dailyUsagePrefix)\(feature.rawValue).day"
    }

    private func dailyUsageCountKey(for feature: LimitedFeature) -> String {
        "\(dailyUsagePrefix)\(feature.rawValue).count"
    }

    private func dailyUsageKeysKey(for feature: LimitedFeature) -> String {
        "\(dailyUsagePrefix)\(feature.rawValue).keys"
    }

    private static func normalizedUsageKey(_ usageKey: String) -> String {
        usageKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func dayIdentifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

}

struct GuestOnboardingPolicy {
    static let defaultCooldown: TimeInterval = 10 * 24 * 60 * 60

    let cooldown: TimeInterval

    init(cooldown: TimeInterval = defaultCooldown) {
        self.cooldown = cooldown
    }

    func shouldShowAutomatically(lastPromptAt: Date?, now: Date) -> Bool {
        guard let lastPromptAt else { return true }
        return now >= lastPromptAt.addingTimeInterval(cooldown)
    }
}
