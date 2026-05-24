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

    mutating func startupCompleted(accountAvailable: Bool, hasUser: Bool) -> Action {
        guard !hasStarted else { return .none }
        hasStarted = true
        return syncAction(accountAvailable: accountAvailable, hasUser: hasUser, delay: Self.startupDelay)
    }

    func signInCompleted(accountAvailable: Bool, hasUser: Bool) -> Action {
        syncAction(accountAvailable: accountAvailable, hasUser: hasUser, delay: Self.startupDelay)
    }

    func localLibraryChanged(accountAvailable: Bool, hasUser: Bool) -> Action {
        guard !isApplyingCloudSnapshot else { return .none }
        return syncAction(accountAvailable: accountAvailable, hasUser: hasUser, delay: Self.localChangeDelay)
    }

    func signOutStarted() -> Action {
        .cancel
    }

    mutating func setApplyingCloudSnapshot(_ isApplying: Bool) {
        isApplyingCloudSnapshot = isApplying
    }

    private func syncAction(accountAvailable: Bool, hasUser: Bool, delay: Duration) -> Action {
        guard accountAvailable, hasUser else { return .none }
        return .schedule(delay)
    }
}
