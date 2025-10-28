import Foundation

private final class ISO8601UTCFormatter: @unchecked Sendable {
    static let shared = ISO8601UTCFormatter()

    private let formatter: ISO8601DateFormatter
    private let lock = NSLock()

    private init() {
        formatter = ISO8601DateFormatter()
        formatter.timeZone = .utc
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }

    func date(from string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: string)
    }
}

extension TimeZone {
    static let utc = TimeZone(secondsFromGMT: 0)!
}

extension Date {
    private static let utcFormatter = ISO8601UTCFormatter.shared

    /// Normalizes the date using an ISO-8601 representation in UTC to ensure
    /// SwiftData persistence always stores the timestamp without a local
    /// timezone offset.
    func normalizedToUTC() -> Date {
        let formatter = Date.utcFormatter
        let stringRepresentation = formatter.string(from: self)
        return formatter.date(from: stringRepresentation) ?? self
    }
}
