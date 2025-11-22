import AppTrackingTransparency
import Foundation
import UIKit
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
    private var appDidBecomeActiveObserver: NSObjectProtocol?

    private init() {
        let storedStatus = storage.string(forKey: UserDefaultsKey.analyticsConsentStatus)
        consentStatus = ConsentStatus(rawValue: storedStatus ?? ConsentStatus.notDetermined.rawValue) ?? .notDetermined

        setupPostHogIfNeeded()

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.requestTrackingAuthorizationIfNeeded() }
        }
    }

    deinit {
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
        }
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
