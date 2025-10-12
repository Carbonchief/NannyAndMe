import ActivityKit
import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct StopRunningActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Action"

    @Parameter(title: "Action Identifier")
    var actionID: String

    init() {}

    init(actionID: UUID) {
        self.actionID = actionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let dataStore = DurationDataStore()

        do {
            guard let uuid = UUID(uuidString: actionID) else {
                return .result()
            }

            try dataStore.stopAction(withID: uuid)
            await updateLiveActivity(afterStoppingActionWithID: uuid)
            await reloadDurationWidgets()
        } catch DurationDataStore.StopActionError.actionNotFound {
            return .result()
        } catch DurationDataStore.StopActionError.stateUnavailable {
            return .result()
        }

        return .result()
    }
}

@available(iOS 17.0, *)
private extension StopRunningActionIntent {
    func updateLiveActivity(afterStoppingActionWithID actionID: UUID) async {
        let activities = Activity<DurationActivityAttributes>.activities

        guard let activity = activities.first(where: { activity in
            activity.content.state.actions.contains(where: { $0.id == actionID })
        }) else { return }

        let currentContent = activity.content
        var newState = currentContent.state
        newState.actions.removeAll(where: { $0.id == actionID })
        newState.updatedAt = Date()

        let updatedContent = ActivityContent(
            state: newState,
            staleDate: currentContent.staleDate
        )

        if newState.actions.isEmpty {
            await activity.end(updatedContent, dismissalPolicy: .immediate)
        } else {
            await activity.update(updatedContent)
        }
    }

    func reloadDurationWidgets() async {
        await MainActor.run {
            let center = WidgetCenter.shared
            center.reloadTimelines(ofKind: DurationActivity().kind)
            center.reloadTimelines(ofKind: DurationActivityControl.kind)
        }
    }
}
