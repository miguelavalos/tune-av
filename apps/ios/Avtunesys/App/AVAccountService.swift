import ClerkKit
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
    var isAvailable: Bool {
        guard !Self.shouldForceGuestForUITests else { return false }
        if Self.uiTestAccountUser != nil { return true }
        return AppConfig.isAVAccountAvailable
    }

    var currentUser: AccountUser? {
        guard !Self.shouldForceGuestForUITests else { return nil }
        if let uiTestAccountUser = Self.uiTestAccountUser {
            return uiTestAccountUser
        }
        guard isAvailable, let user = Clerk.shared.user else {
            return nil
        }

        let displayName =
            [user.firstName, user.lastName]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        return AccountUser(
            id: user.id,
            displayName: displayName.isEmpty ? L10n.string("account.displayName.listener") : displayName,
            emailAddress: user.primaryEmailAddress?.emailAddress
        )
    }

    func getToken() async throws -> String? {
        guard isAvailable, let session = Clerk.shared.session else {
            return nil
        }

        return try await session.getToken()
    }

    func signInWithApple() async throws {
        guard isAvailable else {
            throw AVAccountServiceError.unavailable
        }

        _ = try await Clerk.shared.auth.signInWithApple()
    }

    func signInWithGoogle() async throws {
        guard isAvailable else {
            throw AVAccountServiceError.unavailable
        }

        _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
    }

    func signOut() async throws {
        guard isAvailable else { return }
        try await Clerk.shared.auth.signOut()
    }

    private static var shouldForceGuestForUITests: Bool {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["AVTUNESYS_UI_TESTS"] == "1"
        return isUITesting && environment["AVTUNESYS_UI_TESTS_FORCE_GUEST"] == "1"
    }

    private static var uiTestAccountUser: AccountUser? {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["AVTUNESYS_UI_TESTS"] == "1"
        guard isUITesting else { return nil }
        guard environment["AVTUNESYS_UI_TESTS_ACCOUNT_MODE"] != nil else { return nil }

        return AccountUser(
            id: "ui-test-user",
            displayName: "UI Test User",
            emailAddress: "ui-test@example.test"
        )
    }
}
