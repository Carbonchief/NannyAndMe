import Foundation
import PostHog

/// Lightweight PostHog helper for manual analytics instrumentation.
enum Analytics {
    static func setup() {
        var config = PostHogConfig(
            apiKey: "phc_LnHkvLd42Z0HUUa1DWyq7fGkrDXoXzKO2AuORKfqqwP",
            host: "https://eu.i.posthog.com"
        )

        // SwiftUI-friendly config:
        config.captureApplicationLifecycleEvents = true
        config.captureElementInteractions = true       // limited in SwiftUI; harmless to leave on
        config.captureScreenViews = false              // we will do manual screen events
        config.sessionReplay = .disabled               // enable later if you want
        config.flushAt = 10
        config.flushInterval = 10

        PostHogSDK.shared.setup(config)
    }

    static func identify(userId: String?, properties: [String: Any] = [:]) {
        if let userId = userId, !userId.isEmpty {
            PostHogSDK.shared.identify(userId, properties: properties)
        } else {
            PostHogSDK.shared.identify(properties: properties)
        }
    }

    static func capture(_ event: String, properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    static func screen(_ name: String, properties: [String: Any] = [:]) {
        // PostHog iOS sends `$screen` with name in properties
        var props = properties
        props["$screen_name"] = name
        PostHogSDK.shared.capture("$screen", properties: props)
    }
}
