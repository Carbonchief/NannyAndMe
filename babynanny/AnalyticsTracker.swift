import Foundation
import PostHog

enum AnalyticsTracker {
    static func capture(_ event: String, properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    static func identifyUser(email: String) {
        PostHogSDK.shared.identify(email)
    }
}
