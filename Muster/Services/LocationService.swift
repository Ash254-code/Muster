import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published private(set) var lastLocation: CLLocation? = nil
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isUpdating: Bool = false

    @Published private(set) var adminDesiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    @Published private(set) var adminDistanceFilter: CLLocationDistance = kCLLocationAccuracyNearestTenMeters
    @Published private(set) var adminBackgroundUpdatesEnabled: Bool = false
    @Published private(set) var adminPausesAutomatically: Bool = true
    @Published private(set) var adminHeadingUpdatesEnabled: Bool = false

    // True device heading (0 = North). nil until available.
    @Published private(set) var headingDegrees: Double? = nil

    private let manager = CLLocationManager()

    // Accepted breadcrumb / smoothing state
    private var lastAcceptedLocation: CLLocation? = nil
    private var smoothedHeadingDegrees: Double? = nil

    // Filtering + tuning
    private let minHorizontalAccuracy: CLLocationAccuracy = 0
    private let maxHorizontalAccuracy: CLLocationAccuracy = 40

    // Increased slightly to suppress tiny visual jitter / GPS wobble.
    private let minLocationDeltaMeters: CLLocationDistance = 4.0

    private let stationarySpeedThreshold: CLLocationSpeed = 0.7
    private let lowSpeedThreshold: CLLocationSpeed = 1.5
    private let lowSpeedMinDeltaMeters: CLLocationDistance = 5.0
    private let maxReasonableSpeedMetersPerSecond: CLLocationSpeed = 40.0   // ~144 km/h GPS spike filter
    private let staleGapStartsFreshTrackAfter: TimeInterval = 20.0
    private let maxLocationAgeSeconds: TimeInterval = 15.0

    // Slightly smoother / calmer heading for map display.
    private let headingSmoothingFactor: Double = 0.10
    private let headingDeadbandDegrees: Double = 3.0

    override init() {
        super.init()

        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5

        // Background recording support
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true

        authorization = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    // MARK: - Public API

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse:
            // Ask for Always so breadcrumbs can continue in background.
            manager.requestAlwaysAuthorization()

        case .authorizedAlways, .restricted, .denied:
            break

        @unknown default:
            break
        }
    }

    func start() {
        lastError = nil

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let servicesEnabled = CLLocationManager.locationServicesEnabled()
                let headingAvailable = CLLocationManager.headingAvailable()

                DispatchQueue.main.async {
                    guard let self else { return }

                    guard servicesEnabled else {
                        self.isUpdating = false
                        self.lastError = "Location Services are disabled."
                        return
                    }

                    if headingAvailable {
                        self.manager.startUpdatingHeading()
                    }

                    self.manager.startUpdatingLocation()
                    self.isUpdating = true
                }
            }

        case .notDetermined:
            requestPermission()

        case .denied:
            isUpdating = false
            lastError = "Location access denied. Enable location permissions in Settings."

        case .restricted:
            isUpdating = false
            lastError = "Location access is restricted on this device."

        @unknown default:
            isUpdating = false
            lastError = "Unknown location authorization status."
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isUpdating = false
    }

    func requestTemporaryFullAccuracy(purposeKey: String) {
        guard manager.accuracyAuthorization == .reducedAccuracy else { return }
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey)
    }

    func forceRefreshNow() {
        manager.requestLocation()
    }

    // MARK: - Private helpers

    private func accept(_ location: CLLocation) {
        lastAcceptedLocation = location
        lastLocation = location
    }

    private func isFreshEnough(_ location: CLLocation) -> Bool {
        abs(location.timestamp.timeIntervalSinceNow) <= maxLocationAgeSeconds
    }

    private func shouldAccept(_ newLocation: CLLocation) -> Bool {
        // Reject invalid / poor accuracy fixes
        if newLocation.horizontalAccuracy < minHorizontalAccuracy { return false }
        if newLocation.horizontalAccuracy > maxHorizontalAccuracy { return false }

        // Reject stale cached fixes
        if !isFreshEnough(newLocation) { return false }

        guard let last = lastAcceptedLocation else { return true }

        let distance = newLocation.distance(from: last)
        let dt = newLocation.timestamp.timeIntervalSince(last.timestamp)

        // If the app was backgrounded / updates paused / there is a long gap,
        // accept the new point as a fresh continuation and do not reject it.
        if dt > staleGapStartsFreshTrackAfter {
            return true
        }

        // Guard against zero / negative timestamps
        if dt <= 0 {
            return false
        }

        // Ignore duplicates / tiny jitter
        if distance < minLocationDeltaMeters {
            return false
        }

        // Ignore obvious GPS teleport spikes
        let inferredSpeed = distance / dt
        if inferredSpeed > maxReasonableSpeedMetersPerSecond {
            return false
        }

        let reportedSpeed = max(newLocation.speed, 0)

        // When nearly stationary, be stricter so breadcrumbs stay clean.
        if reportedSpeed < stationarySpeedThreshold, distance < 6 {
            return false
        }

        // Extra low-speed cleanup: if moving very slowly and the jump is tiny,
        // it is usually GPS wobble rather than real travel.
        if reportedSpeed < lowSpeedThreshold, distance < lowSpeedMinDeltaMeters {
            return false
        }

        return true
    }

    private func normalizeDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }

    private func shortestAngleDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private func smoothHeading(_ rawDegrees: Double) -> Double {
        let normalized = normalizeDegrees(rawDegrees)

        guard let current = smoothedHeadingDegrees else {
            smoothedHeadingDegrees = normalized
            return normalized
        }

        let delta = shortestAngleDelta(from: current, to: normalized)

        if abs(delta) < headingDeadbandDegrees {
            return current
        }

        let next = normalizeDegrees(current + (delta * headingSmoothingFactor))
        smoothedHeadingDegrees = next
        return next
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            self.accuracyAuthorization = manager.accuracyAuthorization

            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.lastError = nil

            case .denied:
                self.isUpdating = false
                self.lastError = "Location access denied. Enable location permissions in Settings."

            case .restricted:
                self.isUpdating = false
                self.lastError = "Location access is restricted on this device."

            case .notDetermined:
                break

            @unknown default:
                self.isUpdating = false
                self.lastError = "Unknown location authorization status."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let newestAcceptable = locations.last(where: { self.shouldAccept($0) }) else { return }
            self.accept(newestAcceptable)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError

            // Ignore transient "location unknown"
            if nsError.domain == kCLErrorDomain,
               nsError.code == CLError.locationUnknown.rawValue {
                return
            }

            self.lastError = error.localizedDescription
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            guard newHeading.headingAccuracy >= 0 else { return }

            // Prefer true heading when available, else magnetic
            let rawHeading: Double
            if newHeading.trueHeading >= 0 {
                rawHeading = newHeading.trueHeading
            } else {
                rawHeading = newHeading.magneticHeading
            }

            self.headingDegrees = self.smoothHeading(rawHeading)
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}
