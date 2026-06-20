import AVProductAccountFoundation
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
    @Published private(set) var isRefreshingAccountAccess: Bool
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
        self.isRefreshingAccountAccess = false
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

    var productAccountState: AVProductAccountState {
        if isAccountSessionTemporarilyUnavailable, let accountUser {
            return .temporarilyUnavailable(AVProductAccountSession(
                user: accountUser.productAccountUser,
                isTemporarilyUnavailable: true
            ))
        }

        if let accountUser {
            return .signedIn(AVProductAccountSession(user: accountUser.productAccountUser))
        }

        return .guest
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
        isRefreshingAccountAccess = true
        defer {
            if generation == accessRefreshGeneration {
                isRefreshingAccountAccess = false
            }
        }

        let diagnostics = TuneProductAccountDiagnostics()
        let sessionController = AVProductAccountSessionController(
            configuration: .tuneAV,
            provider: TuneProductAccountProvider(accountService: accountService),
            resolver: TuneProductAccountResolver(
                profileResolver: accountProfileResolver
            ),
            persistence: TuneProductAccountPersistence(userDefaults: userDefaults, key: lastKnownAccountUserKey),
            diagnostics: diagnostics
        )

        let productAccountState = await sessionController.restore()
        let diagnosticEvents = await diagnostics.events

        guard generation == accessRefreshGeneration else { return }

        if diagnosticEvents.contains(.providerSessionActive) {
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.account", operation: "restore_active")
        }

        if diagnosticEvents.contains(.providerSessionUnavailable) ||
            diagnosticEvents.contains(.providerTokenUnavailable) ||
            diagnosticEvents.contains(.productUserResolutionTemporarilyUnavailable) {
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.account", operation: "restore_temporarily_unavailable")
        }

        if diagnosticEvents.contains(.providerSignedOut), productAccountState.user != nil {
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.account", operation: "restore_signed_out_preserved_local_user")
            authLogger.error("Account AV reported signed out while a local account user exists; preserving local account state")
        } else if diagnosticEvents.contains(.providerSignedOut) {
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.account", operation: "restore_signed_out")
        }

        switch productAccountState {
        case .signedIn(let session):
            accountUser = AccountUser(productAccountUser: session.user)
            TuneAVDiagnostics.setUserContext(id: session.user.id)
            isAccountSessionTemporarilyUnavailable = false
        case .temporarilyUnavailable(let session):
            accountUser = AccountUser(productAccountUser: session.user)
            TuneAVDiagnostics.setUserContext(id: session.user.id)
            isAccountSessionTemporarilyUnavailable = true
            authLogger.error("Account AV session is temporarily unavailable during access refresh")
        case .restoring(let lastKnownUser):
            accountUser = lastKnownUser.map(AccountUser.init(productAccountUser:))
            isAccountSessionTemporarilyUnavailable = lastKnownUser != nil
        case .guest:
            if diagnosticEvents.contains(.productUserResolutionTemporarilyUnavailable) ||
                diagnosticEvents.contains(.providerTokenUnavailable) ||
                diagnosticEvents.contains(.providerSessionUnavailable) {
                isAccountSessionTemporarilyUnavailable = true
                accountSession = nil
                platformUserId = nil
                subscriptionOffer = nil
                subscriptionError = nil
                isWaitingForSubscriptionReconciliation = false
                subscriptionReconciliationSource = nil
                resolveAccessState()
                return
            }

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
            TuneAVDiagnostics.capture(error, feature: "tune.subscription", operation: "load_offer", step: "unknown")
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
            TuneAVDiagnostics.addBreadcrumb(feature: "tune.subscription", operation: source.diagnosticsOperation)
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
            TuneAVDiagnostics.capture(
                error,
                feature: "tune.subscription",
                operation: source.diagnosticsOperation,
                step: "unknown"
            )
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

    private func clearSignedOutAccountState() {
        accountUser = nil
        platformUserId = nil
        subscriptionOffer = nil
        subscriptionError = nil
        isAccountSessionTemporarilyUnavailable = false
        isWaitingForSubscriptionReconciliation = false
        subscriptionReconciliationSource = nil
        clearLastKnownAccountUser()
        TuneAVDiagnostics.clearUserContext()
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

private extension AVProductAccountConfiguration {
    static let tuneAV = AVProductAccountConfiguration(
        appIdentifier: "tuneav",
        appDisplayName: "Tune AV",
        allowsGuestMode: true
    )
}

private extension AccountUser {
    init(productAccountUser user: AVProductAccountUser) {
        self.init(id: user.id, displayName: user.displayName, emailAddress: user.emailAddress)
    }

    var productAccountUser: AVProductAccountUser {
        AVProductAccountUser(id: id, displayName: displayName, emailAddress: emailAddress)
    }
}

@MainActor
private struct TuneProductAccountProvider: AVProductAccountProviderSessioning {
    let accountService: AVAccountService

    func restoreProviderSession() async -> AVProductAccountProviderRestoreResult {
        switch await accountService.restoreSession() {
        case .signedOut:
            return .signedOut
        case .active:
            return .active
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .invalidated:
            return .invalidated
        }
    }

    func getProviderToken() async throws -> String? {
        try await accountService.getToken()
    }

    func signOutProvider() async throws {
        try await accountService.signOut()
    }
}

@MainActor
private struct TuneProductAccountResolver: AVProductAccountResolving {
    let profileResolver: AccountProfileResolving

    func resolveProductAccount(
        providerToken: String,
        configuration: AVProductAccountConfiguration
    ) async throws -> AVProductAccountUser {
        _ = providerToken
        _ = configuration

        let accountUser = try await profileResolver.resolveCurrentAccountUser()
        return accountUser.productAccountUser
    }
}

@MainActor
private struct TuneProductAccountPersistence: AVProductAccountPersistence {
    let userDefaults: UserDefaults
    let key: String

    func loadLastKnownUser() async -> AVProductAccountUser? {
        guard let data = userDefaults.data(forKey: key),
              let user = try? JSONDecoder().decode(AccountUser.self, from: data) else {
            return nil
        }
        return user.productAccountUser
    }

    func saveLastKnownUser(_ user: AVProductAccountUser) async throws {
        let accountUser = AccountUser(productAccountUser: user)
        guard let data = try? JSONEncoder().encode(accountUser) else { return }
        userDefaults.set(data, forKey: key)
    }

    func clearLastKnownUser() async throws {
        userDefaults.removeObject(forKey: key)
    }
}

private actor TuneProductAccountDiagnostics: AVProductAccountDiagnostics {
    private(set) var events: [AVProductAccountDiagnosticEvent] = []

    func recordAccountEvent(_ event: AVProductAccountDiagnosticEvent) {
        events.append(event)
    }
}

private extension AccessController.SubscriptionReconciliationSource {
    var diagnosticsOperation: String {
        switch self {
        case .purchase:
            return "purchase"
        case .restore:
            return "restore"
        }
    }
}
