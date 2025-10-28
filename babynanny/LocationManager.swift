import CoreLocation
import Foundation

/// Handles while-in-use location authorization and one-shot location capture for action logging.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    struct CapturedLocation: Sendable {
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
        ensurePreciseAccuracyIfNeeded() // spawns a MainActor task internally
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

    /// Schedules a MainActor task to request temporary full-accuracy if needed.
    /// Intentionally non-async to be easy to call from sync contexts.
    @MainActor
    func ensurePreciseAccuracyIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.requestPreciseAccuracyIfNeeded()
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            // Ensure all CLLocationManager interaction happens on the MainActor.
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.resume(throwing: CLError(.locationUnknown))
                    return
                }
                if let existing = self.continuation {
                    existing.resume(throwing: CLError(.locationUnknown))
                }
                self.continuation = continuation
                self.manager.requestLocation()
            }
        }
    }

    /// Performs the async temporary-precision request and updates accuracy publications.
    /// Must run on the MainActor because it touches `manager` and published properties.
    @MainActor
    private func requestPreciseAccuracyIfNeeded() async {
        guard #available(iOS 14.0, *) else { return }

        // Read first (no suspension)
        let currentAccuracy = manager.accuracyAuthorization
        accuracyAuthorization = currentAccuracy
        guard currentAccuracy == .reducedAccuracy else { return }

        // Use the completion-handler form to avoid capturing a non-Sendable across an await.
        // This keeps everything strictly on the MainActor with no suspension while holding `manager`.
        if #available(iOS 15.0, *) {
            do {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    manager.requestTemporaryFullAccuracyAuthorization(
                        withPurposeKey: Self.preciseAccuracyPurposeKey
                    ) { error in
                        if let error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume(returning: ())
                        }
                    }
                }

                // Re-read after the request completes (still on MainActor).
                accuracyAuthorization = manager.accuracyAuthorization
            } catch {
                // Ignore and keep reduced accuracy
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

    // MARK: - CLLocationManagerDelegate (nonisolated entry points)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let updatedAccuracy: CLAccuracyAuthorization? = {
            if #available(iOS 14.0, *) { return manager.accuracyAuthorization }
            else { return nil }
        }()

        let shouldRequestPrecision = status == .authorizedWhenInUse || status == .authorizedAlways
        let isDenied = status == .denied

        // Hop back to the MainActor to mutate state.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            if let updatedAccuracy {
                self.accuracyAuthorization = updatedAccuracy
            }
            if isDenied {
                self.continuation?.resume(throwing: CLError(.denied))
                self.continuation = nil
            }
            if shouldRequestPrecision {
                // Call the MainActor-bound helper (no cross-actor send of `self`).
                self.ensurePreciseAccuracyIfNeeded()
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Snapshot only Sendable values before hopping to MainActor
        let coord: CLLocationCoordinate2D? = locations.first?.coordinate
        let snapAccuracy: CLAccuracyAuthorization? = {
            if #available(iOS 14.0, *) { return manager.accuracyAuthorization }
            else { return nil }
        }()

        Task { @MainActor [weak self] in
            guard let self else { return }

            if let coord, CLLocationCoordinate2DIsValid(coord) {
                // Recreate a new CLLocation on MainActor to avoid sending non-Sendable across the hop
                let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                self.lastKnownLocation = loc
                self.continuation?.resume(returning: loc)
            } else {
                self.continuation?.resume(throwing: CLError(.locationUnknown))
            }

            if let snapAccuracy {
                self.accuracyAuthorization = snapAccuracy
            }

            self.continuation = nil
        }
    }


    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}
