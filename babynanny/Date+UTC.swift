import Foundation

private struct ISO8601FormatterBox: @unchecked Sendable {
    let formatter: ISO8601DateFormatter

    init(configure: (ISO8601DateFormatter) -> Void) {
        let formatter = ISO8601DateFormatter()
        configure(formatter)
        self.formatter = formatter
    }
}

extension TimeZone {
    static let utc = TimeZone(secondsFromGMT: 0)!
}

extension Date {
    private static let utcFormatterBox = ISO8601FormatterBox { formatter in
        formatter.timeZone = .utc
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    private static var utcFormatter: ISO8601DateFormatter {
        utcFormatterBox.formatter
    }

    /// Normalizes the date using an ISO-8601 representation in UTC to ensure
    /// SwiftData persistence always stores the timestamp without a local
    /// timezone offset.
    func normalizedToUTC() -> Date {
        let formatter = Date.utcFormatter
        let stringRepresentation = formatter.string(from: self)
        return formatter.date(from: stringRepresentation) ?? self
    }
}
