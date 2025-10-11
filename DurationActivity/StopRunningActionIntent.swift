import AppIntents
import Foundation

@available(iOS 17.0, *)
struct StopRunningActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Action"

    @Parameter(title: "Action Identifier")
    var actionID: UUID

    init() {}

    init(actionID: UUID) {
        self.actionID = actionID
    }

    func perform() async throws -> some IntentResult {
        let dataStore = DurationDataStore()

        do {
            try dataStore.stopAction(withID: actionID)
        } catch DurationDataStore.StopActionError.actionNotFound {
            return .result()
        } catch DurationDataStore.StopActionError.stateUnavailable {
            return .result()
        }

        return .result()
    }
}
