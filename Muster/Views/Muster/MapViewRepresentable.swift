import SwiftUI
import MapKit
import CoreLocation
import UIKit

private let kSheepPinExpirySecondsKey = "sheep_pin_expiry_s"
private let kDefaultMapZoomDistanceMeters: CLLocationDistance = 20_000

struct MapViewRepresentable: UIViewRepresentable {

    @Binding var followUser: Bool
    let activeTrackPoints: [TrackPoint]
    let previousSessions: [MusterSession]
    let markers: [MusterMarker]
    let mapMarkers: [MapMarker]
    let xrsContacts: [XRSRadioContact]
    let xrsTrailGroups: [[CLLocationCoordinate2D]]
    let xrsTrailColorRaw: String

    let importedBoundaries: [ImportedBoundary]
    let importedTracks: [ImportedTrack]
    let importedMarkers: [ImportedMarker]

    let userLocation: CLLocation?
    let userHeadingDegrees: Double?

    let ringCount: Int
    let ringSpacingMeters: Double
    let ringColorRaw: String
    let ringThicknessScale: Double
    let ringDistanceLabelsEnabled: Bool

    @Binding var orientationRaw: String
    @Binding var mapStyleRaw: String
    @Binding var recenterNonce: Int
    @Binding var fitRadiosNonce: Int

    @Binding var metersPerPoint: Double
    @Binding var activeTrackAppearanceRaw: String   // "altitude" | "speed" | "off"

    let headsUpPitchDegrees: Double
    let headsUpUserVerticalOffset: Double
    let headsUpBottomObstructionHeight: Double

    let destinationCoordinate: CLLocationCoordinate2D?
    let activeDestinationMarkerID: UUID?

    let onRequestGoToMarker: (MusterMarker) -> Void
    let onArriveAtDestination: () -> Void

    let onLongPressAtCoordinate: (CLLocationCoordinate2D) -> Void
    let onTapSessionMarker: (MusterMarker) -> Void
    let onTapMapMarker: (MapMarker) -> Void
    let onTapImportedMarker: (ImportedMarker) -> Void
    let onLongPressSessionMarker: (MusterMarker) -> Void
    let onLongPressMapMarker: (MapMarker) -> Void
    let onLongPressPreviousTrack: (UUID) -> Void
    let onLongPressImportedTrack: (UUID, String) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator

