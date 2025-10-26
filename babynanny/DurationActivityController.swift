#if canImport(ActivityKit)
import ActivityKit
import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, *)
enum DurationActivityController {
    /// Requests or updates the live activity for the supplied action. The
    /// caller must supply a `ModelContext` that owns the `model` to keep the
    /// SwiftData hierarchy consistent while we derive display values.
    @MainActor
    static func synchronizeActivity(for model: BabyActionModel) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endActivities(excluding: [])
            return
        }

        let existingActivity = existingActivity(for: model.id)

        guard model.profile != nil else {
            if let existingActivity {
                await existingActivity.end(
                    existingActivity.content,
                    dismissalPolicy: .immediate
                )
            }
            return
        }

        let state = model.makeContentState()
        let content = ActivityContent(state: state, staleDate: nil)

        if let existing = existingActivity {
            await existing.update(content)
            if state.endDate != nil {
                await existing.end(content, dismissalPolicy: .immediate)
            }
        } else if state.endDate == nil {
            do {
                _ = try Activity<DurationAttributes>.request(
                    attributes: DurationAttributes(activityID: model.id),
                    content: content,
                    pushType: nil
                )
            } catch {
                #if DEBUG
                print("Failed to start Duration live activity: \(error)")
                #endif
            }
        }
    }

    /// Ends all running activities whose identifiers are not present in the
    /// provided set. Useful after reconciling SwiftData changes.
    @MainActor
    static func endActivities(excluding activeIDs: Set<UUID>) async {
        for activity in Activity<DurationAttributes>.activities where activeIDs.contains(activity.attributes.activityID) == false {
            await activity.end(
                activity.content,
                dismissalPolicy: .immediate
            )
        }
    }

    /// Restores the Live Activity state from SwiftData when the app launches.
    /// This scans for any active actions (endDate == nil) and ensures the Live
    /// Activity tree reflects them.
    @MainActor
    static func syncAllActiveActivities(in context: ModelContext) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endActivities(excluding: [])
            return
        }

        let descriptor = FetchDescriptor<BabyActionModel>()
        let models = (try? context.fetch(descriptor)) ?? []
        let running = models.filter { model in
            model.endDate == nil &&
                model.category.isInstant == false &&
                model.profile != nil
        }
        let runningIDs = Set(running.map(\.id))

        for model in running {
            await synchronizeActivity(for: model)
        }

        await endActivities(excluding: runningIDs)
    }

    @MainActor
    private static func existingActivity(for id: UUID) -> Activity<DurationAttributes>? {
        Activity<DurationAttributes>.activities.first { $0.attributes.activityID == id }
    }
}

@available(iOS 17.0, *)
private extension BabyActionModel {
    func makeContentState() -> DurationAttributes.ContentState {
        DurationAttributes.ContentState(
            activityID: id,
            profileDisplayName: sanitizedProfileName,
            actionType: category.title,
            actionSubtype: asSnapshot().subtypeWord,
            actionIconSystemName: actionIconSystemName,
            actionAccentColorHex: actionAccentColorHex,
            startDate: startDate,
            endDate: endDate,
            notePreview: nil
        )
    }

    private var sanitizedProfileName: String? {
        let trimmed = profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.nilIfEmpty
    }

    private var actionIconSystemName: String {
        if let diaperType {
            return diaperType.icon
        }

        if let feedingType {
            return feedingType.icon
        }

        return category.icon
    }

    private var actionAccentColorHex: String? {
        category.accentColor.hexString()
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case .some(let value) where value.isEmpty == false:
            return value
        default:
            return nil
        }
    }
}

#if canImport(UIKit)
private extension Color {
    func hexString() -> String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        let a = Int(round(alpha * 255))

        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
#endif
#endif
