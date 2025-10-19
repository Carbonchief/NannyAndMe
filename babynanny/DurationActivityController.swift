#if canImport(ActivityKit)
import ActivityKit
import Foundation
import SwiftData

@available(iOS 17.0, *)
enum DurationActivityController {
    /// Requests or updates the live activity for the supplied action. The
    /// caller must supply a `ModelContext` that owns the `model` to keep the
    /// SwiftData hierarchy consistent while we derive display values.
    @MainActor
    static func synchronizeActivity(for model: BabyActionModel) async {
        guard ActivityAuthorizationInfo.areActivitiesEnabled else {
            await endActivities(excluding: [])
            return
        }

        let state = model.makeContentState()

        if let existing = existingActivity(for: model.id) {
            await existing.update(using: state)
            if state.endDate != nil {
                await existing.end(using: state, dismissalPolicy: .immediate)
            }
        } else if state.endDate == nil {
            do {
                _ = try await Activity<DurationAttributes>.request(
                    attributes: DurationAttributes(activityID: model.id),
                    contentState: state,
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
            await activity.end(using: activity.content.state, dismissalPolicy: .immediate)
        }
    }

    /// Restores the Live Activity state from SwiftData when the app launches.
    /// This scans for any active actions (endDate == nil) and ensures the Live
    /// Activity tree reflects them.
    @MainActor
    static func syncAllActiveActivities(in context: ModelContext) async {
        guard ActivityAuthorizationInfo.areActivitiesEnabled else {
            await endActivities(excluding: [])
            return
        }

        let descriptor = FetchDescriptor<BabyActionModel>()
        let models = (try? context.fetch(descriptor)) ?? []
        let running = models.filter { $0.endDate == nil && $0.category.isInstant == false }
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
            profileDisplayName: profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            actionType: category.title,
            startDate: startDate,
            endDate: endDate,
            notePreview: nil
        )
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
#endif