        map.showsUserLocation = false
        map.userTrackingMode = .none

        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.isRotateEnabled = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isPitchEnabled = true
        map.showsBuildings = false
        map.showsScale = false

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.55
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delaysTouchesEnded = false
        longPress.delegate = context.coordinator
        map.addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapInteractionGesture(_:))
        )
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        pan.require(toFail: longPress)
        map.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapInteractionGesture(_:))
        )
        pinch.cancelsTouchesInView = false
        pinch.delegate = context.coordinator
        map.addGestureRecognizer(pinch)

        let rotate = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapInteractionGesture(_:))
        )
        rotate.cancelsTouchesInView = false
        rotate.delegate = context.coordinator
        map.addGestureRecognizer(rotate)

        context.coordinator.longPressGesture = longPress

        context.coordinator.attachMapView(map)
        context.coordinator.startObservingQuickZoom(on: map)
        context.coordinator.startSheepPinFadeTimer(on: map)

        applyMapStyle(map)

        let fallback = CLLocationCoordinate2D(latitude: -25.2744, longitude: 133.7751)
        let startCenter = userLocation?.coordinate ?? fallback

        let camera = MKMapCamera()
        camera.centerCoordinate = startCenter
        camera.centerCoordinateDistance = kDefaultMapZoomDistanceMeters
        camera.pitch = 0
        camera.heading = 0

        map.setCamera(camera, animated: false)
        context.coordinator.syncCameraStateFromMap(map)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        applyMapStyle(map)
        map.userTrackingMode = .none

        context.coordinator.updateUserLocationAnnotation(
            map: map,
            userLocation: userLocation,
            orientationRaw: orientationRaw,
            followUser: followUser
        )

        context.coordinator.applyCameraModeIfNeeded(
            map: map,
            userLocation: userLocation
        )

        if followUser, let loc = userLocation {
            context.coordinator.updateFollowTarget(
                map: map,
                userLocation: loc,
                orientationRaw: orientationRaw
            )
        }

        context.coordinator.applyRecenterIfNeeded(
            map: map,
            userLocation: userLocation,
            recenterNonce: recenterNonce,
            orientationRaw: orientationRaw
        )

        context.coordinator.applyFitRadiosIfNeeded(
            map: map,
            userLocation: userLocation,
            xrsContacts: xrsContacts,
            destinationCoordinate: destinationCoordinate,
            fitRadiosNonce: fitRadiosNonce
        )

        context.coordinator.updatePreviousTracks(
            map: map,
            sessions: previousSessions
        )
        context.coordinator.updateImportedTracks(
            map: map,
            importedTracks: importedTracks
        )
        context.coordinator.updateImportedBoundaries(
            map: map,
            importedBoundaries: importedBoundaries
        )
        context.coordinator.updateActiveBreadcrumb(
            map: map,
            points: activeTrackPoints
        )
        context.coordinator.updateSessionMarkers(
            map: map,
            markers: markers,
            activeDestinationMarkerID: activeDestinationMarkerID
        )
        context.coordinator.updateMapMarkers(
            map: map,
            mapMarkers: mapMarkers
        )
        context.coordinator.updateXRSContacts(
            map: map,
            contacts: xrsContacts
        )
        context.coordinator.updateXRSTrails(
            map: map,
            trailGroups: xrsTrailGroups,
            colorRaw: xrsTrailColorRaw
        )
        context.coordinator.updateImportedMarkers(
            map: map,
            importedMarkers: importedMarkers
        )
        context.coordinator.updateRings(
            map: map,
            centerLocation: userLocation,
            ringCount: ringCount,
            spacingM: ringSpacingMeters,
            colorRaw: ringColorRaw,
            thicknessScale: ringThicknessScale,
            labelsEnabled: ringDistanceLabelsEnabled
        )
        context.coordinator.updateDestinationLine(
            map: map,
            userLocation: userLocation,
            destinationCoordinate: destinationCoordinate
        )
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stopObservingQuickZoom()
        coordinator.stopSheepPinFadeTimer()
        coordinator.detachMapView()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, metersPerPoint: $metersPerPoint)
    }

    private func applyMapStyle(_ map: MKMapView) {
        switch mapStyleRaw {
        case "satellite":
            map.mapType = .satellite
        case "hybrid":
            map.mapType = .hybrid
        case "plain":
            map.mapType = .mutedStandard
        default:
            map.mapType = .standard
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

        var parent: MapViewRepresentable

        private var activeBreadcrumbSegments: [TrackStyledPolyline] = []
        private var completedBreadcrumbSegments: [TrackStyledPolyline] = []
        private let activeBreadcrumbChunkSegmentCount = 200
        private var activeBreadcrumbChunkStartSegmentIndex: Int?

        private var previousTrackPolylines: [HistoricalPolyline] = []
        private var importedTrackPolylines: [ImportedTrackPolyline] = []
        private var importedBoundaryPolygons: [ImportedBoundaryPolygon] = []
        private var xrsTrailPolylines: [XRSTrailPolyline] = []
        private var destinationLine: MKPolyline?
        private var ringOverlays: [MKCircle] = []
        private var ringLabelAnnotations: [RingLabelAnnotation] = []

        private var previousTrackSignature: String = ""
        private var importedTrackSignature: String = ""
        private var importedBoundarySignature: String = ""
        private var xrsTrailSignature: String = ""
        private var ringsSignature: String = ""

        private var hasTriggeredDestinationArrival = false
        private let destinationArrivalDistanceMeters: CLLocationDistance = 120
        private var metersPerPoint: Binding<Double>
        private var lastRecenterNonce: Int = 0
        private var lastFitRadiosNonce: Int = 0
        private var quickZoomObserver: NSObjectProtocol?
        private var stepZoomObserver: NSObjectProtocol?
        private weak var observedMap: MKMapView?
        private var sheepPinFadeTimer: Timer?
        private var userLocationAnnotation: UserLocationAnnotation?
        private var destinationLineCoordinateCache: CLLocationCoordinate2D?

        weak var longPressGesture: UILongPressGestureRecognizer?

        private var displayLink: CADisplayLink?
        private var displayedCenter: CLLocationCoordinate2D?
        private var targetCenter: CLLocationCoordinate2D?
        private var displayedHeading: CLLocationDirection = 0
        private var targetHeading: CLLocationDirection = 0
        private var displayedDistance: CLLocationDistance = kDefaultMapZoomDistanceMeters
        private var targetDistance: CLLocationDistance = kDefaultMapZoomDistanceMeters
        private var displayedPitch: CGFloat = 0
        private var targetPitch: CGFloat = 0
        private var lastDisplayTickTime: CFTimeInterval = 0

        private var lastKnownCameraDistance: CLLocationDistance = kDefaultMapZoomDistanceMeters
        private var lastKnownMapHeightPoints: CGFloat = 0

        private var isAnimatingCameraTransition = false
        private var cameraAnimationDeadline: CFTimeInterval = 0
        private var suppressFollowCameraUntil: CFTimeInterval = 0

        private var lastAppliedOrientationRaw: String = ""
        private var lastAppliedMapStyleRaw: String = ""
        private var lastAppliedHeadsUpPitchDegrees: Double = -1
        private var lastAppliedHeadsUpUserVerticalOffset: Double = -1
        private var lastAppliedHeadsUpBottomObstructionHeight: Double = -1
        private var userHasManuallyAdjustedPitch = false
        private var lastPresetPitchDegrees: Double = -1

        private var lastActiveBreadcrumbRenderAt: CFTimeInterval = 0
        private let activeBreadcrumbRenderInterval: CFTimeInterval = 1.0
        private var lastRenderedTrackAppearanceRaw: String = ""
        private var lastRenderedActiveBreadcrumbCount: Int = 0
        private var lastRenderedActiveBreadcrumbLastPoint: CLLocationCoordinate2D?
        private var lastRenderedActiveBreadcrumbMinElevation: Double?
        private var lastRenderedActiveBreadcrumbMaxElevation: Double?
        private var lastRenderedActiveBreadcrumbMinSpeed: Double?
        private var lastRenderedActiveBreadcrumbMaxSpeed: Double?

        private var suppressSelectionUntil: Date = .distantPast
        private let longPressSelectionSuppressDuration: TimeInterval = 0.9

        private enum LongPressedTrackTarget {
            case previous(sessionID: UUID)
            case imported(trackID: UUID, name: String)
        }

        init(parent: MapViewRepresentable, metersPerPoint: Binding<Double>) {
            self.parent = parent
            self.metersPerPoint = metersPerPoint
            self.lastAppliedOrientationRaw = parent.orientationRaw
            self.lastAppliedMapStyleRaw = parent.mapStyleRaw
            self.lastAppliedHeadsUpPitchDegrees = parent.headsUpPitchDegrees
            self.lastAppliedHeadsUpUserVerticalOffset = min(max(parent.headsUpUserVerticalOffset.rounded(), 0), 10)
            self.lastAppliedHeadsUpBottomObstructionHeight = max(0, parent.headsUpBottomObstructionHeight)
            self.lastPresetPitchDegrees = parent.headsUpPitchDegrees
        }

        deinit {
            stopObservingQuickZoom()
            stopSheepPinFadeTimer()
            stopDisplayLink()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === longPressGesture || otherGestureRecognizer === longPressGesture {
                return true
            }
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let map = observedMap else { return true }

            let point = touch.location(in: map)

            if annotationView(at: point, in: map) != nil {
                return gestureRecognizer === longPressGesture
            }

            if gestureRecognizer === longPressGesture {
                let bottomBlockedZone: CGFloat = 160
                if point.y > map.bounds.height - bottomBlockedZone {
                    return false
                }
            }

            return true
        }

        func attachMapView(_ map: MKMapView) {
            observedMap = map
            lastKnownMapHeightPoints = map.bounds.height
            startDisplayLinkIfNeeded()
        }

        func detachMapView() {
            observedMap = nil
            resetOverlaySignatures()
            stopDisplayLink()
        }

        private func startDisplayLinkIfNeeded() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
            lastDisplayTickTime = 0
        }

        func startObservingQuickZoom(on map: MKMapView) {
            stopObservingQuickZoom()

            quickZoomObserver = NotificationCenter.default.addObserver(
                forName: .musterQuickZoomRequested,
                object: nil,
                queue: .main
            ) { [weak self, weak map] notification in
                guard let self, let map else { return }
                guard let meters = notification.userInfo?["meters"] as? Double else { return }
                self.applyQuickZoom(map: map, distanceMeters: meters)
            }

            stepZoomObserver = NotificationCenter.default.addObserver(
                forName: .musterStepZoomRequested,
                object: nil,
                queue: .main
            ) { [weak self, weak map] notification in
                guard let self, let map else { return }
                guard let deltaMeters = notification.userInfo?["deltaMeters"] as? Double else { return }
                self.applyStepZoom(map: map, deltaMeters: deltaMeters)
            }
        }

        func stopObservingQuickZoom() {
            if let quickZoomObserver {
                NotificationCenter.default.removeObserver(quickZoomObserver)
                self.quickZoomObserver = nil
            }

            if let stepZoomObserver {
                NotificationCenter.default.removeObserver(stepZoomObserver)
                self.stepZoomObserver = nil
            }
        }

        func startSheepPinFadeTimer(on map: MKMapView) {
            observedMap = map
            stopSheepPinFadeTimer()

            sheepPinFadeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                guard let self, let map = self.observedMap else { return }
                self.refreshSessionMarkerAppearance(map: map)
            }
        }

        func stopSheepPinFadeTimer() {
            sheepPinFadeTimer?.invalidate()
            sheepPinFadeTimer = nil
        }

        func updateUserLocationAnnotation(
            map: MKMapView,
            userLocation: CLLocation?,
            orientationRaw: String,
            followUser: Bool
        ) {
            guard let userLocation else {
                if let existing = userLocationAnnotation {
                    map.removeAnnotation(existing)
                    userLocationAnnotation = nil
                }
                return
            }

            let shouldShowTriangle = (orientationRaw == "headsUp") && followUser
            let heading = resolvedHeading(for: userLocation)

            if let existing = userLocationAnnotation {
                existing.coordinate = userLocation.coordinate
                existing.isHeadsUp = shouldShowTriangle
                existing.headingDegrees = heading

                if let view = map.view(for: existing) as? UserLocationAnnotationView {
                    view.annotation = existing
                    view.configure(
                        isHeadsUp: shouldShowTriangle,
                        headingDegrees: heading
                    )
                    view.layer.zPosition = 10000
                    map.bringSubviewToFront(view)
                }
            } else {
                let annotation = UserLocationAnnotation(
                    coordinate: userLocation.coordinate,
                    isHeadsUp: shouldShowTriangle,
                    headingDegrees: heading
                )
                userLocationAnnotation = annotation
                map.addAnnotation(annotation)

                DispatchQueue.main.async { [weak self, weak map] in
                    guard
                        let self,
                        let map,
                        let annotation = self.userLocationAnnotation,
                        let view = map.view(for: annotation) as? UserLocationAnnotationView
                    else { return }

                    view.configure(
                        isHeadsUp: shouldShowTriangle,
                        headingDegrees: heading
                    )
                    view.layer.zPosition = 10000
                    map.bringSubviewToFront(view)
                }
            }
        }

        func applyCameraModeIfNeeded(
            map: MKMapView,
            userLocation: CLLocation?
        ) {
            let presetPitch = parent.headsUpPitchDegrees
            let snappedVerticalOffset = normalizedHeadsUpUserVerticalOffset()
            let snappedBottomObstructionHeight = normalizedHeadsUpBottomObstructionHeight()

            let orientationChanged = parent.orientationRaw != lastAppliedOrientationRaw
            let mapStyleChanged = parent.mapStyleRaw != lastAppliedMapStyleRaw
            let presetPitchChanged = presetPitch != lastPresetPitchDegrees
            let verticalOffsetChanged = snappedVerticalOffset != lastAppliedHeadsUpUserVerticalOffset
            let bottomObstructionChanged = snappedBottomObstructionHeight != lastAppliedHeadsUpBottomObstructionHeight

            guard orientationChanged || mapStyleChanged || presetPitchChanged || verticalOffsetChanged || bottomObstructionChanged else {
                return
            }

            lastAppliedOrientationRaw = parent.orientationRaw
            lastAppliedMapStyleRaw = parent.mapStyleRaw
            lastAppliedHeadsUpPitchDegrees = presetPitch
            lastAppliedHeadsUpUserVerticalOffset = normalizedHeadsUpUserVerticalOffset()
            lastAppliedHeadsUpBottomObstructionHeight = normalizedHeadsUpBottomObstructionHeight()

            if presetPitchChanged {
                userHasManuallyAdjustedPitch = false
                lastPresetPitchDegrees = presetPitch
                lastAppliedHeadsUpPitchDegrees = presetPitch
            }

            let logicalCenter: CLLocationCoordinate2D
            if parent.followUser, let userLocation {
                logicalCenter = userLocation.coordinate
            } else {
                logicalCenter = displayedCenter ?? map.centerCoordinate
            }

            let heading: CLLocationDirection
            if parent.orientationRaw == "headsUp" {
                if let userLocation, parent.followUser {
                    heading = resolvedHeading(for: userLocation)
                } else {
                    heading = normalizeHeading(displayedHeading != 0 ? displayedHeading : map.camera.heading)
                }
            } else {
                heading = 0
            }

            let pitchToApply: CGFloat
            if parent.orientationRaw == "headsUp" {
                if presetPitchChanged {
                    pitchToApply = CGFloat(presetPitch)
                } else if userHasManuallyAdjustedPitch {
                    pitchToApply = displayedPitch
                } else {
                    pitchToApply = CGFloat(presetPitch)
                }
            } else {
                pitchToApply = 0
            }

            setCameraTargets(
                center: logicalCenter,
                heading: heading,
                distance: currentPreservedDistance(from: map),
                pitch: pitchToApply,
                snap: mapStyleChanged
            )

            if mapStyleChanged {
                applyDrivingCameraIfPossible()
                syncCameraStateFromMap(map)
            } else {
                beginCameraAnimation(duration: 0.30)
            }
        }

        func updateFollowTarget(
            map: MKMapView,
            userLocation: CLLocation,
            orientationRaw: String
        ) {
            let newCoord = userLocation.coordinate
            let preservedDistance = currentPreservedDistance(from: map)
            let pitch = resolvedPitchDegrees()

            if let currentDisplayed = displayedCenter {
                let a = CLLocation(latitude: currentDisplayed.latitude, longitude: currentDisplayed.longitude)
                let b = CLLocation(latitude: newCoord.latitude, longitude: newCoord.longitude)
                let distance = a.distance(from: b)

                if distance < 2.5 {
                    let heading: CLLocationDirection = orientationRaw == "headsUp"
                        ? resolvedHeading(for: userLocation)
                        : 0

                    setCameraTargets(
                        center: currentDisplayed,
                        heading: heading,
                        distance: preservedDistance,
                        pitch: pitch,
                        snap: false
                    )
                    return
                }
            }

            let heading: CLLocationDirection = orientationRaw == "headsUp"
                ? resolvedHeading(for: userLocation)
                : 0

            setCameraTargets(
                center: newCoord,
                heading: heading,
                distance: preservedDistance,
                pitch: pitch,
                snap: false
            )
        }

        private func applyStepZoom(map: MKMapView, deltaMeters: Double) {
            let currentDistance = max(80, map.camera.centerCoordinateDistance)
            let targetDistance = currentDistance + deltaMeters
            applyQuickZoom(map: map, distanceMeters: targetDistance)
        }

        private func applyQuickZoom(map: MKMapView, distanceMeters: Double) {
            let distance = max(80, distanceMeters)
            lastKnownCameraDistance = distance

            let logicalCenter: CLLocationCoordinate2D
            let logicalHeading: CLLocationDirection

            if let loc = parent.userLocation {
                parent.followUser = true
                logicalCenter = loc.coordinate
                logicalHeading = parent.orientationRaw == "headsUp"
                    ? resolvedHeading(for: loc)
                    : 0
            } else {
                logicalCenter = displayedCenter ?? map.centerCoordinate
                logicalHeading = parent.orientationRaw == "headsUp"
                    ? normalizeHeading(displayedHeading != 0 ? displayedHeading : map.camera.heading)
                    : 0
            }

            isAnimatingCameraTransition = false
            cameraAnimationDeadline = 0
            lastDisplayTickTime = 0

            setCameraTargets(
                center: logicalCenter,
                heading: logicalHeading,
                distance: distance,
                pitch: resolvedPitchDegrees(),
                snap: true
            )

            syncCameraStateFromMap(map)
        }

        private func beginCameraAnimation(duration: CFTimeInterval) {
            isAnimatingCameraTransition = true
            cameraAnimationDeadline = CACurrentMediaTime() + duration
            suppressFollowCameraUntil = CACurrentMediaTime() + 0.02
            lastDisplayTickTime = 0
        }

        @objc
        func handleMapInteractionGesture(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                if parent.followUser {
                    parent.followUser = false
                }
            default:
                break
            }
        }

        @objc
        func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }

            switch gesture.state {
            case .began:
                suppressSelectionUntil = Date().addingTimeInterval(longPressSelectionSuppressDuration)

                let point = gesture.location(in: map)

                if let annotationView = annotationView(at: point, in: map) {
                    if let sessionView = annotationView as? SessionMarkerAnnotationView {
                        sessionView.suppressTapTemporarily()
                    } else if let mapMarkerView = annotationView as? MapMarkerAnnotationView {
                        mapMarkerView.suppressTapTemporarily()
                    }

                    if let ann = annotationView.annotation as? SessionMarkerAnnotation {
                        map.deselectAnnotation(ann, animated: false)
                        DispatchQueue.main.async {
                            self.parent.onLongPressSessionMarker(ann.marker)
                        }
                        return
                    }

                    if let ann = annotationView.annotation as? MapMarkerAnnotation {
                        map.deselectAnnotation(ann, animated: false)
                        DispatchQueue.main.async {
                            self.parent.onLongPressMapMarker(ann.marker)
                        }
                        return
                    }
                }

                if let trackTarget = longPressedTrackTarget(at: point, in: map) {
                    switch trackTarget {
                    case .previous(let sessionID):
                        parent.onLongPressPreviousTrack(sessionID)
                    case .imported(let trackID, let name):
                        parent.onLongPressImportedTrack(trackID, name)
                    }
                    return
                }

                let coordinate = map.convert(point, toCoordinateFrom: map)
                parent.onLongPressAtCoordinate(coordinate)

            case .changed:
                suppressSelectionUntil = Date().addingTimeInterval(longPressSelectionSuppressDuration)

            case .ended, .cancelled, .failed:
                suppressSelectionUntil = Date().addingTimeInterval(0.35)

            default:
                break
            }
        }

        private func longPressedTrackTarget(at point: CGPoint, in map: MKMapView) -> LongPressedTrackTarget? {
            for polyline in previousTrackPolylines {
                guard let sessionID = polyline.sessionID else { continue }
                if isPoint(point, near: polyline, in: map) {
                    return .previous(sessionID: sessionID)
                }
            }

            for polyline in importedTrackPolylines {
                guard let trackID = polyline.trackID else { continue }
                if isPoint(point, near: polyline, in: map) {
                    let trimmedName = polyline.trackName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return .imported(trackID: trackID, name: trimmedName.isEmpty ? "Track" : trimmedName)
                }
            }

            return nil
        }

        private func isPoint(_ point: CGPoint, near polyline: MKPolyline, in map: MKMapView) -> Bool {
            guard let renderer = map.renderer(for: polyline) as? MKPolylineRenderer,
                  let path = renderer.path else { return false }

            let mapPoint = MKMapPoint(map.convert(point, toCoordinateFrom: map))
            let rendererPoint = renderer.point(for: mapPoint)
            let tapTolerance = max(12, renderer.lineWidth + 14)
            let stroked = path.copy(
                strokingWithWidth: tapTolerance,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 0
            )

            return stroked.contains(rendererPoint)
        }

        private func signature(for sessions: [MusterSession]) -> String {
            sessions.map {
                "\($0.id.uuidString):\($0.points.count)"
            }
            .joined(separator: "|")
        }

        private func signature(for importedTracks: [ImportedTrack]) -> String {
            importedTracks.map {
                "\($0.id.uuidString):\($0.coordinates.count)"
            }
            .joined(separator: "|")
        }

        private func signature(for importedBoundaries: [ImportedBoundary]) -> String {
            importedBoundaries.map { boundary in
                let ringCounts = boundary.rings.map { "\($0.count)" }.joined(separator: ",")
                return "\(boundary.id.uuidString):\(ringCounts)"
            }
            .joined(separator: "|")
        }

        private func signature(forXRSTrails trailGroups: [[CLLocationCoordinate2D]], colorRaw: String) -> String {
            trailGroups.enumerated().map { index, group in
                let points = group.map { point in
                    "\(String(format: "%.6f", point.latitude)),\(String(format: "%.6f", point.longitude))"
                }
                .joined(separator: ";")

                return "\(index):\(points)"
            }
            .joined(separator: "|") + "|color:\(colorRaw)"
        }

        private func signature(
            for centerLocation: CLLocation?,
            ringCount: Int,
            spacingM: Double,
            colorRaw: String,
            thicknessScale: Double,
            labelsEnabled: Bool
        ) -> String {
            guard let centerLocation else { return "nil" }
            let lat = String(format: "%.6f", centerLocation.coordinate.latitude)
            let lon = String(format: "%.6f", centerLocation.coordinate.longitude)
            let spacing = String(format: "%.1f", spacingM)
            let thickness = String(format: "%.2f", thicknessScale)
            return "\(lat),\(lon)|\(ringCount)|\(spacing)|\(colorRaw)|thickness:\(thickness)|labels:\(labelsEnabled)"
        }

        private func annotationView(at point: CGPoint, in map: MKMapView) -> MKAnnotationView? {
            let hitView = map.hitTest(point, with: nil)
            return annotationView(from: hitView)
        }

        private func annotationView(from view: UIView?) -> MKAnnotationView? {
            var current = view
            while let v = current {
                if let annotationView = v as? MKAnnotationView {
                    return annotationView
                }
                current = v.superview
            }
            return nil
        }

        func applyRecenterIfNeeded(
            map: MKMapView,
            userLocation: CLLocation?,
            recenterNonce: Int,
            orientationRaw: String
        ) {
            guard recenterNonce != lastRecenterNonce else { return }
            lastRecenterNonce = recenterNonce
            guard let loc = userLocation else { return }

            let distance = currentPreservedDistance(from: map)
            let heading: CLLocationDirection = orientationRaw == "headsUp"
                ? resolvedHeading(for: loc)
                : 0

            parent.followUser = true
            userHasManuallyAdjustedPitch = false
            lastPresetPitchDegrees = parent.headsUpPitchDegrees

            setCameraTargets(
                center: loc.coordinate,
                heading: heading,
                distance: distance,
                pitch: resolvedPitchDegrees(),
                snap: true
            )
        }

        func applyFitRadiosIfNeeded(
            map: MKMapView,
            userLocation: CLLocation?,
            xrsContacts: [XRSRadioContact],
            destinationCoordinate: CLLocationCoordinate2D?,
            fitRadiosNonce: Int
        ) {
            guard fitRadiosNonce != lastFitRadiosNonce else { return }
            lastFitRadiosNonce = fitRadiosNonce

            var rect: MKMapRect?

            if let userLocation {
                let point = MKMapPoint(userLocation.coordinate)
                let tinyRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
                rect = rect == nil ? tinyRect : rect!.union(tinyRect)
            }

            for contact in xrsContacts {
                let point = MKMapPoint(contact.coordinate)
                let tinyRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
                rect = rect == nil ? tinyRect : rect!.union(tinyRect)
            }

            if let destinationCoordinate {
                let point = MKMapPoint(destinationCoordinate)
                let tinyRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
                rect = rect == nil ? tinyRect : rect!.union(tinyRect)
            }

            guard let finalRect = rect else { return }

            parent.followUser = false
            userHasManuallyAdjustedPitch = false

            let paddedRect = map.mapRectThatFits(
                finalRect,
                edgePadding: UIEdgeInsets(top: 90, left: 70, bottom: 180, right: 70)
            )

            map.setVisibleMapRect(paddedRect, animated: true)
            syncCameraStateFromMap(map)
        }

        func applyFollowCamera(
            map: MKMapView,
            userLocation: CLLocation,
            distanceMeters: Double,
            orientationRaw: String,
            animated: Bool
        ) {
            let distance = max(80, distanceMeters)
            let heading: CLLocationDirection = orientationRaw == "headsUp"
                ? resolvedHeading(for: userLocation)
                : 0

            setCameraTargets(
                center: userLocation.coordinate,
                heading: heading,
                distance: distance,
                pitch: resolvedPitchDegrees(),
                snap: !animated
            )
        }

        private func setCameraTargets(
            center: CLLocationCoordinate2D,
            heading: CLLocationDirection,
            distance: CLLocationDistance,
            pitch: CGFloat,
            snap: Bool
        ) {
            targetCenter = center
            targetHeading = normalizeHeading(heading)
            targetDistance = max(80, distance)
            targetPitch = pitch
            lastKnownCameraDistance = targetDistance

            if displayedCenter == nil || snap {
                displayedCenter = center
                displayedHeading = normalizeHeading(heading)
                displayedDistance = max(80, distance)
                displayedPitch = pitch
                applyDrivingCameraIfPossible()
            }
        }

        @objc
        private func handleDisplayLink() {
            let now = CACurrentMediaTime()
            guard now >= suppressFollowCameraUntil else { return }

            let shouldRun = parent.followUser || isAnimatingCameraTransition
            guard shouldRun else { return }

            guard let targetCenter, let displayedCenter else { return }

            let dt = lastDisplayTickTime == 0 ? (1.0 / 60.0) : min(0.05, now - lastDisplayTickTime)
            lastDisplayTickTime = now

            let positionAlpha = min(1.0, dt * (isAnimatingCameraTransition ? 7.2 : 3.2))
            let headingAlpha = min(1.0, dt * (isAnimatingCameraTransition ? 6.2 : 2.2))
            let distanceAlpha = min(1.0, dt * (isAnimatingCameraTransition ? 8.5 : 4.0))
            let pitchAlpha = min(1.0, dt * (isAnimatingCameraTransition ? 8.5 : 4.5))

            let newLat = displayedCenter.latitude + (targetCenter.latitude - displayedCenter.latitude) * positionAlpha
            let newLon = displayedCenter.longitude + (targetCenter.longitude - displayedCenter.longitude) * positionAlpha
            self.displayedCenter = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)

            let headingDelta = shortestHeadingDelta(from: displayedHeading, to: targetHeading)
            displayedHeading = normalizeHeading(displayedHeading + headingDelta * headingAlpha)

            displayedDistance += (targetDistance - displayedDistance) * distanceAlpha
            displayedDistance = max(80, displayedDistance)
            lastKnownCameraDistance = displayedDistance

            displayedPitch += (targetPitch - displayedPitch) * pitchAlpha

            applyDrivingCameraIfPossible()

            if isAnimatingCameraTransition {
                let centerReached: Bool = {
                    guard let displayedCenter = self.displayedCenter else { return true }
                    let a = CLLocation(latitude: displayedCenter.latitude, longitude: displayedCenter.longitude)
                    let b = CLLocation(latitude: targetCenter.latitude, longitude: targetCenter.longitude)
                    return a.distance(from: b) < 0.8
                }()

                let headingReached = abs(shortestHeadingDelta(from: displayedHeading, to: targetHeading)) < 0.8
                let distanceReached = abs(displayedDistance - targetDistance) < 1.0
                let pitchReached = abs(displayedPitch - targetPitch) < 0.5
                let timedOut = now >= cameraAnimationDeadline

                if (centerReached && headingReached && distanceReached && pitchReached) || timedOut {
                    self.displayedCenter = targetCenter
                    displayedHeading = targetHeading
                    displayedDistance = targetDistance
                    displayedPitch = targetPitch
                    applyDrivingCameraIfPossible()

                    isAnimatingCameraTransition = false
                    lastDisplayTickTime = 0
                }
            }
        }

        private func applyDrivingCameraIfPossible() {
            guard let map = observedMap, let displayedCenter else { return }

            let heading = parent.orientationRaw == "headsUp" ? displayedHeading : 0
            let pitch = parent.orientationRaw == "headsUp" ? displayedPitch : 0

            let camera = finalCamera(
                center: displayedCenter,
                distance: displayedDistance,
                heading: heading,
                pitch: pitch
            )

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            map.setCamera(camera, animated: false)
            CATransaction.commit()

            keepUserLocationViewOnTop(in: map)
        }

        private func finalCamera(
            center: CLLocationCoordinate2D,
            distance: CLLocationDistance,
            heading: CLLocationDirection,
            pitch: CGFloat
        ) -> MKMapCamera {
            let camera = MKMapCamera()

            if parent.orientationRaw == "headsUp" {
                let styled = styledCameraValues(
                    logicalCenter: center,
                    logicalDistance: distance,
                    heading: heading,
                    pitch: pitch
                )
                camera.centerCoordinate = styled.center
                camera.centerCoordinateDistance = styled.distance
                camera.heading = heading
                camera.pitch = pitch
            } else {
                camera.centerCoordinate = center
                camera.centerCoordinateDistance = max(80, distance)
                camera.heading = 0
                camera.pitch = 0
            }

            return camera
        }

        private func currentPreservedDistance(from map: MKMapView) -> CLLocationDistance {
            let mapDistance = max(80, map.camera.centerCoordinateDistance)
            let storedDistance = max(80, lastKnownCameraDistance)

            if abs(storedDistance - mapDistance) > 1 {
                return storedDistance
            }

            return mapDistance
        }

        func syncCameraStateFromMap(_ map: MKMapView) {
            let renderedDistance = max(80, map.camera.centerCoordinateDistance)
            let heading = normalizeHeading(map.camera.heading)
            let center = map.centerCoordinate
            let pitch = parent.orientationRaw == "headsUp" ? CGFloat(map.camera.pitch) : 0
            let logicalDistance: CLLocationDistance

            if parent.orientationRaw == "headsUp" {
                logicalDistance = max(
                    80,
                    renderedDistance / distanceCompensationFactor(for: pitch)
                )
            } else {
                logicalDistance = renderedDistance
            }

            lastKnownCameraDistance = logicalDistance
            displayedCenter = center
            targetCenter = center
            displayedHeading = heading
            targetHeading = heading
            displayedDistance = logicalDistance
            targetDistance = logicalDistance
            displayedPitch = pitch
            targetPitch = pitch

            lastAppliedOrientationRaw = parent.orientationRaw
            lastAppliedHeadsUpPitchDegrees = Double(pitch)
            lastAppliedHeadsUpUserVerticalOffset = normalizedHeadsUpUserVerticalOffset()
            lastAppliedHeadsUpBottomObstructionHeight = normalizedHeadsUpBottomObstructionHeight()
        }

        private func resolvedPitchDegrees() -> CGFloat {
            guard parent.orientationRaw == "headsUp" else { return 0 }

            if userHasManuallyAdjustedPitch {
                return displayedPitch
            }

            return CGFloat(parent.headsUpPitchDegrees)
        }

        private func normalizedHeadsUpUserVerticalOffset() -> Double {
            min(max(parent.headsUpUserVerticalOffset.rounded(), 0), 10)
        }

        private func normalizedHeadsUpBottomObstructionHeight() -> Double {
            max(0, parent.headsUpBottomObstructionHeight)
        }

        private func styledCameraValues(
            logicalCenter: CLLocationCoordinate2D,
            logicalDistance: CLLocationDistance,
            heading: CLLocationDirection,
            pitch: CGFloat
        ) -> (center: CLLocationCoordinate2D, distance: CLLocationDistance) {
            let pitchValue = Double(pitch)
            let verticalSetting = normalizedHeadsUpUserVerticalOffset()
            let distanceCompensation = distanceCompensationFactor(for: pitch)

            let compensatedDistance = max(80, logicalDistance * distanceCompensation)

            let verticalProgress = verticalSetting / 10.0

            let maxForwardOffsetMultiplier: Double
            switch pitchValue {
            case ..<1:
                maxForwardOffsetMultiplier = 0.115
            case ..<60:
                maxForwardOffsetMultiplier = 0.14
            case ..<75:
                maxForwardOffsetMultiplier = 0.165
            default:
                maxForwardOffsetMultiplier = 0.195
            }

            let requestedForwardOffset = compensatedDistance * maxForwardOffsetMultiplier * verticalProgress

            let maxSafeForwardOffset: CLLocationDistance
            switch pitchValue {
            case ..<1:
                maxSafeForwardOffset = compensatedDistance * 0.13
            case ..<60:
                maxSafeForwardOffset = compensatedDistance * 0.17
            case ..<75:
                maxSafeForwardOffset = compensatedDistance * 0.2
            default:
                maxSafeForwardOffset = compensatedDistance * 0.24
            }

            let forwardOffset = min(requestedForwardOffset, maxSafeForwardOffset)

            let styledCenter: CLLocationCoordinate2D
            if forwardOffset > 0 {
                styledCenter = offsetCoordinate(
                    logicalCenter,
                    meters: forwardOffset,
                    bearingDegrees: heading
                )
            } else {
                styledCenter = logicalCenter
            }

            return (styledCenter, compensatedDistance)
        }

        private func distanceCompensationFactor(for pitch: CGFloat) -> Double {
            switch Double(pitch) {
            case ..<1:
                return 1.0
            case ..<60:
                return 0.94
            case ..<75:
                return 0.82
            default:
                return 0.68
            }
        }

        private func keepUserLocationViewOnTop(in map: MKMapView) {
            guard
                let annotation = userLocationAnnotation,
                let view = map.view(for: annotation)
            else { return }

            view.layer.zPosition = 10000
            map.bringSubviewToFront(view)
        }

        private func offsetCoordinate(
            _ coordinate: CLLocationCoordinate2D,
            meters: CLLocationDistance,
            bearingDegrees: CLLocationDirection
        ) -> CLLocationCoordinate2D {
            let earthRadius = 6_378_137.0
            let distanceRadians = meters / earthRadius
            let bearing = bearingDegrees * .pi / 180.0

            let lat1 = coordinate.latitude * .pi / 180.0
            let lon1 = coordinate.longitude * .pi / 180.0

            let lat2 = asin(
                sin(lat1) * cos(distanceRadians) +
                cos(lat1) * sin(distanceRadians) * cos(bearing)
            )

            let lon2 = lon1 + atan2(
                sin(bearing) * sin(distanceRadians) * cos(lat1),
                cos(distanceRadians) - sin(lat1) * sin(lat2)
            )

            return CLLocationCoordinate2D(
                latitude: lat2 * 180.0 / .pi,
                longitude: lon2 * 180.0 / .pi
            )
        }

        private func normalizeHeading(_ heading: CLLocationDirection) -> CLLocationDirection {
            var value = heading.truncatingRemainder(dividingBy: 360)
            if value < 0 { value += 360 }
            return value
        }

        private func shortestHeadingDelta(
            from: CLLocationDirection,
            to: CLLocationDirection
        ) -> CLLocationDirection {
            var delta = (to - from).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            return delta
        }

        private func coordinatesEqual(
            _ lhs: CLLocationCoordinate2D?,
            _ rhs: CLLocationCoordinate2D?
        ) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil):
                return true
            case let (l?, r?):
                return l.latitude == r.latitude && l.longitude == r.longitude
            default:
                return false
            }
        }

        private func resetArrivalStateIfNeeded(for destinationCoordinate: CLLocationCoordinate2D?) {
            if destinationCoordinate == nil {
                hasTriggeredDestinationArrival = false
                destinationLineCoordinateCache = nil
                return
            }

            if !coordinatesEqual(destinationCoordinate, destinationLineCoordinateCache) {
                hasTriggeredDestinationArrival = false
                destinationLineCoordinateCache = destinationCoordinate
            }
        }

        func updatePreviousTracks(map: MKMapView, sessions: [MusterSession]) {
            let newSignature = signature(for: sessions)
            guard newSignature != previousTrackSignature else { return }
            previousTrackSignature = newSignature

            if !previousTrackPolylines.isEmpty {
                map.removeOverlays(previousTrackPolylines)
                previousTrackPolylines.removeAll()
            }

            guard !sessions.isEmpty else { return }

            var newOverlays: [HistoricalPolyline] = []

            for session in sessions {
                let coords = session.points.map(\.coordinate)
                guard coords.count > 1 else { continue }

                var mutableCoords = coords
                let poly = HistoricalPolyline(
                    coordinates: &mutableCoords,
                    count: mutableCoords.count
                )
                poly.sessionID = session.id
                newOverlays.append(poly)
            }

            previousTrackPolylines = newOverlays
            if !newOverlays.isEmpty {
                map.addOverlays(newOverlays, level: .aboveRoads)
            }
        }

        func updateImportedTracks(map: MKMapView, importedTracks: [ImportedTrack]) {
            let newSignature = signature(for: importedTracks)
            guard newSignature != importedTrackSignature else { return }
            importedTrackSignature = newSignature

            if !importedTrackPolylines.isEmpty {
                map.removeOverlays(importedTrackPolylines)
                importedTrackPolylines.removeAll()
            }

            guard !importedTracks.isEmpty else { return }

            var newOverlays: [ImportedTrackPolyline] = []

            for track in importedTracks {
                let coords = track.coordinates
                guard coords.count > 1 else { continue }

                var mutableCoords = coords
                let poly = ImportedTrackPolyline(
                    coordinates: &mutableCoords,
                    count: mutableCoords.count
                )
                poly.trackID = track.id
                poly.trackName = track.displayTitle
                newOverlays.append(poly)
            }

            importedTrackPolylines = newOverlays
            if !newOverlays.isEmpty {
                map.addOverlays(newOverlays)
            }
        }

        func updateImportedBoundaries(map: MKMapView, importedBoundaries: [ImportedBoundary]) {
            let newSignature = signature(for: importedBoundaries)
            guard newSignature != importedBoundarySignature else { return }
            importedBoundarySignature = newSignature

            if !importedBoundaryPolygons.isEmpty {
                map.removeOverlays(importedBoundaryPolygons)
                importedBoundaryPolygons.removeAll()
            }

            guard !importedBoundaries.isEmpty else { return }

            var newOverlays: [ImportedBoundaryPolygon] = []

            for boundary in importedBoundaries {
                for ring in boundary.rings {
                    let coords = ring.map(\.clCoordinate)
                    guard coords.count >= 3 else { continue }

                    var mutableCoords = coords
                    let polygon = ImportedBoundaryPolygon(
                        coordinates: &mutableCoords,
                        count: mutableCoords.count
                    )
                    polygon.boundaryID = boundary.id
                    polygon.boundaryName = boundary.displayTitle
                    polygon.boundary = boundary
                    newOverlays.append(polygon)
                }
            }

            importedBoundaryPolygons = newOverlays
            if !newOverlays.isEmpty {
                map.addOverlays(newOverlays, level: .aboveRoads)
            }
        }

        func updateActiveBreadcrumb(map: MKMapView, points: [TrackPoint]) {
            guard points.count > 1 else {
                resetActiveBreadcrumb(map: map)
                lastRenderedActiveBreadcrumbCount = 0
                lastRenderedActiveBreadcrumbLastPoint = nil
                lastRenderedActiveBreadcrumbMinElevation = nil
                lastRenderedActiveBreadcrumbMaxElevation = nil
                lastRenderedActiveBreadcrumbMinSpeed = nil
                lastRenderedActiveBreadcrumbMaxSpeed = nil
                lastActiveBreadcrumbRenderAt = CACurrentMediaTime()
                return
            }

            let latestPoint = points.last?.coordinate
            let countChanged = points.count != lastRenderedActiveBreadcrumbCount
            let lastPointChanged = !coordinatesEqual(latestPoint, lastRenderedActiveBreadcrumbLastPoint)
            let modeChanged = activeTrackAppearanceModeRaw() != lastRenderedTrackAppearanceRaw

            guard countChanged || lastPointChanged || modeChanged else {
                return
            }

            let now = CACurrentMediaTime()
            let forceRenderBecauseLargeJump = points.count - lastRenderedActiveBreadcrumbCount >= 10
            let shouldThrottle = (now - lastActiveBreadcrumbRenderAt) < activeBreadcrumbRenderInterval

            if shouldThrottle && !forceRenderBecauseLargeJump && !modeChanged {
                return
            }

            let elevations = points.compactMap(\.elevationM)
            let minElevation = elevations.min()
            let maxElevation = elevations.max()

            let speeds = breadcrumbSpeeds(points: points)
            let minSpeed = speeds.min()
            let maxSpeed = speeds.max()

            let elevationRangeChanged =
                minElevation != lastRenderedActiveBreadcrumbMinElevation ||
                maxElevation != lastRenderedActiveBreadcrumbMaxElevation

            let speedRangeChanged =
                minSpeed != lastRenderedActiveBreadcrumbMinSpeed ||
                maxSpeed != lastRenderedActiveBreadcrumbMaxSpeed

            let requiresFullRebuild =
                elevationRangeChanged ||
                speedRangeChanged ||
                modeChanged ||
                activeBreadcrumbChunkStartSegmentIndex == nil ||
                points.count < lastRenderedActiveBreadcrumbCount ||
                !isBreadcrumbAppendCompatible(points: points)

            if requiresFullRebuild {
                rebuildAllBreadcrumbChunks(
                    map: map,
                    points: points,
                    minElevation: minElevation,
                    maxElevation: maxElevation,
                    minSpeed: minSpeed,
                    maxSpeed: maxSpeed
                )
            } else {
                updateActiveBreadcrumbChunkOnly(
                    map: map,
                    points: points,
                    minElevation: minElevation,
                    maxElevation: maxElevation,
                    minSpeed: minSpeed,
                    maxSpeed: maxSpeed
                )
            }

            lastActiveBreadcrumbRenderAt = now
            lastRenderedActiveBreadcrumbCount = points.count
            lastRenderedActiveBreadcrumbLastPoint = latestPoint
            lastRenderedActiveBreadcrumbMinElevation = minElevation
            lastRenderedActiveBreadcrumbMaxElevation = maxElevation
            lastRenderedActiveBreadcrumbMinSpeed = minSpeed
            lastRenderedActiveBreadcrumbMaxSpeed = maxSpeed
            lastRenderedTrackAppearanceRaw = activeTrackAppearanceModeRaw()
        }

        private func resetActiveBreadcrumb(map: MKMapView) {
            if !activeBreadcrumbSegments.isEmpty {
                map.removeOverlays(activeBreadcrumbSegments)
                activeBreadcrumbSegments.removeAll()
            }

            if !completedBreadcrumbSegments.isEmpty {
                map.removeOverlays(completedBreadcrumbSegments)
                completedBreadcrumbSegments.removeAll()
            }

            activeBreadcrumbChunkStartSegmentIndex = nil
        }

        private func resetOverlaySignatures() {
            previousTrackSignature = ""
            importedTrackSignature = ""
            importedBoundarySignature = ""
            xrsTrailSignature = ""
            ringsSignature = ""
        }

        private func isBreadcrumbAppendCompatible(points: [TrackPoint]) -> Bool {
            guard lastRenderedActiveBreadcrumbCount > 0 else { return false }
            guard lastRenderedActiveBreadcrumbCount <= points.count else { return false }

            let previousLastIndex = lastRenderedActiveBreadcrumbCount - 1
            guard previousLastIndex < points.count else { return false }

            let currentStoredPoint = points[previousLastIndex].coordinate
            return coordinatesEqual(currentStoredPoint, lastRenderedActiveBreadcrumbLastPoint)
        }

        private func rebuildAllBreadcrumbChunks(
            map: MKMapView,
            points: [TrackPoint],
            minElevation: Double?,
            maxElevation: Double?,
            minSpeed: Double?,
            maxSpeed: Double?
        ) {
            resetActiveBreadcrumb(map: map)

            let totalSegments = max(0, points.count - 1)
            guard totalSegments > 0 else { return }

            let activeChunkStart = chunkStartSegmentIndex(forTotalPoints: points.count)
            activeBreadcrumbChunkStartSegmentIndex = activeChunkStart

            var completed: [TrackStyledPolyline] = []
            var active: [TrackStyledPolyline] = []

            var segmentStart = 1
            while segmentStart <= totalSegments {
                let segmentEnd = min(totalSegments, segmentStart + activeBreadcrumbChunkSegmentCount - 1)
                let chunkSegments = makeBreadcrumbSegments(
                    points: points,
                    segmentStartIndex: segmentStart,
                    segmentEndIndex: segmentEnd,
                    minElevation: minElevation,
                    maxElevation: maxElevation,
                    minSpeed: minSpeed,
                    maxSpeed: maxSpeed
                )

                if segmentStart == activeChunkStart {
                    active.append(contentsOf: chunkSegments)
                } else {
                    completed.append(contentsOf: chunkSegments)
                }

                segmentStart += activeBreadcrumbChunkSegmentCount
            }

            completedBreadcrumbSegments = completed
            activeBreadcrumbSegments = active

            if !completed.isEmpty {
                map.addOverlays(completed, level: .aboveRoads)
            }
            if !active.isEmpty {
                map.addOverlays(active, level: .aboveLabels)
            }
        }

        private func updateActiveBreadcrumbChunkOnly(
            map: MKMapView,
            points: [TrackPoint],
            minElevation: Double?,
            maxElevation: Double?,
            minSpeed: Double?,
            maxSpeed: Double?
        ) {
            let newChunkStart = chunkStartSegmentIndex(forTotalPoints: points.count)

            if let existingChunkStart = activeBreadcrumbChunkStartSegmentIndex,
               newChunkStart != existingChunkStart {
                completedBreadcrumbSegments.append(contentsOf: activeBreadcrumbSegments)
                activeBreadcrumbSegments.removeAll()
                activeBreadcrumbChunkStartSegmentIndex = newChunkStart
            } else if activeBreadcrumbChunkStartSegmentIndex == nil {
                activeBreadcrumbChunkStartSegmentIndex = newChunkStart
            }

            if !activeBreadcrumbSegments.isEmpty {
                map.removeOverlays(activeBreadcrumbSegments)
                activeBreadcrumbSegments.removeAll()
            }

            let totalSegments = max(0, points.count - 1)
            guard totalSegments > 0 else { return }

            let activeStart = activeBreadcrumbChunkStartSegmentIndex ?? newChunkStart
            let activeEnd = totalSegments

            let rebuiltActiveSegments = makeBreadcrumbSegments(
                points: points,
                segmentStartIndex: activeStart,
                segmentEndIndex: activeEnd,
                minElevation: minElevation,
                maxElevation: maxElevation,
                minSpeed: minSpeed,
                maxSpeed: maxSpeed
            )

            activeBreadcrumbSegments = rebuiltActiveSegments

            if !rebuiltActiveSegments.isEmpty {
                map.addOverlays(rebuiltActiveSegments, level: .aboveLabels)
            }
        }

        private func chunkStartSegmentIndex(forTotalPoints pointCount: Int) -> Int {
            let totalSegments = max(0, pointCount - 1)
            guard totalSegments > 0 else { return 1 }

            let zeroBasedChunk = (totalSegments - 1) / activeBreadcrumbChunkSegmentCount
            return (zeroBasedChunk * activeBreadcrumbChunkSegmentCount) + 1
        }

        private func makeBreadcrumbSegments(
            points: [TrackPoint],
            segmentStartIndex: Int,
            segmentEndIndex: Int,
            minElevation: Double?,
            maxElevation: Double?,
            minSpeed: Double?,
            maxSpeed: Double?
        ) -> [TrackStyledPolyline] {
            guard points.count > 1 else { return [] }
            guard segmentStartIndex >= 1 else { return [] }
            guard segmentEndIndex >= segmentStartIndex else { return [] }
            guard segmentEndIndex < points.count else { return [] }

            var segments: [TrackStyledPolyline] = []
            segments.reserveCapacity(segmentEndIndex - segmentStartIndex + 1)

            let mode = activeTrackAppearanceModeRaw()

            for index in segmentStartIndex...segmentEndIndex {
                let a = points[index - 1]
                let b = points[index]

                var coords = [a.coordinate, b.coordinate]
                let segment = TrackStyledPolyline(coordinates: &coords, count: 2)

                switch mode {
                case "speed":
                    let speed = breadcrumbSpeedBetween(a, b)
                    segment.strokeColor = speedGradientColor(
                        for: speed,
                        minSpeed: minSpeed,
                        maxSpeed: maxSpeed
                    )

                case "off":
                    segment.strokeColor = UIColor(red: 0.10, green: 0.35, blue: 1.00, alpha: 1.0)

                default:
                    let elev = b.elevationM ?? a.elevationM
                    segment.strokeColor = elevationGradientColor(
                        for: elev,
                        minElevation: minElevation,
                        maxElevation: maxElevation
                    )
                }

                segments.append(segment)
            }

            return segments
        }

        func updateDestinationLine(
            map: MKMapView,
            userLocation: CLLocation?,
            destinationCoordinate: CLLocationCoordinate2D?
        ) {
            resetArrivalStateIfNeeded(for: destinationCoordinate)

            if let line = destinationLine {
                map.removeOverlay(line)
                destinationLine = nil
            }

            guard let userLocation, let destinationCoordinate else { return }

            let targetLocation = CLLocation(
                latitude: destinationCoordinate.latitude,
                longitude: destinationCoordinate.longitude
            )

            let distanceToTarget = userLocation.distance(from: targetLocation)

            if distanceToTarget <= destinationArrivalDistanceMeters {
                if !hasTriggeredDestinationArrival {
                    hasTriggeredDestinationArrival = true
                    destinationLineCoordinateCache = nil

                    DispatchQueue.main.async { [parent] in
                        parent.onArriveAtDestination()
                    }
                }
                return
            }

            var coords = [userLocation.coordinate, destinationCoordinate]
            let poly = MKPolyline(coordinates: &coords, count: 2)
            destinationLine = poly
            map.addOverlay(poly, level: .aboveLabels)
        }

        func updateSessionMarkers(
            map: MKMapView,
            markers: [MusterMarker],
            activeDestinationMarkerID: UUID?
        ) {
            let existing = map.annotations.compactMap { $0 as? SessionMarkerAnnotation }

            let existingIDs = Set(existing.map { $0.marker.id })
            let newIDs = Set(markers.map { $0.id })

            let toRemove = existing.filter { !newIDs.contains($0.marker.id) }
            if !toRemove.isEmpty {
                map.removeAnnotations(toRemove)
            }

            let toAdd = markers
                .filter { !existingIDs.contains($0.id) }
                .map { marker in
                    SessionMarkerAnnotation(
                        marker: marker,
                        isActiveDestination: marker.id == activeDestinationMarkerID
                    )
                }

            if !toAdd.isEmpty {
                map.addAnnotations(toAdd)
            }

            let survivors = map.annotations.compactMap { $0 as? SessionMarkerAnnotation }
            for ann in survivors {
                guard let updated = markers.first(where: { $0.id == ann.marker.id }) else { continue }

                ann.marker = updated
                ann.coordinate = updated.coordinate

                let shouldBeActive = (updated.id == activeDestinationMarkerID)
                if ann.isActiveDestination != shouldBeActive {
                    ann.isActiveDestination = shouldBeActive
                }

                if let view = map.view(for: ann) as? SessionMarkerAnnotationView {
                    configureSessionMarkerView(view, for: ann)
                    view.onTap = { [weak self] marker in
                        self?.parent.onTapSessionMarker(marker)
                    }
                    view.onLongPress = { [weak self] marker in
                        self?.parent.onLongPressSessionMarker(marker)
                    }
                }
            }
        }

        func updateMapMarkers(
            map: MKMapView,
            mapMarkers: [MapMarker]
        ) {
            let existing = map.annotations.compactMap { $0 as? MapMarkerAnnotation }

            let existingIDs = Set(existing.map { $0.marker.id })
            let newIDs = Set(mapMarkers.map { $0.id })

            let toRemove = existing.filter { !newIDs.contains($0.marker.id) }
            if !toRemove.isEmpty {
                map.removeAnnotations(toRemove)
            }

            let toAdd = mapMarkers
                .filter { !existingIDs.contains($0.id) }
                .map { MapMarkerAnnotation(marker: $0) }

            if !toAdd.isEmpty {
                map.addAnnotations(toAdd)
            }

            let survivors = map.annotations.compactMap { $0 as? MapMarkerAnnotation }
            for ann in survivors {
                if let updated = mapMarkers.first(where: { $0.id == ann.marker.id }) {
                    ann.marker = updated
                    ann.coordinate = updated.coordinate

                    if let view = map.view(for: ann) as? MapMarkerAnnotationView {
                        view.configure(with: updated)
                        view.onTap = { [weak self] marker in
                            self?.parent.onTapMapMarker(marker)
                        }
                        view.onLongPress = { [weak self] marker in
                            self?.parent.onLongPressMapMarker(marker)
                        }
                    }
                }
            }
        }

        func updateXRSContacts(
            map: MKMapView,
            contacts: [XRSRadioContact]
        ) {
            let existing = map.annotations.compactMap { $0 as? XRSRadioAnnotation }

            let existingIDs = Set(existing.map { $0.contact.id })
            let newIDs = Set(contacts.map { $0.id })

            let toRemove = existing.filter { !newIDs.contains($0.contact.id) }
            if !toRemove.isEmpty {
                map.removeAnnotations(toRemove)
            }

            let toAdd = contacts
                .filter { !existingIDs.contains($0.id) }
                .map { XRSRadioAnnotation(contact: $0) }

            if !toAdd.isEmpty {
                map.addAnnotations(toAdd)
            }

            let survivors = map.annotations.compactMap { $0 as? XRSRadioAnnotation }
            for ann in survivors {
                if let updated = contacts.first(where: { $0.id == ann.contact.id }) {
                    ann.contact = updated
                    ann.coordinate = updated.coordinate

                    if let view = map.view(for: ann) as? XRSRadioAnnotationView {
                        view.configure(with: updated)
                    }
                }
            }
        }

        func updateImportedMarkers(
            map: MKMapView,
            importedMarkers: [ImportedMarker]
        ) {
            let existing = map.annotations.compactMap { $0 as? ImportedMarkerAnnotation }

            let existingIDs = Set(existing.map { $0.marker.id })
            let newIDs = Set(importedMarkers.map { $0.id })

            let toRemove = existing.filter { !newIDs.contains($0.marker.id) }
            if !toRemove.isEmpty {
                map.removeAnnotations(toRemove)
            }

            let toAdd = importedMarkers
                .filter { !existingIDs.contains($0.id) }
                .map { ImportedMarkerAnnotation(marker: $0) }

            if !toAdd.isEmpty {
                map.addAnnotations(toAdd)
            }

            let survivors = map.annotations.compactMap { $0 as? ImportedMarkerAnnotation }
            for ann in survivors {
                if let updated = importedMarkers.first(where: { $0.id == ann.marker.id }) {
                    ann.marker = updated
                    if let view = map.view(for: ann) as? ImportedMarkerAnnotationView {
                        view.configure(with: updated)
                    }
                }
            }
        }
        func updateXRSTrails(
            map: MKMapView,
            trailGroups: [[CLLocationCoordinate2D]],
            colorRaw: String
        ) {
            let newSignature = signature(forXRSTrails: trailGroups, colorRaw: colorRaw)
            guard newSignature != xrsTrailSignature else { return }
            xrsTrailSignature = newSignature

            if !xrsTrailPolylines.isEmpty {
                map.removeOverlays(xrsTrailPolylines)
                xrsTrailPolylines.removeAll()
            }

            guard !trailGroups.isEmpty else { return }

            let strokeColor = xrsTrailColor(from: colorRaw)

            var newOverlays: [XRSTrailPolyline] = []

            for group in trailGroups {
                guard group.count >= 2 else { continue }

                for index in 1..<group.count {
                    var coords = [group[index - 1], group[index]]
                    let polyline = XRSTrailPolyline(coordinates: &coords, count: 2)
                    polyline.strokeColor = strokeColor
                    newOverlays.append(polyline)
                }
            }

            xrsTrailPolylines = newOverlays

            if !newOverlays.isEmpty {
                map.addOverlays(newOverlays, level: .aboveLabels)
            }
        }
        
        func updateRings(
            map: MKMapView,
            centerLocation: CLLocation?,
            ringCount: Int,
            spacingM: Double,
            colorRaw: String,
            thicknessScale: Double,
            labelsEnabled: Bool
        ) {
            let newSignature = signature(
                for: centerLocation,
                ringCount: ringCount,
                spacingM: spacingM,
                colorRaw: colorRaw,
                thicknessScale: thicknessScale,
                labelsEnabled: labelsEnabled
            )
            guard newSignature != ringsSignature else { return }
            ringsSignature = newSignature

            if !ringOverlays.isEmpty {
                map.removeOverlays(ringOverlays)
                ringOverlays.removeAll()
            }
            if !ringLabelAnnotations.isEmpty {
                map.removeAnnotations(ringLabelAnnotations)
                ringLabelAnnotations.removeAll()
            }

            guard let center = centerLocation else { return }
            guard ringCount > 0, spacingM > 0 else { return }

            var newRings: [MKCircle] = []
            var newLabels: [RingLabelAnnotation] = []
            newRings.reserveCapacity(ringCount)
            newLabels.reserveCapacity(ringCount)

            for i in 1...ringCount {
                let radiusMeters = spacingM * Double(i)
                let circle = MKCircle(
                    center: center.coordinate,
                    radius: radiusMeters
                )
                newRings.append(circle)

                if labelsEnabled {
                    let labelCoordinate = offsetCoordinate(
                        center.coordinate,
                        meters: radiusMeters,
                        bearingDegrees: 330
                    )
                    newLabels.append(
                        RingLabelAnnotation(
                            coordinate: labelCoordinate,
                            distanceText: "\(Int(radiusMeters))m"
                        )
                    )
                }
            }

            ringOverlays = newRings
            map.addOverlays(newRings, level: .aboveRoads)
            ringLabelAnnotations = newLabels
            map.addAnnotations(newLabels)
        }

        func mapView(_ mapView: MKMapView, shouldSelect view: MKAnnotationView) -> Bool {
            if let annotation = view.annotation {
                if annotation is SessionMarkerAnnotation || annotation is MapMarkerAnnotation {
                    return false
                }
            }

            if Date() < suppressSelectionUntil {
                return false
            }

            if let longPressGesture,
               longPressGesture.state == .began || longPressGesture.state == .changed {
                return false
            }

            return true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let strokeScale = overlayStrokeScale(for: mapView)

            if let polyline = overlay as? TrackStyledPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = polyline.strokeColor
                renderer.lineWidth = 6 * strokeScale
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            if let polyline = overlay as? XRSTrailPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = polyline.strokeColor
                renderer.lineWidth = 6 * strokeScale
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            if let polyline = overlay as? HistoricalPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                r.strokeColor = UIColor(red: 0.07, green: 0.14, blue: 0.30, alpha: 0.85)
                r.lineWidth = 6 * strokeScale
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }

            if let polyline = overlay as? ImportedTrackPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                r.strokeColor = UIColor.systemPurple.withAlphaComponent(0.85)
                r.lineWidth = 5 * strokeScale
                r.lineCap = .round
                r.lineJoin = .round
                r.lineDashPattern = [6, 4]
                return r
            }

            if let polygon = overlay as? ImportedBoundaryPolygon {
                let r = MKPolygonRenderer(polygon: polygon)

                let stroke = colorFromHex(
                    polygon.boundary?.strokeHex,
                    fallback: .systemYellow
                )

                r.strokeColor = stroke
                r.lineWidth = 4 * strokeScale
                r.fillColor = .clear
                return r
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)

                if polyline === destinationLine {
                    renderer.strokeColor = UIColor.systemOrange
                    renderer.lineWidth = 3 * strokeScale
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                } else {
                    renderer.strokeColor = UIColor.systemBlue
                    renderer.lineWidth = 3 * strokeScale
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                }

                return renderer
            }

            if let circle = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: circle)
                r.strokeColor = ringColor(from: parent.ringColorRaw).withAlphaComponent(0.95)
                r.lineWidth = max(1.25, min(5.0, 2.5 * parent.ringThicknessScale))
                r.fillColor = .clear
                return r
            }

            return MKOverlayRenderer()
        }

        private func overlayStrokeScale(for mapView: MKMapView) -> CGFloat {
            switch mapView.mapType {
            case .satelliteFlyover, .hybridFlyover:
                return 0.45
            default:
                return 1.0
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let ann = annotation as? UserLocationAnnotation {
                let id = "userLocationCustom"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? UserLocationAnnotationView)
                    ?? UserLocationAnnotationView(annotation: ann, reuseIdentifier: id)

                view.annotation = ann
                view.configure(
                    isHeadsUp: ann.isHeadsUp,
                    headingDegrees: ann.headingDegrees
                )
                view.layer.zPosition = 10000
                view.displayPriority = .required

                DispatchQueue.main.async {
                    mapView.bringSubviewToFront(view)
                }

                return view
            }

            if let ann = annotation as? RingLabelAnnotation {
                let id = "ringLabel"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? RingLabelAnnotationView)
                    ?? RingLabelAnnotationView(annotation: ann, reuseIdentifier: id)
                view.annotation = ann
                view.displayPriority = .required
                view.layer.zPosition = 6000
                return view
            }

            if let ann = annotation as? SessionMarkerAnnotation {
                let id = "sessionMarker"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? SessionMarkerAnnotationView)
                    ?? SessionMarkerAnnotationView(annotation: ann, reuseIdentifier: id)

                view.annotation = ann
                configureSessionMarkerView(view, for: ann)
                view.onTap = { [weak self] marker in
                    self?.parent.onTapSessionMarker(marker)
                }
                view.onLongPress = { [weak self] marker in
                    self?.parent.onLongPressSessionMarker(marker)
                }
                return view
            }

            if let ann = annotation as? MapMarkerAnnotation {
                let id = "mapEmojiMarker"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MapMarkerAnnotationView)
                    ?? MapMarkerAnnotationView(annotation: ann, reuseIdentifier: id)

                view.annotation = ann
                view.configure(with: ann.marker)
                view.onTap = { [weak self] marker in
                    self?.parent.onTapMapMarker(marker)
                }
                view.onLongPress = { [weak self] marker in
                    self?.parent.onLongPressMapMarker(marker)
                }
                return view
            }

            if let ann = annotation as? XRSRadioAnnotation {
                let id = "xrsRadioMarker"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? XRSRadioAnnotationView)
                    ?? XRSRadioAnnotationView(annotation: ann, reuseIdentifier: id)

                view.annotation = ann
                view.configure(with: ann.contact)
                return view
            }

            if let ann = annotation as? ImportedMarkerAnnotation {
                let id = "importedMarker"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? ImportedMarkerAnnotationView)
                    ?? ImportedMarkerAnnotationView(annotation: ann, reuseIdentifier: id)

                view.annotation = ann
                view.configure(with: ann.marker)
                view.onTap = { [weak self] marker in
                    self?.parent.onTapImportedMarker(marker)
                }
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let ann = view.annotation as? UserLocationAnnotation {
                DispatchQueue.main.async {
                    mapView.deselectAnnotation(ann, animated: false)
                }
                return
            }

            if let ann = view.annotation as? XRSRadioAnnotation {
                DispatchQueue.main.async {
                    mapView.deselectAnnotation(ann, animated: false)
                }
                return
            }

            if let ann = view.annotation as? ImportedMarkerAnnotation {
                DispatchQueue.main.async { [parent] in
                    mapView.deselectAnnotation(ann, animated: false)
                    parent.onTapImportedMarker(ann.marker)
                }
                return
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let rect = mapView.visibleMapRect
            let p1 = MKMapPoint(x: rect.minX, y: rect.midY)
            let p2 = MKMapPoint(x: rect.maxX, y: rect.midY)
            let metersWide = p1.distance(to: p2)

            let w = max(1.0, Double(mapView.bounds.width))
            metersPerPoint.wrappedValue = metersWide / w

            let renderedDistance = max(80, mapView.camera.centerCoordinateDistance)
            if parent.orientationRaw == "headsUp" {
                lastKnownCameraDistance = max(
                    80,
                    renderedDistance / distanceCompensationFactor(for: CGFloat(mapView.camera.pitch))
                )
            } else {
                lastKnownCameraDistance = renderedDistance
            }
            lastKnownMapHeightPoints = mapView.bounds.height

            if parent.orientationRaw == "headsUp" && !isAnimatingCameraTransition {
                let livePitch = CGFloat(mapView.camera.pitch)
                let pitchDeltaFromPreset = abs(Double(livePitch) - parent.headsUpPitchDegrees)

                if pitchDeltaFromPreset > 1.0 {
                    userHasManuallyAdjustedPitch = true
                    displayedPitch = livePitch
                    targetPitch = livePitch
                    lastAppliedHeadsUpPitchDegrees = Double(livePitch)
                }
            }

            if !parent.followUser && !isAnimatingCameraTransition {
                syncCameraStateFromMap(mapView)
            }

            keepUserLocationViewOnTop(in: mapView)
        }

        private func refreshSessionMarkerAppearance(map: MKMapView) {
            let annotations = map.annotations.compactMap { $0 as? SessionMarkerAnnotation }
            for ann in annotations {
                if let view = map.view(for: ann) as? SessionMarkerAnnotationView {
                    configureSessionMarkerView(view, for: ann)
                }
            }
        }

        private func configureSessionMarkerView(_ view: SessionMarkerAnnotationView, for annotation: SessionMarkerAnnotation) {
            let marker = annotation.marker
            view.canShowCallout = false
            view.rightCalloutAccessoryView = nil
            view.clusteringIdentifier = nil
            view.displayPriority = .required
            view.markerTintColor = tint(for: marker.type, isActiveDestination: annotation.isActiveDestination)

            if marker.type == .sheepPin {
                let sheepPinIconRaw = UserDefaults.standard.string(forKey: "sheep_pin_icon") ?? "sheep"
                let sheepPinGlyph: String

                switch sheepPinIconRaw {
                case "cattle":
                    sheepPinGlyph = "🐄"
                case "flag":
                    sheepPinGlyph = "🚩"
                case "target":
                    sheepPinGlyph = "🎯"
                case "bell":
                    sheepPinGlyph = "🔔"
                case "pin":
                    sheepPinGlyph = "📍"
                default:
                    sheepPinGlyph = "🐑"
                }

                view.glyphImage = nil
                view.glyphText = sheepPinGlyph
                view.glyphTintColor = nil
                view.alpha = sheepPinOpacity(for: marker)
                view.setSheepCountBadge(
                    sheepCountEstimate: marker.sheepCountEstimate,
                    alpha: sheepPinOpacity(for: marker)
                )
            } else {
                view.glyphText = nil
                view.glyphImage = UIImage(systemName: marker.type.symbol)
                view.glyphTintColor = .white
                view.alpha = 1.0
                view.setSheepCountBadge(
                    sheepCountEstimate: nil,
                    alpha: 1.0
                )
            }
        }

        private func tint(for type: MarkerType, isActiveDestination: Bool) -> UIColor {
            if isActiveDestination { return .systemRed }

            switch type {
            case .gate: return .systemIndigo
            case .yard: return .systemGreen
            case .water: return .systemTeal
            case .issue: return .systemOrange
            case .note: return .systemBlue
            case .sheepPin: return .systemRed
            }
        }

        private func sheepPinOpacity(for marker: MusterMarker) -> CGFloat {
            let expiry = sheepPinExpirySeconds()
            guard expiry > 0 else { return 1.0 }

            let age = Date().timeIntervalSince(marker.t)
            let fadeStart = expiry * 0.8

            if age <= fadeStart { return 1.0 }
            if age >= expiry { return 0.1 }

            let progress = (age - fadeStart) / (expiry - fadeStart)
            let opacity = 1.0 - (progress * 0.9)
            return CGFloat(max(0.1, min(1.0, opacity)))
        }

        private func sheepPinExpirySeconds() -> TimeInterval {
            let stored = UserDefaults.standard.double(forKey: kSheepPinExpirySecondsKey)
            return stored > 0 ? stored : 3600
        }
        private func xrsTrailColor(from raw: String) -> UIColor {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "red":
                return .systemRed
            case "green":
                return .systemGreen
            case "orange":
                return .systemOrange
            case "yellow":
                return .systemYellow
            case "white":
                return .white
            default:
                return .systemBlue
            }
        }
        private func colorFromHex(_ hex: String?, fallback: UIColor) -> UIColor {
            guard let hex else { return fallback }

            let cleaned = hex
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
                .uppercased()

            guard cleaned.count == 6 || cleaned.count == 8 else { return fallback }

            var value: UInt64 = 0
            guard Scanner(string: cleaned).scanHexInt64(&value) else { return fallback }

            if cleaned.count == 6 {
                let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
                let g = CGFloat((value & 0x00FF00) >> 8) / 255.0
                let b = CGFloat(value & 0x0000FF) / 255.0
                return UIColor(red: r, green: g, blue: b, alpha: 1.0)
            } else {
                let a = CGFloat((value & 0xFF000000) >> 24) / 255.0
                let r = CGFloat((value & 0x00FF0000) >> 16) / 255.0
                let g = CGFloat((value & 0x0000FF00) >> 8) / 255.0
                let b = CGFloat(value & 0x000000FF) / 255.0
                return UIColor(red: r, green: g, blue: b, alpha: a)
            }
        }

        private func resolvedHeading(for location: CLLocation) -> CLLocationDirection {
            if location.course >= 0, location.speed > 1.0 {
                return location.course
            }

            if let heading = parent.userHeadingDegrees {
                return heading
            }

            return 0
        }

        private func activeTrackAppearanceModeRaw() -> String {
            let raw = parent.activeTrackAppearanceRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch raw {
            case "speed", "off", "altitude":
                return raw
            default:
                return "altitude"
            }
        }

        private func breadcrumbSpeeds(points: [TrackPoint]) -> [Double] {
            guard points.count > 1 else { return [] }
            var values: [Double] = []
            values.reserveCapacity(points.count - 1)

            for index in 1..<points.count {
                values.append(breadcrumbSpeedBetween(points[index - 1], points[index]))
            }

            return values
        }

        private func breadcrumbSpeedBetween(_ a: TrackPoint, _ b: TrackPoint) -> Double {
            let dt = b.t.timeIntervalSince(a.t)
            guard dt > 0 else { return 0 }

            let from = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
            let to = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
            return from.distance(from: to) / dt
        }

        private func elevationGradientColor(
            for elevation: Double?,
            minElevation: Double?,
            maxElevation: Double?
        ) -> UIColor {
            guard
                let elevation,
                let minElevation,
                let maxElevation,
                maxElevation > minElevation
            else {
                return .systemGreen
            }

            let t = max(0, min(1, (elevation - minElevation) / (maxElevation - minElevation)))
            let hue = CGFloat((1.0 - t) * 0.65)
            return UIColor(hue: hue, saturation: 0.90, brightness: 0.95, alpha: 1.0)
        }

        private func speedGradientColor(
            for speed: Double,
            minSpeed: Double?,
            maxSpeed: Double?
        ) -> UIColor {
            guard
                let minSpeed,
                let maxSpeed,
                maxSpeed > minSpeed
            else {
                return .systemBlue
            }

            let t = max(0, min(1, (speed - minSpeed) / (maxSpeed - minSpeed)))
            let hue = CGFloat((1.0 - t) * 0.65)
            return UIColor(hue: hue, saturation: 0.90, brightness: 0.95, alpha: 1.0)
        }

        private func ringColor(from raw: String) -> UIColor {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "yellow":
                return .systemYellow
            case "orange":
                return .systemOrange
            case "red":
                return .systemRed
            case "green":
                return .systemGreen
            case "purple":
                return .systemPurple
            case "black":
                return .black
            case "white":
                return .white
            default:
                return .systemBlue
            }
        }
    }
}

