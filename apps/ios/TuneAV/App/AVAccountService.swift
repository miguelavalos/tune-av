import AccountAV
import Foundation

@MainActor
protocol AVAccountService {
    var isAvailable: Bool { get }
    var providerSessionUser: AccountUser? { get }

    func restoreSession() async -> AVAccountSessionRestoreResult
    func getToken() async throws -> String?
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    func signOut() async throws
}

enum AVAccountSessionRestoreResult: Equatable {
    case signedOut
    case active(AccountUser)
    case temporarilyUnavailable(AccountUser?)
    case invalidated
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

    var providerSessionUser: AccountUser? {
        guard !Self.shouldForceGuestForUITests else { return nil }
        if let uiTestAccountUser = Self.uiTestAccountUser {
            return uiTestAccountUser
        }
        return Self.accountUser(from: accountService.providerSessionUser)
    }

    func restoreSession() async -> AVAccountSessionRestoreResult {
        guard !Self.shouldForceGuestForUITests else { return .signedOut }
        if let uiTestAccountUser = Self.uiTestAccountUser {
            return .active(uiTestAccountUser)
        }

        switch await accountService.restoreSession() {
        case .signedOut:
            return .signedOut
        case .active(let user):
            guard let user = Self.accountUser(from: user) else { return .signedOut }
            return .active(user)
        case .temporarilyUnavailable(let user):
            return .temporarilyUnavailable(Self.accountUser(from: user))
        case .invalidated:
            return .invalidated
        }
    }

    func getToken() async throws -> String? {
        if Self.shouldUseGuestTokenForUITests {
            return nil
        }
        if Self.uiTestAccountUser != nil {
            return TuneAVUITestEnvironment.accountToken
        }
        return try await accountService.getToken()
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
        if Self.uiTestAccountUser != nil {
            return
        }
        guard isAvailable else { return }
        try await accountService.signOut()
    }

    private static var shouldForceGuestForUITests: Bool {
        TuneAVUITestEnvironment.current.shouldForceGuest
    }

    private static var shouldUseGuestTokenForUITests: Bool {
        let environment = TuneAVUITestEnvironment.current
        return environment.isEnabled && !environment.hasAccountOverride
    }

    private static var uiTestAccountUser: AccountUser? {
        guard TuneAVUITestEnvironment.current.hasAccountOverride else { return nil }

        return AccountUser(
            id: TuneAVUITestEnvironment.accountUserId,
            displayName: TuneAVUITestEnvironment.accountUserDisplayName,
            emailAddress: TuneAVUITestEnvironment.accountUserEmailAddress
        )
    }

    private static func accountUser(from user: AccountAVUser?) -> AccountUser? {
        guard let user else { return nil }
        return AccountUser(
            id: user.id,
            displayName: user.displayName,
            emailAddress: user.emailAddress
        )
    }
}
