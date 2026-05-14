import Foundation

enum TuneAVDateCoding {
    private static let formatterLock = NSLock()
    private nonisolated(unsafe) static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private nonisolated(unsafe) static let internetFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date {
        formatterLock.lock()
        defer { formatterLock.unlock() }

        return fractionalFormatter.date(from: value) ??
            internetFormatter.date(from: value) ??
            .distantPast
    }

    static func string(from date: Date) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }

        return fractionalFormatter.string(from: date)
    }

    static func dayIdentifier(for date: Date = .now, timeZone: TimeZone = .current) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: timeZone, formatOptions: [.withFullDate])
    }

}
