import Foundation
import ActivityKit
import CoreLocation

@MainActor
final class GoToLiveActivityManager {

    static let shared = GoToLiveActivityManager()

    private var activity: Activity<GoToMarkerAttributes>?
    private var lastNavigationDistanceMeters: Double = 0
    private var lastNavigationRelativeBearingDegrees: Double = 0
    private var lastNavigationArrived: Bool = false
    private var lastRecordingDistanceMeters: Double = 0
    private var radioOverrideTask: Task<Void, Never>?

    private init() {}

    func start(markerName: String, coordinate: CLLocationCoordinate2D) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        radioOverrideTask?.cancel()
        radioOverrideTask = nil

        let attributes = GoToMarkerAttributes(
            markerName: markerName,
            lat: coordinate.latitude,
            lon: coordinate.longitude
        )

        let initialState = GoToMarkerAttributes.ContentState(
            distanceMeters: 0,
            relativeBearingDegrees: 0,
            arrived: false,
            radioUser: nil,
            radioDistanceMeters: nil,
            radioRelativeBearingDegrees: nil,
            presentationMode: .goTo,
            recordingActive: false,
            recordingDistanceMeters: nil
        )

        lastNavigationDistanceMeters = 0
        lastNavigationRelativeBearingDegrees = 0
        lastNavigationArrived = false

        do {
            if let existing = activity {
                Task {
                    await existing.end(nil, dismissalPolicy: .immediate)
                }
            }

            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(120)),
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func startRecording() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        radioOverrideTask?.cancel()
        radioOverrideTask = nil
        lastRecordingDistanceMeters = 0

        let attributes = GoToMarkerAttributes(
            markerName: "Recording",
            lat: 0,
            lon: 0
        )

        let initialState = GoToMarkerAttributes.ContentState(
            distanceMeters: 0,
            relativeBearingDegrees: 0,
            arrived: false,
            radioUser: nil,
            radioDistanceMeters: nil,
            radioRelativeBearingDegrees: nil,
            presentationMode: .recording,
            recordingActive: true,
            recordingDistanceMeters: 0
        )

        do {
            if let existing = activity {
                Task {
                    await existing.end(nil, dismissalPolicy: .immediate)
                }
            }

            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(120)),
                pushType: nil
            )
        } catch {
            print("Failed to start recording Live Activity: \(error)")
        }
    }

    func update(distanceMeters: Double, relativeBearingDegrees: Double) async {
        guard let activity else { return }

        let cleanDistance = max(0, distanceMeters)
        let arrived = cleanDistance < 30

        lastNavigationDistanceMeters = cleanDistance
        lastNavigationRelativeBearingDegrees = relativeBearingDegrees
        lastNavigationArrived = arrived

        let newState = GoToMarkerAttributes.ContentState(
            distanceMeters: cleanDistance,
            relativeBearingDegrees: relativeBearingDegrees,
            arrived: arrived,
            radioUser: currentRadioUser(from: activity),
            radioDistanceMeters: currentRadioDistance(from: activity),
            radioRelativeBearingDegrees: currentRadioBearing(from: activity),
            presentationMode: .goTo,
            recordingActive: false,
            recordingDistanceMeters: nil
        )

        await activity.update(
            .init(
                state: newState,
                staleDate: Date().addingTimeInterval(120)
            )
        )
    }

    func updateRecording(distanceMeters: Double) async {
        guard let activity else { return }

        let cleanDistance = max(0, distanceMeters)
        lastRecordingDistanceMeters = cleanDistance

        let newState = GoToMarkerAttributes.ContentState(
            distanceMeters: 0,
            relativeBearingDegrees: 0,
            arrived: false,
            radioUser: nil,
            radioDistanceMeters: nil,
            radioRelativeBearingDegrees: nil,
            presentationMode: .recording,
            recordingActive: true,
            recordingDistanceMeters: cleanDistance
        )

        await activity.update(
            .init(
                state: newState,
                staleDate: Date().addingTimeInterval(120)
            )
        )
    }

    func showRadioUpdate(
        userName: String,
        distanceMeters: Double,
        relativeBearingDegrees: Double?,
        displaySeconds: TimeInterval = 15
    ) async {
        guard let activity else { return }
        guard activity.content.state.presentationMode == .goTo else { return }

        radioOverrideTask?.cancel()

        let cleanName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let radioState = GoToMarkerAttributes.ContentState(
            distanceMeters: lastNavigationDistanceMeters,
            relativeBearingDegrees: lastNavigationRelativeBearingDegrees,
            arrived: lastNavigationArrived,
            radioUser: cleanName,
            radioDistanceMeters: max(0, distanceMeters),
            radioRelativeBearingDegrees: relativeBearingDegrees,
            presentationMode: .goTo,
            recordingActive: false,
            recordingDistanceMeters: nil
        )

        await activity.update(
            .init(
                state: radioState,
                staleDate: Date().addingTimeInterval(max(displaySeconds, 15))
            )
        )

        radioOverrideTask = Task { [weak self] in
            let nanoseconds = UInt64(max(displaySeconds, 1) * 1_000_000_000)

            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            await self?.clearRadioOverride()
        }
    }

    func clearRadioOverride() async {
        guard let activity else { return }
        guard activity.content.state.presentationMode == .goTo else { return }

        radioOverrideTask?.cancel()
        radioOverrideTask = nil

        let restoredState = GoToMarkerAttributes.ContentState(
            distanceMeters: lastNavigationDistanceMeters,
            relativeBearingDegrees: lastNavigationRelativeBearingDegrees,
            arrived: lastNavigationArrived,
            radioUser: nil,
            radioDistanceMeters: nil,
            radioRelativeBearingDegrees: nil,
            presentationMode: .goTo,
            recordingActive: false,
            recordingDistanceMeters: nil
        )

        await activity.update(
            .init(
                state: restoredState,
                staleDate: Date().addingTimeInterval(120)
            )
        )
    }

    func stop() async {
        radioOverrideTask?.cancel()
        radioOverrideTask = nil

        guard let activity else { return }

        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    private func currentRadioUser(from activity: Activity<GoToMarkerAttributes>) -> String? {
        activity.content.state.radioUser
    }

    private func currentRadioDistance(from activity: Activity<GoToMarkerAttributes>) -> Double? {
        activity.content.state.radioDistanceMeters
    }

    private func currentRadioBearing(from activity: Activity<GoToMarkerAttributes>) -> Double? {
        activity.content.state.radioRelativeBearingDegrees
    }
}
