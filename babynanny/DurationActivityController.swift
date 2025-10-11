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
enum DurationActivityController {
    static func request(
        profileName: String?,
        actions: [DurationActivityAttributes.ContentState.RunningAction]
    ) async throws -> Activity<DurationActivityAttributes> {
        let attributes = DurationActivityAttributes(profileName: profileName)
        let content = DurationActivityAttributes.ContentState(actions: actions, updatedAt: Date())
        return try Activity.request(
            attributes: attributes,
            content: .init(state: content, staleDate: nil),
            pushType: nil
        )
    }

    static func updateAll(_ actions: [DurationActivityAttributes.ContentState.RunningAction]) async {
        let state = DurationActivityAttributes.ContentState(actions: actions, updatedAt: Date())
        for activity in Activity<DurationActivityAttributes>.activities {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    static func endAll() async {
        for activity in Activity<DurationActivityAttributes>.activities {
            await activity.end(
                .init(state: activity.content.state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}

@available(iOS 17.0, *)
extension DurationActivityAttributes.ContentState.RunningAction {
    init(action: BabyAction) {
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
