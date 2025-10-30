import Foundation

extension TimeZone {
    static let utc = TimeZone(secondsFromGMT: 0)!
}

extension Date {
    private static let utcFormatStyle = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
        timeZone: .utc
    )

    /// Normalizes the date using an ISO-8601 representation in UTC to ensure
    /// SwiftData persistence always stores the timestamp without a local
    /// timezone offset.
    func normalizedToUTC() -> Date {
        let style = Date.utcFormatStyle
        let stringRepresentation = self.formatted(style)
        return (try? Date(stringRepresentation, strategy: style)) ?? self
    }
}
