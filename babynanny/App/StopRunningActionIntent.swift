import ActivityKit
import AppIntents
import os

@available(iOS 17.0, *)
struct StopRunningActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Running Action"

    @Parameter(title: "Action ID")
    var actionID: String

    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "LiveActivities")

    init() {}
    init(actionID: UUID) { self.actionID = actionID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        logger.debug("StopRunningActionIntent invoked for id: \(self.actionID, privacy: .public)")

        guard let actionUUID = UUID(uuidString: actionID) else {
            logger.error("Invalid action identifier supplied: \(self.actionID, privacy: .public)")
            return .result()
        }

        var current = RunningActionStore.load()
        let beforeCount = current.count
        current.removeAll { $0.id == actionUUID }
        logger.debug("Removed action? \(beforeCount != current.count)")

        RunningActionStore.save(current)

        let mapped = current.map(DurationActivityAttributes.ContentState.RunningAction.init)

        if mapped.isEmpty {
            await DurationActivityController.endAll()
        } else {
            await DurationActivityController.updateAll(mapped)
        }

        return .result()
    }
}
