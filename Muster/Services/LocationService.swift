import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var lastLocation: CLLocation? = nil
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy
    @Published private(set) var isUpdating: Bool = false
    @Published private(set) var lastError: String? = nil

    // MARK: - Private

    private let manager: CLLocationManager = CLLocationManager()

    // MARK: - Init

    override init() {
        super.init()

        manager.delegate = self

        // Best for mustering map tracking (tweak if needed)
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2.0          // meters between updates
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false // keep false unless you truly need background

        // Seed current state
        authorization = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    // MARK: - Public API

    /// Call this when the map view appears (or when a session starts).
    func start() {
        lastError = nil

        authorization = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization

        switch authorization {
        case .notDetermined:
            // ✅ This is what makes iOS show "While Using the App"
            manager.requestWhenInUseAuthorization()

        case .restricted, .denied:
            // User must change in Settings
            lastError = "Location permission is off. Enable it in Settings → Tepari → Location."

        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdating()

        @unknown default:
            lastError = "Unknown location authorization state."
        }
    }

    /// Call this when leaving the map / ending session to save battery.
    func stop() {
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    /// Optional helper if you want to prompt for Precise again (iOS may not show a prompt depending on state).
    func requestTemporaryPreciseAuthorization(purposeKey: String) {
        // Requires NSLocationTemporaryUsageDescriptionDictionary in Info.plist
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey)
    }

    // MARK: - Private helpers

    private func beginUpdating() {
        guard !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization

        switch authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            lastError = nil
            beginUpdating()

        case .denied, .restricted:
            stop()
            lastError = "Location permission is off. Enable it in Settings → Tepari → Location."

        case .notDetermined:
            // waiting on user prompt
            break

        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        // Filter junk readings if needed
        if loc.horizontalAccuracy < 0 { return }

        lastLocation = loc
        lastError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }
}
