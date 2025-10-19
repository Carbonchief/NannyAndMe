import AppIntents
import Foundation

@available(iOS 17.0, *)
struct StopRunningActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Action"
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Action Identifier")
    var actionID: String

    init() {}

    init(actionID: UUID) {
        self.actionID = actionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        // The live activity is driven by SwiftData. We immediately hand off to
        // the app so the underlying model is updated before the activity ends.
        return .result()
    }
}
