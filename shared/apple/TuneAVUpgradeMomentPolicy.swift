import Foundation

/// Decides when to show the one-time contextual upgrade moment to Guest and Free listeners:
/// after the 10th distinct song discovered in the current app session, or on the 3rd distinct day
/// the person listens with Tune AV. Whichever comes first is shown once and remembered in `UserDefaults`.
struct TuneAVUpgradeMomentPolicy {
    enum Trigger: String, Equatable {
        case tenthDiscoveredTrack
        case thirdListeningDay
    }

    static let discoveredTrackThreshold = 10
    static let listeningDayThreshold = 3
    static let shownKey = "tuneav.upgradeMoment.shown"
    static let listeningDaysKey = "tuneav.upgradeMoment.listeningDays"

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var sessionDiscoveredTrackKeys: Set<String> = []

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    var hasBeenShown: Bool {
        defaults.bool(forKey: Self.shownKey)
    }

    var sessionDiscoveredTrackCount: Int {
        sessionDiscoveredTrackKeys.count
    }

    var listeningDayCount: Int {
        storedListeningDays.count
    }

    /// Records one discovered song for this session. Returns the trigger exactly once, when the 10th
    /// distinct song is recorded and the moment has not been shown before.
    mutating func noteDiscoveredTrack(key: String, isEligible: Bool) -> Trigger? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty else { return nil }
        sessionDiscoveredTrackKeys.insert(normalizedKey)
        guard isEligible, !hasBeenShown else { return nil }
        guard sessionDiscoveredTrackKeys.count >= Self.discoveredTrackThreshold else { return nil }
        markShown()
        return .tenthDiscoveredTrack
    }

    /// Records that the person listened on `date`. Returns the trigger exactly once, on the 3rd distinct
    /// calendar day, when the moment has not been shown before.
    mutating func noteListeningDay(_ date: Date, isEligible: Bool) -> Trigger? {
        let dayIdentifier = Self.dayIdentifier(for: date, calendar: calendar)
        var days = storedListeningDays
        if !days.contains(dayIdentifier) {
            days.append(dayIdentifier)
            defaults.set(Array(days.suffix(Self.listeningDayThreshold)), forKey: Self.listeningDaysKey)
        }
        guard isEligible, !hasBeenShown else { return nil }
        guard days.count >= Self.listeningDayThreshold else { return nil }
        markShown()
        return .thirdListeningDay
    }

    private var storedListeningDays: [String] {
        defaults.stringArray(forKey: Self.listeningDaysKey) ?? []
    }

    private func markShown() {
        defaults.set(true, forKey: Self.shownKey)
    }

    private static func dayIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

extension UpgradePrompt {
    /// Contextual upgrade moment copy. Uses `.aviAction` as the carrier feature so the existing limit sheet
    /// identifiers and primary action (open the paywall) apply unchanged.
    static func upgradeMoment(_ trigger: TuneAVUpgradeMomentPolicy.Trigger) -> UpgradePrompt {
        switch trigger {
        case .tenthDiscoveredTrack:
            UpgradePrompt(
                feature: .aviAction,
                title: L10n.string("limits.upgrade.moment.discoveries.title"),
                message: L10n.string("limits.upgrade.moment.discoveries.message", TuneAVUpgradeMomentPolicy.discoveredTrackThreshold)
            )
        case .thirdListeningDay:
            UpgradePrompt(
                feature: .aviAction,
                title: L10n.string("limits.upgrade.moment.days.title"),
                message: L10n.string("limits.upgrade.moment.days.message")
            )
        }
    }
}
