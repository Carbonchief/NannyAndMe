import CoreLocation
import Foundation

/// Handles while-in-use location authorization and one-shot location capture for action logging.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct CapturedLocation: Equatable {
        var coordinate: CLLocationCoordinate2D
        var placename: String?
    }

    static let shared = LocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastKnownLocation: CLLocation?

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        lastKnownLocation = nil
        super.init()
        manager.delegate = self
        if #available(iOS 14.0, *) {
            manager.desiredAccuracy = kCLLocationAccuracyReduced
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
        manager.distanceFilter = 50
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
    }

    func captureCurrentLocation() async -> CapturedLocation? {
        guard isAuthorizedForUse else { return nil }

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

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            if let existing = self.continuation {
                existing.resume(throwing: CLError(.locationUnknown))
            }
            self.continuation = continuation
            self.manager.requestLocation()
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
        if manager.authorizationStatus == .denied {
            continuation?.resume(throwing: CLError(.denied))
            continuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            continuation?.resume(throwing: CLError(.locationUnknown))
            continuation = nil
            return
        }

        lastKnownLocation = location
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
