import AppIntents
import Foundation

private enum DurationIntentError: LocalizedError {
    case invalidIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            return String(localized: "intent.duration.invalidIdentifier", defaultValue: "Unable to stop the selected action.")
        }
    }
}

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

    func perform() async throws -> some IntentResult & OpensIntent & ReturnsValue<Void> {
        guard let uuid = UUID(uuidString: actionID) else {
            throw DurationIntentError.invalidIdentifier
        }

        guard let url = URL(string: "nannyme://activity/\(uuid.uuidString)/stop") else {
            throw DurationIntentError.invalidIdentifier
        }

        return IntentResult<Void>.result(value: (), opens: url)
    }
}
