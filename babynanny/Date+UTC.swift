import Foundation

extension TimeZone {
    static let utc = TimeZone(secondsFromGMT: 0)!
}

extension Date {
    private static let utcFormatStyle = ISO8601FormatStyle(timeZone: .utc)
        .includingFractionalSeconds()

    /// Normalizes the date using an ISO-8601 representation in UTC to ensure
    /// SwiftData persistence always stores the timestamp without a local
    /// timezone offset.
    func normalizedToUTC() -> Date {
        let style = Date.utcFormatStyle
        let stringRepresentation = style.format(self)

        do {
            return try style.parse(stringRepresentation)
        } catch {
            return self
        }
    }
}
