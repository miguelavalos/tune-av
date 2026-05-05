import Foundation
import OSLog

@MainActor
protocol EntitlementService {
    func resolveAccess(for user: AccountUser?) -> ResolvedAccess
    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess
}

@MainActor
struct LocalEntitlementService: EntitlementService {
    func resolveAccess(for user: AccountUser?) -> ResolvedAccess {
        if let uiTestAccess = Self.uiTestResolvedAccess() {
            return uiTestAccess
        }
        guard user != nil else { return .guest }
        return resolvedAccess(for: .free)
    }

    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess {
        resolveAccess(for: user)
    }

    private func resolvedAccess(for planTier: PlanTier) -> ResolvedAccess {
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
}

@MainActor
final class PlatformBackedEntitlementService: EntitlementService {
    private let fallback: EntitlementService
    private let apiClient: AVAccountAPIClient
    private let authLogger = Logger(subsystem: "com.avalsys.tuneav", category: "auth")

    init(
        fallback: EntitlementService = LocalEntitlementService(),
        apiClient: AVAccountAPIClient
    ) {
        self.fallback = fallback
        self.apiClient = apiClient
    }

    func resolveAccess(for user: AccountUser?) -> ResolvedAccess {
        fallback.resolveAccess(for: user)
    }

    func refreshAccess(for user: AccountUser?) async -> ResolvedAccess {
        guard user != nil else { return .guest }

        let fallbackAccess = await fallback.refreshAccess(for: user)
        guard !Self.shouldUseUITestAccessOverride else {
            return fallbackAccess
        }
        guard apiClient.isConfigured() else {
            authLogger.error("Unable to refresh Account AV access: missing API base URL")
            return fallbackAccess
        }

        do {
            authLogger.info("Refreshing Account AV access")
            let payload = try await apiClient.fetchMeAccess()
            guard let tuneAVAccess = payload.apps.first(where: { $0.appId == "tuneav" }) else {
                authLogger.error("Unable to refresh Account AV access: tuneav entry missing")
                return fallbackAccess
            }

            authLogger.info("Resolved Tune AV access mode \(tuneAVAccess.accessMode.rawValue, privacy: .public)")
            return ResolvedAccess(
                planTier: tuneAVAccess.planTier,
                accessMode: tuneAVAccess.accessMode,
                capabilities: tuneAVAccess.capabilities,
                limits: tuneAVAccess.limits
            )
        } catch {
            authLogger.error("Unable to refresh Account AV access: \(String(reflecting: error), privacy: .public)")
            return fallbackAccess
        }
    }

    private static var shouldUseUITestAccessOverride: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["TUNEAV_UI_TESTS"] == "1" &&
            environment["TUNEAV_UI_TESTS_ACCOUNT_MODE"] != nil
    }
}
