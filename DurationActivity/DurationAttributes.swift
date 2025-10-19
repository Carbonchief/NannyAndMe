import ActivityKit
import Foundation

/// Attributes shared between the live activity extension and the main app.
/// Keep this file in sync with `babynanny/Duration/DurationAttributes.swift`.
struct DurationAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var activityID: UUID
        var profileDisplayName: String?
        var actionType: String
        var actionIconSystemName: String?
        /// Hex encoded accent color matching the action's category/subtype.
        var actionAccentColorHex: String?
        var startDate: Date
        var endDate: Date?
        var notePreview: String?
    }

    var activityID: UUID
}