final class TrackStyledPolyline: MKPolyline {
    var strokeColor: UIColor = .systemGreen
}

final class HistoricalPolyline: MKPolyline {
    var sessionID: UUID?
}

final class XRSTrailPolyline: MKPolyline {
    var strokeColor: UIColor = .systemBlue
}
final class ImportedTrackPolyline: MKPolyline {
    var trackID: UUID?
    var trackName: String?
}

final class ImportedBoundaryPolygon: MKPolygon {
    var boundaryID: UUID?
    var boundaryName: String?
    var boundary: ImportedBoundary?
}

final class UserLocationAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var isHeadsUp: Bool
    var headingDegrees: Double

    init(coordinate: CLLocationCoordinate2D, isHeadsUp: Bool, headingDegrees: Double) {
        self.coordinate = coordinate
        self.isHeadsUp = isHeadsUp
        self.headingDegrees = headingDegrees
        super.init()
    }

    var title: String? { nil }
    var subtitle: String? { nil }
}

final class SessionMarkerAnnotation: NSObject, MKAnnotation {

    var marker: MusterMarker
    dynamic var coordinate: CLLocationCoordinate2D
    var isActiveDestination: Bool

    init(marker: MusterMarker, isActiveDestination: Bool) {
        self.marker = marker
        self.coordinate = marker.coordinate
        self.isActiveDestination = isActiveDestination
        super.init()
    }

