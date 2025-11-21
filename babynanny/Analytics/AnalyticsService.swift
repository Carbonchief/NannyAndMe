import Foundation
import os
import PostHog

/// Thin wrapper around the PostHog SDK that centralizes configuration and event helpers.
@MainActor
final class AnalyticsService: ObservableObject {
    private let client: PostHogSDK
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "analytics")

    private(set) var isEnabled = false

    init(configuration: AnalyticsConfiguration, client: PostHogSDK = .shared) {
        self.client = client

        let options = PostHogSDK.Options(autocapture: configuration.autocapture)
        client.setup(apiKey: configuration.apiKey, host: configuration.host, options: options)
        isEnabled = true
        logger.info("Analytics configured with autocapture set to \(configuration.autocapture, privacy: .public)")
    }

    private init(client: PostHogSDK = .shared, isEnabled: Bool) {
        self.client = client
        self.isEnabled = isEnabled
    }

    static func makeFromBundle(logger: Logger = Logger(subsystem: "com.prioritybit.babynanny", category: "analytics")) -> AnalyticsService {
        do {
            let configuration = try AnalyticsConfiguration.loadFromBundle()
            return AnalyticsService(configuration: configuration)
        } catch {
            logger.error("Failed to initialize analytics: \(error.localizedDescription, privacy: .public)")
            return AnalyticsService(isEnabled: false)
        }
    }

    func capture(_ event: String, properties: [String: Any]? = nil) {
        guard isEnabled else { return }
        client.capture(event, properties: properties)
    }

    func screen(_ name: String, properties: [String: Any]? = nil) {
        guard isEnabled else { return }
        client.screen(name, properties: properties)
    }

    func identify(_ userId: String, properties: [String: Any]? = nil) {
        guard isEnabled else { return }
        client.identify(userId, userProperties: properties)
    }
}
