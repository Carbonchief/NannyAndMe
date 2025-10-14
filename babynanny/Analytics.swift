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
        config.captureElementInteractions = false      // manual instrumentation only
        config.captureScreenViews = false              // we will do manual screen events
        config.sessionReplay = false                   // enable later if you want
        config.flushAt = 10

        PostHogSDK.shared.setup(config)
    }

    static func identify(userId: String?, properties: [String: Any] = [:]) {
        let trimmed = userId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let distinctId = (trimmed?.isEmpty == false) ? trimmed : nil
        let nsProperties = properties.isEmpty ? nil : properties as NSDictionary

        guard let sdkObject = PostHogSDK.shared as? NSObject else {
            sendIdentifyFallback(distinctId: distinctId, properties: properties)
            return
        }

        if let distinctId = distinctId {
            if let nsProperties, sdkObject.performIfAvailable(selector: "identify:properties:", with: distinctId, and: nsProperties) {
                return
            }

            if sdkObject.performIfAvailable(selector: "identify:", with: distinctId) {
                if let nsProperties {
                    applyPersonProperties(nsProperties, on: sdkObject)
                }
                return
            }
        } else if let nsProperties {
            if sdkObject.performIfAvailable(selector: "identifyWithProperties:", with: nsProperties) {
                return
            }

            if sdkObject.performIfAvailable(selector: "identify:properties:", with: nil, and: nsProperties) {
                return
            }
        }

        sendIdentifyFallback(distinctId: distinctId, properties: properties)
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

private extension Analytics {
    static func applyPersonProperties(_ properties: NSDictionary, on sdkObject: NSObject) {
        guard properties.count > 0 else { return }
        if sdkObject.performIfAvailable(selector: "setPersonProperties:", with: properties) {
            return
        }

        let payload = ["$set": properties as? [String: Any] ?? [:]]
        PostHogSDK.shared.capture("$identify", properties: payload)
    }

    static func sendIdentifyFallback(distinctId: String?, properties: [String: Any]) {
        guard !properties.isEmpty else {
            if let distinctId, let sdkObject = PostHogSDK.shared as? NSObject {
                _ = sdkObject.performIfAvailable(selector: "identify:", with: distinctId)
            }
            return
        }

        var payload: [String: Any] = ["$set": properties]
        if let distinctId {
            payload["$distinct_id"] = distinctId
        }

        PostHogSDK.shared.capture("$identify", properties: payload)
    }
}

private extension NSObject {
    @discardableResult
    func performIfAvailable(selector: String, with firstArgument: Any?, and secondArgument: Any? = nil) -> Bool {
        let selector = NSSelectorFromString(selector)
        guard responds(to: selector) else { return false }
        _ = perform(selector, with: firstArgument, with: secondArgument)
        return true
    }
}
