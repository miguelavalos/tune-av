import Foundation

struct MacCloudSyncTrigger {
    enum Action: Equatable {
        case schedule(Duration)
        case cancel
        case none
    }

    static let startupDelay: Duration = .seconds(1)
    static let localChangeDelay: Duration = .seconds(5)

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