    var title: String? { marker.displayTitle }
    var subtitle: String? {
        marker.type == .sheepPin ? "Tap pin to navigate" : marker.note
    }
}

final class MapMarkerAnnotation: NSObject, MKAnnotation {

    var marker: MapMarker
    dynamic var coordinate: CLLocationCoordinate2D

    init(marker: MapMarker) {
        self.marker = marker
        self.coordinate = marker.coordinate
        super.init()
    }

    var title: String? { marker.displayTitle }
    var subtitle: String? { marker.templateDescription }
}

final class XRSRadioAnnotation: NSObject, MKAnnotation {

    var contact: XRSRadioContact
    dynamic var coordinate: CLLocationCoordinate2D

    init(contact: XRSRadioContact) {
        self.contact = contact
        self.coordinate = contact.coordinate
        super.init()
    }

    var title: String? { contact.name }
    var subtitle: String? { contact.status }
}

final class ImportedMarkerAnnotation: NSObject, MKAnnotation {

    var marker: ImportedMarker

    init(marker: ImportedMarker) {
        self.marker = marker
        super.init()
    }

    var coordinate: CLLocationCoordinate2D { marker.coordinate }
    var title: String? { marker.displayTitle }
    var subtitle: String? { marker.note ?? marker.markerType }
}

