import AppIntents
import Foundation

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
        } catch DurationDataStore.StopActionError.actionNotFound {
            return .result()
        } catch DurationDataStore.StopActionError.stateUnavailable {
            return .result()
        }

        return .result()
    }
}
