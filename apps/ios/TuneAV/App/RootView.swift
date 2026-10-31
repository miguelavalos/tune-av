import AVLaunchFoundation
import AVPaywallFoundation
import AVProductAccountFoundation
import OSLog
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var authPresentationState: AVProductAccountAuthPresentationState = .hidden
    @State private var authenticationWasSkipped = false
    @State private var automaticGuestOnboardingIsPresented = false
    @State private var tuneBackendService: TuneAVAppDataService?
    @State private var tuneBackendServiceUserID: String?
    @State private var librarySyncTask: Task<Void, Never>?
    @State private var lastAutomaticAccountRefreshRequestedAt: Date?
    @State private var lastAutomaticLibrarySyncRequestedAt: Date?

    private let startupLogger = Logger(subsystem: "com.avalsys.tuneav", category: "startup")
    private let launchContext = LaunchContext.current
    private var splashPolicy: AVSplashTransitionPolicy {
        AVSplashTransitionPolicy(isDisabled: launchContext.shouldDisableSplash)
    }

    var body: some View {
        Group {
            if shouldShowOnboarding {
                AuthOnboardingView(
                    authPresentationState: $authPresentationState,
                    accountIsAvailable: accessController.accountIsAvailable,
                    onContinueWithApple: startAppleSignIn,
                    onContinueWithGoogle: startGoogleSignIn,
                    onSkip: skipAuthentication
                )
            } else {
                AppShellView(
                    launchContext: launchContext,
                    startSignInFlow: startSignInFlow,
                    synchronizeLibraryNow: refreshLibrarySync
                )
                    .environmentObject(accessController)
                    .avSplashTransition(policy: splashPolicy) { startedAt in
                        logStartupOperation("splash", startedAt: startedAt)
                    } splash: {
                        TuneAVSplashView()
                    }
                    .id(accessController.isSignedIn ? "signed-in-shell" : "skipped-auth-shell")
            }
        }
        .tint(TuneAVTheme.highlight)
        .task(id: scenePhase) {
            libraryStore.configureLocalFeedbackRetention(for: accessController.accessMode)
            updateIdleTimer(for: scenePhase)
            guard scenePhase == .active else {
                cancelScheduledLibrarySync()
                return
            }
            await refreshActiveAccountStateIfNeeded()
            scheduleSignedInLibrarySync(after: .milliseconds(350))
            markAutomaticGuestOnboardingSeenIfNeeded()
        }
        .onChange(of: libraryStore.settings.keepScreenAwake) { _, _ in
            updateIdleTimer(for: scenePhase)
        }
        .onChange(of: accessController.accessMode) { _, _ in
            libraryStore.configureLocalFeedbackRetention(for: accessController.accessMode)
            authPresentationState = .hidden

            if accessController.accessMode != .guest {
                automaticGuestOnboardingIsPresented = false
                guard scenePhase == .active else { return }
                if accessController.capabilities.canUseCloudSync {
                    scheduleSignedInLibrarySync(after: .milliseconds(150))
                } else {
                    lastAutomaticLibrarySyncRequestedAt = nil
                    Task {
                        await refreshTuneBackendService()
                    }
                }
            } else {
                cancelScheduledLibrarySync()
                libraryStore.setAppDataService(nil)
                libraryStore.setBackendService(nil)
                clearTuneBackendService()
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        if TuneAVUITestEnvironment.current.shouldForceGuestOnboarding {
            return authPresentationState != .hidden || automaticGuestOnboardingIsPresented
        }
        guard !authenticationWasSkipped else { return false }
        guard !launchContext.shouldDisableOnboarding else { return false }
        let rootGate = AVProductAccountAuthFlowRootGate(
            accountState: accessController.productAccountState,
            authPresentationState: authPresentationState
        )
        return rootGate.shouldShowOnboarding || automaticGuestOnboardingIsPresented
    }

    private func startSignInFlow(showAuthOptions: Bool = false) {
        authenticationWasSkipped = false
        automaticGuestOnboardingIsPresented = false
        authPresentationState = showAuthOptions ? .onboardingOptions : .onboardingCollapsed
    }

    private func skipAuthentication() {
        accessController.cancelPendingPurchase()
        authenticationWasSkipped = true
        automaticGuestOnboardingIsPresented = false
        authPresentationState = .hidden
        accessController.skipForNow()
    }

    private func startAppleSignIn() async throws {
        try await accessController.accountService.signInWithApple()
        authenticationWasSkipped = false
        automaticGuestOnboardingIsPresented = false
        await accessController.syncFromAccountProvider()
        lastAutomaticAccountRefreshRequestedAt = .now
        authPresentationState = .hidden
        await accessController.resumePendingPurchaseIfNeeded()
    }

    private func startGoogleSignIn() async throws {
        try await accessController.accountService.signInWithGoogle()
        authenticationWasSkipped = false
        automaticGuestOnboardingIsPresented = false
        await accessController.syncFromAccountProvider()
        lastAutomaticAccountRefreshRequestedAt = .now
        authPresentationState = .hidden
        await accessController.resumePendingPurchaseIfNeeded()
    }

    private func refreshLibrarySync() async {
        if launchContext.isUITesting, let status = launchContext.uiTestCloudSyncStatus {
            switch status {
            case "conflict":
                libraryStore.setCloudSyncStatusForUITests(.conflict)
            case "failed":
                libraryStore.setCloudSyncStatusForUITests(.failed)
            case "synced":
                libraryStore.setCloudSyncStatusForUITests(.synced(.now))
            default:
                libraryStore.setCloudSyncStatusForUITests(.idle)
            }
            return
        }

        guard accessController.capabilities.canUseCloudSync else {
            libraryStore.setAppDataService(nil)
            await refreshTuneBackendService()
            return
        }

        guard let appDataService = configuredTuneBackendService() else {
            libraryStore.setAppDataService(nil)
            libraryStore.setBackendService(nil)
            return
        }

        libraryStore.setBackendService(appDataService, userID: accessController.accountUser?.id)
        libraryStore.setAppDataService(appDataService)
        await libraryStore.refreshCloudLibraryIfNeeded()
        await libraryStore.refreshUserSummary(force: true)
    }

    private func scheduleLibrarySync(after delay: Duration? = nil) {
        librarySyncTask?.cancel()
        librarySyncTask = Task { @MainActor in
            if let delay {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            await measureStartupOperation("library_sync") {
                await refreshLibrarySync()
            }
            guard !Task.isCancelled else { return }
            librarySyncTask = nil
        }
    }

    private func scheduleSignedInLibrarySync(after delay: Duration? = nil) {
        guard accessController.isSignedIn else {
            cancelScheduledLibrarySync()
            return
        }

        let syncPolicy = RootStartupSyncPolicy(
            accountIsAvailable: accessController.accountIsAvailable,
            isSignedIn: accessController.isSignedIn,
            lastAccountRefreshRequestedAt: lastAutomaticAccountRefreshRequestedAt,
            lastLibrarySyncRequestedAt: lastAutomaticLibrarySyncRequestedAt,
            now: .now
        )
        guard syncPolicy.shouldScheduleLibrarySync else { return }

        lastAutomaticLibrarySyncRequestedAt = syncPolicy.now
        scheduleLibrarySync(after: delay)
    }

    private func cancelScheduledLibrarySync() {
        librarySyncTask?.cancel()
        librarySyncTask = nil
    }

    private func refreshTuneBackendService() async {
        guard let backendService = configuredTuneBackendService() else {
            libraryStore.setBackendService(nil)
            return
        }

        libraryStore.setBackendService(backendService, userID: accessController.accountUser?.id)
        await libraryStore.refreshUserSummary()
    }

    private func configuredTuneBackendService() -> TuneAVAppDataService? {
        guard accessController.isSignedIn, let userID = accessController.accountUser?.id else {
            clearTuneBackendService()
            return nil
        }

        if tuneBackendServiceUserID == userID,
           let tuneBackendService,
           tuneBackendService.isConfigured() {
            return tuneBackendService
        }

        let service = TuneAVAppDataService(
            apiClient: AVAccountAPIClient(getToken: { try await accessController.accountService.getToken() })
        )
        guard service.isConfigured() else {
            clearTuneBackendService()
            return nil
        }

        tuneBackendService = service
        tuneBackendServiceUserID = userID
        return service
    }

    private func clearTuneBackendService() {
        tuneBackendService = nil
        tuneBackendServiceUserID = nil
    }

    private func markAutomaticGuestOnboardingSeenIfNeeded() {
        if TuneAVUITestEnvironment.current.shouldForceGuestOnboarding {
            forceGuestOnboardingForUITestsIfNeeded()
            return
        }
        guard !launchContext.shouldDisableOnboarding else { return }
        guard !accessController.isSignedIn else { return }
        guard !authenticationWasSkipped else { return }
        guard accessController.shouldAutoShowGuestOnboarding else { return }
        guard authPresentationState == .hidden else { return }

        automaticGuestOnboardingIsPresented = true
        authPresentationState = .onboardingCollapsed
        accessController.markGuestOnboardingPromptShown()
    }

    private func forceGuestOnboardingForUITestsIfNeeded() {
        guard !authenticationWasSkipped else { return }
        guard authPresentationState == .hidden else { return }
        automaticGuestOnboardingIsPresented = true
        authPresentationState = TuneAVUITestEnvironment.current.shouldShowExpandedOnboardingAuthOptions
            ? .onboardingOptions
            : .onboardingCollapsed
    }

    private func updateIdleTimer(for phase: ScenePhase) {
        UIApplication.shared.isIdleTimerDisabled = phase == .active && libraryStore.settings.keepScreenAwake
    }

    private func refreshActiveAccountStateIfNeeded() async {
        let syncPolicy = RootStartupSyncPolicy(
            accountIsAvailable: accessController.accountIsAvailable,
            isSignedIn: accessController.isSignedIn,
            lastAccountRefreshRequestedAt: lastAutomaticAccountRefreshRequestedAt
        )
        guard syncPolicy.shouldRefreshAccountState else { return }
        lastAutomaticAccountRefreshRequestedAt = syncPolicy.now
        await measureStartupOperation("access_sync") {
            await accessController.syncFromAccountProvider()
        }
    }

    private func measureStartupOperation(_ name: String, operation: () async -> Void) async {
        let startedAt = Date()
        await operation()
        logStartupOperation(name, startedAt: startedAt)
    }

    private func logStartupOperation(_ name: String, startedAt: Date) {
        let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        startupLogger.info("Startup operation completed name=\(name, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public)")
    }
}

struct RootStartupSyncPolicy: Equatable {
    let accountIsAvailable: Bool
    let isSignedIn: Bool
    let lastAccountRefreshRequestedAt: Date?
    let lastLibrarySyncRequestedAt: Date?
    let now: Date

    init(
        accountIsAvailable: Bool,
        isSignedIn: Bool,
        lastAccountRefreshRequestedAt: Date? = nil,
        lastLibrarySyncRequestedAt: Date? = nil,
        now: Date = .now
    ) {
        self.accountIsAvailable = accountIsAvailable
        self.isSignedIn = isSignedIn
        self.lastAccountRefreshRequestedAt = lastAccountRefreshRequestedAt
        self.lastLibrarySyncRequestedAt = lastLibrarySyncRequestedAt
        self.now = now
    }

    var shouldRefreshAccountState: Bool {
        (accountIsAvailable || isSignedIn) && lastAccountRefreshRequestedAt == nil
    }

    /// Minimum spacing between automatic library pulls triggered by app activation.
    static let foregroundSyncInterval: TimeInterval = 60

    var shouldScheduleLibrarySync: Bool {
        guard isSignedIn else { return false }
        guard let lastLibrarySyncRequestedAt else { return true }
        return now.timeIntervalSince(lastLibrarySyncRequestedAt) >= Self.foregroundSyncInterval
    }
}

/// Limit and upgrade-moment sheet. The primary action opens the Pro paywall for every tier (guests see
/// the price there and sign in on purchase); guests also get sign-in as a secondary action.
struct UpgradeRecommendationSheet: View {
    let prompt: UpgradePrompt
    let isGuest: Bool
    let accountIsAvailable: Bool
    let onPrimaryAction: () -> Void
    let onSignIn: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AVUpgradePromptSheet(
                eyebrow: L10n.string("limits.upgrade.eyebrow"),
                title: prompt.title,
                message: prompt.message,
                primaryButtonTitle: L10n.string("limits.upgrade.viewPro"),
                dismissButtonTitle: L10n.string("limits.upgrade.notNow"),
                accessibilityIdentifier: "limits.upgrade.sheet.\(prompt.feature.rawValue)",
                onPrimaryAction: onPrimaryAction,
                onDismiss: onDismiss
            )

            if isGuest, accountIsAvailable {
                Button(action: onSignIn) {
                    Text(L10n.string("limits.upgrade.signInInstead"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .accessibilityIdentifier("limits.upgrade.signIn")
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }
}

struct MissingConfigurationView: View {
    var body: some View {
        ZStack {
            TuneAVTheme.shellBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .padding(14)
                    .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                    }

                Text(L10n.string("root.missingConfiguration.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textPrimary)

                Text(L10n.string("root.missingConfiguration.message"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TuneAVTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(TuneAVTheme.cardSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
                    }
            )
            .padding(24)
        }
    }
}

#Preview {
    MissingConfigurationView()
}