final class RingLabelAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let distanceText: String

    init(coordinate: CLLocationCoordinate2D, distanceText: String) {
        self.coordinate = coordinate
        self.distanceText = distanceText
        super.init()
    }

    var title: String? { distanceText }
    var subtitle: String? { nil }
}

final class UserLocationAnnotationView: MKAnnotationView {

    private let glyphView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let ann = annotation as? UserLocationAnnotation else { return }
            configure(
                isHeadsUp: ann.isHeadsUp,
                headingDegrees: ann.headingDegrees
            )
        }
    }

    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        backgroundColor = .clear
        canShowCallout = false
        centerOffset = .zero
        collisionMode = .circle
        displayPriority = .required
        isOpaque = false

        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.contentMode = .scaleAspectFit
        addSubview(glyphView)

        NSLayoutConstraint.activate([
            glyphView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: 24),
            glyphView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    func configure(isHeadsUp: Bool, headingDegrees: Double) {
        if isHeadsUp {
            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
            glyphView.image = UIImage(systemName: "location.north.fill", withConfiguration: config)?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            glyphView.transform = .identity
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
            glyphView.image = UIImage(systemName: "circle.inset.filled", withConfiguration: config)?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            glyphView.transform = .identity
        }
    }
}

final class RingLabelAnnotationView: MKAnnotationView {
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let ring = annotation as? RingLabelAnnotation else { return }
            label.text = ring.distanceText
        }
    }

    private func setup() {
        canShowCallout = false
        isEnabled = false
        isOpaque = false
        collisionMode = .none
        centerOffset = CGPoint(x: 0, y: -4)

        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = UIColor.label
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.72)
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.textAlignment = .center

        addSubview(label)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.sizeToFit()
        let horizontalPadding: CGFloat = 7
        let verticalPadding: CGFloat = 3
        label.frame = CGRect(
            x: 0,
            y: 0,
            width: label.bounds.width + (horizontalPadding * 2),
            height: label.bounds.height + (verticalPadding * 2)
        )
        frame = label.frame
    }
}

