import Foundation

enum TuneAVDateCoding {
    static func date(from value: String) -> Date {
        iso8601Formatter(includingFractionalSeconds: true).date(from: value) ??
            iso8601Formatter(includingFractionalSeconds: false).date(from: value) ??
            .distantPast
    }

    static func string(from date: Date) -> String {
        iso8601Formatter(includingFractionalSeconds: true).string(from: date)
    }

    static func dayIdentifier(for date: Date = .now, timeZone: TimeZone = .current) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: timeZone, formatOptions: [.withFullDate])
    }

    private static func iso8601Formatter(includingFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includingFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
