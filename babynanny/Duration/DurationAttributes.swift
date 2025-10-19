#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Attributes shared between the main app and the Duration live activity.
/// Keep this file in sync with `DurationActivity/DurationAttributes.swift`.
struct DurationAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        /// Stable identifier that matches the SwiftData `BabyActionModel`.
        var activityID: UUID
        /// Optional display name. We avoid exposing it when the profile prefers
        /// additional privacy.
        var profileDisplayName: String?
        /// Raw action type string (`BabyActionCategory.title`).
        var actionType: String
        /// Start date of the running action.
        var startDate: Date
        /// End date when the action is finished. `nil` while the action is
        /// active so the UI can show a live timer.
        var endDate: Date?
        /// Optional short note for the lock screen / Dynamic Island.
        var notePreview: String?
    }

    /// The identifier mirrors the SwiftData record. This lets the app link an
    /// activity that outlives process launches back to its database row.
    var activityID: UUID
}
#endif