final class SessionMarkerAnnotationView: MKMarkerAnnotationView {

    var onTap: ((MusterMarker) -> Void)?
    var onLongPress: ((MusterMarker) -> Void)?

    private var tapGesture: UITapGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!
    private var suppressTapUntil: Date = .distantPast

    private let sheepCountBadgeBackground = UIView()
    private let sheepCountBadgeLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupInteraction()
        setupSheepCountBadge()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupInteraction()
        setupSheepCountBadge()
    }

    override var annotation: MKAnnotation? {
        didSet {
            canShowCallout = false
        }
    }

    private func setupInteraction() {
        canShowCallout = false
        isUserInteractionEnabled = true

        if tapGesture == nil {
            tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tapGesture.cancelsTouchesInView = false
            addGestureRecognizer(tapGesture)
        }

        if longPressGesture == nil {
            longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            longPressGesture.minimumPressDuration = 0.55
            longPressGesture.cancelsTouchesInView = false
            addGestureRecognizer(longPressGesture)
        }

        tapGesture.require(toFail: longPressGesture)
    }

    private func setupSheepCountBadge() {
        sheepCountBadgeBackground.translatesAutoresizingMaskIntoConstraints = false
        sheepCountBadgeBackground.backgroundColor = .systemRed
        sheepCountBadgeBackground.layer.cornerCurve = .continuous
        sheepCountBadgeBackground.layer.borderWidth = 1
        sheepCountBadgeBackground.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        sheepCountBadgeBackground.clipsToBounds = true
        sheepCountBadgeBackground.isHidden = true
        sheepCountBadgeBackground.isUserInteractionEnabled = false

        sheepCountBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        sheepCountBadgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        sheepCountBadgeLabel.textColor = .white
        sheepCountBadgeLabel.textAlignment = .center
        sheepCountBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        sheepCountBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(sheepCountBadgeBackground)
        sheepCountBadgeBackground.addSubview(sheepCountBadgeLabel)

        bringSubviewToFront(sheepCountBadgeBackground)
        sheepCountBadgeBackground.layer.zPosition = 999

        clipsToBounds = false
        layer.masksToBounds = false
        sheepCountBadgeBackground.clipsToBounds = true

        NSLayoutConstraint.activate([
            sheepCountBadgeBackground.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 18),
            sheepCountBadgeBackground.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -19),
            sheepCountBadgeBackground.heightAnchor.constraint(equalToConstant: 20),
            sheepCountBadgeBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),

            sheepCountBadgeLabel.leadingAnchor.constraint(equalTo: sheepCountBadgeBackground.leadingAnchor, constant: 6),
            sheepCountBadgeLabel.trailingAnchor.constraint(equalTo: sheepCountBadgeBackground.trailingAnchor, constant: -6),
            sheepCountBadgeLabel.centerYAnchor.constraint(equalTo: sheepCountBadgeBackground.centerYAnchor)
        ])
    }

    func setSheepCountBadge(sheepCountEstimate: Int?, alpha: CGFloat) {
        guard let sheepCountEstimate else {
            sheepCountBadgeBackground.isHidden = true
            sheepCountBadgeLabel.text = nil
            return
        }

        let text = sheepCountEstimate >= 100 ? "100+" : "\(sheepCountEstimate)"
        sheepCountBadgeLabel.text = text
        sheepCountBadgeBackground.isHidden = false
        sheepCountBadgeBackground.alpha = alpha
        sheepCountBadgeLabel.alpha = alpha
        sheepCountBadgeBackground.layer.cornerRadius = 10
        bringSubviewToFront(sheepCountBadgeBackground)
    }

    func suppressTapTemporarily() {
        suppressTapUntil = Date().addingTimeInterval(0.8)
    }

    @objc
    private func handleTap() {
        guard Date() >= suppressTapUntil else { return }
        guard let ann = annotation as? SessionMarkerAnnotation else { return }
        onTap?(ann.marker)
    }

    @objc
    private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        suppressTapTemporarily()
        guard let ann = annotation as? SessionMarkerAnnotation else { return }
        onLongPress?(ann.marker)
    }
}

