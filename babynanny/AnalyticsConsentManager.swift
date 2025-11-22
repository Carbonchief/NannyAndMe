import AppTrackingTransparency
import Foundation
import PostHog

/// Manages App Tracking Transparency consent and defers PostHog setup until permission is granted.
@MainActor
final class AnalyticsConsentManager: ObservableObject {
    enum ConsentStatus: String {
        case notDetermined
        case authorized
        case denied
    }

    static let shared = AnalyticsConsentManager()

    @Published private(set) var consentStatus: ConsentStatus
    private var hasConfiguredPostHog = false
    private let storage = UserDefaults.standard

    private init() {
        let storedStatus = storage.string(forKey: UserDefaultsKey.analyticsConsentStatus)
        consentStatus = ConsentStatus(rawValue: storedStatus ?? ConsentStatus.notDetermined.rawValue) ?? .notDetermined

        setupPostHogIfNeeded()
    }

    var isAnalyticsEnabled: Bool { hasConfiguredPostHog }
    var canTrackIdentifyingData: Bool { consentStatus == .authorized }

    func requestTrackingAuthorizationIfNeeded() async {
        let systemStatus = ATTrackingManager.trackingAuthorizationStatus
        syncConsentStatus(with: systemStatus)

        setupPostHogIfNeeded()

        switch systemStatus {
        case .authorized:
            return
        case .denied, .restricted:
            return
        case .notDetermined:
            break
        @unknown default:
            updateConsentStatus(.denied)
            return
        }

        let status = await ATTrackingManager.requestTrackingAuthorization()

        switch status {
        case .authorized:
            updateConsentStatus(.authorized)
        case .denied, .restricted:
            updateConsentStatus(.denied)
        case .notDetermined:
            break
        @unknown default:
            updateConsentStatus(.denied)
        }
    }

    func configureIfNeeded() {
        setupPostHogIfNeeded()
    }

    private func syncConsentStatus(with systemStatus: ATTrackingManager.AuthorizationStatus) {
        switch systemStatus {
        case .authorized:
            updateConsentStatus(.authorized)
        case .denied, .restricted:
            updateConsentStatus(.denied)
        case .notDetermined:
            updateConsentStatus(.notDetermined)
        @unknown default:
            updateConsentStatus(.denied)
        }
    }

    private func updateConsentStatus(_ status: ConsentStatus) {
        consentStatus = status
        storage.set(status.rawValue, forKey: UserDefaultsKey.analyticsConsentStatus)
    }

    private func setupPostHogIfNeeded() {
        guard hasConfiguredPostHog == false else { return }

        let config = PostHogConfig(
            apiKey: "phc_LnHkvLd42Z0HUUa1DWyq7fGkrDXoXzKO2AuORKfqqwP",
            host: "https://eu.i.posthog.com"
        )

        PostHogSDK.shared.setup(config)
        hasConfiguredPostHog = true
    }
}
