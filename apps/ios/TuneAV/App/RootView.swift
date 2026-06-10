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
    @State private var automaticGuestOnboardingIsPresented = false
    @State private var tuneBackendService: TuneAVAppDataService?
    @State private var tuneBackendServiceUserID: String?
    @State private var librarySyncTask: Task<Void, Never>?
    @State private var lastAutomaticLibrarySyncRequestedAt: Date?
    @State private var realtimeSessionTask: Task<Void, Never>?
    @State private var activeRealtimeSessionOwnerUserID: String?
    @StateObject private var proLibraryObserver = TuneAVProLibraryObserver()

    private let startupLogger = Logger(subsystem: "com.avalsys.tuneav", category: "startup")
    private let proRealtimeLogger = Logger(subsystem: "com.avalsys.tuneav", category: "pro-realtime")
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
                    onSkip: {
                        automaticGuestOnboardingIsPresented = false
                        authPresentationState = .hidden
                        accessController.skipForNow()
                    }
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
            startProRealtimeSyncIfNeeded()
            scheduleSignedInLibrarySync(after: .milliseconds(350))
            markAutomaticGuestOnboardingSeenIfNeeded()
        }
        .onChange(of: libraryStore.settings.keepScreenAwake) { _, _ in
            updateIdleTimer(for: scenePhase)
        }
        .onReceive(proLibraryObserver.$projection.compactMap { $0 }) { projection in
            Task { @MainActor in
                await libraryStore.handleProRealtimeInvalidation(projection)
            }
        }
        .onReceive(proLibraryObserver.$errorMessage.compactMap { $0 }) { errorMessage in
            proRealtimeLogger.error("Tune AV Pro realtime observer error=\(errorMessage, privacy: .public)")
        }
        .onChange(of: accessController.accessMode) { _, _ in
            libraryStore.configureLocalFeedbackRetention(for: accessController.accessMode)
            authPresentationState = .hidden

            if accessController.accessMode != .guest {
                automaticGuestOnboardingIsPresented = false
                guard scenePhase == .active else { return }
                if accessController.capabilities.canUseCloudSync {
                    lastAutomaticLibrarySyncRequestedAt = .now
                    scheduleLibrarySync(after: .milliseconds(150))
                } else {
                    Task {
                        await refreshTuneBackendService()
                    }
                }
            } else {
                cancelScheduledLibrarySync()
                stopProRealtimeSync()
                libraryStore.setAppDataService(nil)
                libraryStore.setBackendService(nil)
                clearTuneBackendService()
            }
        }
        .onChange(of: accessController.accountUser) { _, _ in
            startProRealtimeSyncIfNeeded()
        }
        .onChange(of: accessController.capabilities) { _, _ in
            startProRealtimeSyncIfNeeded()
        }
    }

    private var shouldShowOnboarding: Bool {
        guard !launchContext.shouldDisableOnboarding else { return false }
        let rootGate = AVProductAccountAuthFlowRootGate(
            accountState: accessController.productAccountState,
            authPresentationState: authPresentationState
        )
        return rootGate.shouldShowOnboarding || automaticGuestOnboardingIsPresented
    }

    private func startSignInFlow(showAuthOptions: Bool = false) {
        authPresentationState = showAuthOptions ? .onboardingOptions : .onboardingCollapsed
    }

    private func startAppleSignIn() async throws {
        try await accessController.accountService.signInWithApple()
        automaticGuestOnboardingIsPresented = false
        await accessController.syncFromAccountProvider()
        await refreshLibrarySync()
        authPresentationState = .hidden
    }

    private func startGoogleSignIn() async throws {
        try await accessController.accountService.signInWithGoogle()
        automaticGuestOnboardingIsPresented = false
        await accessController.syncFromAccountProvider()
        await refreshLibrarySync()
        authPresentationState = .hidden
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
        startProRealtimeSyncIfNeeded()
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

    private func startProRealtimeSyncIfNeeded() {
        guard proLibraryObserver.isConfigured,
              accessController.capabilities.canUseCloudSync,
              let ownerUserId = accessController.accountUser?.id else {
            stopProRealtimeSync()
            return
        }
        guard activeRealtimeSessionOwnerUserID != ownerUserId else { return }

        activeRealtimeSessionOwnerUserID = ownerUserId
        realtimeSessionTask?.cancel()
        TuneAVRealtimeSessionStore.shared.clear()
        proLibraryObserver.clear()
        let client = TuneAVRealtimeSessionClient(
            apiClient: AVAccountAPIClient(getToken: { try await accessController.accountService.getToken() })
        )
        guard client.isConfigured else { return }

        realtimeSessionTask = Task { @MainActor in
            do {
                proRealtimeLogger.info("Creating Tune AV Pro realtime session ownerUserId=\(ownerUserId, privacy: .private(mask: .hash))")
                let realtimeSessionId = try await client.createRealtimeSession()
                guard accessController.accountUser?.id == ownerUserId,
                      accessController.capabilities.canUseCloudSync else { return }
                TuneAVRealtimeSessionStore.shared.update(ownerUserId: ownerUserId, realtimeSessionId: realtimeSessionId)
                proRealtimeLogger.info("Created Tune AV Pro realtime session ownerUserId=\(ownerUserId, privacy: .private(mask: .hash))")
                proLibraryObserver.observeLibraryProjection(ownerUserId: ownerUserId)
            } catch {
                proRealtimeLogger.error("Tune AV Pro realtime session failed errorType=\(String(describing: type(of: error)), privacy: .public)")
                activeRealtimeSessionOwnerUserID = nil
                proLibraryObserver.clear()
            }
        }
    }

    private func stopProRealtimeSync() {
        realtimeSessionTask?.cancel()
        realtimeSessionTask = nil
        activeRealtimeSessionOwnerUserID = nil
        TuneAVRealtimeSessionStore.shared.clear()
        proLibraryObserver.clear()
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
        guard !launchContext.shouldDisableOnboarding else { return }
        guard accessController.shouldAutoShowGuestOnboarding else { return }

        automaticGuestOnboardingIsPresented = true
        accessController.markGuestOnboardingPromptShown()
    }

    private func updateIdleTimer(for phase: ScenePhase) {
        UIApplication.shared.isIdleTimerDisabled = phase == .active && libraryStore.settings.keepScreenAwake
    }

    private func refreshActiveAccountStateIfNeeded() async {
        let syncPolicy = RootStartupSyncPolicy(
            accountIsAvailable: accessController.accountIsAvailable,
            isSignedIn: accessController.isSignedIn
        )
        guard syncPolicy.shouldRefreshAccountState else { return }
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
    static let automaticLibrarySyncInterval: TimeInterval = 300

    let accountIsAvailable: Bool
    let isSignedIn: Bool
    let lastLibrarySyncRequestedAt: Date?
    let now: Date

    init(
        accountIsAvailable: Bool,
        isSignedIn: Bool,
        lastLibrarySyncRequestedAt: Date? = nil,
        now: Date = .now
    ) {
        self.accountIsAvailable = accountIsAvailable
        self.isSignedIn = isSignedIn
        self.lastLibrarySyncRequestedAt = lastLibrarySyncRequestedAt
        self.now = now
    }

    var shouldRefreshAccountState: Bool {
        accountIsAvailable || isSignedIn
    }

    var shouldScheduleLibrarySync: Bool {
        guard isSignedIn else { return false }
        guard let lastLibrarySyncRequestedAt else { return true }
        return now.timeIntervalSince(lastLibrarySyncRequestedAt) >= Self.automaticLibrarySyncInterval
    }
}

struct UpgradeRecommendationSheet: View {
    let prompt: UpgradePrompt
    let isGuest: Bool
    let accountIsAvailable: Bool
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        AVUpgradePromptSheet(
            eyebrow: L10n.string("limits.upgrade.eyebrow"),
            title: prompt.title,
            message: prompt.message,
            primaryButtonTitle: primaryButtonTitle,
            primaryButtonIsDisabled: isGuest && !accountIsAvailable,
            dismissButtonTitle: L10n.string("limits.upgrade.notNow"),
            accessibilityIdentifier: "limits.upgrade.sheet.\(prompt.feature.rawValue)",
            onPrimaryAction: onPrimaryAction,
            onDismiss: onDismiss
        )
    }

    private var primaryButtonTitle: String {
        if isGuest {
            accountIsAvailable
                ? L10n.string("limits.upgrade.connectAccount")
                : L10n.string("limits.upgrade.profile")
        } else {
            L10n.string("limits.upgrade.profile")
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