final class MapMarkerAnnotationView: MKAnnotationView {

    var onTap: ((MapMarker) -> Void)?
    var onLongPress: ((MapMarker) -> Void)?

    private let emojiLabel = UILabel()
    private let titleBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let titleLabel = UILabel()

    private var tapGesture: UITapGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!
    private var suppressTapUntil: Date = .distantPast

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let ann = annotation as? MapMarkerAnnotation else { return }
            configure(with: ann.marker)
        }
    }

    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 88, height: 60)
        backgroundColor = .clear
        canShowCallout = false
        centerOffset = CGPoint(x: 0, y: -20)
        collisionMode = .circle
        displayPriority = .required
        isUserInteractionEnabled = true

        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.font = .systemFont(ofSize: 30)
        emojiLabel.textAlignment = .center
        emojiLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        titleBackground.translatesAutoresizingMaskIntoConstraints = false
        titleBackground.clipsToBounds = true
        titleBackground.layer.cornerRadius = 10
        titleBackground.layer.cornerCurve = .continuous
        titleBackground.layer.borderWidth = 1
        titleBackground.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = UIColor.white
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(emojiLabel)
        addSubview(titleBackground)
        titleBackground.contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            emojiLabel.topAnchor.constraint(equalTo: topAnchor),
            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            titleBackground.topAnchor.constraint(equalTo: emojiLabel.bottomAnchor, constant: -2),
            titleBackground.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleBackground.heightAnchor.constraint(equalToConstant: 22),
            titleBackground.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            titleBackground.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: titleBackground.contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: titleBackground.contentView.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: titleBackground.contentView.centerYAnchor)
        ])

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)

        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0.55
        longPressGesture.cancelsTouchesInView = false
        addGestureRecognizer(longPressGesture)

        tapGesture.require(toFail: longPressGesture)
    }

    func configure(with marker: MapMarker) {
        emojiLabel.text = marker.emoji

        let title = marker.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = title
        titleBackground.isHidden = title.isEmpty
    }

    func suppressTapTemporarily() {
        suppressTapUntil = Date().addingTimeInterval(0.8)
    }

    @objc
    private func handleTap() {
        guard Date() >= suppressTapUntil else { return }
        guard let ann = annotation as? MapMarkerAnnotation else { return }
        onTap?(ann.marker)
    }

    @objc
    private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        suppressTapTemporarily()
        guard let ann = annotation as? MapMarkerAnnotation else { return }
        onLongPress?(ann.marker)
    }
}

