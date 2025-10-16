import Foundation

extension TimeZone {
    static let utc = TimeZone(secondsFromGMT: 0)!
}

extension Date {
    private static let utcFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .utc
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Normalizes the date using an ISO-8601 representation in UTC to ensure
    /// SwiftData persistence always stores the timestamp without a local
    /// timezone offset.
    func normalizedToUTC() -> Date {
        let formatter = Date.utcFormatter
        let stringRepresentation = formatter.string(from: self)
        return formatter.date(from: stringRepresentation) ?? self
    }
}
