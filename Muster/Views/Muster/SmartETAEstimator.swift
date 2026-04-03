import Foundation
import CoreLocation
import Combine

@MainActor
final class SmartETAEstimator: ObservableObject {

    struct Sample {
        let time: Date
        let distance: CLLocationDistance
    }

    @Published private(set) var etaSeconds: TimeInterval?
    @Published private(set) var displayText: String = "—"
    @Published private(set) var isRecalculating: Bool = false
    @Published private(set) var isArriving: Bool = false

    private var samples: [Sample] = []
    private var startSample: Sample?
    private var lastDisplayUpdate: Date?

    private let arrivalDistanceMeters: CLLocationDistance
    private let minimumElapsedSeconds: TimeInterval

    private let arrivalTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    init(
        arrivalDistanceMeters: CLLocationDistance = 50,
        minimumElapsedSeconds: TimeInterval = 60
    ) {
        self.arrivalDistanceMeters = arrivalDistanceMeters
        self.minimumElapsedSeconds = minimumElapsedSeconds
    }

    func reset() {
        samples.removeAll()
        startSample = nil
        etaSeconds = nil
        displayText = "—"
        isRecalculating = false
        isArriving = false
        lastDisplayUpdate = nil
    }

    func update(distance: CLLocationDistance?, at now: Date = Date()) {
        guard let distance else {
            etaSeconds = nil
            isRecalculating = true
            isArriving = false
            displayText = "Recalc"
            return
        }

        // Set start sample once
        if startSample == nil {
            startSample = Sample(time: now, distance: distance)
        }

        appendSampleIfNeeded(distance: distance, now: now)

        isArriving = distance <= arrivalDistanceMeters
        if isArriving {
            etaSeconds = 0
            isRecalculating = false
            displayText = "Arriving"
            return
        }

        recalculateETA(currentDistance: distance, now: now)
    }

    private func appendSampleIfNeeded(distance: CLLocationDistance, now: Date) {
        guard let last = samples.last else {
            samples.append(Sample(time: now, distance: distance))
            return
        }

        // Only store roughly every 10 seconds (lightweight history)
        if now.timeIntervalSince(last.time) >= 10 {
            samples.append(Sample(time: now, distance: distance))
        }

        // Keep only last 1 hour
        samples.removeAll { now.timeIntervalSince($0.time) > 3600 }
    }

    private func recalculateETA(currentDistance: CLLocationDistance, now: Date) {

        guard let start = startSample else {
            displayText = "Calc…"
            return
        }

        let elapsed = now.timeIntervalSince(start.time)

        // ⏳ Wait at least 1 minute before showing ETA
        guard elapsed >= minimumElapsedSeconds else {
            etaSeconds = nil
            isRecalculating = true
            displayText = "Calc…"
            return
        }

        let referenceSample: Sample

        if elapsed <= 3600 {
            // Use full journey baseline
            referenceSample = start
        } else {
            // Use rolling 1 hour window
            referenceSample = samples.first ?? start
        }

        let distanceDelta = referenceSample.distance - currentDistance
        let timeDelta = now.timeIntervalSince(referenceSample.time)

        guard distanceDelta > 0, timeDelta > 0 else {
            etaSeconds = nil
            isRecalculating = true
            displayText = "Recalc"
            return
        }

        let speed = distanceDelta / timeDelta

        // Reject extremely slow movement (prevents nonsense ETA)
        guard speed > 0.3 else {
            etaSeconds = nil
            isRecalculating = true
            displayText = "Recalc"
            return
        }

        let eta = currentDistance / speed

        guard eta.isFinite, eta >= 0 else {
            etaSeconds = nil
            isRecalculating = true
            displayText = "Recalc"
            return
        }

        etaSeconds = eta
        isRecalculating = false

        // ⏱ Only update display once per minute (stable UI)
        if let lastUpdate = lastDisplayUpdate,
           now.timeIntervalSince(lastUpdate) < 60 {
            return
        }

        lastDisplayUpdate = now

        let minutesRemaining = Int((eta / 60.0).rounded())

        if minutesRemaining <= 5 {
            displayText = "\(max(1, minutesRemaining))m"
        } else {
            let arrivalDate = now.addingTimeInterval(eta)
            displayText = arrivalTimeFormatter.string(from: arrivalDate)
        }
    }
}
