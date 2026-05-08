import Foundation

struct FeatureLimitState: Equatable {
    let feature: LimitedFeature
    let currentUsage: Int
    let limit: Int?
    private let allowedOverride: Bool?

    init(feature: LimitedFeature, currentUsage: Int, limit: Int?, allowedOverride: Bool? = nil) {
        self.feature = feature
        self.currentUsage = currentUsage
        self.limit = limit
        self.allowedOverride = allowedOverride
    }

    var isLimited: Bool {
        limit != nil
    }

    var isAllowed: Bool {
        if let allowedOverride {
            return allowedOverride
        }
        guard let limit else { return true }
        return currentUsage < limit
    }

    var remaining: Int? {
        guard let limit else { return nil }
        return max(limit - currentUsage, 0)
    }
}

struct TuneAVDailyUsageLimiter {
    enum KeyStyle {
        case dayBucket(prefix: String)
        case dateScoped(prefix: String)
    }

    private let defaults: UserDefaults
    private let keyStyle: KeyStyle
    private let now: () -> Date
    private let limitedFeatures: Set<LimitedFeature>?

    init(
        defaults: UserDefaults = .standard,
        keyStyle: KeyStyle,
        limitedFeatures: Set<LimitedFeature>? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.keyStyle = keyStyle
        self.limitedFeatures = limitedFeatures
        self.now = now
    }

    func limitState(for feature: LimitedFeature, limit: Int?) -> FeatureLimitState {
        FeatureLimitState(feature: feature, currentUsage: usageCount(for: feature), limit: resolvedLimit(for: feature, limit: limit))
    }

    func canUse(_ feature: LimitedFeature, limit: Int?) -> Bool {
        limitState(for: feature, limit: limit).isAllowed
    }

    func canUse(_ feature: LimitedFeature, limit: Int?, usageKey: String) -> Bool {
        let bucket = usageBucket(for: feature)
        if bucket.usageKeys.contains(Self.normalizedUsageKey(usageKey)) {
            return true
        }

        return FeatureLimitState(
            feature: feature,
            currentUsage: bucket.count,
            limit: resolvedLimit(for: feature, limit: limit)
        ).isAllowed
    }

    func recordUse(_ feature: LimitedFeature) {
        guard isTracked(feature) else { return }
        let bucket = usageBucket(for: feature)
        write(dayIdentifier: bucket.dayIdentifier, count: bucket.count + 1, usageKeys: nil, for: feature)
    }

    func recordUse(_ feature: LimitedFeature, usageKey: String) {
        guard isTracked(feature) else { return }
        let normalizedUsageKey = Self.normalizedUsageKey(usageKey)
        guard !normalizedUsageKey.isEmpty else {
            recordUse(feature)
            return
        }

        var bucket = usageBucket(for: feature)
        guard !bucket.usageKeys.contains(normalizedUsageKey) else { return }

        bucket.usageKeys.insert(normalizedUsageKey)
        let sortedUsageKeys = bucket.usageKeys.sorted()
        write(
            dayIdentifier: bucket.dayIdentifier,
            count: max(bucket.count + 1, sortedUsageKeys.count),
            usageKeys: sortedUsageKeys,
            for: feature
        )
    }

    func useIfAllowed(_ feature: LimitedFeature, limit: Int?) -> FeatureLimitState {
        let state = limitState(for: feature, limit: limit)
        guard state.isAllowed else { return state }
        recordUse(feature)
        return state
    }

    func useIfAllowed(_ feature: LimitedFeature, limit: Int?, usageKey: String) -> FeatureLimitState {
        let normalizedUsageKey = Self.normalizedUsageKey(usageKey)
        guard !normalizedUsageKey.isEmpty else {
            return useIfAllowed(feature, limit: limit)
        }

        let bucket = usageBucket(for: feature)
        if bucket.usageKeys.contains(normalizedUsageKey) {
            return FeatureLimitState(
                feature: feature,
                currentUsage: bucket.count,
                limit: resolvedLimit(for: feature, limit: limit),
                allowedOverride: true
            )
        }

        let state = FeatureLimitState(feature: feature, currentUsage: bucket.count, limit: resolvedLimit(for: feature, limit: limit))
        guard state.isAllowed else { return state }
        recordUse(feature, usageKey: usageKey)
        return state
    }

    func usageCount(for feature: LimitedFeature) -> Int {
        guard isTracked(feature) else { return 0 }
        return usageBucket(for: feature).count
    }

    func clearUsage(for features: Set<LimitedFeature>) {
        for feature in features {
            defaults.removeObject(forKey: countKey(for: feature))
            defaults.removeObject(forKey: keysKey(for: feature))
            if let dayKey = dayKey(for: feature) {
                defaults.removeObject(forKey: dayKey)
            }
        }
    }

    static func normalizedUsageKey(_ usageKey: String) -> String {
        usageKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func usageBucket(for feature: LimitedFeature) -> (dayIdentifier: String, count: Int, usageKeys: Set<String>) {
        let dayIdentifier = Self.dayIdentifier(for: now())

        if let dayKey = dayKey(for: feature) {
            let storedDay = defaults.string(forKey: dayKey)
            guard storedDay == dayIdentifier else {
                return (dayIdentifier, 0, [])
            }
        }

        let usageKeys = Set(
            defaults.stringArray(forKey: keysKey(for: feature))?
                .map(Self.normalizedUsageKey)
                .filter { !$0.isEmpty } ?? []
        )
        return (dayIdentifier, max(defaults.integer(forKey: countKey(for: feature)), usageKeys.count), usageKeys)
    }

    private func write(dayIdentifier: String, count: Int, usageKeys: [String]?, for feature: LimitedFeature) {
        if let dayKey = dayKey(for: feature) {
            defaults.set(dayIdentifier, forKey: dayKey)
        }
        defaults.set(count, forKey: countKey(for: feature))
        if let usageKeys {
            defaults.set(usageKeys, forKey: keysKey(for: feature))
        }
    }

    private func resolvedLimit(for feature: LimitedFeature, limit: Int?) -> Int? {
        guard isTracked(feature) else { return nil }
        return limit
    }

    private func isTracked(_ feature: LimitedFeature) -> Bool {
        limitedFeatures?.contains(feature) ?? true
    }

    private func dayKey(for feature: LimitedFeature) -> String? {
        switch keyStyle {
        case .dayBucket(let prefix):
            return "\(prefix)\(feature.rawValue).day"
        case .dateScoped:
            return nil
        }
    }

    private func countKey(for feature: LimitedFeature) -> String {
        switch keyStyle {
        case .dayBucket(let prefix):
            return "\(prefix)\(feature.rawValue).count"
        case .dateScoped(let prefix):
            return "\(prefix)\(feature.rawValue).\(Self.dayIdentifier(for: now()))"
        }
    }

    private func keysKey(for feature: LimitedFeature) -> String {
        "\(countKey(for: feature)).keys"
    }

    private static func dayIdentifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
