import AccountAV
import Foundation
import OSLog

@MainActor
final class MacAccountController: ObservableObject {
    @Published private(set) var currentUser: AccountAVUser?
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let accountService: AccountAVService
    private let logger = Logger(subsystem: "com.avalsys.tuneav.mac", category: "auth")

    init() {
        self.accountService = ClerkAccountAVService(
            publishableKeyProvider: { MacAppConfig.avAccountKey },
            fallbackDisplayName: "Tune AV Listener",
            loggerSubsystem: "com.avalsys.tuneav.mac"
        )
        self.currentUser = accountService.currentUser
    }

    init(
        accountService: AccountAVService
    ) {
        self.accountService = accountService
        self.currentUser = accountService.currentUser
    }

    var isAvailable: Bool {
        accountService.isAvailable
    }

    var isSignedIn: Bool {
        currentUser != nil
    }

    func currentToken() async throws -> String? {
        try await accountService.getToken()
    }

    func refreshSession() async {
        guard isAvailable else {
            currentUser = nil
            return
        }

        do {
            _ = try await accountService.getToken()
            currentUser = accountService.currentUser
            errorMessage = nil
        } catch {
            logger.error("Unable to refresh Account AV session: \(String(reflecting: error), privacy: .public)")
            currentUser = accountService.currentUser
        }
    }

    func signInWithApple() async -> Bool {
        await runAuthentication {
            try await accountService.signInWithApple()
        }
    }

    func signInWithGoogle() async -> Bool {
        await runAuthentication {
            try await accountService.signInWithGoogle()
        }
    }

    func signOut() async -> Bool {
        await runAuthentication {
            try await accountService.signOut()
        }
    }

    private func runAuthentication(_ operation: () async throws -> Void) async -> Bool {
        guard isAvailable else {
            errorMessage = AccountAVError.unavailable.localizedDescription
            return false
        }
        guard !isAuthenticating else { return false }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await operation()
            currentUser = accountService.currentUser
            errorMessage = nil
            return true
        } catch {
            logger.error("Account AV operation failed: \(String(reflecting: error), privacy: .public)")
            currentUser = accountService.currentUser
            errorMessage = error.localizedDescription
            return false
        }
    }
}
