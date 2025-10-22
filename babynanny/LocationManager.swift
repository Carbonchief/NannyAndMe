import CoreLocation
import Foundation

/// Handles while-in-use location authorization and one-shot location capture for action logging.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct CapturedLocation {
        var coordinate: CLLocationCoordinate2D
        var placename: String?
    }

    private static let preciseAccuracyPurposeKey = "ActionLoggingPreciseAccuracy"

    static let shared = LocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var lastKnownLocation: CLLocation?

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        if #available(iOS 14.0, *) {
            accuracyAuthorization = manager.accuracyAuthorization
        } else {
            accuracyAuthorization = .fullAccuracy
        }
        lastKnownLocation = nil
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
    }

    var isAuthorizedForUse: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    func requestPermissionIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
        ensurePreciseAccuracyIfNeeded()
    }

    func captureCurrentLocation() async -> CapturedLocation? {
        guard isAuthorizedForUse else { return nil }

        await requestPreciseAccuracyIfNeeded()

        if let lastKnownLocation {
            return await geocodeIfNeeded(for: lastKnownLocation)
        }

        do {
            let location = try await requestLocation()
            return await geocodeIfNeeded(for: location)
        } catch {
            return nil
        }
    }

    /// Requests temporary full-accuracy authorization when the system only allows reduced accuracy.
    func ensurePreciseAccuracyIfNeeded() {
        Task { [weak self] in
            await self?.requestPreciseAccuracyIfNeeded()
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            if let existing = self.continuation {
                existing.resume(throwing: CLError(.locationUnknown))
            }
            self.continuation = continuation
            self.manager.requestLocation()
        }
    }

    /// Performs the async temporary-precision request and updates accuracy publications.
    private func requestPreciseAccuracyIfNeeded() async {
        guard #available(iOS 14.0, *) else { return }
        let currentAccuracy = manager.accuracyAuthorization
        accuracyAuthorization = currentAccuracy
        guard currentAccuracy == .reducedAccuracy else { return }

        if #available(iOS 15.0, *) {
            do {
                let granted = try await manager.requestTemporaryFullAccuracyAuthorization(
                    withPurposeKey: Self.preciseAccuracyPurposeKey
                )
                if granted {
                    accuracyAuthorization = manager.accuracyAuthorization
                }
            } catch {
                // Ignore errors and continue using the current accuracy authorization state.
            }
        }
    }

    private func geocodeIfNeeded(for location: CLLocation) async -> CapturedLocation? {
        let coordinate = location.coordinate
        if CLLocationCoordinate2DIsValid(coordinate) == false {
            return nil
        }

        let placename: String?
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            placename = placemarks.first?.locality ?? placemarks.first?.name
        } catch {
            placename = nil
        }

        lastKnownLocation = location
        return CapturedLocation(coordinate: coordinate, placename: placename)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if #available(iOS 14.0, *) {
            accuracyAuthorization = manager.accuracyAuthorization
        }
        if manager.authorizationStatus == .denied {
            continuation?.resume(throwing: CLError(.denied))
            continuation = nil
        }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            ensurePreciseAccuracyIfNeeded()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            continuation?.resume(throwing: CLError(.locationUnknown))
            continuation = nil
            return
        }

        lastKnownLocation = location
        if #available(iOS 14.0, *) {
            accuracyAuthorization = manager.accuracyAuthorization
        }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
