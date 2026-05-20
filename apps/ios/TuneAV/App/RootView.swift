import SwiftUI
import UIKit
import OSLog

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var accessController: AccessController
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var authOptionsArePresented = false
    @State private var automaticGuestOnboardingIsPresented = false
    @State private var isShowingAccountOnboarding = false
    @State private var isShowingSplash = false
    @State private var hasShownSplashThisLaunch = false
    @State private var tuneBackendService: TuneAVAppDataService?
    @State private var tuneBackendServiceUserID: String?
    @State private var librarySyncTask: Task<Void, Never>?
    @State private var lastAutomaticLibrarySyncRequestedAt: Date?

    private let startupLogger = Logger(subsystem: "com.avalsys.tuneav", category: "startup")
    private let launchContext = LaunchContext.current
    var body: some View {
        Group {
            if shouldShowOnboarding {
                AuthOnboardingView(
                    authOptionsArePresented: $authOptionsArePresented,
                    accountIsAvailable: accessController.accountIsAvailable,
                    onContinueWithApple: startAppleSignIn,
                    onContinueWithGoogle: startGoogleSignIn,
                    onSkip: {
                        automaticGuestOnboardingIsPresented = false
                        isShowingAccountOnboarding = false
                        accessController.skipForNow()
                    }
                )
            } else {
                AppShellView(
                    launchContext: launchContext,
                    startSignInFlow: startSignInFlow
                )
                    .environmentObject(accessController)
                    .overlay {
                        if isShowingSplash {
                            TuneAVSplashView()
                                .transition(.opacity)
                                .zIndex(1)
                        }
                    }
                    .task {
                        await showInitialSplashIfNeeded()
                    }
            }
        }
        .tint(TuneAVTheme.highlight)
        .task(id: scenePhase) {
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
            authOptionsArePresented = false

            if accessController.accessMode != .guest {
                automaticGuestOnboardingIsPresented = false
                isShowingAccountOnboarding = false
            } else {
                cancelScheduledLibrarySync()
                libraryStore.setAppDataService(nil)
                libraryStore.setBackendService(nil)
                clearTuneBackendService()
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        guard !launchContext.shouldDisableOnboarding else { return false }
        return isShowingAccountOnboarding || automaticGuestOnboardingIsPresented
    }

    private func startSignInFlow(showAuthOptions: Bool = false) {
        authOptionsArePresented = showAuthOptions
        isShowingAccountOnboarding = true
    }

    private func startAppleSignIn() async throws {
        try await accessController.accountService.signInWithApple()
        automaticGuestOnboardingIsPresented = false
        await accessController.syncFromAccountProvider()
        await refreshLibrarySync()
        isShowingAccountOnboarding = false
    }

    private func startGoogleSignIn() async throws {
        try await accessController.accountService.signInWithGoogle()
        automaticGuestOnboardingIsPresented = false
        await accessController.syncFromAccountProvider()
        await refreshLibrarySync()
        isShowingAccountOnboarding = false
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

        libraryStore.setBackendService(appDataService)
        libraryStore.setAppDataService(appDataService)
        await libraryStore.refreshUserSummary()
        await libraryStore.refreshCloudLibraryIfNeeded()
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

    private func refreshTuneBackendService() async {
        guard let backendService = configuredTuneBackendService() else {
            libraryStore.setBackendService(nil)
            return
        }

        libraryStore.setBackendService(backendService)
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

    private func showInitialSplashIfNeeded() async {
        guard !launchContext.shouldDisableSplash, !hasShownSplashThisLaunch else {
            isShowingSplash = false
            return
        }

        hasShownSplashThisLaunch = true
        let startedAt = Date()
        isShowingSplash = true
        try? await Task.sleep(for: .milliseconds(1650))

        await MainActor.run {
            withAnimation(.easeOut(duration: 0.35)) {
                isShowingSplash = false
            }
        }
        logStartupOperation("splash", startedAt: startedAt)
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
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TuneAVTheme.textInverse)
                    .frame(width: 48, height: 48)
                    .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("limits.upgrade.eyebrow"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .textCase(.uppercase)

                    Text(prompt.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                }
            }

            Text(prompt.message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TuneAVTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("limits.upgrade.message")

            VStack(spacing: 12) {
                Button(action: onPrimaryAction) {
                    Text(primaryButtonTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(TuneAVTheme.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(isGuest && !accountIsAvailable)
                .accessibilityIdentifier("limits.upgrade.primary")

                Button(action: onDismiss) {
                    Text(L10n.string("limits.upgrade.notNow"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(TuneAVTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityIdentifier("limits.upgrade.dismiss")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("limits.upgrade.sheet.\(prompt.feature.rawValue)")
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
