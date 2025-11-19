import Foundation
import UIKit

enum ActionHaptics {
    @MainActor
    static func playLogSuccess() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    private static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: UserDefaultsKey.actionHapticsEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: UserDefaultsKey.actionHapticsEnabled)
    }
}
