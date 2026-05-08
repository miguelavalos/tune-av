import Foundation

struct GuestOnboardingPolicy {
    static let defaultCooldown: TimeInterval = 10 * 24 * 60 * 60

    let cooldown: TimeInterval

    init(cooldown: TimeInterval = Self.defaultCooldown) {
        self.cooldown = cooldown
    }

    func shouldShowAutomatically(lastPromptAt: Date?, now: Date) -> Bool {
        guard let lastPromptAt else { return true }
        return now >= lastPromptAt.addingTimeInterval(cooldown)
    }
}
