import Foundation

enum MacAccountAccessRefreshPolicy {
    static func shouldResolveLocalAccessAfterActiveRestore(
        previousUserID: String?,
        restoredUserID: String
    ) -> Bool {
        previousUserID != restoredUserID
    }

    static func shouldResolveLocalAccessAfterUnavailableRestore(hasCurrentUser: Bool) -> Bool {
        !hasCurrentUser
    }
}

struct MacCloudSyncTrigger {
    enum Action: Equatable {
        case schedule(Duration)
        case cancel
        case none
    }

    static let startupDelay: Duration = .seconds(1)
    static let localChangeDelay: Duration = .seconds(5)
    /// Minimum spacing between automatic pulls triggered by app activation or system wake.
    static let foregroundSyncInterval: TimeInterval = 60

    private(set) var hasStarted = false
    private(set) var isApplyingCloudSnapshot = false

    mutating func startupCompleted(accountAvailable: Bool, hasUser: Bool, hasProAccess: Bool) -> Action {
        guard !hasStarted else { return .none }
        hasStarted = true
        return syncAction(accountAvailable: accountAvailable, hasUser: hasUser, hasProAccess: hasProAccess, delay: Self.startupDelay)
    }

    func signInCompleted(accountAvailable: Bool, hasUser: Bool, hasProAccess: Bool) -> Action {
        syncAction(accountAvailable: accountAvailable, hasUser: hasUser, hasProAccess: hasProAccess, delay: Self.startupDelay)
    }

    func localLibraryChanged(accountAvailable _: Bool, hasUser _: Bool, hasProAccess _: Bool) -> Action {
        .none
    }

    func foregroundActivated(
        accountAvailable: Bool,
        hasUser: Bool,
        hasProAccess: Bool,
        lastAutomaticSyncRequestedAt: Date?,
        now: Date = .now
    ) -> Action {
        guard hasStarted else { return .none }
        if let lastAutomaticSyncRequestedAt,
           now.timeIntervalSince(lastAutomaticSyncRequestedAt) < Self.foregroundSyncInterval {
            return .none
        }
        return syncAction(accountAvailable: accountAvailable, hasUser: hasUser, hasProAccess: hasProAccess, delay: Self.startupDelay)
    }

    func signOutStarted() -> Action {
        .cancel
    }

    mutating func setApplyingCloudSnapshot(_ isApplying: Bool) {
        isApplyingCloudSnapshot = isApplying
    }

    private func syncAction(accountAvailable: Bool, hasUser: Bool, hasProAccess: Bool, delay: Duration) -> Action {
        guard accountAvailable, hasUser, hasProAccess else { return .none }
        return .schedule(delay)
    }
}

struct MacCloudSyncExecutionGate {
    private(set) var isRunning = false
    private(set) var hasPendingFollowUp = false

    mutating func begin() -> Bool {
        guard !isRunning else {
            hasPendingFollowUp = true
            return false
        }

        isRunning = true
        hasPendingFollowUp = false
        return true
    }

    mutating func consumePendingFollowUp() -> Bool {
        guard hasPendingFollowUp else { return false }
        hasPendingFollowUp = false
        return true
    }

    mutating func finish() {
        isRunning = false
        hasPendingFollowUp = false
    }
}

