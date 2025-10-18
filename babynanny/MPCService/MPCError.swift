import Foundation

/// Domain errors thrown by the MPC service layer.
enum MPCError: Error, LocalizedError, Equatable {
    case invalidState(expected: String, actual: String)
    case invitationRejected
    case sessionFailed
    case encodingFailed
    case decodingFailed
    case unsupportedEnvelopeVersion(current: Int, received: Int)
    case transferCancelled
    case resourceNotFound
    case timeout

    var errorDescription: String? {
        switch self {
        case let .invalidState(expected, actual):
            return "Expected state \(expected) but found \(actual)."
        case .invitationRejected:
            return "The invitation was rejected by the remote device."
        case .sessionFailed:
            return "The connection became unavailable."
        case .encodingFailed:
            return "Unable to prepare data for sending."
        case .decodingFailed:
            return "Received data could not be read."
        case let .unsupportedEnvelopeVersion(current, received):
            return "This app supports version \(current) but received \(received)."
        case .transferCancelled:
            return "The transfer was cancelled."
        case .resourceNotFound:
            return "The requested resource could not be located."
        case .timeout:
            return "The operation timed out before completion."
        }
    }
}
