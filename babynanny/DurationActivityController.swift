#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 17.0, *)
struct DurationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        struct RunningAction: Codable, Hashable, Identifiable {
            var id: UUID
            var category: DurationActivityCategory
            var title: String
            var subtitle: String?
            var subtypeWord: String?
            var startDate: Date
            var iconSystemName: String
        }

        var actions: [RunningAction]
        var updatedAt: Date
    }

    var profileName: String?
}

@available(iOS 17.0, *)
enum DurationActivityCategory: String, Codable, Hashable {
    case sleep
    case diaper
    case feeding
}

@available(iOS 17.0, *)
@MainActor
final class DurationActivityController {
    static let shared = DurationActivityController()

    private var activity: Activity<DurationActivityAttributes>?

    private init() {}

    func update(for profileName: String?, actions: [BabyActionSnapshot]) {
        let authorization = ActivityAuthorizationInfo()
        guard authorization.areActivitiesEnabled else {
            endActivity()
            return
        }

        let runningActions = actions
            .filter { !$0.category.isInstant && $0.endDate == nil }
            .sorted(by: { $0.startDate < $1.startDate })
            .map(DurationActivityAttributes.ContentState.RunningAction.init)

        guard runningActions.isEmpty == false else {
            endActivity()
            return
        }

        if let activity,
           activity.attributes.profileName != profileName {
            endActivity()
        }

        let contentState = DurationActivityAttributes.ContentState(
            actions: runningActions,
            updatedAt: Date()
        )

        let content = ActivityContent(
            state: contentState,
            staleDate: activity?.content.staleDate
        )

        if let activity {
            Task {
                await activity.update(content)
            }
        } else {
            let attributes = DurationActivityAttributes(profileName: profileName)

            do {
                activity = try Activity<DurationActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                #if DEBUG
                print("Failed to start DurationActivity: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func endActivity() {
        guard let activity else { return }

        Task {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }

        self.activity = nil
    }
}

@available(iOS 17.0, *)
private extension DurationActivityAttributes.ContentState.RunningAction {
    init(action: BabyActionSnapshot) {
        id = action.id
        category = DurationActivityCategory(rawValue: action.category.rawValue) ?? .sleep
        title = action.category.title

        let detail = action.detailDescription
        subtitle = detail == action.category.title ? nil : detail
        subtypeWord = action.subtypeWord
        startDate = action.startDate
        iconSystemName = action.icon
    }
}
#endif