final class XRSRadioAnnotationView: MKAnnotationView {

    var onTap: ((XRSRadioContact) -> Void)?

    private let circleView = UIView()
    private let letterLabel = UILabel()

    private var tapGesture: UITapGestureRecognizer!
    private var suppressTapUntil: Date = .distantPast

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let ann = annotation as? XRSRadioAnnotation else { return }
            configure(with: ann.contact)
        }
    }

    private func setup() {

        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        backgroundColor = .clear
        canShowCallout = false
        centerOffset = CGPoint(x: 0, y: -10)
        collisionMode = .circle
        displayPriority = .required
        isUserInteractionEnabled = true

        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = .systemOrange
        circleView.layer.cornerRadius = 17
        circleView.layer.cornerCurve = .continuous
        circleView.layer.borderWidth = 2
        circleView.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        circleView.clipsToBounds = true

        letterLabel.translatesAutoresizingMaskIntoConstraints = false
        letterLabel.font = .systemFont(ofSize: 16, weight: .bold)
        letterLabel.textAlignment = .center
        letterLabel.textColor = .white

        addSubview(circleView)
        circleView.addSubview(letterLabel)

        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 34),
            circleView.heightAnchor.constraint(equalToConstant: 34),

            letterLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            letterLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor)
        ])

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
    }

    func configure(with contact: XRSRadioContact) {
        circleView.backgroundColor = radioFillColor(for: contact)

        let trimmed = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = trimmed.first {
            letterLabel.text = String(first).uppercased()
        } else {
            letterLabel.text = "?"
        }
    }

    private func radioFillColor(for contact: XRSRadioContact) -> UIColor {
        let age = Date().timeIntervalSince(contact.updatedAt)

        if age <= 120 {
            return .systemGreen
        } else if age <= 300 {
            return .systemYellow
        } else {
            return UIColor.brown
        }
    }

    func suppressTapTemporarily() {
        suppressTapUntil = Date().addingTimeInterval(0.8)
    }

    @objc
    private func handleTap() {
        guard Date() >= suppressTapUntil else { return }
        guard let ann = annotation as? XRSRadioAnnotation else { return }
        onTap?(ann.contact)
    }
}

final class ImportedMarkerAnnotationView: MKMarkerAnnotationView {

    var onTap: ((ImportedMarker) -> Void)?

    private var tapGesture: UITapGestureRecognizer!
    private var suppressTapUntil: Date = .distantPast

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let ann = annotation as? ImportedMarkerAnnotation else { return }
            configure(with: ann.marker)
        }
    }

    private func setup() {
        canShowCallout = false
        clusteringIdentifier = nil
        displayPriority = .defaultHigh
        animatesWhenAdded = false
        isUserInteractionEnabled = true

        if tapGesture == nil {
            tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tapGesture.cancelsTouchesInView = false
            addGestureRecognizer(tapGesture)
        }
    }

    func configure(with marker: ImportedMarker) {
        let rawEmoji = marker.emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let categoryIcon = marker.category.defaultIcon.trimmingCharacters(in: .whitespacesAndNewlines)

        markerTintColor = tintColor(for: marker.category)
        glyphTintColor = .white

        if marker.category == .boundaries || marker.category == .tracks {
            glyphText = nil
            glyphImage = nil
        } else if !rawEmoji.isEmpty {
            glyphText = rawEmoji
            glyphImage = nil
        } else if !categoryIcon.isEmpty {
            glyphText = categoryIcon
            glyphImage = nil
        } else {
            glyphText = "•"
            glyphImage = nil
        }
    }

    @objc
    private func handleTap() {
        guard Date() >= suppressTapUntil else { return }
        guard let ann = annotation as? ImportedMarkerAnnotation else { return }
        onTap?(ann.marker)
    }

    private func tintColor(for category: ImportCategory) -> UIColor {
        switch category {
        case .boundaries:
            return .systemYellow
        case .tracks:
            return .systemPurple
        case .waterPoints:
            return .systemBlue
        case .yards:
            return .systemBrown
        case .other:
            return .systemGreen
        }
    }
}
private extension Notification.Name {
    static let musterQuickZoomRequested = Notification.Name("muster_quick_zoom_requested")
    static let musterStepZoomRequested = Notification.Name("muster_step_zoom_requested")
}
