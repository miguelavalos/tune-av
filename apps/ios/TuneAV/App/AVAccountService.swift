import AccountAV
import Foundation

@MainActor
protocol AVAccountService {
    var isAvailable: Bool { get }
    var currentUser: AccountUser? { get }

    func getToken() async throws -> String?
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    func signOut() async throws
}

enum AVAccountServiceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            L10n.string("account.error.unavailable")
        }
    }
}

struct DefaultAVAccountService: AVAccountService {
    private let accountService = ClerkAccountAVService(
        publishableKeyProvider: { AppConfig.avAccountKey },
        fallbackDisplayName: L10n.string("account.displayName.listener"),
        loggerSubsystem: "com.avalsys.tuneav"
    )

    var isAvailable: Bool {
        guard !Self.shouldForceGuestForUITests else { return false }
        if Self.uiTestAccountUser != nil { return true }
        return accountService.isAvailable
    }

    var currentUser: AccountUser? {
        guard !Self.shouldForceGuestForUITests else { return nil }
        if let uiTestAccountUser = Self.uiTestAccountUser {
            return uiTestAccountUser
        }
        guard let user = accountService.currentUser else { return nil }
        return AccountUser(
            id: user.id,
            displayName: user.displayName,
            emailAddress: user.emailAddress
        )
    }

    func getToken() async throws -> String? {
        try await accountService.getToken()
    }

    func signInWithApple() async throws {
        guard isAvailable else {
            throw AVAccountServiceError.unavailable
        }
        try await accountService.signInWithApple()
    }

    func signInWithGoogle() async throws {
        guard isAvailable else {
            throw AVAccountServiceError.unavailable
        }
        try await accountService.signInWithGoogle()
    }

    func signOut() async throws {
        guard isAvailable else { return }
        try await accountService.signOut()
    }

    private static var shouldForceGuestForUITests: Bool {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["TUNEAV_UI_TESTS"] == "1"
        return isUITesting && environment["TUNEAV_UI_TESTS_FORCE_GUEST"] == "1"
    }

    private static var uiTestAccountUser: AccountUser? {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["TUNEAV_UI_TESTS"] == "1"
        guard isUITesting else { return nil }
        guard environment["TUNEAV_UI_TESTS_ACCOUNT_MODE"] != nil else { return nil }

        return AccountUser(
            id: "ui-test-user",
            displayName: "UI Test User",
            emailAddress: "ui-test@example.test"
        )
    }
}
