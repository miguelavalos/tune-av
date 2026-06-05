import Foundation

typealias ResolvedAccess = TuneAVResolvedAccess

struct AccountSession: Equatable {
    let user: AccountUser
    let planTier: PlanTier
    let accessMode: AccessMode
    let capabilities: AccessCapabilities
}

struct AccountUser: Codable, Equatable {
    let id: String
    let displayName: String
    let emailAddress: String?

    var initials: String {
        TuneAVInitials.make(from: displayName)
    }
}
