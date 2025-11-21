import Foundation
import PostHog

@MainActor
enum AnalyticsTracker {
    static func capture(_ event: String, properties: [String: Any]? = nil) {
        guard AnalyticsConsentManager.shared.isAnalyticsEnabled else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    static func identifyUser(email: String) {
        guard AnalyticsConsentManager.shared.canTrackIdentifyingData else { return }
        PostHogSDK.shared.identify(email)
    }
}
