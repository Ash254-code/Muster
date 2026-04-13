import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit
import MediaPlayer
import AVFoundation
import AudioToolbox


// Shared keys (must match Settings)
private let kRingCountKey = "rings_count"              // Int
private let kRingSpacingKey = "rings_spacing_m"        // Double
private let kRingColorKey = "rings_color"              // String
private let kRingThicknessScaleKey = "rings_thickness_scale" // Double (0.5...2.0)
private let kRingDistanceLabelsEnabledKey = "rings_distance_labels_enabled" // Bool
private let kMapOrientationKey = "map_orientation"     // String: "headsUp" | "northUp"
private let kHeadsUpPitchDegreesKey = "heads_up_pitch_degrees" // Double
private let kHeadsUpUserVerticalOffsetKey = "heads_up_user_vertical_offset" // Double 0...10

// Quick zoom preset keys
private let kQuickZoom1MetersKey = "quick_zoom_1_m"    // Double
private let kQuickZoom2MetersKey = "quick_zoom_2_m"    // Double
private let kQuickZoom3MetersKey = "quick_zoom_3_m"    // Double

// Sheep pin keys (must match MusterStore prefs)
private let kSheepPinEnabledKey = "sheep_pin_enabled"  // Bool
private let kSheepPinIconKey = "sheep_pin_icon"        // String

private let kTopLeftPillMetricKey = "top_left_pill_metric"
private let kTopRightPillMetricKey = "top_right_pill_metric"

private let kMediaButtonEnabledKey = "media_button_enabled" // Bool
private let kXRSRadioTrailsEnabledKey = "xrs_radio_trails_enabled" // Bool
private let kXRSRadioTrailColorKey = "xrs_radio_trail_color" // String
private let kAutosteerEnabledKey = "autosteer_enabled" // Bool
private let kAutosteerWorkingWidthKey = "autosteer_working_width_m" // Double
private let kAutosteerTrackModeKey = "autosteer_track_mode" // String
private let kAutosteerFarmNameKey = "autosteer_farm_name" // String
private let kAutosteerPaddockNameKey = "autosteer_paddock_name" // String
private let kAutosteerTrackNameKey = "autosteer_track_name" // String
private let kAutosteerAggressivenessKey = "autosteer_aggressiveness" // Double
private let kAutosteerLookAheadKey = "autosteer_look_ahead_m" // Double
private let kAutosteerLightbarStepCMKey = "autosteer_lightbar_step_cm" // Double
private let kAutosteerSetupModeKey = "autosteer_setup_mode" // String
private let kAutosteerSetupActiveKey = "autosteer_setup_active" // Bool
private let kCruiseControlEnabledKey = "cruise_control_enabled" // Bool
private let kCruiseControlSpeedKPHKey = "cruise_control_speed_kph" // Double

struct MapMainView: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct ManualGoToTarget {
        let coordinate: CLLocationCoordinate2D
        let title: String
        let subtitle: String
    }

    private enum LongPressedTrackTarget {
        case previousSession(sessionID: UUID, name: String, createdAt: Date)
        case imported(trackID: UUID, name: String, createdAt: Date)

        var name: String {
            switch self {
            case .previousSession(_, let name, _), .imported(_, let name, _):
                return name
            }
        }

        var createdAt: Date {
            switch self {
            case .previousSession(_, _, let createdAt), .imported(_, _, let createdAt):
                return createdAt
            }
        }
    }

    private enum TopSidePillMetric: String, CaseIterable, Identifiable {
        case weather
        case wind
        case altitude
        case distanceToTarget
        case etaAtTarget
        case headingBearing
        case tripDistance

        var id: String { rawValue }

        var menuTitle: String {
            switch self {
            case .weather: return "Weather"
            case .wind: return "Wind"
            case .altitude: return "Altitude"
            case .distanceToTarget: return "Distance to Target"
            case .etaAtTarget: return "ETA at Target"
            case .headingBearing: return "Heading / Bearing"
            case .tripDistance: return "Total kms on track / trip"
            }
        }
    }

    private enum TopSidePillPosition {
        case left
        case right
    }

    private struct TopSidePillContent {
        let valueText: String
        let labelText: String
        let systemImage: String
        let imageRotationDegrees: Double
        let animateRotation: Bool
    }

    private struct AutosteerGuidanceStatus {
        let signedOffsetToNearestLineM: Double
        let nearestLineIndex: Int

        var offsetCentimeters: Double {
            abs(signedOffsetToNearestLineM) * 100
        }

        var lineIsLeft: Bool {
            signedOffsetToNearestLineM < 0
        }
    }

    private struct RawAutosteerGuidanceSample {
        let signedDistanceToBaseLineM: Double
        let nearestLineIndex: Int
    }

    private struct PendingAutosteerTrackSaveRequest {
        let farmName: String
        let paddockName: String
        let trackName: String
    }

    private enum MapModeOption: String, CaseIterable, Identifiable {
        case explore
        case driving
        case hybrid
        case satellite
        case blank

        var id: String { rawValue }

        var title: String {
            switch self {
            case .explore: return "Explore"
            case .driving: return "Driving"
            case .hybrid: return "Hybrid"
            case .satellite: return "Satellite"
            case .blank: return "Blank"
            }
        }

        var subtitle: String {
            switch self {
            case .explore: return "General map"
            case .driving: return "Road focus"
            case .hybrid: return "Roads + imagery"
            case .satellite: return "Aerial imagery"
            case .blank: return "No base map"
            }
        }

        var storedValue: String {
            switch self {
            case .explore: return "standard"
            case .driving: return "plain"
            case .hybrid: return "hybrid"
            case .satellite: return "satellite"
            case .blank: return "blank"
            }
        }

        var systemImage: String {
            switch self {
            case .explore: return "map.fill"
            case .driving: return "car.fill"
            case .hybrid: return "square.3.layers.3d.top.filled"
            case .satellite: return "globe.americas.fill"
            case .blank: return "square.slash"
            }
        }

        var tint: Color {
            switch self {
            case .explore: return .blue
            case .driving: return .green
            case .hybrid: return .orange
            case .satellite: return .purple
            case .blank: return .gray
            }
        }

        var isDarkPreview: Bool {
            switch self {
            case .explore, .driving, .hybrid, .blank:
                return true
            case .satellite:
                return false
            }
        }
    }

    private enum AutosteerReadinessStep: Int, CaseIterable, Identifiable {
        case autosteerEnabled
        case gpsSignalValid
        case guidanceTrackSelected
        case goButtonPressed

        var id: Int { rawValue }
    }


    @EnvironmentObject private var app: AppState
    @StateObject private var location = LocationService()
    @StateObject private var weatherStore = WeatherPillStore()
    @StateObject private var smartETA = SmartETAEstimator()

    @State private var followUser = true
    @State private var showSettings = false
    @State private var showRingsSettings = false
    @State private var gotoTarget: MusterMarker? = nil

    @State private var showMarkerSheet = false
    @State private var showPreviousMusters = false
    @State private var showCurrentTrack = false
    @State private var pendingMarkerCoordinate: CLLocationCoordinate2D? = nil
    @State private var markerSheetPointA: CLLocationCoordinate2D? = nil
    @State private var markerSheetPointB: CLLocationCoordinate2D? = nil
    @State private var selectedQuickZoomMeters: Double? = nil
    @State private var showMapLayerSheet = false
    @State private var showArrivedBanner = false
    @State private var showQuickZoomEditor = false
    @State private var showImportFilterSheet = false
    @State private var showImportFlow = false
    @State private var showMapSetsSheet = false
    @State private var cruiseSpeedPopupText: String?
    @State private var zoomDistancePopupText: String?
    @State private var zoomDistanceHideWorkItem: DispatchWorkItem?
    @State private var cruiseSpeedPopupHideWorkItem: DispatchWorkItem?
    @State private var mapStyleBeforeAutosteerLock: String = "standard"
    @State private var startMapSetCreationFlowOnOpen = false
    @State private var showMissingMapSetPrompt = false
    @State private var pendingTrackName = ""
    @State private var showNewTrackNamePrompt = false
    @State private var displayedActiveTrackPoints: [TrackPoint] = []

    // Long-press marker actions
    @State private var longPressedSessionMarker: MusterMarker? = nil
    @State private var longPressedMapMarker: MapMarker? = nil
    @State private var showLongPressedSessionMarkerDialog = false
    @State private var showLongPressedMapMarkerDialog = false
    @State private var longPressedTrackTarget: LongPressedTrackTarget? = nil
    @State private var showLongPressedTrackDialog = false
    @State private var pendingTrackDeleteConfirmation: LongPressedTrackTarget? = nil
    @State private var showTrackDeleteConfirmationAlert = false

    // Editing / moving session marker
    @State private var editingSessionMarker: MusterMarker? = nil
    @State private var editingSessionMarkerName: String = ""
    @State private var movingSessionMarker: MusterMarker? = nil

    // Editing / moving permanent map marker
    @State private var editingMapMarker: MapMarker? = nil
    @State private var editingMapMarkerName: String = ""
    @State private var movingMapMarker: MapMarker? = nil

    @State private var showEditSessionMarkerAlert = false
    @State private var showEditMapMarkerAlert = false

    @State private var topPillPickerSide: TopSidePillPosition? = nil

    // Generic Go To target for any non-sheep marker
    @State private var manualGoToTarget: ManualGoToTarget? = nil
    @State private var activeRadioGoToContactID: UUID? = nil

    // Sheep quick-drop scrub UI
    @State private var showSheepCountPopover = false
    @State private var sheepCountSelectionIndex = 0
    @State private var suppressNextSheepButtonTap = false
    @State private var isSheepScrubbing = false
    @State private var sheepScrubStartY: CGFloat? = nil
    @State private var sheepLastHapticIndex: Int? = nil

    @State private var showFenceApproachWarning = false
    @State private var activeFenceWarningBoundaryID: UUID? = nil
    @State private var lastFenceWarningAt: Date = .distantPast
    @State private var fenceWarningDistanceMeters: Double? = nil
    @State private var fenceWarningPlayer: AVAudioPlayer?

    @AppStorage(kRingCountKey) private var ringCount: Int = 4
    @AppStorage(kRingSpacingKey) private var ringSpacingM: Double = 100
    @AppStorage(kRingColorKey) private var ringColorRaw: String = "blue"
    @AppStorage(kRingThicknessScaleKey) private var ringThicknessScale: Double = 1.0
    @AppStorage(kRingDistanceLabelsEnabledKey) private var ringDistanceLabelsEnabled: Bool = true
    @AppStorage(kMapOrientationKey) private var orientationRaw: String = "headsUp"
    @AppStorage(kHeadsUpPitchDegreesKey) private var headsUpPitchDegrees: Double = 45
    @AppStorage(kHeadsUpUserVerticalOffsetKey) private var headsUpUserVerticalOffset: Double = 10
    @AppStorage("map_style") private var mapStyleRaw: String = "standard"
    @AppStorage(kSheepPinEnabledKey) private var sheepPinEnabled: Bool = true
    @AppStorage(kSheepPinIconKey) private var sheepPinIconRaw: String = "sheep"
    @AppStorage(kTopLeftPillMetricKey) private var topLeftPillMetricRaw: String = TopSidePillMetric.weather.rawValue
    @AppStorage(kTopRightPillMetricKey) private var topRightPillMetricRaw: String = TopSidePillMetric.wind.rawValue

    @AppStorage(kQuickZoom1MetersKey) private var quickZoom1M: Double = 1000
    @AppStorage(kQuickZoom2MetersKey) private var quickZoom2M: Double = 5000
    @AppStorage(kQuickZoom3MetersKey) private var quickZoom3M: Double = 12000

    // Admin tuning
    @AppStorage(kAdminBottomSheetSnapThresholdKey) private var bottomSheetSnapThreshold: Double = 80
    @AppStorage(kAdminBottomSheetSpringResponseKey) private var bottomSheetSpringResponse: Double = 0.34
    @AppStorage(kAdminBottomSheetSpringDampingKey) private var bottomSheetSpringDamping: Double = 0.88
    @AppStorage(kAdminRightControlsBottomGapKey) private var rightControlsBottomGap: Double = 96

    @AppStorage(kMediaButtonEnabledKey) private var mediaButtonEnabled: Bool = true
    @AppStorage(kXRSRadioTrailsEnabledKey) private var xrsRadioTrailsEnabled: Bool = true
    @AppStorage(kXRSRadioTrailColorKey) private var xrsRadioTrailColorRaw: String = "blue"
    @AppStorage(kAutosteerEnabledKey) private var autosteerEnabled: Bool = false
    @AppStorage(kAutosteerWorkingWidthKey) private var autosteerWorkingWidthM: Double = 36
    @AppStorage(kAutosteerTrackModeKey) private var autosteerTrackModeRaw: String = "A+B line"
    @AppStorage(kAutosteerFarmNameKey) private var autosteerFarmName: String = ""
    @AppStorage(kAutosteerPaddockNameKey) private var autosteerPaddockName: String = ""
    @AppStorage(kAutosteerTrackNameKey) private var autosteerTrackName: String = ""
    @AppStorage(kAutosteerLookAheadKey) private var autosteerLookAheadM: Double = 12
    @AppStorage(kAutosteerLightbarStepCMKey) private var autosteerLightbarStepCM: Double = 2
    @AppStorage(kAutosteerSetupModeKey) private var autosteerSetupModeRaw: String = "none"
    @AppStorage(kAutosteerSetupActiveKey) private var autosteerSetupActive: Bool = false
    @AppStorage(kCruiseControlEnabledKey) private var cruiseControlEnabled: Bool = false
    @AppStorage(kCruiseControlSpeedKPHKey) private var cruiseControlSpeedKPH: Double = 0

    private var isHeadsUp: Bool { orientationRaw == "headsUp" }

    @State private var recenterNonce: Int = 0
    @State private var metersPerPoint: Double = 1.0
    @State private var activeTrackAppearanceRaw: String = "altitude"
    @State private var panelDetent: MapBottomPanelDetent = .collapsed
    @State private var showRadioDebug = false
    @State private var fitRadiosNonce: Int = 0
    @State private var showRadioList = false
    @State private var showTPMSDashboard = false
    @State private var showAutosteerSettings = false
    @State private var showAutosteerQuickActions = false
    @State private var showAutosteerTrackSelector = false
    @State private var showAutosteerLightbarStepEditor = false
    @State private var autosteerLightbarStepDraftCM: Double = 2
    @State private var autosteerActive = false
    @State private var autosteerPointA: CLLocationCoordinate2D? = nil
    @State private var autosteerPointB: CLLocationCoordinate2D? = nil
    @State private var autosteerHeadingInput: String = ""
    @State private var showAutosteerHeadingPrompt = false
    @State private var showAutosteerHeadingValidationWarning = false
    @State private var autosteerHeadingValidationWarningMessage = ""
    @State private var curveTrackRecording = false
    @State private var curvePulse = false
    @State private var curveRecordedCenters: [CLLocationCoordinate2D] = []
    @State private var showAutosteerTrackSaveSheet = false
    @State private var showAutosteerReadinessSheet = false
    @State private var showCruiseControlSheet = false
    @State private var autosteerSaveFarm = ""
    @State private var autosteerSavePaddock = ""
    @State private var autosteerSaveTrackName = ""
    @State private var autosteerFilteredSignedOffsetM: Double = 0
    @State private var autosteerLockedGuidanceLineIndex: Int = 0
    @State private var autosteerLastGuidanceTimestamp: Date? = nil
    @State private var autosteerLastRawBaseDistanceM: Double? = nil
    @State private var autosteerGuidanceSeeded = false
    @State private var mapCenterCoordinate: CLLocationCoordinate2D? = nil
    @State private var knownFarms: [AutosteerFarmRecord] = []
    @State private var expandedAutosteerPaddockIDs: Set<UUID> = []
    @State private var selectedFarmOption: String = "__new__"
    @State private var selectedPaddockOption: String = "__new__"
    @State private var selectedTrackQuickPick: String? = nil
    @State private var showAddFarmPrompt = false
    @State private var showAddPaddockPrompt = false
    @State private var showDuplicateTrackWarning = false
    @State private var newFarmNameInput = ""
    @State private var newPaddockNameInput = ""
    @State private var pendingTrackSaveRequest: PendingAutosteerTrackSaveRequest? = nil

    private let sheepPinTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let xrsCleanupTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let activeTrackDisplayRefreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private let topPillHeight: CGFloat = 42
    private let topSidePillMinWidth: CGFloat = 104
    private let topSpeedPillMinWidth: CGFloat = 160

    private let sheepCountOptions: [Int] = [1, 2, 3, 4, 5, 10, 15, 20, 25, 50, 75, 100]

    private let fenceWarningSpeedThresholdMPS: CLLocationSpeed = 10.0 / 3.6
    private let fenceWarningShowDistanceMeters: CLLocationDistance = 75
    private let fenceWarningHideDistanceMeters: CLLocationDistance = 95
    private let fenceWarningHeadingToleranceDegrees: Double = 55
    private let fenceWarningCooldownSeconds: TimeInterval = 8

    private var activeSession: MusterSession? { app.muster.activeSession }
    private var mapMarkers: [MapMarker] { app.muster.visibleMapMarkers }
    private var activeSheepTarget: MusterMarker? { app.muster.activeSheepTarget }

    private var isSheepPinReady: Bool {
        location.lastLocation != nil
    }

    private var sheepPinButtonIcon: String {
        switch sheepPinIconRaw {
        case "cattle": return "🐄"
        case "flag": return "🚩"
        case "target": return "🎯"
        case "bell": return "🔔"
        case "pin": return "📍"
        default: return "🐑"
        }
    }

    private var xrsContacts: [XRSRadioContact] {
        app.xrs.allContacts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var prioritizedGroupTrackingContacts: [XRSRadioContact] {
        app.cellularTracking.mappedContactsWithRadioFallback(xrsContacts)
    }

    private var shouldShowXRSTrailsOnMap: Bool {
        xrsRadioTrailsEnabled && activeSession?.isActive == true
    }

    private var gpsConnectedForAutosteer: Bool {
        location.lastLocation != nil && location.lastError == nil
    }

    private var autosteerTrackReady: Bool {
        let selectedTrackHasPreview = (selectedAutosteerTrackRecord?.previewCoordinates.count ?? 0) >= 2
        let setupTrackHasPreview = previewCoordinatesForPendingSetup().count >= 2
        return selectedTrackHasPreview || setupTrackHasPreview
    }

    private var curveTrackHasRecordedPoints: Bool {
        curveRecordedCenters.count >= 2
    }

    private var autosteerGoReady: Bool {
        autosteerEnabled &&
        gpsConnectedForAutosteer &&
        autosteerTrackReady
    }

    private var autosteerPrerequisitesReady: Bool {
        autosteerEnabled && gpsConnectedForAutosteer && autosteerTrackReady
    }

    private var shouldShowGuidanceOnlyViewport: Bool {
        false
    }

    private var temporaryPreviewPointA: CLLocationCoordinate2D? {
        if markerSheetPointA != nil || markerSheetPointB != nil {
            return markerSheetPointA
        }

        guard isAutosteerTrackSetupActive else { return nil }
        switch autosteerSetupModeRaw {
        case "A+B line", "A+Heading":
            return autosteerPointA
        default:
            return nil
        }
    }

    private var temporaryPreviewPointB: CLLocationCoordinate2D? {
        if markerSheetPointA != nil || markerSheetPointB != nil {
            return markerSheetPointB
        }

        guard isAutosteerTrackSetupActive else { return nil }
        switch autosteerSetupModeRaw {
        case "A+B line":
            return autosteerPointB
        default:
            return nil
        }
    }

    private var autosteerReadinessCount: Int {
        [autosteerEnabled, gpsConnectedForAutosteer, autosteerTrackReady, autosteerActive].filter { $0 }.count
    }

    private var autosteerReadinessSteps: [(step: AutosteerReadinessStep, title: String, isComplete: Bool)] {
        [
            (.autosteerEnabled, "Part 1 of 4 · Autosteer enabled", autosteerEnabled),
            (.gpsSignalValid, "Part 2 of 4 · GPS/Satellite signal valid", gpsConnectedForAutosteer),
            (.guidanceTrackSelected, "Part 3 of 4 · Valid guidance track selected", autosteerTrackReady),
            (.goButtonPressed, "Part 4 of 4 · Auto steer button pressed", autosteerActive)
        ]
    }

    private var autosteerReadinessAccessibilityHint: String {
        autosteerReadinessSteps
            .map { "\($0.title): \($0.isComplete ? "ready" : "not ready")" }
            .joined(separator: ", ")
    }

    private var isAutosteerTrackSetupActive: Bool {
        autosteerSetupActive && autosteerSetupModeRaw != "none"
    }

    private var existingPaddocksForSelectedFarm: [String] {
        let farmName = autosteerSaveFarm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let farm = knownFarms.first(where: { $0.name.caseInsensitiveCompare(farmName) == .orderedSame }) else {
            return []
        }
        return farm.paddocks.map(\.name)
    }

    private var farmOptionsForSaveSheet: [String] {
        var options = knownFarms.map(\.name)
        let pendingFarm = autosteerSaveFarm.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingFarm.isEmpty == false,
           options.contains(where: { $0.caseInsensitiveCompare(pendingFarm) == .orderedSame }) == false {
            options.insert(pendingFarm, at: 0)
        }
        return options
    }

    private var paddockOptionsForSaveSheet: [String] {
        var options = existingPaddocksForSelectedFarm
        let pendingPaddock = autosteerSavePaddock.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingPaddock.isEmpty == false,
           options.contains(where: { $0.caseInsensitiveCompare(pendingPaddock) == .orderedSame }) == false {
            options.insert(pendingPaddock, at: 0)
        }
        return options
    }

    private let trackQuickPickOptions: [String] = ["North", "East", "South", "West"]

    private var isAutosteerSaveFormComplete: Bool {
        autosteerSaveFarm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        autosteerSavePaddock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        autosteerSaveTrackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var selectedAutosteerFarmDisplay: String {
        let farm = autosteerFarmName.trimmingCharacters(in: .whitespacesAndNewlines)
        return farm.isEmpty ? "—" : farm
    }

    private var selectedAutosteerPaddockDisplay: String {
        let paddock = autosteerPaddockName.trimmingCharacters(in: .whitespacesAndNewlines)
        return paddock.isEmpty ? "—" : paddock
    }

    private var selectedAutosteerNameDisplay: String {
        let track = autosteerTrackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return track.isEmpty ? "—" : track
    }

    private var selectedAutosteerTrackRecord: AutosteerTrackRecord? {
        let farm = autosteerFarmName.trimmingCharacters(in: .whitespacesAndNewlines)
        let paddock = autosteerPaddockName.trimmingCharacters(in: .whitespacesAndNewlines)
        let track = autosteerTrackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard farm.isEmpty == false, paddock.isEmpty == false, track.isEmpty == false else { return nil }

        func findTrack(in farms: [AutosteerFarmRecord]) -> AutosteerTrackRecord? {
            farms
                .first(where: { $0.name.caseInsensitiveCompare(farm) == .orderedSame })?
                .paddocks.first(where: { $0.name.caseInsensitiveCompare(paddock) == .orderedSame })?
                .tracks.first(where: { $0.name.caseInsensitiveCompare(track) == .orderedSame })
        }

        if let match = findTrack(in: knownFarms) {
            return match
        }

        return findTrack(in: AutosteerLibraryStore.load())
    }

    private var xrsTrailGroups: [[CLLocationCoordinate2D]] {
        guard shouldShowXRSTrailsOnMap else { return [] }

        return xrsContacts.compactMap { contact in
            let trail = app.xrs.trailPoints(for: contact.name)
            let coords = trail.map(\.coordinate)
            return coords.count >= 2 ? coords : nil
        }
    }
    private var leftPillMetric: TopSidePillMetric {
        TopSidePillMetric(rawValue: topLeftPillMetricRaw) ?? .weather
    }

    private var rightPillMetric: TopSidePillMetric {
        TopSidePillMetric(rawValue: topRightPillMetricRaw) ?? .wind
    }

    private var speedNumberText: String {
        guard let s = location.lastLocation?.speed, s >= 0 else { return "—" }
        let (value, _) = UnitFormatting.speedValueAndUnit(fromMetersPerSecond: s)
        return String(format: "%.0f", max(0, value))
    }

    private var speedUnitText: String {
        let (_, unit) = UnitFormatting.speedValueAndUnit(fromMetersPerSecond: 0)
        return unit
    }

    private var speedPillActualSpeedKPH: Double? {
        guard let speedMPS = location.lastLocation?.speed, speedMPS >= 0 else { return nil }
        return speedMPS * 3.6
    }

    private var clampedCruiseControlSpeedKPH: Double {
        max(2, min(100, cruiseControlSpeedKPH))
    }

    private var cruiseControlDisplaySpeedText: String {
        String(format: "%.0f", clampedCruiseControlSpeedKPH)
    }

    private var cruiseControlDisplayUnitText: String {
        "km/h"
    }

    private var cruiseControlSetSpeedText: String {
        "\(cruiseControlDisplaySpeedText) \(cruiseControlDisplayUnitText)"
    }

    private var cruiseControlIsActive: Bool {
        cruiseControlEnabled && autosteerActive
    }

    private var speedPillShouldHighlightMatch: Bool {
        guard cruiseControlIsActive,
              let actualSpeedKPH = speedPillActualSpeedKPH else { return false }

        return abs(actualSpeedKPH - clampedCruiseControlSpeedKPH) <= 1
    }

    private var speedPillRingColor: Color {
        if cruiseControlIsActive { return .green }
        if cruiseControlEnabled { return .orange }
        return .clear
    }

    private var hasSpeedPillRing: Bool {
        cruiseControlEnabled
    }

    private var elevationText: String {
        guard let altitude = location.lastLocation?.altitude else { return "--" }
        return UnitFormatting.formattedDistance(altitude, decimalsIfLarge: 0)
    }

    private var kilometresForDayText: String {
        app.muster.kilometresForDayText
    }

    private var markerCount: Int {
        activeSession?.markers.count ?? 0
    }

    private var permanentMarkerCount: Int {
        mapMarkers.count
    }

    private var xrsRadioCount: Int {
        xrsContacts.count
    }

    private var hasActiveRadioConnection: Bool {
        app.xrs.isConnected
    }

    private var previousMusterCount: Int {
        app.muster.previousSessions.count
    }

    private var trackPointCount: Int {
        activeSession?.points.count ?? 0
    }

    private var visibleImportCategoryCount: Int {
        ImportCategory.allCases.filter { app.muster.isImportCategoryVisible($0) }.count
    }

    private var importFilterSummaryText: String {
        "\(visibleImportCategoryCount)/\(ImportCategory.allCases.count)"
    }

    private var effectiveTargetCoordinate: CLLocationCoordinate2D? {
        if let manualGoToTarget { return manualGoToTarget.coordinate }
        return activeSheepTarget?.coordinate
    }

    private var destinationDistanceMeters: CLLocationDistance? {
        guard let user = location.lastLocation,
              let target = effectiveTargetCoordinate else { return nil }

        let targetLoc = CLLocation(latitude: target.latitude, longitude: target.longitude)
        return user.distance(from: targetLoc)
    }

    private var destinationDistanceText: String {
        guard let dist = destinationDistanceMeters else { return "—" }
        if dist < 30 { return "Here" }
        return UnitFormatting.formattedDistanceCompact(dist, decimalsIfLarge: 1)
    }

    private var destinationETASeconds: TimeInterval? {
        smartETA.etaSeconds
    }

    private var destinationETAText: String {
        guard let eta = smartETA.etaSeconds else { return "—" }
        if smartETA.isArriving { return "Arriving" }

        let arrivalDate = Date().addingTimeInterval(eta)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: arrivalDate)
    }

    private var destinationSubtitleText: String {
        if let manualGoToTarget {
            return manualGoToTarget.subtitle
        }

        guard let target = activeSheepTarget else { return "" }
        let trimmed = target.note?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return "Mob"
    }

    private var targetArrowRotationDegrees: Double {
        guard let user = location.lastLocation,
              let target = effectiveTargetCoordinate else { return 0 }

        let bearingToTarget = bearingDegrees(
            from: user.coordinate,
            to: target
        )

        let facing = currentFacingDegrees(from: user)
        return shortestSignedDegrees(from: facing, to: bearingToTarget)
    }

    private var headingBearingValueText: String {
        let degrees: Double

        if let user = location.lastLocation, let target = effectiveTargetCoordinate {
            degrees = bearingDegrees(from: user.coordinate, to: target)
        } else if let user = location.lastLocation {
            degrees = currentFacingDegrees(from: user)
        } else {
            return "—"
        }

        return "\(Int(degrees.rounded()))°"
    }

    private var headingBearingLabelText: String {
        effectiveTargetCoordinate != nil ? "Bearing" : "Heading"
    }

    private var headingBearingRotationDegrees: Double {
        if let user = location.lastLocation, let target = effectiveTargetCoordinate {
            return bearingDegrees(from: user.coordinate, to: target)
        }

        guard let user = location.lastLocation else { return 0 }
        return currentFacingDegrees(from: user)
    }

    private var tripDistanceMeters: CLLocationDistance {
        guard activeTrackPoints.count >= 2 else { return 0 }

        var total: CLLocationDistance = 0

        for index in 1..<activeTrackPoints.count {
            let previous = activeTrackPoints[index - 1].coordinate
            let current = activeTrackPoints[index].coordinate

            let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
            total += currentLocation.distance(from: previousLocation)
        }

        return total
    }

    private var tripDistanceText: String {
        let meters = tripDistanceMeters

        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000.0)
        }

        return "\(Int(meters.rounded()))m"
    }

    private var totalDistanceTextForCurrentTrack: String {
        let meters = tripDistanceMeters

        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000.0)
        }

        return "\(Int(meters.rounded())) m"
    }

    private var normalizedQuickZooms: [Double] {
        [
            normalizedQuickZoomValue(quickZoom1M),
            normalizedQuickZoomValue(quickZoom2M),
            normalizedQuickZoomValue(quickZoom3M)
        ]
    }

    private var activeTrackPoints: [TrackPoint] {
        activeSession?.points ?? []
    }

    private var visiblePreviousTrackSessions: [MusterSession] {
        app.muster.visiblePreviousSessions
    }

    private var sessionMarkers: [MusterMarker] {
        activeSession?.markers ?? []
    }

    private var currentMapMarkers: [MapMarker] {
        mapMarkers
    }

    private var importedBoundaries: [ImportedBoundary] {
        app.muster.visibleImportedBoundaries
    }

    private var importedTracks: [ImportedTrack] {
        app.muster.visibleImportedTracks
    }

    private var importedMarkers: [ImportedMarker] {
        app.muster.visibleImportedMarkers
    }

    private var activeDestinationMarkerID: UUID? {
        gotoTarget?.id
    }

    private var weatherRefreshKey: String {
        guard let loc = location.lastLocation else { return "none" }
        let lat = (loc.coordinate.latitude * 1000).rounded() / 1000
        let lon = (loc.coordinate.longitude * 1000).rounded() / 1000
        return "\(lat),\(lon)"
    }

    private var normalizedHeadsUpPitchDegrees: Double {
        let allowed: [Double] = [0, 45, 80]
        if allowed.contains(headsUpPitchDegrees) { return headsUpPitchDegrees }
        return allowed.min(by: { abs($0 - headsUpPitchDegrees) < abs($1 - headsUpPitchDegrees) }) ?? 45
    }

    private var normalizedHeadsUpUserVerticalOffset: Double {
        min(max(headsUpUserVerticalOffset.rounded(), 0), 10)
    }

    private var effectiveMapPitchDegrees: Double {
        isHeadsUp ? normalizedHeadsUpPitchDegrees : 0
    }

    private var headsUpPitchLabel: String {
        let displayValue = effectiveMapPitchDegrees

        switch Int(displayValue.rounded()) {
        case 0:
            return "0°"
        case 45:
            return "45°"
        case 80:
            return "80°"
        default:
            return "\(Int(displayValue.rounded()))°"
        }
    }

    private var topPillPickerPresented: Binding<Bool> {
        Binding(
            get: { topPillPickerSide != nil },
            set: { if !$0 { topPillPickerSide = nil } }
        )
    }

    private var topPillPickerTitle: String {
        switch topPillPickerSide {
        case .left:
            return "Left Pill"
        case .right:
            return "Right Pill"
        case nil:
            return "Choose Pill"
        }
    }

    private var selectedSheepCountValue: Int {
        sheepCountOptions[sheepCountSelectionIndex]
    }

    private var selectedSheepCountDisplayText: String {
        sheepCountDisplayText(for: selectedSheepCountValue)
    }

    private var mapCenterChangeToken: String {
        guard let center = mapCenterCoordinate else { return "nil" }
        return "\(center.latitude),\(center.longitude)"
    }

    private var sheepCountPopoverLabelText: String {
        switch sheepPinIconRaw {
        case "cattle":
            return "CATTLE"
        case "flag":
            return "FLAG"
        case "target":
            return "TARGET"
        case "bell":
            return "BELL"
        case "pin":
            return "PIN"
        default:
            return "SHEEP"
        }
    }

    private var selectedMapModeOption: MapModeOption {
        switch mapStyleRaw {
        case "plain":
            return .driving
        case "hybrid":
            return .hybrid
        case "satellite":
            return .satellite
        case "blank":
            return .blank
        default:
            return .explore
        }
    }
    var body: some View {
        observedMainContent
    }

    private var sheetHostedMainContent: some View {
        mainContent
            .sheet(isPresented: $showSettings) {
                settingsSheet
            }
            .sheet(isPresented: $showRingsSettings) {
                ringsSettingsSheet
            }
            .sheet(isPresented: $showMarkerSheet, onDismiss: {
                pendingMarkerCoordinate = nil
                markerSheetPointA = nil
                markerSheetPointB = nil
            }) {
                markerSheet
            }
            .sheet(isPresented: $showRadioDebug) {
                BLERadioDebugView()
                    .environmentObject(app)
            }
            .sheet(isPresented: $showRadioList) {
                radioListSheet
            }
            .sheet(isPresented: $showQuickZoomEditor) {
                quickZoomEditorSheet
            }
            .sheet(isPresented: $showImportFilterSheet) {
                importFilterSheet
            }
            .sheet(isPresented: $showImportFlow) {
                NavigationStack {
                    ImportExportView(mode: .import, startImporterOnAppear: true)
                        .environmentObject(app)
                }
            }
            .sheet(isPresented: $showMapSetsSheet) {
                MapSetsSheetView(startInCreateFlow: startMapSetCreationFlowOnOpen)
                    .environmentObject(app)
            }
            .onChange(of: showMapSetsSheet) { _, isPresented in
                handleMapSetsSheetChanged(isPresented)
            }
            .onChange(of: autosteerSetupActive) { _, isActive in
                handleAutosteerSetupActiveChanged(isActive)
                resetAutosteerGuidanceFilter()
            }
            .onChange(of: autosteerWorkingWidthM) { _, _ in
                resetAutosteerGuidanceFilter()
            }
            .onChange(of: autosteerTrackModeRaw) { _, _ in
                resetAutosteerGuidanceFilter()
            }
            .onChange(of: autosteerFarmName) { _, _ in
                resetAutosteerGuidanceFilter()
            }
            .onChange(of: autosteerPaddockName) { _, _ in
                resetAutosteerGuidanceFilter()
            }
            .onChange(of: autosteerTrackName) { _, _ in
                resetAutosteerGuidanceFilter()
            }
            .onChange(of: autosteerEnabled) { _, isEnabled in
                if isEnabled {
                    applyAutosteerMapLockIfNeeded()
                } else {
                    autosteerActive = false
                    if mapStyleRaw == "blank", mapStyleBeforeAutosteerLock != "blank" {
                        mapStyleRaw = mapStyleBeforeAutosteerLock
                    }
                }
            }
            .onChange(of: mapStyleRaw) { _, newStyle in
                if autosteerEnabled, autosteerSetupActive == false, newStyle != "blank" {
                    mapStyleRaw = "blank"
                }
            }
            .onChange(of: orientationRaw) { _, newOrientation in
                if autosteerEnabled, autosteerSetupActive == false, newOrientation != "headsUp" {
                    orientationRaw = "headsUp"
                }
            }
            .onAppear {
                applyAutosteerMapLockIfNeeded()
            }
            .onChange(of: mapCenterChangeToken) { _, _ in
                handleMapCenterCoordinateChanged(mapCenterCoordinate)
            }
            .confirmationDialog(
                "Map Set Required",
                isPresented: $showMissingMapSetPrompt,
                titleVisibility: .visible
            ) {
                Button("Create New Map Set") {
                    startMapSetCreationFlowOnOpen = true
                    showMapSetsSheet = true
                }
                Button("Select Map Set From List") {
                    startMapSetCreationFlowOnOpen = false
                    showMapSetsSheet = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("New Muster or track can’t be started without a Map Set selected.")
            }
            .alert("New Track", isPresented: $showNewTrackNamePrompt) {
                TextField("Track name", text: $pendingTrackName)
                Button("Cancel", role: .cancel) {}
                Button("Start") {
                    if app.muster.startSession(name: pendingTrackName) == false {
                        showMissingMapSetPrompt = true
                    }
                }
            } message: {
                Text("Choose a track name.")
            }
            .sheet(isPresented: $showTPMSDashboard) {
                tpmsDashboardSheet
            }
            .sheet(isPresented: $showAutosteerSettings) {
                NavigationStack {
                    AutosteerSettingsView()
                }
            }
            .sheet(isPresented: $showAutosteerTrackSelector) {
                NavigationStack {
                    List {
                        if knownFarms.isEmpty {
                            Text("No saved autosteer tracks yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(knownFarms) { farm in
                                Section(farm.name) {
                                    ForEach(farm.paddocks) { paddock in
                                        VStack(alignment: .leading, spacing: 10) {
                                            Button {
                                                toggleAutosteerPaddockExpansion(paddockID: paddock.id)
                                            } label: {
                                                let paddockContainsSelectedTrack = isCurrentlySelectedAutosteerPaddock(
                                                    farmName: farm.name,
                                                    paddockName: paddock.name
                                                )
                                                HStack(spacing: 10) {
                                                    Image(systemName: expandedAutosteerPaddockIDs.contains(paddock.id) ? "chevron.down" : "chevron.right")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                    Text(paddock.name)
                                                        .foregroundStyle(.primary)
                                                    Spacer()
                                                    if paddockContainsSelectedTrack {
                                                        ZStack {
                                                            Circle()
                                                                .fill(.green)
                                                                .frame(width: 30, height: 30)
                                                            Text("\(paddock.tracks.count)")
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(.white)
                                                        }
                                                    } else {
                                                        Text("\(paddock.tracks.count)")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(.secondary)
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 4)
                                                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)

                                            if expandedAutosteerPaddockIDs.contains(paddock.id) {
                                                ForEach(paddock.tracks) { track in
                                                    Button {
                                                        autosteerFarmName = farm.name
                                                        autosteerPaddockName = paddock.name
                                                        autosteerTrackName = track.name
                                                        autosteerTrackModeRaw = track.mode
                                                        showAutosteerTrackSelector = false
                                                    } label: {
                                                        let isSelectedTrack = isCurrentlySelectedAutosteerTrack(
                                                            farmName: farm.name,
                                                            paddockName: paddock.name,
                                                            trackName: track.name
                                                        )
                                                        HStack {
                                                            VStack(alignment: .leading, spacing: 4) {
                                                                Text(track.name)
                                                                    .foregroundStyle(.primary)
                                                                Text("\(farm.name) > \(paddock.name) > \(track.name)")
                                                                    .font(.caption)
                                                                    .foregroundStyle(.secondary)
                                                                    .lineLimit(2)
                                                            }

                                                            Spacer()

                                                            if isSelectedTrack {
                                                                Image(systemName: "checkmark.circle.fill")
                                                                    .foregroundStyle(.green)
                                                            }
                                                        }
                                                        .padding(.leading, 24)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Track")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                showAutosteerTrackSelector = false
                            }
                        }
                    }
                    .onAppear(perform: prepareAutosteerTrackSelector)
                }
            }
            .fullScreenCover(isPresented: $showPreviousMusters) {
                previousMustersCover
            }
            .fullScreenCover(isPresented: $showCurrentTrack) {
                currentTrackCover
            }
    }

    private var dialogHostedMainContent: some View {
        sheetHostedMainContent
            .confirmationDialog(
                longPressedSessionMarker?.displayTitle ?? "Marker",
                isPresented: $showLongPressedSessionMarkerDialog,
                titleVisibility: .visible,
                actions: longPressedSessionMarkerDialogActions,
                message: longPressedSessionMarkerDialogMessage
            )
            .confirmationDialog(
                longPressedMapMarker?.displayTitle ?? "Marker",
                isPresented: $showLongPressedMapMarkerDialog,
                titleVisibility: .visible,
                actions: longPressedMapMarkerDialogActions,
                message: longPressedMapMarkerDialogMessage
            )
            .confirmationDialog(
                "Track",
                isPresented: $showLongPressedTrackDialog,
                titleVisibility: .visible,
                actions: longPressedTrackDialogActions,
                message: longPressedTrackDialogMessage
            )
            .alert(
                "Confirm Delete",
                isPresented: $showTrackDeleteConfirmationAlert,
                presenting: pendingTrackDeleteConfirmation
            ) { track in
                Button("Delete", role: .destructive) {
                    deleteLongPressedTrack(track)
                    pendingTrackDeleteConfirmation = nil
                }
            } message: { track in
                Text("Delete \(track.name)? This cannot be undone.")
            }
    }

    private var presentedMainContent: some View {
        dialogHostedMainContent
            .confirmationDialog(
                topPillPickerTitle,
                isPresented: topPillPickerPresented,
                titleVisibility: .visible
            ) {
                ForEach(TopSidePillMetric.allCases) { metric in
                    Button(metric.menuTitle) {
                        applyTopPillMetric(metric)
                    }
                }

                Button("Cancel", role: .cancel) {
                    topPillPickerSide = nil
                }
            } message: {
                Text("Choose what this pill displays.")
            }
            .alert("Edit Marker", isPresented: $showEditSessionMarkerAlert) {
                editSessionMarkerAlertActions
            } message: {
                Text("Update the marker name.")
            }
            .alert("Edit Marker", isPresented: $showEditMapMarkerAlert) {
                editMapMarkerAlertActions
            } message: {
                Text("Update the marker name.")
            }
    }

    private var lifecycleMainContent: some View {
        presentedMainContent
            .onAppear(perform: handleMainViewAppear)
            .onReceive(app.$pendingQuickAction) { _ in
                processPendingQuickActionIfNeeded()
            }
            .onDisappear(perform: handleMainViewDisappear)
            .onChange(of: quickZoom1M) { _, newValue in
                quickZoom1M = normalizedQuickZoomValue(newValue)
                syncSelectedQuickZoomIfNeeded()
            }
            .onChange(of: quickZoom2M) { _, newValue in
                quickZoom2M = normalizedQuickZoomValue(newValue)
                syncSelectedQuickZoomIfNeeded()
            }
            .onChange(of: xrsContacts) { _, contacts in
                guard let activeRadioGoToContactID else { return }
                guard let updated = contacts.first(where: { $0.id == activeRadioGoToContactID }) else { return }

                let trimmedStatus = updated.status?.trimmingCharacters(in: .whitespacesAndNewlines)

                manualGoToTarget = ManualGoToTarget(
                    coordinate: updated.coordinate,
                    title: updated.name,
                    subtitle: trimmedStatus?.isEmpty == false ? (trimmedStatus ?? "Radio") : "Radio"
                )

                GoToLiveActivityManager.shared.start(
                    markerName: updated.name,
                    coordinate: updated.coordinate
                )
            }
            .onChange(of: quickZoom3M) { _, newValue in
                quickZoom3M = normalizedQuickZoomValue(newValue)
                syncSelectedQuickZoomIfNeeded()
            }
            .onChange(of: headsUpPitchDegrees) { _, newValue in
                headsUpPitchDegrees = normalizedHeadsUpPitchValue(newValue)
            }
            .onChange(of: headsUpUserVerticalOffset) { _, newValue in
                headsUpUserVerticalOffset = normalizedHeadsUpUserVerticalOffsetValue(newValue)
            }
            .onChange(of: app.muster.activeSessionID) { _, _ in
                syncDisplayedActiveTrackPoints()
            }
    }

    private var observedMainContent: some View {
        lifecycleMainContent
            .onChange(of: location.lastLocation) { _, newLoc in
                guard let loc = newLoc else { return }

                updateAutosteerGuidanceFilter(using: loc)
                evaluateFenceApproachWarning(using: loc)

                smartETA.update(distance: destinationDistanceMeters)

                if activeSession?.isActive == true {
                    app.muster.considerRecording(location: loc)
                }

                Task {
                    await refreshWeatherIfNeeded()
                }

                if let distance = destinationDistanceMeters,
                   effectiveTargetCoordinate != nil {
                    Task {
                        await GoToLiveActivityManager.shared.update(
                            distanceMeters: distance,
                            relativeBearingDegrees: targetArrowRotationDegrees
                        )
                    }
                } else {
                    Task {
                        await GoToLiveActivityManager.shared.stop()
                    }
                }
            }
            .onReceive(sheepPinTimer) { _ in
                app.muster.tickSheepPinMaintenance()
            }
            .onReceive(xrsCleanupTimer) { _ in
                app.xrs.removeStaleContacts()
            }
            .onReceive(activeTrackDisplayRefreshTimer) { _ in
                syncDisplayedActiveTrackPoints()
            }
            .task(id: weatherRefreshKey) {
                await refreshWeatherIfNeeded()
            }
    }

    // MARK: - Main content

    private var mainContent: some View {
        GeometryReader { geo in
            ZStack {
                mapLayer(totalHeight: geo.size.height)
                    .ignoresSafeArea()

                if showArrivedBanner {
                    VStack {
                        GlassPill {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)

                                Text("Arrived at Target")
                                    .font(.headline)
                            }
                        }
                        .padding(.top, 56)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(30)
                }

                if let cruiseSpeedPopupText {
                    Text(cruiseSpeedPopupText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(37)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        ZStack(alignment: .top) {
                            topPillRow

                            if effectiveTargetCoordinate != nil {
                                VStack {
                                    sheepCompassWidget
                                        .padding(.top, 56)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 2)

                    Spacer()
                }

                if let zoomDistancePopupText {
                    VStack {
                        HStack {
                            topLeftZoomPill(zoomDistancePopupText: zoomDistancePopupText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, topPillHeight + 22)

                        Spacer()
                    }
                    .zIndex(36)
                    .allowsHitTesting(false)
                }

                if showFenceApproachWarning {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(39)

                    VStack {
                        Spacer()

                        VStack(spacing: 10) {
                            Text("WARNING")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Fence approaching")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            if let dist = fenceWarningDistanceMeters {
                                Text(UnitFormatting.formattedDistance(dist, decimalsIfLarge: 0))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(maxWidth: 340)
                        .background(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(.red.opacity(0.96))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

                        Spacer()
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(40)
                }

                if showMapLayerSheet {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                showMapLayerSheet = false
                            }
                        }
                }

                if showMapLayerSheet {
                    VStack(spacing: 0) {
                        Spacer()

                        mapLayerSheet
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 10)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
                }

                if showAutosteerQuickActions {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            dismissAutosteerQuickActions()
                        }
                        .zIndex(24)

                    autosteerQuickActionsSheet(
                        maxWidth: autosteerGuidanceBarMaxWidth(for: geo.size.width)
                    )
                        .padding(.horizontal, 18)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                        .zIndex(25)
                }

                VStack(spacing: 0) {
                    Spacer()

                    if movingSessionMarker != nil || movingMapMarker != nil {
                        moveBanner
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }

                    appleMapsStyleBottomPanel(
                        totalHeight: geo.size.height,
                        safeAreaBottom: geo.safeAreaInsets.bottom
                    )
                }
                .zIndex(10)
            }
            .overlay(alignment: .bottomTrailing) {
                if !showMapLayerSheet {
                    VStack(spacing: 10) {
                        if !followUser {
                            centerMapButton
                        }

                        rightSideControlPill
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, floatingControlsBottomPadding(for: geo.size.height))
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: panelDetent)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !showMapLayerSheet {
                    leftSideFloatingPills
                        .padding(.leading, 12)
                        .padding(.bottom, floatingControlsBottomPadding(for: geo.size.height))
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: panelDetent)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if !showMapLayerSheet, autosteerEnabled {
                    autosteerGuidanceBar(autosteerGuidanceStatus)
                        .frame(maxWidth: autosteerGuidanceBarMaxWidth(for: geo.size.width))
                        .padding(.bottom, floatingControlsBottomPadding(for: geo.size.height) + 2)
                        .onLongPressGesture(minimumDuration: 0.45) {
                            presentAutosteerLightbarStepEditor()
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .overlay(alignment: .top) {
                if isAutosteerTrackSetupActive {
                    autosteerTrackSetupOverlay(maxWidth: geo.size.width)
                        .padding(.top, 76)
                }
            }
            .overlay(alignment: .center) {
                if isAutosteerTrackSetupActive {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.red)
                        .shadow(radius: 4)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showArrivedBanner)
        .onAppear {
            cruiseControlSpeedKPH = clampedCruiseControlSpeedKPH
        }
        .onChange(of: cruiseControlSpeedKPH) { _, _ in
            let clamped = clampedCruiseControlSpeedKPH
            if abs(cruiseControlSpeedKPH - clamped) > 0.001 {
                cruiseControlSpeedKPH = clamped
            }
        }
        .sheet(isPresented: $showAutosteerLightbarStepEditor) {
            autosteerLightbarStepEditorSheet
                .presentationDetents([.height(250)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCruiseControlSheet) {
            cruiseControlSheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
    }

    private var autosteerLightbarStepEditorSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Lightbar Step Size")
                        .font(.headline)
                    Text("Current: \(UnitFormatting.formattedCentimeters(autosteerLightbarStepCM))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(UnitFormatting.formattedCentimeters(autosteerLightbarStepDraftCM))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Slider(value: $autosteerLightbarStepDraftCM, in: 1...50, step: 1)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button("Cancel") {
                        showAutosteerLightbarStepEditor = false
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        autosteerLightbarStepCM = autosteerLightbarStepDraftCM
                        showAutosteerLightbarStepEditor = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .navigationTitle("Autosteer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var cruiseControlSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Enable Cruise Control", isOn: $cruiseControlEnabled)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Cruise Speed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(Int(clampedCruiseControlSpeedKPH)) km/h")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Slider(value: $cruiseControlSpeedKPH, in: 2...100, step: 1)
                    Text("Adjust between 2 and 100 km/h.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Cruise Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showCruiseControlSheet = false
                    }
                }
            }
        }
    }

    private func presentAutosteerLightbarStepEditor() {
        autosteerLightbarStepDraftCM = max(1, min(50, autosteerLightbarStepCM.rounded()))
        showAutosteerLightbarStepEditor = true
    }

    private func autosteerQuickActionsSheet(maxWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    dismissAutosteerQuickActions()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }

            Text("Autosteer")
                .font(.system(size: 50 / 3, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 2)

            autosteerSectionHeading("Current Track - \(selectedAutosteerFarmDisplay) > \(selectedAutosteerPaddockDisplay)")
            autosteerQuickActionPill {
                handleAutosteerQuickAction {
                    refreshKnownFarms()
                    showAutosteerTrackSelector = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "road.lanes")
                        .foregroundStyle(.blue)
                    Text(selectedAutosteerNameDisplay)
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            }

            autosteerSectionHeading("Create New Tracks")
            autosteerQuickActionPill {
                handleAutosteerQuickAction {
                    beginAutosteerSetup(mode: "A+B line")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        .foregroundStyle(.blue)
                    Text("A + B")
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            autosteerQuickActionPill {
                handleAutosteerQuickAction {
                    beginAutosteerSetup(mode: "A+Heading")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.filled.curvepath")
                        .foregroundStyle(.blue)
                    Text("A + Heading")
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            autosteerQuickActionPill {
                handleAutosteerQuickAction {
                    beginAutosteerSetup(mode: "Curve Track")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                        .foregroundStyle(.blue)
                    Text("Curve")
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            }

            autosteerSectionHeading("Settings")
            autosteerQuickActionPill {
                handleAutosteerQuickAction {
                    showAutosteerSettings = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "steeringwheel")
                        .foregroundStyle(.blue)
                    Text("Autosteer")
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            }

            autosteerQuickActionPill {
                handleAutosteerQuickAction {
                    showCruiseControlSheet = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.open.with.lines.needle.67percent.and.arrowtriangle.and.car")
                        .foregroundStyle(.blue)
                    Text("Cruise Control")
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: maxWidth)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(chromeStroke.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
    }

    private func autosteerSectionHeading(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    private func autosteerQuickActionPill<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(.white.opacity(0.93))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
    }

    private func dismissAutosteerQuickActions() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showAutosteerQuickActions = false
        }
    }

    private func handleAutosteerQuickAction(_ action: @escaping () -> Void) {
        dismissAutosteerQuickActions()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            action()
        }
    }

    private func mapLayer(totalHeight: CGFloat) -> some View {
        MapViewRepresentable(
            followUser: $followUser,
            activeTrackPoints: displayedActiveTrackPoints,
            previousSessions: visiblePreviousTrackSessions,
            markers: sessionMarkers,
            mapMarkers: currentMapMarkers,
            xrsContacts: prioritizedGroupTrackingContacts,
            xrsTrailGroups: xrsTrailGroups,
            xrsTrailColorRaw: xrsRadioTrailColorRaw,
            importedBoundaries: importedBoundaries,
            importedTracks: importedTracks,
            importedMarkers: importedMarkers,
            userLocation: location.lastLocation,
            userHeadingDegrees: location.headingDegrees,
            useCrosshairUserMarker: isAutosteerTrackSetupActive,
            ringCount: ringCount,
            ringSpacingMeters: ringSpacingM,
            ringColorRaw: ringColorRaw,
            ringThicknessScale: ringThicknessScale,
            ringDistanceLabelsEnabled: ringDistanceLabelsEnabled,
            autosteerTrackPreviewCoordinates: autosteerEnabled ? (selectedAutosteerTrackRecord?.previewCoordinates ?? []) : [],
            autosteerTrackSpacingMeters: autosteerEnabled ? autosteerWorkingWidthM : 0,
            autosteerLockedLineIndex: (autosteerEnabled && autosteerActive) ? autosteerGuidanceStatus.nearestLineIndex : nil,
            autosteerUserCoordinate: autosteerEnabled ? location.lastLocation?.coordinate : nil,
            orientationRaw: $orientationRaw,
            mapStyleRaw: $mapStyleRaw,
            guidanceNoMapEnabled: shouldShowGuidanceOnlyViewport,
            recenterNonce: $recenterNonce,
            fitRadiosNonce: $fitRadiosNonce,
            metersPerPoint: $metersPerPoint,
            activeTrackAppearanceRaw: $activeTrackAppearanceRaw,
            mapCenterCoordinate: $mapCenterCoordinate,
            headsUpPitchDegrees: effectiveMapPitchDegrees,
            headsUpUserVerticalOffset: normalizedHeadsUpUserVerticalOffset,
            headsUpBottomObstructionHeight: headsUpBottomObstructionHeight(for: totalHeight),
            destinationCoordinate: effectiveTargetCoordinate,
            activeDestinationMarkerID: activeDestinationMarkerID,
            temporaryPointA: temporaryPreviewPointA,
            temporaryPointB: temporaryPreviewPointB,
            onRequestGoToMarker: { marker in
                startGoTo(marker)
            },
            onArriveAtDestination: {
                DispatchQueue.main.async {
                    clearGoToTarget()
                    showArrivedBanner = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showArrivedBanner = false
                    }

                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            },
            onLongPressAtCoordinate: { coordinate in
                DispatchQueue.main.async {
                    if let moving = movingSessionMarker {
                        app.muster.moveSessionMarker(
                            markerID: moving.id,
                            in: activeSession?.id,
                            to: coordinate
                        )
                        movingSessionMarker = nil
                    } else if let moving = movingMapMarker {
                        app.muster.moveMapMarker(markerID: moving.id, to: coordinate)
                        movingMapMarker = nil
                    } else {
                        pendingMarkerCoordinate = coordinate
                        showMarkerSheet = true
                    }
                }
            },
            onTapSessionMarker: { marker in
                DispatchQueue.main.async {
                    startGoTo(marker)
                }
            },
            onTapMapMarker: { marker in
                DispatchQueue.main.async {
                    startGoTo(marker)
                }
            },
            onTapImportedMarker: { marker in
                DispatchQueue.main.async {
                    startGoTo(marker)
                }
            },
            onLongPressSessionMarker: { marker in
                DispatchQueue.main.async {
                    movingMapMarker = nil
                    longPressedMapMarker = nil
                    showLongPressedMapMarkerDialog = false
                    editingMapMarker = nil
                    showEditMapMarkerAlert = false

                    longPressedSessionMarker = marker
                    showLongPressedSessionMarkerDialog = true
                }
            },
            onLongPressMapMarker: { marker in
                DispatchQueue.main.async {
                    movingSessionMarker = nil
                    longPressedSessionMarker = nil
                    showLongPressedSessionMarkerDialog = false
                    editingSessionMarker = nil
                    showEditSessionMarkerAlert = false

                    longPressedMapMarker = marker
                    showLongPressedMapMarkerDialog = true
                }
            },
            onLongPressPreviousTrack: { sessionID in
                DispatchQueue.main.async {
                    movingSessionMarker = nil
                    movingMapMarker = nil
                    longPressedMapMarker = nil
                    longPressedSessionMarker = nil
                    showLongPressedMapMarkerDialog = false
                    showLongPressedSessionMarkerDialog = false

                    let session = app.muster.sessions.first(where: { $0.id == sessionID })
                    let sessionName = session?.name ?? "Track"
                    let createdAt = session?.startedAt ?? Date()
                    longPressedTrackTarget = .previousSession(
                        sessionID: sessionID,
                        name: sessionName,
                        createdAt: createdAt
                    )
                    showLongPressedTrackDialog = true
                }
            },
            onLongPressImportedTrack: { trackID, trackName in
                DispatchQueue.main.async {
                    movingSessionMarker = nil
                    movingMapMarker = nil
                    longPressedMapMarker = nil
                    longPressedSessionMarker = nil
                    showLongPressedMapMarkerDialog = false
                    showLongPressedSessionMarkerDialog = false

                    let importedTrack = app.muster.visibleImportedTracks.first(where: { $0.id == trackID })
                    let createdAt = importedTrack?.createdAt ?? Date()
                    longPressedTrackTarget = .imported(
                        trackID: trackID,
                        name: trackName,
                        createdAt: createdAt
                    )
                    showLongPressedTrackDialog = true
                }
            },
            onZoomDistanceChange: { distance in
                DispatchQueue.main.async {
                    showZoomDistancePopup(distanceMeters: distance)
                }
            }
        )
    }

    // MARK: - Sheets / covers

    private var settingsSheet: some View {
        SettingsView()
            .environmentObject(app)
            .presentationDetents([.large])
    }

    private var ringsSettingsSheet: some View {
        NavigationStack {
            RingsSettingsView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SheetCloseButton()
                    }
                }
        }
        .presentationDetents([.large])
    }

    private var markerSheet: some View {
        MarkerSheet(
            templates: app.muster.customImportCategories.map {
                MarkerTemplate(id: $0.id, description: $0.title, emoji: $0.icon)
            },
            currentCoordinate: location.lastLocation?.coordinate,
            markedPointA: markerSheetPointA,
            markedPointB: markerSheetPointB,
            onMarkPointA: { coordinate in
                markerSheetPointA = coordinate
                markerSheetPointB = nil
            },
            onMarkPointB: { coordinate in
                markerSheetPointB = coordinate
            },
            onUndoPointB: {
                markerSheetPointB = nil
            },
            onDrop: { template, markerName in
                guard let coordinate = pendingMarkerCoordinate else { return }

                let trimmedName = markerName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                app.muster.addMapMarker(
                    coordinate: coordinate,
                    templateID: template.id,
                    name: (trimmedName?.isEmpty == false) ? trimmedName! : ""
                )

                pendingMarkerCoordinate = nil
                markerSheetPointA = nil
                markerSheetPointB = nil
            }
        )
        .environmentObject(app)
        .presentationDetents([.medium, .large])
    }
    private var previousMustersCover: some View {
        MenuSheetView()
            .environmentObject(app)
    }

    private var currentTrackCover: some View {
        CurrentTrackView(
            session: activeSession,
            currentLocation: location.lastLocation
        )
    }

    // MARK: - Dialog actions

    private func handleMapSetsSheetChanged(_ isPresented: Bool) {
        guard isPresented == false else { return }
        startMapSetCreationFlowOnOpen = false
    }

    private func handleAutosteerSetupActiveChanged(_ isActive: Bool) {
        if isActive {
            followUser = false
        } else if autosteerEnabled {
            applyAutosteerMapLockIfNeeded()
        }
    }

    private func handleMapCenterCoordinateChanged(_ newCenter: CLLocationCoordinate2D?) {
        guard curveTrackRecording, let center = newCenter else { return }
        if let last = curveRecordedCenters.last {
            let lastLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let nextLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            if nextLoc.distance(from: lastLoc) < 2 { return }
        }
        curveRecordedCenters.append(center)
    }

    private func handleArrivedAtDestination() {
        DispatchQueue.main.async {
            clearGoToTarget()
            showArrivedBanner = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showArrivedBanner = false
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func handleLongPressAtCoordinate(_ coordinate: CLLocationCoordinate2D) {
        DispatchQueue.main.async {
            if let moving = movingSessionMarker {
                app.muster.moveSessionMarker(
                    markerID: moving.id,
                    in: activeSession?.id,
                    to: coordinate
                )
                movingSessionMarker = nil
            } else if let moving = movingMapMarker {
                app.muster.moveMapMarker(markerID: moving.id, to: coordinate)
                movingMapMarker = nil
            } else {
                pendingMarkerCoordinate = coordinate
                showMarkerSheet = true
            }
        }
    }

    private func handleTapSessionMarker(_ marker: MusterMarker) {
        DispatchQueue.main.async {
            startGoTo(marker)
        }
    }

    private func handleTapMapMarker(_ marker: MapMarker) {
        DispatchQueue.main.async {
            startGoTo(marker)
        }
    }

    private func handleTapImportedMarker(_ marker: ImportedMarker) {
        DispatchQueue.main.async {
            startGoTo(marker)
        }
    }

    private func handleLongPressSessionMarker(_ marker: MusterMarker) {
        DispatchQueue.main.async {
            movingMapMarker = nil
            longPressedMapMarker = nil
            showLongPressedMapMarkerDialog = false
            editingMapMarker = nil
            showEditMapMarkerAlert = false

            longPressedSessionMarker = marker
            showLongPressedSessionMarkerDialog = true
        }
    }

    private func handleLongPressMapMarker(_ marker: MapMarker) {
        DispatchQueue.main.async {
            movingSessionMarker = nil
            longPressedSessionMarker = nil
            showLongPressedSessionMarkerDialog = false
            editingSessionMarker = nil
            showEditSessionMarkerAlert = false

            longPressedMapMarker = marker
            showLongPressedMapMarkerDialog = true
        }
    }

    private func handleLongPressPreviousTrack(_ sessionID: UUID) {
        DispatchQueue.main.async {
            movingSessionMarker = nil
            movingMapMarker = nil
            longPressedMapMarker = nil
            longPressedSessionMarker = nil
            showLongPressedMapMarkerDialog = false
            showLongPressedSessionMarkerDialog = false

            let session = app.muster.sessions.first(where: { $0.id == sessionID })
            let sessionName = session?.name ?? "Track"
            let createdAt = session?.startedAt ?? Date()
            longPressedTrackTarget = .previousSession(sessionID: sessionID, name: sessionName, createdAt: createdAt)
            showLongPressedTrackDialog = true
        }
    }

    private func handleLongPressImportedTrack(_ trackID: UUID, _ trackName: String) {
        DispatchQueue.main.async {
            movingSessionMarker = nil
            movingMapMarker = nil
            longPressedMapMarker = nil
            longPressedSessionMarker = nil
            showLongPressedMapMarkerDialog = false
            showLongPressedSessionMarkerDialog = false

            let importedTrack = app.muster.visibleImportedTracks.first(where: { $0.id == trackID })
            let createdAt = importedTrack?.createdAt ?? Date()
            longPressedTrackTarget = .imported(trackID: trackID, name: trackName, createdAt: createdAt)
            showLongPressedTrackDialog = true
        }
    }

    @ViewBuilder
    private func longPressedMapMarkerDialogActions() -> some View {
        Button("Edit") {
            guard let marker = longPressedMapMarker else { return }
            editingMapMarker = marker
            editingMapMarkerName = marker.displayTitle
            showLongPressedMapMarkerDialog = false
            longPressedMapMarker = nil
            showEditMapMarkerAlert = true
        }

        Button("Move") {
            guard let marker = longPressedMapMarker else { return }
            movingMapMarker = marker
            movingSessionMarker = nil
            showLongPressedMapMarkerDialog = false
            longPressedMapMarker = nil
        }

        Button("Delete", role: .destructive) {
            guard let marker = longPressedMapMarker else { return }
            deletePermanentMapMarker(marker)
            showLongPressedMapMarkerDialog = false
            longPressedMapMarker = nil
        }

        Button("Cancel", role: .cancel) {
            showLongPressedMapMarkerDialog = false
            longPressedMapMarker = nil
        }
    }
    @ViewBuilder
    private func longPressedSessionMarkerDialogActions() -> some View {
        Button("Edit") {
            guard let marker = longPressedSessionMarker else { return }
            editingSessionMarker = marker
            editingSessionMarkerName = marker.displayTitle
            showLongPressedSessionMarkerDialog = false
            longPressedSessionMarker = nil
            showEditSessionMarkerAlert = true
        }

        Button("Move") {
            guard let marker = longPressedSessionMarker else { return }
            movingSessionMarker = marker
            movingMapMarker = nil
            showLongPressedSessionMarkerDialog = false
            longPressedSessionMarker = nil
        }

        Button("Delete", role: .destructive) {
            guard let marker = longPressedSessionMarker else { return }
            deleteSessionMarker(marker)
            showLongPressedSessionMarkerDialog = false
            longPressedSessionMarker = nil
        }

        Button("Cancel", role: .cancel) {
            showLongPressedSessionMarkerDialog = false
            longPressedSessionMarker = nil
        }
    }
    @ViewBuilder
    private func longPressedSessionMarkerDialogMessage() -> some View {
        Text("Edit, move, or delete this session marker.")
    }

    @ViewBuilder
    private func longPressedTrackDialogActions() -> some View {
        Button("Cancel", role: .cancel) {
            showLongPressedTrackDialog = false
            longPressedTrackTarget = nil
        }

        Button("Delete", role: .destructive) {
            guard let target = longPressedTrackTarget else { return }
            pendingTrackDeleteConfirmation = target
            showLongPressedTrackDialog = false
            longPressedTrackTarget = nil
            showTrackDeleteConfirmationAlert = true
        }
    }

    @ViewBuilder
    private func longPressedTrackDialogMessage() -> some View {
        if let target = longPressedTrackTarget {
            Text("Created \(target.createdAt.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    @ViewBuilder
    private func longPressedMapMarkerDialogMessage() -> some View {
        Text("Edit, move, or delete this permanent marker.")
    }

    @ViewBuilder
    private var editSessionMarkerAlertActions: some View {
        TextField("Name", text: $editingSessionMarkerName)

        Button("Save") {
            saveSessionMarkerEdit()
        }

        Button("Cancel", role: .cancel) {
            editingSessionMarker = nil
            editingSessionMarkerName = ""
        }
    }

    @ViewBuilder
    private var editMapMarkerAlertActions: some View {
        TextField("Name", text: $editingMapMarkerName)

        Button("Save") {
            saveMapMarkerEdit()
        }

        Button("Cancel", role: .cancel) {
            editingMapMarker = nil
            editingMapMarkerName = ""
        }
    }

    // MARK: - Top pills

    private var chromeFill: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.94)
            : Color(uiColor: .systemBackground).opacity(0.78)
    }

    private var chromeStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.10)
    }

    private var chromePrimaryText: Color {
        colorScheme == .dark ? Color.white : Color.black.opacity(0.9)
    }

    private var chromeSecondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.58)
    }

    private var chromeShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.10)
    }

    private var topPillRow: some View {
        HStack(spacing: 10) {
            topSidePill(metric: leftPillMetric, side: .left)
                .frame(width: 108)

            topSpeedPill
                .frame(maxWidth: .infinity)

            Group {
                if autosteerEnabled {
                    autosteerReadinessButton
                } else {
                    topSidePill(metric: rightPillMetric, side: .right)
                }
            }
            .frame(width: 108)
        }
    }

    private func topLeftZoomPill(zoomDistancePopupText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(chromePrimaryText)

            Text(zoomDistancePopupText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(chromePrimaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 14)
        .frame(width: 108, height: topPillHeight)
        .background(
            Capsule(style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 2)
        )
        .shadow(color: chromeShadow, radius: 8, y: 3)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func topSidePill(metric: TopSidePillMetric, side: TopSidePillPosition) -> some View {
        let content = contentForTopSidePill(metric)

        return VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: content.systemImage)
                    .font(.system(size: metric == .headingBearing ? 12 : 17, weight: .semibold))
                    .foregroundStyle(chromePrimaryText)
                    .rotationEffect(.degrees(content.imageRotationDegrees))
                    .animation(
                        content.animateRotation ? .easeInOut(duration: 0.25) : nil,
                        value: content.imageRotationDegrees
                    )

                Text(content.valueText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(chromePrimaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(content.labelText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(chromeSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: topPillHeight)
        .background(
            Capsule(style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 2)
        )
        .shadow(color: chromeShadow, radius: 8, y: 3)
        .contentShape(Capsule(style: .continuous))
        .onLongPressGesture {
            topPillPickerSide = side
        }
    }

    private func contentForTopSidePill(_ metric: TopSidePillMetric) -> TopSidePillContent {
        switch metric {
        case .weather:
            return TopSidePillContent(
                valueText: weatherStore.isLoading ? "Loading" : weatherStore.temperatureText,
                labelText: "Weather",
                systemImage: weatherStore.symbolName,
                imageRotationDegrees: 0,
                animateRotation: false
            )

        case .wind:
            return TopSidePillContent(
                valueText: weatherStore.windText,
                labelText: "Wind",
                systemImage: "location.north.fill",
                imageRotationDegrees: weatherStore.windDirectionDegrees,
                animateRotation: true
            )

        case .altitude:
            return TopSidePillContent(
                valueText: elevationText,
                labelText: "Altitude",
                systemImage: "mountain.2.fill",
                imageRotationDegrees: 0,
                animateRotation: false
            )

        case .distanceToTarget:
            return TopSidePillContent(
                valueText: destinationDistanceText,
                labelText: "Distance",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                imageRotationDegrees: 0,
                animateRotation: false
            )

        case .etaAtTarget:
            return TopSidePillContent(
                valueText: destinationETAText,
                labelText: "ETA",
                systemImage: "clock.fill",
                imageRotationDegrees: 0,
                animateRotation: false
            )

        case .headingBearing:
            return TopSidePillContent(
                valueText: headingBearingValueText,
                labelText: headingBearingLabelText,
                systemImage: "location.north.fill",
                imageRotationDegrees: headingBearingRotationDegrees,
                animateRotation: true
            )

        case .tripDistance:
            return TopSidePillContent(
                valueText: tripDistanceText,
                labelText: "Trip",
                systemImage: "road.lanes",
                imageRotationDegrees: 0,
                animateRotation: false
            )
        }
    }

    private var topSpeedPill: some View {
        VStack(spacing: 0) {
            Text(speedNumberText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(speedPillShouldHighlightMatch ? Color.green : chromePrimaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(speedUnitText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(chromeSecondaryText)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(
            Capsule(style: .continuous)
                .fill(chromeFill)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }

    private var moveBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(chromePrimaryText)

            Text("Long press the new location to move marker")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(chromePrimaryText)

            Spacer()

            Button {
                movingSessionMarker = nil
                movingMapMarker = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(chromeSecondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            Capsule(style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 2)
        )
    }

    // MARK: - Target compass

    private var sheepCompassWidget: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(chromeFill)
                    .frame(width: 98, height: 98)

                Circle()
                    .strokeBorder(chromeStroke, lineWidth: 1)
                    .frame(width: 98, height: 98)

                Circle()
                    .strokeBorder(
                        destinationDistanceMeters ?? 999 >= 30
                        ? .white.opacity(0.14)
                        : .green.opacity(0.55),
                        lineWidth: 2
                    )
                    .frame(width: 84, height: 84)

                compassTicks
                    .frame(width: 82, height: 82)

                Text("N")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.92))
                    .offset(y: -32)

                sheepArrow
                    .rotationEffect(.degrees(targetArrowRotationDegrees))

                VStack(spacing: 1) {
                    Text(destinationDistanceText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(chromePrimaryText)

                    if destinationDistanceMeters ?? 999 >= 30 {
                        Text("TARGET")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(chromeSecondaryText)
                            .tracking(0.8)
                    } else {
                        Text("ARRIVED")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.green.opacity(0.9))
                            .tracking(0.8)
                    }
                }
            }

            HStack(spacing: 6) {
                Text(destinationSubtitleText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(chromePrimaryText)
                    .lineLimit(1)

                ZStack {
                    Button {
                        clearGoToTarget()
                    } label: {
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chromeSecondaryText)
                        .allowsHitTesting(false)
                }
                .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(chromeFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(chromeStroke, lineWidth: 1)
            )
        }
    }

    private var compassTicks: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { idx in
                Rectangle()
                    .fill(idx == 0 ? .red.opacity(0.85) : .white.opacity(0.20))
                    .frame(width: 2, height: idx.isMultiple(of: 3) ? 8 : 5)
                    .offset(y: -34)
                    .rotationEffect(.degrees(Double(idx) * 30.0))
            }
        }
    }

    private var sheepArrow: some View {
        VStack(spacing: 0) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.red)
                .shadow(color: .red.opacity(0.28), radius: 3, y: 1)
                .offset(y: -13)
        }
    }

    private var autosteerReadinessButton: some View {
        let fraction = Double(autosteerReadinessCount) / 4.0
        return Button {
            if autosteerGoReady {
                let shouldActivateAutosteer = autosteerActive == false
                autosteerActive.toggle()
                if shouldActivateAutosteer, cruiseControlEnabled {
                    showCruiseControlSetSpeedPopup()
                }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(autosteerActive ? .success : .warning)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showAutosteerReadinessSheet = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(chromeFill)
                    .frame(width: 64, height: 64)

                Circle()
                    .stroke(chromeStroke.opacity(0.8), lineWidth: 8)
                    .frame(width: 58, height: 58)

                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        autosteerGoReady ? .green : .orange,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 66, height: 66)

                VStack(spacing: 0) {
                    if autosteerActive && autosteerGoReady {
                        Image(systemName: "steeringwheel")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.green)
                    } else {
                        Text(autosteerActive ? "ON" : "GO")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(autosteerActive ? .green : chromePrimaryText)
                    }
                    Text("\(autosteerReadinessCount)/4")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(chromeSecondaryText)

                    if cruiseControlIsActive {
                        Text(cruiseControlSetSpeedText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .accessibilityLabel("Autosteer readiness")
            .accessibilityValue("\(autosteerReadinessCount) of 4 checks ready")
            .accessibilityHint(autosteerReadinessAccessibilityHint)
        }
        .sheet(isPresented: $showAutosteerReadinessSheet) {
            NavigationStack {
                List {
                    Section {
                        ForEach(autosteerReadinessSteps, id: \.step.id) { item in
                            Button {
                                handleAutosteerReadinessStepTap(item.step)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(item.isComplete ? .green : .red)
                                        .font(.system(size: 19, weight: .semibold))
                                    Text(item.title)
                                        .foregroundStyle(.primary)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption.weight(.semibold))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Autosteer checklist")
                    } footer: {
                        Text("Tap a part to jump straight to the relevant place to view or fix it.")
                    }
                }
                .navigationTitle("Autosteer not ready")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func autosteerTrackPillButton(
        _ title: String,
        foreground: Color? = nil,
        fill: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let foregroundColor = foreground ?? chromePrimaryText
        let fillColor = fill ?? chromeFill

        return Button(title, action: action)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 40)
            .background(Capsule().fill(fillColor))
            .buttonStyle(.plain)
    }

    private func handleAutosteerReadinessStepTap(_ step: AutosteerReadinessStep) {
        showAutosteerReadinessSheet = false

        switch step {
        case .autosteerEnabled, .gpsSignalValid:
            showAutosteerSettings = true
        case .guidanceTrackSelected:
            showAutosteerTrackSelector = true
        case .goButtonPressed:
            guard autosteerPrerequisitesReady else { return }
            autosteerActive = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func autosteerTrackSetupOverlay(maxWidth: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Create New Track")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(chromeSecondaryText)
                .frame(maxWidth: .infinity, alignment: .center)

            PillWrapLayout(spacing: 8, rowSpacing: 8) {
                if autosteerSetupModeRaw == "A+B line" {
                    autosteerTrackPillButton("X") {
                        resetAutosteerSetupFlow()
                    }

                    autosteerTrackPillButton(autosteerPointA == nil ? "Mark A" : "Re-mark A") {
                        guard let coordinate = mapCenterCoordinate ?? location.lastLocation?.coordinate else { return }
                        autosteerPointA = coordinate
                    }

                    if autosteerPointA != nil {
                        autosteerTrackPillButton(autosteerPointB == nil ? "Mark B" : "Re-mark B") {
                            guard let coordinate = mapCenterCoordinate ?? location.lastLocation?.coordinate else { return }
                            autosteerPointB = coordinate
                        }
                    }

                    if autosteerPointA != nil, autosteerPointB != nil {
                        autosteerTrackPillButton("Save", foreground: .black, fill: .white.opacity(0.88)) {
                            completeAutosteerSetupAndPromptForSave()
                        }
                    }
                } else {
                    Button(action: handleAutosteerSetupPrimaryAction) {
                        HStack(spacing: 8) {
                            if autosteerSetupModeRaw == "Curve Track" && curveTrackRecording {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                    .scaleEffect(curvePulse ? 1.25 : 0.8)
                                    .opacity(curvePulse ? 0.4 : 1.0)
                                    .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: curvePulse)
                            }
                            Text(autosteerSetupPrimaryButtonTitle)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(chromePrimaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(chromeFill))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: min(maxWidth - 24, 560), alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    
        .alert("Enter Heading", isPresented: $showAutosteerHeadingPrompt) {
            TextField("Heading (e.g. 123.4567)", text: $autosteerHeadingInput)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if validateAutosteerHeadingInput() {
                    completeAutosteerSetupAndPromptForSave()
                }
            }
        } message: {
            Text("Enter heading to 4 decimal places.")
        }
        .alert("Invalid Heading", isPresented: $showAutosteerHeadingValidationWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(autosteerHeadingValidationWarningMessage)
        }
        .sheet(isPresented: $showAutosteerTrackSaveSheet) {
            NavigationStack {
                Form {
                    Section("Farm") {
                        if farmOptionsForSaveSheet.isEmpty {
                            Text("No farms yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(farmOptionsForSaveSheet, id: \.self) { farmName in
                                        selectablePillButton(
                                            title: farmName,
                                            isSelected: selectedFarmOption.caseInsensitiveCompare(farmName) == .orderedSame
                                        ) {
                                            selectedFarmOption = farmName
                                            autosteerSaveFarm = farmName
                                            selectedPaddockOption = "__new__"
                                            autosteerSavePaddock = ""
                                        }
                                    }
                                }
                            }
                        }

                        Button("Add New") {
                            newFarmNameInput = ""
                            showAddFarmPrompt = true
                        }
                        .buttonStyle(.bordered)
                    }

                    Section("Paddock") {
                        if paddockOptionsForSaveSheet.isEmpty {
                            Text("No paddocks for selected farm.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(paddockOptionsForSaveSheet, id: \.self) { paddock in
                                        selectablePillButton(
                                            title: paddock,
                                            isSelected: selectedPaddockOption.caseInsensitiveCompare(paddock) == .orderedSame
                                        ) {
                                            selectedPaddockOption = paddock
                                            autosteerSavePaddock = paddock
                                        }
                                    }
                                }
                            }
                        }

                        Button("Add New") {
                            newPaddockNameInput = ""
                            showAddPaddockPrompt = true
                        }
                        .buttonStyle(.bordered)
                    }

                    Section("Track") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(trackQuickPickOptions, id: \.self) { option in
                                    selectablePillButton(title: option, isSelected: selectedTrackQuickPick == option) {
                                        selectedTrackQuickPick = option
                                        autosteerSaveTrackName = option
                                    }
                                }
                            }
                        }
                        TextField("Custom track name", text: $autosteerSaveTrackName)
                            .onChange(of: autosteerSaveTrackName) { _, value in
                                let match = trackQuickPickOptions.first {
                                    $0.caseInsensitiveCompare(value.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                                }
                                selectedTrackQuickPick = match
                            }
                    }
                }
                .navigationTitle("Save Track")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            resetAutosteerSetupFlow()
                            showAutosteerTrackSaveSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            handleAutosteerTrackSaveTapped()
                        }
                        .disabled(isAutosteerSaveFormComplete == false)
                        .tint(isAutosteerSaveFormComplete ? .blue : .secondary)
                    }
                }
                .alert("Duplicate Track", isPresented: $showDuplicateTrackWarning) {
                    Button("Overwrite Existing", role: .destructive) {
                        if let request = pendingTrackSaveRequest {
                            persistAutosteerTrackSave(
                                farmName: request.farmName,
                                paddockName: request.paddockName,
                                trackName: request.trackName
                            )
                        }
                    }
                    Button("Keep Both") {
                        guard let request = pendingTrackSaveRequest else { return }
                        let uniqueTrackName = AutosteerLibraryStore.nextUniqueTrackName(
                            farmName: request.farmName,
                            paddockName: request.paddockName,
                            baseTrackName: request.trackName
                        )
                        persistAutosteerTrackSave(
                            farmName: request.farmName,
                            paddockName: request.paddockName,
                            trackName: uniqueTrackName
                        )
                    }
                    Button("Cancel", role: .cancel) {
                        pendingTrackSaveRequest = nil
                    }
                } message: {
                    if let request = pendingTrackSaveRequest {
                        Text("A track named \(request.farmName) > \(request.paddockName) > \(request.trackName) already exists.")
                    }
                }
                .alert("Add Farm", isPresented: $showAddFarmPrompt) {
                    TextField("Farm name", text: $newFarmNameInput)
                    Button("Cancel", role: .cancel) {
                        newFarmNameInput = ""
                    }
                    Button("Save") {
                        let trimmed = newFarmNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.isEmpty == false else { return }
                        autosteerSaveFarm = trimmed
                        selectedFarmOption = trimmed
                        autosteerSavePaddock = ""
                        selectedPaddockOption = "__new__"
                        newFarmNameInput = ""
                    }
                    .disabled(newFarmNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } message: {
                    Text("Enter a farm name.")
                }
                .alert("Add Paddock", isPresented: $showAddPaddockPrompt) {
                    TextField("Paddock name", text: $newPaddockNameInput)
                    Button("Cancel", role: .cancel) {
                        newPaddockNameInput = ""
                    }
                    Button("Save") {
                        let trimmed = newPaddockNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.isEmpty == false else { return }
                        autosteerSavePaddock = trimmed
                        selectedPaddockOption = trimmed
                        newPaddockNameInput = ""
                    }
                    .disabled(newPaddockNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } message: {
                    Text("Enter a paddock name.")
                }
            }
        }
        .onAppear {
            if autosteerSetupModeRaw == "Curve Track" {
                curvePulse = true
            }
        }
    }

    private struct PillWrapLayout: Layout {
        var spacing: CGFloat
        var rowSpacing: CGFloat

        func sizeThatFits(
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) -> CGSize {
            let availableWidth = proposal.width ?? .greatestFiniteMagnitude
            var currentRowWidth: CGFloat = 0
            var currentRowHeight: CGFloat = 0
            var maxRowWidth: CGFloat = 0
            var totalHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                let canFitInCurrentRow = currentRowWidth == 0 || (currentRowWidth + spacing + size.width) <= availableWidth

                if canFitInCurrentRow {
                    currentRowWidth = currentRowWidth == 0 ? size.width : currentRowWidth + spacing + size.width
                    currentRowHeight = max(currentRowHeight, size.height)
                } else {
                    maxRowWidth = max(maxRowWidth, currentRowWidth)
                    totalHeight += currentRowHeight + rowSpacing
                    currentRowWidth = size.width
                    currentRowHeight = size.height
                }
            }

            maxRowWidth = max(maxRowWidth, currentRowWidth)
            totalHeight += currentRowHeight

            return CGSize(
                width: proposal.width ?? maxRowWidth,
                height: totalHeight
            )
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) {
            let availableWidth = bounds.width
            var rows: [[(index: Int, size: CGSize)]] = []
            var currentRow: [(index: Int, size: CGSize)] = []
            var currentRowWidth: CGFloat = 0

            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(.unspecified)
                let canFitInCurrentRow = currentRow.isEmpty || (currentRowWidth + spacing + size.width) <= availableWidth

                if canFitInCurrentRow {
                    currentRow.append((index: index, size: size))
                    currentRowWidth = currentRow.count == 1 ? size.width : currentRowWidth + spacing + size.width
                } else {
                    rows.append(currentRow)
                    currentRow = [(index: index, size: size)]
                    currentRowWidth = size.width
                }
            }

            if !currentRow.isEmpty {
                rows.append(currentRow)
            }

            var y = bounds.minY
            for row in rows {
                let rowWidth = row.reduce(CGFloat.zero) { partial, entry in
                    partial + entry.size.width
                } + CGFloat(max(0, row.count - 1)) * spacing
                let rowHeight = row.reduce(CGFloat.zero) { max($0, $1.size.height) }
                var x = bounds.minX + max(0, (availableWidth - rowWidth) / 2)

                for entry in row {
                    subviews[entry.index].place(
                        at: CGPoint(x: x, y: y),
                        proposal: ProposedViewSize(width: entry.size.width, height: entry.size.height)
                    )
                    x += entry.size.width + spacing
                }

                y += rowHeight + rowSpacing
            }
        }
    }

    @ViewBuilder
    private func selectablePillButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
    }

    private var autosteerSetupPrimaryButtonTitle: String {
        switch autosteerSetupModeRaw {
        case "A+B line":
            if autosteerPointA == nil { return "Mark point A" }
            if autosteerPointB == nil { return "Mark point B" }
            return "Re-mark point B"
        case "A+Heading":
            return "Mark point A"
        case "Curve Track":
            return curveTrackRecording ? "Stop" : "Rec"
        default:
            return "Start"
        }
    }

    private func handleAutosteerSetupPrimaryAction() {
        guard let coordinate = mapCenterCoordinate ?? location.lastLocation?.coordinate else { return }

        switch autosteerSetupModeRaw {
        case "A+B line":
            if autosteerPointA == nil {
                autosteerPointA = coordinate
            } else {
                autosteerPointB = coordinate
            }
        case "A+Heading":
            autosteerPointA = coordinate
            showAutosteerHeadingPrompt = true
        case "Curve Track":
            curveTrackRecording.toggle()
            if curveTrackRecording == false {
                completeAutosteerSetupAndPromptForSave()
            } else {
                curvePulse = true
            }
        default:
            break
        }
    }

    private func remarkAutosteerPointA() {
        guard let coordinate = mapCenterCoordinate ?? location.lastLocation?.coordinate else { return }
        autosteerPointA = coordinate
    }

    private func remarkAutosteerPointB() {
        guard let coordinate = mapCenterCoordinate ?? location.lastLocation?.coordinate else { return }
        autosteerPointB = coordinate
    }

    private func completeAutosteerSetupAndPromptForSave() {
        refreshKnownFarms()
        selectedFarmOption = "__new__"
        selectedPaddockOption = "__new__"
        selectedTrackQuickPick = nil
        showAutosteerTrackSaveSheet = true
    }

    private func resetAutosteerSetupFlow() {
        autosteerSetupActive = false
        autosteerSetupModeRaw = "none"
        autosteerPointA = nil
        autosteerPointB = nil
        autosteerHeadingInput = ""
        curveTrackRecording = false
        curvePulse = false
        curveRecordedCenters = []
        autosteerSaveFarm = ""
        autosteerSavePaddock = ""
        autosteerSaveTrackName = ""
        selectedFarmOption = "__new__"
        selectedPaddockOption = "__new__"
        selectedTrackQuickPick = nil
        newFarmNameInput = ""
        newPaddockNameInput = ""
        showAddFarmPrompt = false
        showAddPaddockPrompt = false
        showDuplicateTrackWarning = false
        pendingTrackSaveRequest = nil
    }

    private func handleAutosteerTrackSaveTapped() {
        let request = PendingAutosteerTrackSaveRequest(
            farmName: autosteerSaveFarm.trimmingCharacters(in: .whitespacesAndNewlines),
            paddockName: autosteerSavePaddock.trimmingCharacters(in: .whitespacesAndNewlines),
            trackName: autosteerSaveTrackName.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard request.farmName.isEmpty == false, request.paddockName.isEmpty == false, request.trackName.isEmpty == false else {
            return
        }

        if AutosteerLibraryStore.trackExists(
            farmName: request.farmName,
            paddockName: request.paddockName,
            trackName: request.trackName
        ) {
            pendingTrackSaveRequest = request
            showDuplicateTrackWarning = true
            return
        }

        persistAutosteerTrackSave(
            farmName: request.farmName,
            paddockName: request.paddockName,
            trackName: request.trackName
        )
    }

    private func persistAutosteerTrackSave(
        farmName: String,
        paddockName: String,
        trackName: String
    ) {
        AutosteerLibraryStore.upsertTrack(
            farmName: farmName,
            paddockName: paddockName,
            trackName: trackName,
            mode: autosteerSetupModeRaw,
            previewCoordinates: previewCoordinatesForPendingSetup()
        )
        autosteerFarmName = farmName
        autosteerPaddockName = paddockName
        autosteerTrackName = trackName
        autosteerSaveTrackName = trackName
        autosteerTrackModeRaw = autosteerSetupModeRaw
        pendingTrackSaveRequest = nil
        refreshKnownFarms()
        resetAutosteerSetupFlow()
        showAutosteerTrackSaveSheet = false
    }

    private func beginAutosteerSetup(mode: String) {
        autosteerSetupModeRaw = mode
        autosteerSetupActive = true
        followUser = false
        curveRecordedCenters = []
        if mode == "A+B line" || mode == "A+Heading" {
            applyAutosteerTrackCreationMapView()
        }
    }

    private func refreshKnownFarms() {
        knownFarms = AutosteerLibraryStore.load()
        syncAutosteerSelectorExpansionState()
    }

    private func prepareAutosteerTrackSelector() {
        refreshKnownFarms()
        expandedAutosteerPaddockIDs = []
    }

    private func toggleAutosteerPaddockExpansion(paddockID: UUID) {
        if expandedAutosteerPaddockIDs.contains(paddockID) {
            expandedAutosteerPaddockIDs.remove(paddockID)
        } else {
            expandedAutosteerPaddockIDs.insert(paddockID)
        }
    }

    private func syncAutosteerSelectorExpansionState() {
        let validPaddockIDs = Set(knownFarms.flatMap(\.paddocks).map(\.id))
        expandedAutosteerPaddockIDs = expandedAutosteerPaddockIDs.intersection(validPaddockIDs)
    }

    private func previewCoordinatesForPendingSetup() -> [[Double]] {
        func coords(_ c: CLLocationCoordinate2D) -> [Double] { [c.latitude, c.longitude] }

        switch autosteerSetupModeRaw {
        case "A+B line":
            if let a = autosteerPointA, let b = autosteerPointB {
                return [coords(a), coords(b)]
            }
        case "A+Heading":
            if let a = autosteerPointA {
                guard let heading = validatedAutosteerHeadingValue() else { return [] }
                let distanceMeters: CLLocationDistance = 120
                let radians = heading * .pi / 180
                let earth = 6_378_137.0
                let dLat = (distanceMeters * cos(radians)) / earth
                let dLon = (distanceMeters * sin(radians)) / (earth * cos(a.latitude * .pi / 180))
                let b = CLLocationCoordinate2D(
                    latitude: a.latitude + (dLat * 180 / .pi),
                    longitude: a.longitude + (dLon * 180 / .pi)
                )
                return [coords(a), coords(b)]
            }
        case "Curve Track":
            return curveRecordedCenters.map(coords)
        default:
            break
        }
        return []
    }

    private func validateAutosteerHeadingInput() -> Bool {
        guard let _ = validatedAutosteerHeadingValue() else {
            autosteerHeadingValidationWarningMessage = "Heading must be between 0.0000 and 360.0000, with up to 4 decimal places."
            showAutosteerHeadingValidationWarning = true
            return false
        }
        return true
    }

    private func validatedAutosteerHeadingValue() -> Double? {
        let trimmed = autosteerHeadingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        if parts.count == 2, parts[1].count > 4 { return nil }
        guard let value = Double(trimmed), value.isFinite else { return nil }
        guard (0.0...360.0).contains(value) else { return nil }
        return value
    }

    private func isCurrentlySelectedAutosteerTrack(farmName: String, paddockName: String, trackName: String) -> Bool {
        autosteerFarmName.caseInsensitiveCompare(farmName) == .orderedSame &&
        autosteerPaddockName.caseInsensitiveCompare(paddockName) == .orderedSame &&
        autosteerTrackName.caseInsensitiveCompare(trackName) == .orderedSame
    }

    private func isCurrentlySelectedAutosteerPaddock(farmName: String, paddockName: String) -> Bool {
        autosteerFarmName.caseInsensitiveCompare(farmName) == .orderedSame &&
        autosteerPaddockName.caseInsensitiveCompare(paddockName) == .orderedSame
    }

    // MARK: - Right side controls

    private var centerMapButton: some View {
        Button {
            recenterOnUser()
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(chromePrimaryText)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(chromeFill)
                )
                .overlay(
                    Circle()
                        .strokeBorder(chromeStroke, lineWidth: 1)
                )
                .shadow(color: chromeShadow, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var rightSideControlPill: some View {
        VStack(spacing: 0) {
            Button {
                orientationRaw = isHeadsUp ? "northUp" : "headsUp"
                recenterOnUser()
            } label: {
                Image(systemName: isHeadsUp ? "safari.fill" : "location.north.line.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chromePrimaryText)
                    .frame(width: 48, height: 48)
            }

            Rectangle()
                .fill(chromeStroke)
                .frame(width: 24, height: 1)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showMapLayerSheet.toggle()
                }
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chromePrimaryText)
                    .frame(width: 48, height: 48)
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.6)
                    .onEnded { _ in
                        panelDetent = .collapsed
                        showSettings = true
                    }
            )
        }
        .frame(width: 48)
        .background(
            Capsule(style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 1)
        )
        .shadow(color: chromeShadow, radius: 10, y: 4)
        .fixedSize()
    }

    private func recenterOnUser() {
        followUser = true
        recenterNonce &+= 1
    }

    private var autosteerGuidanceStatus: AutosteerGuidanceStatus {
        guard autosteerWorkingWidthM > 0 else {
            return AutosteerGuidanceStatus(signedOffsetToNearestLineM: 0, nearestLineIndex: 0)
        }
        if autosteerGuidanceSeeded {
            return AutosteerGuidanceStatus(
                signedOffsetToNearestLineM: autosteerFilteredSignedOffsetM,
                nearestLineIndex: autosteerLockedGuidanceLineIndex
            )
        }
        guard let userCoordinate = location.lastLocation?.coordinate,
              let raw = rawAutosteerGuidanceSample(userCoordinate: userCoordinate) else {
            return AutosteerGuidanceStatus(signedOffsetToNearestLineM: 0, nearestLineIndex: 0)
        }
        let signedDistanceToNearestLine = raw.signedDistanceToBaseLineM - (Double(raw.nearestLineIndex) * autosteerWorkingWidthM)
        return AutosteerGuidanceStatus(signedOffsetToNearestLineM: -signedDistanceToNearestLine, nearestLineIndex: raw.nearestLineIndex)
    }

    private func rawAutosteerGuidanceSample(userCoordinate: CLLocationCoordinate2D) -> RawAutosteerGuidanceSample? {
        let referenceLine = autosteerReferenceLineCoordinates(userCoordinate: userCoordinate)
        guard let lineA = referenceLine?.0, let lineB = referenceLine?.1 else { return nil }

        let earthRadiusM = 6_378_137.0
        let latitudeRadians = userCoordinate.latitude * .pi / 180
        let metersPerDegreeLat = earthRadiusM * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(latitudeRadians)

        func localPoint(_ c: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: (c.longitude - userCoordinate.longitude) * metersPerDegreeLon,
                y: (c.latitude - userCoordinate.latitude) * metersPerDegreeLat
            )
        }

        let a = localPoint(lineA)
        let b = localPoint(lineB)
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lineLength = hypot(ab.x, ab.y)
        guard lineLength > 0.01 else { return nil }

        let ap = CGPoint(x: -a.x, y: -a.y)
        let signedDistanceToBaseLine = ((ab.x * ap.y) - (ab.y * ap.x)) / lineLength
        let nearestLineIndex = Int((signedDistanceToBaseLine / autosteerWorkingWidthM).rounded())
        return RawAutosteerGuidanceSample(
            signedDistanceToBaseLineM: signedDistanceToBaseLine,
            nearestLineIndex: nearestLineIndex
        )
    }

    private func updateAutosteerGuidanceFilter(using location: CLLocation) {
        guard autosteerWorkingWidthM > 0,
              let raw = rawAutosteerGuidanceSample(userCoordinate: location.coordinate) else {
            resetAutosteerGuidanceFilter()
            return
        }

        let now = location.timestamp
        let speedMPS = max(location.speed, 0)
        let highResponsivenessMode = autosteerEnabled
        let lookAheadSeconds: Double
        if highResponsivenessMode {
            lookAheadSeconds = 0
        } else {
            lookAheadSeconds = speedMPS > 0.3 ? max(0.35, min(2.2, autosteerLookAheadM / speedMPS)) : 0.35
        }

        let predictedBaseDistanceM: Double
        if let lastBase = autosteerLastRawBaseDistanceM,
           let lastTimestamp = autosteerLastGuidanceTimestamp {
            let dt = max(0.02, min(0.7, now.timeIntervalSince(lastTimestamp)))
            let lateralVelocityMPS = (raw.signedDistanceToBaseLineM - lastBase) / dt
            predictedBaseDistanceM = raw.signedDistanceToBaseLineM + (lateralVelocityMPS * lookAheadSeconds)
        } else {
            predictedBaseDistanceM = raw.signedDistanceToBaseLineM
        }

        let projectedLineIndex = Int((predictedBaseDistanceM / autosteerWorkingWidthM).rounded())
        let chosenLineIndex: Int
        if autosteerGuidanceSeeded {
            let distanceToLockedLine = abs(predictedBaseDistanceM - (Double(autosteerLockedGuidanceLineIndex) * autosteerWorkingWidthM))
            let speedFactor = min(speedMPS / 12.0, 1.0)
            let lockSwitchThreshold = (autosteerWorkingWidthM * 0.58) + (autosteerWorkingWidthM * 0.24 * speedFactor)
            chosenLineIndex = distanceToLockedLine > lockSwitchThreshold ? projectedLineIndex : autosteerLockedGuidanceLineIndex
        } else {
            chosenLineIndex = projectedLineIndex
        }

        let projectedDistanceToChosenLine = predictedBaseDistanceM - (Double(chosenLineIndex) * autosteerWorkingWidthM)
        let measuredOffsetToChosenLine = -(raw.signedDistanceToBaseLineM - (Double(chosenLineIndex) * autosteerWorkingWidthM))
        let targetOffsetM = -projectedDistanceToChosenLine
        let dynamicTargetOffsetM: Double
        if highResponsivenessMode {
            dynamicTargetOffsetM = measuredOffsetToChosenLine
        } else {
            dynamicTargetOffsetM = measuredOffsetToChosenLine + ((targetOffsetM - measuredOffsetToChosenLine) * min(speedMPS / 10.0, 0.8))
        }

        if autosteerGuidanceSeeded, let lastTimestamp = autosteerLastGuidanceTimestamp {
            let dt = max(0.02, min(0.7, now.timeIntervalSince(lastTimestamp)))
            let smoothingTimeConstant: Double
            if highResponsivenessMode {
                smoothingTimeConstant = 0.04
            } else {
                smoothingTimeConstant = max(0.10, 0.36 - (0.18 * min(speedMPS / 12.0, 1.0)))
            }
            let alpha = dt / (smoothingTimeConstant + dt)
            autosteerFilteredSignedOffsetM += (dynamicTargetOffsetM - autosteerFilteredSignedOffsetM) * alpha
        } else {
            autosteerFilteredSignedOffsetM = dynamicTargetOffsetM
            autosteerGuidanceSeeded = true
        }

        autosteerLockedGuidanceLineIndex = chosenLineIndex
        autosteerLastRawBaseDistanceM = raw.signedDistanceToBaseLineM
        autosteerLastGuidanceTimestamp = now
    }

    private func resetAutosteerGuidanceFilter() {
        autosteerGuidanceSeeded = false
        autosteerFilteredSignedOffsetM = 0
        autosteerLockedGuidanceLineIndex = 0
        autosteerLastRawBaseDistanceM = nil
        autosteerLastGuidanceTimestamp = nil
    }

    private func autosteerReferenceLineCoordinates(
        userCoordinate: CLLocationCoordinate2D
    ) -> (CLLocationCoordinate2D, CLLocationCoordinate2D)? {
        if let pendingSetupLine = referenceGuidanceLineEndpoints(
            from: previewCoordinatesForPendingSetup(),
            userCoordinate: userCoordinate
        ) {
            return pendingSetupLine
        }

        if let selectedTrackLine = referenceGuidanceLineEndpoints(
            from: selectedAutosteerTrackRecord?.previewCoordinates ?? [],
            userCoordinate: userCoordinate
        ) {
            return selectedTrackLine
        }

        if displayedActiveTrackPoints.count >= 2 {
            let a = displayedActiveTrackPoints[displayedActiveTrackPoints.count - 2].coordinate
            let b = displayedActiveTrackPoints[displayedActiveTrackPoints.count - 1].coordinate
            if a.latitude != b.latitude || a.longitude != b.longitude {
                return (a, b)
            }
        }

        guard let heading = location.headingDegrees else { return nil }
        let headingRadians = heading * .pi / 180
        let distanceMeters: CLLocationDistance = 120
        let earthRadiusM = 6_378_137.0
        let dLat = (distanceMeters * cos(headingRadians)) / earthRadiusM
        let dLon = (distanceMeters * sin(headingRadians)) / (earthRadiusM * cos(userCoordinate.latitude * .pi / 180))

        let projected = CLLocationCoordinate2D(
            latitude: userCoordinate.latitude + (dLat * 180 / .pi),
            longitude: userCoordinate.longitude + (dLon * 180 / .pi)
        )
        return (userCoordinate, projected)
    }

    private func referenceGuidanceLineEndpoints(
        from previewCoordinates: [[Double]],
        userCoordinate: CLLocationCoordinate2D
    ) -> (CLLocationCoordinate2D, CLLocationCoordinate2D)? {
        let validCoordinates: [CLLocationCoordinate2D] = previewCoordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            let coordinate = CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        }

        guard validCoordinates.count >= 2 else { return nil }

        let earthRadiusM = 6_378_137.0
        let latitudeRadians = userCoordinate.latitude * .pi / 180
        let metersPerDegreeLat = earthRadiusM * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(latitudeRadians)

        func localPoint(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: (coordinate.longitude - userCoordinate.longitude) * metersPerDegreeLon,
                y: (coordinate.latitude - userCoordinate.latitude) * metersPerDegreeLat
            )
        }

        let minSegmentLengthMeters = 0.5
        var bestSegment: (CLLocationCoordinate2D, CLLocationCoordinate2D)?
        var bestDistance = Double.greatestFiniteMagnitude

        for index in 0..<(validCoordinates.count - 1) {
            let start = validCoordinates[index]
            let end = validCoordinates[index + 1]
            let segmentLength = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            guard segmentLength > minSegmentLengthMeters else { continue }

            let a = localPoint(start)
            let b = localPoint(end)
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let lengthSquared = (ab.x * ab.x) + (ab.y * ab.y)
            guard lengthSquared > 0 else { continue }

            let t = min(1, max(0, -((a.x * ab.x) + (a.y * ab.y)) / lengthSquared))
            let closestPoint = CGPoint(x: a.x + (ab.x * t), y: a.y + (ab.y * t))
            let distanceToSegment = hypot(closestPoint.x, closestPoint.y)
            if distanceToSegment < bestDistance {
                bestDistance = distanceToSegment
                bestSegment = (start, end)
            }
        }

        return bestSegment
    }

    private func autosteerGuidanceBar(_ guidance: AutosteerGuidanceStatus) -> some View {
        let maxLights = 5
        let guidanceStepCentimeters = max(autosteerLightbarStepCM, 1)
        let activeOffsetCentimeters = max(0, guidance.offsetCentimeters)
        let activeRedLights = min(maxLights, Int(activeOffsetCentimeters / guidanceStepCentimeters))
        let centerLightIsActive = activeOffsetCentimeters < guidanceStepCentimeters

        return VStack(spacing: 6) {
            GeometryReader { proxy in
                let segmentSpacing: CGFloat = 6
                let centerWidth = min(26, max(16, proxy.size.width * 0.12))
                let sideLightWidth = max(
                    8,
                    (proxy.size.width - centerWidth - (segmentSpacing * 10)) / 10
                )

                HStack(spacing: segmentSpacing) {
                    ForEach(0..<maxLights, id: \.self) { index in
                        let threshold = maxLights - index
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(guidance.lineIsLeft && activeRedLights >= threshold ? .red : .red.opacity(0.16))
                            .frame(width: sideLightWidth, height: 6)
                    }

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(centerLightIsActive ? .green : chromeStroke)
                        .frame(width: centerWidth, height: 8)

                    ForEach(0..<maxLights, id: \.self) { index in
                        let threshold = index + 1
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(!guidance.lineIsLeft && activeRedLights >= threshold ? .red : .red.opacity(0.16))
                            .frame(width: sideLightWidth, height: 6)
                    }
                }
            }
            .frame(height: 8)

            Text("\(guidance.lineIsLeft ? "Left" : "Right") \(UnitFormatting.formattedCentimeters(guidance.offsetCentimeters))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(chromePrimaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 1)
        )
        .shadow(color: chromeShadow, radius: 10, y: 4)
    }

    private func autosteerGuidanceBarMaxWidth(for totalWidth: CGFloat) -> CGFloat {
        // Reserve room for left/right floating control columns and breathing space.
        let reservedSideWidth: CGFloat = 160
        return max(150, totalWidth - reservedSideWidth)
    }

    // MARK: - Map layer sheet

    private var mapLayerSheet: some View {
        GeometryReader { proxy in
            let outerPadding: CGFloat = 18
            let interItemSpacing: CGFloat = 10
            let columns = 3
            let availableWidth = proxy.size.width - (outerPadding * 2) - (interItemSpacing * CGFloat(columns - 1))
            let cardWidth = floor(availableWidth / CGFloat(columns))

            VStack(spacing: 0) {
                HStack {
                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            showMapLayerSheet = false
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(chromeStroke)
                                .frame(width: 44, height: 44)

                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(chromePrimaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, outerPadding)
                .padding(.top, 18)

                Text("Map Modes")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(chromePrimaryText)
                    .padding(.top, 6)
                    .padding(.bottom, 20)

                VStack(spacing: 14) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: interItemSpacing), count: columns),
                        spacing: 12
                    ) {
                        mapModeCard(.explore, width: cardWidth)
                        mapModeCard(.driving, width: cardWidth)
                        mapModeCard(.hybrid, width: cardWidth)
                        mapModeCard(.satellite, width: cardWidth)
                        mapModeCard(.blank, width: cardWidth)
                        mapModePlaceholderCard(width: cardWidth)
                    }
                }
                .padding(.horizontal, outerPadding)

                VStack(spacing: 12) {
                    Text("Camera Angle")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(chromeSecondaryText)
                        .padding(.top, 18)

                    HStack(spacing: 12) {
                        anglePill(0)
                        anglePill(45)
                        anglePill(80)
                    }
                }
                .padding(.horizontal, outerPadding)
                .padding(.top, 10)
                .padding(.bottom, 30)

                if autosteerEnabled {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 13, weight: .bold))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Autosteer lock active")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(chromePrimaryText)
                            Text("Map layer is locked to Blank. Camera angle defaults to 80° for guidance but remains adjustable.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(chromeSecondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, outerPadding)
                    .padding(.bottom, 14)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(chromeFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(chromeStroke, lineWidth: 1)
            )
            .shadow(color: chromeShadow, radius: 18, y: 8)
        }
        .frame(height: 660)
    }

    private func mapModeCard(_ option: MapModeOption, width: CGFloat) -> some View {
        let isSelected = selectedMapModeOption == option
        let previewWidth = max(70, width - 8)
        let isLockedByAutosteer = autosteerEnabled && option != .blank

        return Button {
            guard !isLockedByAutosteer else { return }
            mapStyleRaw = option.storedValue
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(option.isDarkPreview ? 0.05 : 0.08))
                        .frame(width: width, height: width * 0.82)

                    previewThumbnail(for: option)
                        .frame(width: previewWidth, height: width * 0.82 - 10)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    HStack(spacing: 6) {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 12, weight: .bold))
                        Text(option.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(chromePrimaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(chromeFill)
                    )
                    .padding(10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            isLockedByAutosteer ? chromeSecondaryText : (isSelected ? option.tint : chromeStroke),
                            lineWidth: isSelected ? 3 : 1
                        )
                )
                .shadow(
                    color: isSelected ? option.tint.opacity(0.32) : .clear,
                    radius: 10,
                    y: 3
                )

                VStack(spacing: 3) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(option.subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(width: width)
            }
            .frame(maxWidth: .infinity)
            .opacity(isLockedByAutosteer ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    private func mapModePlaceholderCard(width: CGFloat) -> some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.05))
                .frame(width: width, height: width * 0.82)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(chromeStroke, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                )

            VStack(spacing: 3) {
                Text("Coming Soon")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("No action yet")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(width: width)
        }
        .frame(maxWidth: .infinity)
    }
   

@ViewBuilder
private func previewThumbnail(for option: MapModeOption) -> some View {
    switch option {
    case .explore:
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.17, blue: 0.24),
                    Color(red: 0.08, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.green.opacity(0.30))
                .frame(width: 84, height: 84)
                .offset(x: -22, y: -12)

            Circle()
                .fill(Color.green.opacity(0.22))
                .frame(width: 62, height: 62)
                .offset(x: 26, y: 18)

            Path { path in
                path.move(to: CGPoint(x: 14, y: 70))
                path.addCurve(
                    to: CGPoint(x: 118, y: 24),
                    control1: CGPoint(x: 40, y: 26),
                    control2: CGPoint(x: 84, y: 76)
                )
            }
            .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))

            Circle()
                .fill(.orange)
                .frame(width: 10, height: 10)
                .offset(x: 18, y: 16)
        }

    case .driving:
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.14, blue: 0.19),
                    Color(red: 0.08, green: 0.10, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Path { path in
                path.move(to: CGPoint(x: 10, y: 76))
                path.addCurve(
                    to: CGPoint(x: 118, y: 18),
                    control1: CGPoint(x: 26, y: 48),
                    control2: CGPoint(x: 90, y: 48)
                )
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))

            Path { path in
                path.move(to: CGPoint(x: 10, y: 76))
                path.addCurve(
                    to: CGPoint(x: 118, y: 18),
                    control1: CGPoint(x: 26, y: 48),
                    control2: CGPoint(x: 90, y: 48)
                )
            }
            .stroke(Color.yellow.opacity(0.95), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 7]))

            Image(systemName: "car.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.green)
                .offset(x: 18, y: 12)
        }

    case .hybrid:
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.18, blue: 0.18),
                    Color(red: 0.10, green: 0.11, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.green.opacity(0.24))
                .frame(width: 88, height: 88)
                .offset(x: -20, y: -10)

            Rectangle()
                .fill(Color(red: 0.72, green: 0.74, blue: 0.71).opacity(0.85))
                .frame(width: 120, height: 10)
                .rotationEffect(.degrees(-28))

            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 86, height: 6)
                .rotationEffect(.degrees(26))

            Circle()
                .fill(.orange)
                .frame(width: 8, height: 8)
                .offset(x: 26, y: 16)
        }

    case .satellite:
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.50, green: 0.60, blue: 0.40),
                    Color(red: 0.38, green: 0.48, blue: 0.31)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.42, green: 0.50, blue: 0.30))
                .frame(width: 46, height: 34)
                .offset(x: -28, y: -20)

            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.60, green: 0.56, blue: 0.42))
                .frame(width: 62, height: 26)
                .offset(x: 22, y: -8)

            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.74, green: 0.70, blue: 0.58))
                .frame(width: 54, height: 22)
                .offset(x: -10, y: 24)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.28))
                .frame(width: 90, height: 6)
                .rotationEffect(.degrees(-24))
        }

    case .blank:
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.11, blue: 0.12),
                    Color(red: 0.07, green: 0.07, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "square.slash")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }
}
    private func anglePill(_ angle: Double) -> some View {
        let isSelected = Int(normalizedHeadsUpPitchDegrees.rounded()) == Int(angle.rounded())

        return Button {
            headsUpPitchDegrees = angle
            if !isHeadsUp {
                orientationRaw = "headsUp"
                recenterOnUser()
            }
        } label: {
            Text("\(Int(angle))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 56)
                .frame(height: 38)
                .padding(.horizontal, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(red: 0.0, green: 0.48, blue: 1.0) : .white.opacity(0.3))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Color(red: 0.35, green: 0.70, blue: 1.0) : .white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: isSelected ? Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.35) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func floatingControlsBottomPadding(for totalHeight: CGFloat) -> CGFloat {
        bottomPanelVisibleHeight(totalHeight: totalHeight) + 8
    }

    private func headsUpBottomObstructionHeight(for totalHeight: CGFloat) -> CGFloat {
        bottomPanelVisibleHeight(totalHeight: totalHeight) + 8
    }

    private func bottomPanelVisibleHeight(totalHeight: CGFloat) -> CGFloat {
        let collapsedHeight = 78.0
        let sanitizedTotalHeight = totalHeight.isFinite ? max(totalHeight, 0) : 0
        let largeHeight = max(520, sanitizedTotalHeight * 0.74)

        switch panelDetent {
        case .collapsed:
            return collapsedHeight
        case .large:
            return largeHeight
        }
    }

    // MARK: - Bottom panel

    private var bottomPanelDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in

                // Ignore drag if sheep scrubbing is active
                guard !isSheepScrubbing else { return }

                let drag = value.translation.height

























































                let predicted = value.predictedEndTranslation.height
                let snap = CGFloat(bottomSheetSnapThreshold)

                let moveUp = drag < -snap || predicted < -(snap * 1.5)
                let moveDown = drag > snap || predicted > (snap * 1.5)

                let target: MapBottomPanelDetent

                if moveUp {
                    switch panelDetent {
                    case .collapsed: target = .large
                    case .large: target = .large
                    }
                } else if moveDown {
                    switch panelDetent {
                    case .large: target = .collapsed
                    case .collapsed: target = .collapsed
                    }
                } else {
                    target = panelDetent
                }

                panelDetent = target
            }
    }

    @ViewBuilder
    private func appleMapsStyleBottomPanel(
        totalHeight: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        if !totalHeight.isFinite || totalHeight <= 0 {
            EmptyView()
        } else {
            let panelHeight = max(bottomPanelVisibleHeight(totalHeight: totalHeight), 0)
            let safeAreaInset = safeAreaBottom.isFinite ? max(safeAreaBottom, 0) : 0

            let panelCornerRadius: CGFloat
            switch panelDetent {
            case .collapsed:
                panelCornerRadius = max(panelHeight / 2, 0)
            case .large:
                panelCornerRadius = 24
            }

            VStack(spacing: 0) {
                Capsule()
                    .fill(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.25))
                    .shadow(color: colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.12), radius: 4)
                    .frame(width: 34, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)

                bottomQuickZoomRow

                if panelDetent != .collapsed {
                    expandedPanelContent
                        .padding(.bottom, safeAreaInset)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: panelHeight, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .fill(chromeFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .strokeBorder(chromeStroke, lineWidth: 1)
            )
            .shadow(color: chromeShadow, radius: 18, y: 4)
            .padding(.horizontal, 6)
            .padding(.bottom, -16)
            .contentShape(Rectangle())
            .gesture(bottomPanelDragGesture)
        }
    }
    private var bottomQuickZoomRow: some View {
        HStack(spacing: 8) {
            radioStatusButton

            HStack(spacing: 6) {
                ForEach(Array(normalizedQuickZooms.enumerated()), id: \.offset) { _, zoomValue in
                    quickZoomButton(
                        title: quickZoomLabel(zoomValue),
                        isSelected: selectedQuickZoomMeters == zoomValue
                    ) {
                        selectedQuickZoomMeters = zoomValue
                        postQuickZoomRequest(zoomValue)

                        // Force refresh so repeated taps always trigger
                        DispatchQueue.main.async {
                            selectedQuickZoomMeters = zoomValue
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .onEnded { _ in
                                showQuickZoomEditor = true
                            }
                    )
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(chromeFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(chromeStroke, lineWidth: 1)
            )

            if sheepPinEnabled {
                sheepScrubButton
                    .frame(width: 64, height: 46)
                    .zIndex(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .overlay(alignment: .topTrailing) {
            if showSheepCountPopover {
                sheepCountPopover
                    .offset(x: -100, y: -140)
                    .scaleEffect(1.12)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(100)
            }
        }
    }

                private var sheepScrubButton: some View {
                    GeometryReader { geo in
                        let buttonFrame = geo.frame(in: .global)

                        Button {
                            handleSheepQuickDropTap()
                        } label: {
                            Text(sheepPinButtonIcon)
                                .font(.system(size: 20))
                                .frame(width: 46, height: 46)
                                .background(
                                    Circle()
                                        .fill(chromeFill)
                                )
                                .overlay(
                                    Rectangle()
                                        .fill(chromePrimaryText.opacity(isSheepScrubbing ? 0.12 : 0))
                                        .frame(width: 2)
                                        .padding(.vertical, 10),
                                    alignment: .center
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSheepPinReady ? .blue : chromeStroke,
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: chromeShadow, radius: 10, y: 4)
                                .foregroundStyle(chromePrimaryText)
                                .opacity(isSheepPinReady ? 1.0 : 0.45)
                                .shadow(
                                    color: showSheepCountPopover ? .white.opacity(0.08) : .clear,
                                    radius: 8,
                                    y: 2
                                )
                                .scaleEffect(showSheepCountPopover ? 1.08 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSheepPinReady)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35)
                                .onEnded { _ in
                                    handleSheepQuickDropLongPress(startY: buttonFrame.midY)
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { value in
                                    handleSheepScrubChanged(value: value, buttonFrame: buttonFrame)
                                }
                                .onEnded { _ in
                                    handleSheepScrubEnded()
                                }
                        )
                    }
                }
    private var sheepCountPopover: some View {
        VStack(spacing: 4) {
            Text(selectedSheepCountDisplayText)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(chromePrimaryText)
                .monospacedDigit()

            Text(sheepCountPopoverLabelText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(chromeSecondaryText)
                .tracking(1)

            Text("↑ slide")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(chromeSecondaryText.opacity(0.8))
                .padding(.top, 2)
        }
        .frame(minWidth: 100)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 1)
        )
        .shadow(color: chromeShadow, radius: 16, y: 8)
    }

    private var radioStatusButton: some View {
        Button {
            followUser = false
            fitRadiosNonce &+= 1
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(hasActiveRadioConnection ? .blue : chromePrimaryText)
                    .frame(width: 64, height: 46)
                    .background(
                        Circle()
                            .fill(chromeFill)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                hasActiveRadioConnection ? .blue : chromeStroke,
                                lineWidth: 2
                            )
                    )

                if xrsRadioCount > 0 {
                    Text("\(min(xrsRadioCount, 9))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(
                            Circle()
                                .fill(.orange)
                        )
                        .offset(x: 2, y: -2)
                }
            }
        }
        .opacity(isSheepScrubbing ? 0.35 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isSheepScrubbing)
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    guard !xrsContacts.isEmpty else { return }
                    showRadioList = true
                }
        )
    }
    private var quickZoomEditorSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                quickZoomSliderRow(title: "Left", value: $quickZoom1M)
                quickZoomSliderRow(title: "Middle", value: $quickZoom2M)
                quickZoomSliderRow(title: "Right", value: $quickZoom3M)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Quick Zoom Buttons")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var importFilterSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ImportCategory.allCases) { category in
                        HStack(spacing: 12) {
                            Text(app.muster.iconForImportCategory(category))
                                .font(.title3)

                            Text(category.title)
                                .font(.body.weight(.semibold))

                            Spacer()

                            Button {
                                app.muster.toggleImportCategoryVisibility(category)
                            } label: {
                                Image(systemName: app.muster.isImportCategoryVisible(category) ? "eye.fill" : "eye.slash.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(app.muster.isImportCategoryVisible(category) ? .primary : .secondary)
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            app.muster.toggleImportCategoryVisibility(category)
                        }
                    }
                } header: {
                    Text("Map Filters")
                } footer: {
                    Text("Turn imported categories on or off on the map.")
                }

                Section {
                    Button("Show All") {
                        app.muster.showAllImportCategories()
                    }

                    Button("Hide All") {
                        app.muster.hideAllImportCategories()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Map Filter")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func quickZoomSliderRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                Text(UnitFormatting.formattedDistance(normalizedQuickZoomValue(value.wrappedValue), decimalsIfLarge: 0))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { normalizedQuickZoomValue(value.wrappedValue) },
                    set: { newValue in
                        value.wrappedValue = normalizedQuickZoomValue(newValue)
                    }
                ),
                in: 1000...20000,
                step: 1000
            )

            HStack {
                Text(UnitFormatting.formattedDistanceCompact(1000, decimalsIfLarge: 0))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(UnitFormatting.formattedDistanceCompact(20000, decimalsIfLarge: 0))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }


    private var radioListSheet: some View {
        NavigationStack {
            List {
                if xrsContacts.isEmpty {
                    ContentUnavailableView(
                        "No radios",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("No recent radio locations available.")
                    )
                } else {
                    ForEach(xrsContacts) { contact in
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)

                                if let status = contact.status?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !status.isEmpty {
                                    Text(status)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text(radioLastSeenText(for: contact))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showRadioList = false
                            startGoTo(contact)
                        }
                    }
                }
            }
            .navigationTitle("Recent Radios")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
    private var tpmsDashboardSheet: some View {
        NavigationStack {
            TPMSDashboardHostView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SheetCloseButton()
                    }
                }
        }
    }

    private var expandedPanelContent: some View {
        let km = kilometresForDayText
        let filter = importFilterSummaryText
        let trackShort = activeTrackAppearanceShortTitle()

        let isActive = activeSession?.isActive == true
        let hasTrack = activeSession?.hasTrack == true

        let prevMusters = "\(previousMusterCount)"

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                bottomActionButton(
                    title: isActive ? "Stop" : "Start",
                    systemImage: isActive ? "stop.fill" : "record.circle.fill"
                ) {
                    if isActive {
                        app.muster.stopActiveSession()
                    } else {
                        startNewTrackFlow()
                    }
                }

                bottomActionButton(
                    title: "New Track",
                    systemImage: "plus.circle.fill"
                ) {
                    startNewTrackFlow()
                }

                bottomActionButton(
                    title: "Map Sets",
                    systemImage: "square.stack.3d.down.right"
                ) {
                    panelDetent = .collapsed
                    showMapSetsSheet = true
                }
            }
            .padding(.horizontal, 14)

            HStack(spacing: 10) {
                bottomActionButton(
                    title: "TPMS",
                    systemImage: "tirepressure"
                ) {
                    panelDetent = .collapsed
                    showTPMSDashboard = true
                }

                bottomActionButton(
                    title: "Rings",
                    systemImage: "scope"
                ) {
                    panelDetent = .collapsed
                    showRingsSettings = true
                }

                bottomActionButton(
                    title: "Settings",
                    systemImage: "gearshape.fill"
                ) {
                    panelDetent = .collapsed
                    showSettings = true
                }
            }
            .padding(.horizontal, 14)

            VStack(spacing: 10) {
                panelButtonRow(
                    title: "Track View",
                    value: trackShort,
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                ) {
                    cycleActiveTrackAppearanceMode()
                }

                panelRow(
                    title: "Distance For Day",
                    value: km,
                    systemImage: "road.lanes"
                )

                panelButtonRow(
                    title: "Current Track",
                    value: hasTrack ? totalDistanceTextForCurrentTrack : "Open",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                ) {
                    panelDetent = .collapsed
                    showCurrentTrack = true
                }

                panelButtonRow(
                    title: "Previous Tracks",
                    value: prevMusters,
                    systemImage: "clock.arrow.circlepath"
                ) {
                    panelDetent = .collapsed
                    showPreviousMusters = true
                }

                panelButtonRow(
                    title: "Map Filter",
                    value: filter,
                    systemImage: "line.3.horizontal.decrease.circle"
                ) {
                    panelDetent = .collapsed
                    showImportFilterSheet = true
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
    }

    private func startNewTrackFlow() {
        pendingTrackName = app.muster.makeSmartSessionName()
        showNewTrackNamePrompt = true
    }

    private func startNewTrackImmediatelyFromQuickAction() {
        let quickTrackName = app.muster.makeSmartSessionName()
        if app.muster.startSession(name: quickTrackName) == false {
            showMissingMapSetPrompt = true
        }
    }

    private func processPendingQuickActionIfNeeded() {
        guard let action = app.pendingQuickAction else { return }
        handleHomeScreenQuickAction(action)
        app.clearPendingQuickAction()
    }

    private func handleHomeScreenQuickAction(_ action: HomeScreenQuickAction) {
        switch action {
        case .startNewTrack:
            startNewTrackImmediatelyFromQuickAction()
        case .importFiles:
            showImportFlow = true
        }
    }

    private func handleMainViewAppear() {
        longPressedSessionMarker = nil
        longPressedMapMarker = nil
        showLongPressedSessionMarkerDialog = false
        showLongPressedMapMarkerDialog = false
        longPressedTrackTarget = nil
        showLongPressedTrackDialog = false
        pendingTrackDeleteConfirmation = nil
        showTrackDeleteConfirmationAlert = false

        editingSessionMarker = nil
        editingSessionMarkerName = ""
        movingSessionMarker = nil

        editingMapMarker = nil
        editingMapMarkerName = ""
        movingMapMarker = nil

        showEditSessionMarkerAlert = false
        showEditMapMarkerAlert = false

        manualGoToTarget = nil
        pendingMarkerCoordinate = nil

        location.start()
        normalizeQuickZoomSettings()
        normalizeHeadsUpPitchSetting()
        normalizeHeadsUpUserVerticalOffsetSetting()
        normalizeTopPillSettings()
        selectedQuickZoomMeters = normalizedQuickZooms[1]
        postQuickZoomRequest(normalizedQuickZooms[1])

        if activeTrackAppearanceRaw != "altitude",
           activeTrackAppearanceRaw != "speed",
           activeTrackAppearanceRaw != "off" {
            activeTrackAppearanceRaw = "altitude"
        }

        selectedQuickZoomMeters = normalizedQuickZoomValue(quickZoom2M)
        app.xrs.removeStaleContacts()
        smartETA.reset()
        syncDisplayedActiveTrackPoints()
        resetSheepCountSelection()
        refreshKnownFarms()

        Task {
            await refreshWeatherIfNeeded()
        }

        processPendingQuickActionIfNeeded()
    }

    private func handleMainViewDisappear() {
        location.stop()
        smartETA.reset()
        isSheepScrubbing = false
        sheepScrubStartY = nil
        sheepLastHapticIndex = nil
        showSheepCountPopover = false
        zoomDistanceHideWorkItem?.cancel()
        zoomDistanceHideWorkItem = nil
        zoomDistancePopupText = nil
        cruiseSpeedPopupHideWorkItem?.cancel()
        cruiseSpeedPopupHideWorkItem = nil
        cruiseSpeedPopupText = nil

        Task {
            await GoToLiveActivityManager.shared.stop()
        }
    }

    private func showZoomDistancePopup(distanceMeters: CLLocationDistance) {
        let normalizedMeters = max(80, Int(distanceMeters.rounded()))
        zoomDistanceHideWorkItem?.cancel()

        withAnimation(.easeInOut(duration: 0.2)) {
            zoomDistancePopupText = "\(normalizedMeters)m"
        }

        let hideWorkItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomDistancePopupText = nil
            }
        }
        zoomDistanceHideWorkItem = hideWorkItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: hideWorkItem)
    }

    private func showCruiseControlSetSpeedPopup() {
        cruiseSpeedPopupHideWorkItem?.cancel()

        let cruiseSpeedMetersPerSecond = max(0, cruiseControlSpeedKPH) / 3.6
        let speedText = UnitFormatting.formattedSpeed(fromMetersPerSecond: cruiseSpeedMetersPerSecond, decimals: 0)

        withAnimation(.easeInOut(duration: 0.18)) {
            cruiseSpeedPopupText = speedText
        }

        let hideWorkItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                cruiseSpeedPopupText = nil
            }
        }
        cruiseSpeedPopupHideWorkItem = hideWorkItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: hideWorkItem)
    }

    private var leftSideFloatingPills: some View {
        VStack(spacing: 10) {
            if mediaButtonEnabled {
                leftSideMediaPill
            }
            leftSideZoomPill
        }
    }

    private var leftSideMediaPill: some View {
        VStack(spacing: 0) {
            Button {
                skipToNextMediaItem()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chromePrimaryText)
                    .frame(width: 48, height: 48)
            }

            Rectangle()
                .fill(chromeStroke)
                .frame(width: 24, height: 1)

            Button {
                playPauseMedia()
            } label: {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chromePrimaryText)
                    .frame(width: 48, height: 48)
            }
        }
        .frame(width: 48)
        .background(
            Capsule(style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 1)
        )
        .shadow(color: chromeShadow, radius: 10, y: 4)
        .fixedSize()
    }

    private var leftSideZoomPill: some View {
        VStack(spacing: 0) {
            Button {
                stepMapZoom(by: -zoomStepIncrementMeters)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chromePrimaryText)
                    .frame(width: 48, height: 48)
            }

            Rectangle()
                .fill(chromeStroke)
                .frame(width: 24, height: 1)

            Button {
                stepMapZoom(by: zoomStepIncrementMeters)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chromePrimaryText)
                    .frame(width: 48, height: 48)
            }
        }
        .frame(width: 48)
        .background(
            Capsule(style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 1)
        )
        .shadow(color: chromeShadow, radius: 10, y: 4)
        .fixedSize()
    }

    private func quickZoomButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : chromePrimaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? .white.opacity(0.22) : chromeStroke, lineWidth: 1)
                )
                .shadow(color: chromeShadow.opacity(isSelected ? 1 : 0.5), radius: 4, y: 1)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }

    private func quickStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(chromeSecondaryText)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(chromePrimaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 1)
        )
        .shadow(color: chromeShadow, radius: 8, y: 3)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
    }

    private func quickStatButton(
        title: String,
        value: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                    }

                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(chromeSecondaryText)

                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(chromePrimaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(chromeFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(chromeStroke, lineWidth: 1)
            )
            .shadow(color: chromeShadow, radius: 8, y: 3)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .buttonStyle(.plain)
    }

    private func bottomActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(chromePrimaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(chromeFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(chromeStroke, lineWidth: 2)
            )
            .shadow(color: chromeShadow, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func panelButtonRow(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            panelRow(title: title, value: value, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func panelRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(chromeSecondaryText)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(chromePrimaryText)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(chromeSecondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(chromeFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(chromeStroke, lineWidth: 1)
        )
    }

    // MARK: - Marker actions

    private func startGoTo(_ marker: MusterMarker) {
        smartETA.reset()
        gotoTarget = marker
        activeRadioGoToContactID = nil

        let trimmed = marker.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = trimmed?.isEmpty == false ? (trimmed ?? marker.type.title) : marker.type.title

        manualGoToTarget = ManualGoToTarget(
            coordinate: marker.coordinate,
            title: marker.displayTitle,
            subtitle: subtitle
        )

        GoToLiveActivityManager.shared.start(
            markerName: marker.displayTitle,
            coordinate: marker.coordinate
        )

        app.muster.clearActiveSheepTarget()
    }

    private func startGoTo(_ marker: MapMarker) {
        smartETA.reset()
        gotoTarget = nil
        activeRadioGoToContactID = nil

        manualGoToTarget = ManualGoToTarget(
            coordinate: marker.coordinate,
            title: marker.displayTitle,
            subtitle: marker.templateDescription
        )

        GoToLiveActivityManager.shared.start(
            markerName: marker.displayTitle,
            coordinate: marker.coordinate
        )

        app.muster.clearActiveSheepTarget()
    }

    private func startGoTo(_ marker: ImportedMarker) {
        smartETA.reset()
        gotoTarget = nil
        activeRadioGoToContactID = nil

        let trimmedNote = marker.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMarkerType = marker.markerType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSubtitle = (trimmedMarkerType?.isEmpty == false) ? (trimmedMarkerType ?? marker.category.title) : marker.category.title

        manualGoToTarget = ManualGoToTarget(
            coordinate: marker.coordinate,
            title: marker.displayTitle,
            subtitle: trimmedNote?.isEmpty == false ? (trimmedNote ?? fallbackSubtitle) : fallbackSubtitle
        )

        GoToLiveActivityManager.shared.start(
            markerName: marker.displayTitle,
            coordinate: marker.coordinate
        )

        app.muster.clearActiveSheepTarget()
    }

    private func clearGoToTarget() {
        gotoTarget = nil
        manualGoToTarget = nil
        activeRadioGoToContactID = nil
        app.muster.clearActiveSheepTarget()
        smartETA.reset()

        Task {
            await GoToLiveActivityManager.shared.stop()
        }
    }

    private func deleteSessionMarker(_ marker: MusterMarker) {
        if gotoTarget?.id == marker.id {
            clearGoToTarget()
        }

        app.muster.deleteSessionMarker(
            markerID: marker.id,
            in: activeSession?.id
        )
    }

    private func deletePermanentMapMarker(_ marker: MapMarker) {
        if manualGoToTarget?.coordinate.latitude == marker.coordinate.latitude,
           manualGoToTarget?.coordinate.longitude == marker.coordinate.longitude,
           manualGoToTarget?.title == marker.displayTitle {
            clearGoToTarget()
        }

        app.muster.deleteMapMarker(markerID: marker.id)
    }

    private func deleteLongPressedTrack(_ track: LongPressedTrackTarget) {
        switch track {
        case .previousSession(let sessionID, _, _):
            app.muster.deleteSession(sessionID: sessionID)
        case .imported(let trackID, _, _):
            app.muster.deleteImportedTrack(trackID: trackID)
        }
    }

    private func saveSessionMarkerEdit() {
        guard let marker = editingSessionMarker else { return }

        let trimmed = editingSessionMarkerName.trimmingCharacters(in: .whitespacesAndNewlines)

        app.muster.renameSessionMarker(
            markerID: marker.id,
            in: activeSession?.id,
            newName: trimmed.isEmpty ? nil : trimmed
        )

        editingSessionMarker = nil
        editingSessionMarkerName = ""
    }

    private func saveMapMarkerEdit() {
        guard let marker = editingMapMarker else { return }

        let trimmed = editingMapMarkerName.trimmingCharacters(in: .whitespacesAndNewlines)

        app.muster.renameMapMarker(
            markerID: marker.id,
            newName: trimmed.isEmpty ? nil : trimmed
        )

        editingMapMarker = nil
        editingMapMarkerName = ""
    }

    // MARK: - Sheep quick-drop scrub

    private func handleSheepQuickDropTap() {
        if suppressNextSheepButtonTap {
            suppressNextSheepButtonTap = false
            return
        }

        _ = dropPlainSheepPin()
    }

    private func handleSheepQuickDropLongPress(startY: CGFloat) {
        guard location.lastLocation != nil else { return }
        guard !isSheepScrubbing else { return }

        suppressNextSheepButtonTap = true
        isSheepScrubbing = true
        sheepScrubStartY = startY
        sheepLastHapticIndex = sheepCountSelectionIndex

        resetSheepCountSelection()
        impactHaptic(.heavy)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            showSheepCountPopover = true
        }
    }

    private func handleSheepScrubChanged(value: DragGesture.Value, buttonFrame: CGRect) {
        guard isSheepScrubbing else { return }

        if sheepScrubStartY == nil {
            sheepScrubStartY = buttonFrame.midY
        }

        let startY = sheepScrubStartY ?? buttonFrame.midY
        let deltaY = startY - value.location.y
        let stepHeight: CGFloat = 30

        let rawIndex = Int(floor(max(0, deltaY) / stepHeight))
        let clampedIndex = max(0, min(sheepCountOptions.count - 1, rawIndex))

        if clampedIndex != sheepCountSelectionIndex {
            sheepCountSelectionIndex = clampedIndex

            if sheepLastHapticIndex != clampedIndex {
                sheepLastHapticIndex = clampedIndex
                impactHaptic(.heavy)
            }
        }

        if showSheepCountPopover == false {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                showSheepCountPopover = true
            }
        }
    }

    private func handleSheepScrubEnded() {
        guard isSheepScrubbing else { return }

        let estimate = selectedSheepCountValue
        isSheepScrubbing = false
        sheepScrubStartY = nil
        sheepLastHapticIndex = nil

        withAnimation(.spring(response: 0.20, dampingFraction: 0.90)) {
            showSheepCountPopover = false
        }

        _ = dropSheepPin(withEstimate: estimate)
    }

    @discardableResult
    private func dropPlainSheepPin() -> Bool {
        guard let loc = location.lastLocation else {
            print("Drop Sheep failed: no current location")
            return false
        }

        let markerID = app.muster.dropSheepPin(at: loc)
        return markerID != nil
    }

    @discardableResult
    private func dropSheepPin(withEstimate sheepCountEstimate: Int) -> UUID? {
        guard let loc = location.lastLocation else {
            print("Drop Sheep failed: no current location")
            return nil
        }

        return app.muster.dropSheepPin(
            at: loc,
            sheepCountEstimate: sheepCountEstimate
        )
    }

    private func resetSheepCountSelection() {
        sheepCountSelectionIndex = 0
    }

    private func sheepCountDisplayText(for value: Int) -> String {
        value >= 100 ? "100+" : "\(value)"
    }

    private func playFenceWarningSound() {
        guard let url = Bundle.main.url(forResource: "fence_alarm", withExtension: "wav") else {
            print("Missing fence_alarm.wav")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            fenceWarningPlayer?.stop()
            fenceWarningPlayer = try AVAudioPlayer(contentsOf: url)
            fenceWarningPlayer?.numberOfLoops = 0
            fenceWarningPlayer?.prepareToPlay()
            fenceWarningPlayer?.play()
        } catch {
            print("Failed to play fence warning sound: \(error)")
        }
    }

    private func impactHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Weather

    private func refreshWeatherIfNeeded() async {
        await weatherStore.refreshIfNeeded(for: location.lastLocation)
    }

    // MARK: - Active track display throttling

    private func syncDisplayedActiveTrackPoints() {
        let latest = activeTrackPoints

        guard displayedActiveTrackPoints.count != latest.count else { return }

        displayedActiveTrackPoints = latest
    }

    // MARK: - Top pill helpers

    private func applyTopPillMetric(_ metric: TopSidePillMetric) {
        switch topPillPickerSide {
        case .left:
            topLeftPillMetricRaw = metric.rawValue
        case .right:
            topRightPillMetricRaw = metric.rawValue
        case nil:
            break
        }

        topPillPickerSide = nil
    }

    private func normalizeTopPillSettings() {
        if TopSidePillMetric(rawValue: topLeftPillMetricRaw) == nil {
            topLeftPillMetricRaw = TopSidePillMetric.weather.rawValue
        }

        if TopSidePillMetric(rawValue: topRightPillMetricRaw) == nil {
            topRightPillMetricRaw = TopSidePillMetric.wind.rawValue
        }
    }

    // MARK: - Quick zoom helpers

    private func cycleActiveTrackAppearanceMode() {
        switch activeTrackAppearanceRaw {
        case "altitude":
            activeTrackAppearanceRaw = "speed"
        case "speed":
            activeTrackAppearanceRaw = "off"
        default:
            activeTrackAppearanceRaw = "altitude"
        }
    }

    private func activeTrackAppearanceTitle() -> String {
        switch activeTrackAppearanceRaw {
        case "speed":
            return "Gradient - Speed"
        case "off":
            return "Off"
        default:
            return "Gradient - Altitude"
        }
    }
    private func activeTrackAppearanceShortTitle() -> String {
        switch activeTrackAppearanceRaw {
        case "speed":
            return "Speed"
        case "off":
            return "Plain"
        default:
            return "Altitude"
        }
    }

    private func normalizedQuickZoomValue(_ value: Double) -> Double {
        let step = 1000.0
        let minValue = 1000.0
        let maxValue = 20000.0
        let clamped = min(max(value, minValue), maxValue)
        return (clamped / step).rounded() * step
    }

    private func quickZoomLabel(_ meters: Double) -> String {
        let normalized = normalizedQuickZoomValue(meters)
        return UnitFormatting.formattedDistanceCompact(normalized, decimalsIfLarge: 0)
    }

    private func postQuickZoomRequest(_ meters: Double) {
        let value = normalizedQuickZoomValue(meters)

        NotificationCenter.default.post(
            name: .musterQuickZoomRequested,
            object: nil,
            userInfo: ["meters": value]
        )
    }

    private func postExactZoomRequest(_ meters: Double) {
        NotificationCenter.default.post(
            name: .musterQuickZoomRequested,
            object: nil,
            userInfo: ["meters": meters]
        )
    }

    private func applyAutosteerMapLockIfNeeded() {
        guard autosteerEnabled else { return }
        if mapStyleRaw != "blank" {
            mapStyleBeforeAutosteerLock = mapStyleRaw
        }
        mapStyleRaw = "blank"
        orientationRaw = "headsUp"
        headsUpPitchDegrees = 80
        postExactZoomRequest(200)
    }

    private func applyAutosteerTrackCreationMapView() {
        mapStyleRaw = "satellite"
        orientationRaw = "northUp"
        postExactZoomRequest(3000)
    }

    private var zoomStepIncrementMeters: Double {
        autosteerEnabled ? 100 : 1000
    }

    private func stepMapZoom(by deltaMeters: Double) {
        NotificationCenter.default.post(
            name: .musterStepZoomRequested,
            object: nil,
            userInfo: ["deltaMeters": deltaMeters]
        )
    }

    private func normalizeQuickZoomSettings() {
        quickZoom1M = normalizedQuickZoomValue(quickZoom1M)
        quickZoom2M = normalizedQuickZoomValue(quickZoom2M)
        quickZoom3M = normalizedQuickZoomValue(quickZoom3M)
    }

    private func syncSelectedQuickZoomIfNeeded() {
        if let selected = selectedQuickZoomMeters {
            let available = normalizedQuickZooms
            if available.contains(selected) == false {
                selectedQuickZoomMeters = available[1]
            }
        } else {
            selectedQuickZoomMeters = normalizedQuickZooms[1]
        }
    }

    private func normalizedHeadsUpPitchValue(_ value: Double) -> Double {
        let allowed: [Double] = [0, 45, 80]
        if allowed.contains(value) { return value }
        return allowed.min(by: { abs($0 - value) < abs($1 - value) }) ?? 45
    }

    private func normalizeHeadsUpPitchSetting() {
        headsUpPitchDegrees = normalizedHeadsUpPitchValue(headsUpPitchDegrees)
    }

    private func normalizedHeadsUpUserVerticalOffsetValue(_ value: Double) -> Double {
        min(max(value.rounded(), 0), 10)
    }

    private func normalizeHeadsUpUserVerticalOffsetSetting() {
        headsUpUserVerticalOffset = normalizedHeadsUpUserVerticalOffsetValue(headsUpUserVerticalOffset)
    }
    private func playPauseMedia() {
        let status = MPMediaLibrary.authorizationStatus()

        switch status {
        case .authorized:
            toggleSystemMusicPlayback()

        case .notDetermined:
            MPMediaLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        toggleSystemMusicPlayback()
                    }
                }
            }

        case .denied, .restricted:
            print("Apple Music access denied or restricted")

        @unknown default:
            print("Unknown Apple Music authorization state")
        }
    }

    private func skipToNextMediaItem() {
        let status = MPMediaLibrary.authorizationStatus()

        switch status {
        case .authorized:
            MPMusicPlayerController.systemMusicPlayer.skipToNextItem()

        case .notDetermined:
            MPMediaLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized {
                        MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
                    }
                }
            }

        case .denied, .restricted:
            print("Apple Music access denied or restricted")

        @unknown default:
            print("Unknown Apple Music authorization state")
        }
    }

    private func toggleSystemMusicPlayback() {
        let player = MPMusicPlayerController.systemMusicPlayer

        switch player.playbackState {
        case .playing:
            player.pause()
        case .paused, .stopped, .interrupted:
            player.play()
        default:
            player.play()
        }
    }


    private func startGoTo(_ contact: XRSRadioContact) {
        gotoTarget = nil
        activeRadioGoToContactID = contact.id

        let trimmedStatus = contact.status?.trimmingCharacters(in: .whitespacesAndNewlines)

        manualGoToTarget = ManualGoToTarget(
            coordinate: contact.coordinate,
            title: contact.name,
            subtitle: trimmedStatus?.isEmpty == false ? (trimmedStatus ?? "Radio") : "Radio"
        )

        GoToLiveActivityManager.shared.start(
            markerName: contact.name,
            coordinate: contact.coordinate
        )

        app.muster.clearActiveSheepTarget()
    }
    private func radioLastSeenText(for contact: XRSRadioContact) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(contact.lastHeard)))

        if seconds < 60 {
            return "\(seconds)s ago"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h \(minutes % 60)m ago"
        }

        let days = hours / 24
        return "\(days)d ago"
    }

    // MARK: - Fence approach warning

    private func evaluateFenceApproachWarning(using location: CLLocation) {
        guard !importedBoundaries.isEmpty else {
            clearFenceApproachWarning()
            return
        }

        let speed = max(location.speed, 0)

        if showFenceApproachWarning {
            if speed < fenceWarningSpeedThresholdMPS {
                clearFenceApproachWarning()
                return
            }

            guard let result = nearestBoundaryApproach(to: location) else {
                clearFenceApproachWarning()
                return
            }

            if result.distanceMeters > fenceWarningHideDistanceMeters || !result.isHeadingTowardFence {
                clearFenceApproachWarning()
                return
            }

            activeFenceWarningBoundaryID = result.boundaryID
            return
        }

        guard speed >= fenceWarningSpeedThresholdMPS else { return }
        guard Date().timeIntervalSince(lastFenceWarningAt) >= fenceWarningCooldownSeconds else { return }

        guard let result = nearestBoundaryApproach(to: location) else { return }
        guard result.distanceMeters <= fenceWarningShowDistanceMeters else { return }
        guard result.isHeadingTowardFence else { return }

        activeFenceWarningBoundaryID = result.boundaryID
        fenceWarningDistanceMeters = result.distanceMeters
        lastFenceWarningAt = Date()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showFenceApproachWarning = true
        }

        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        playFenceWarningSound()
    }

    private func clearFenceApproachWarning() {
        guard showFenceApproachWarning || activeFenceWarningBoundaryID != nil else { return }

        activeFenceWarningBoundaryID = nil
        fenceWarningDistanceMeters = nil

        withAnimation(.easeInOut(duration: 0.18)) {
            showFenceApproachWarning = false
        }
    }

    private func currentTravelDirectionDegrees(from location: CLLocation) -> Double? {
        if location.course >= 0, location.speed >= fenceWarningSpeedThresholdMPS {
            return normalizeDegrees(location.course)
        }

        if let heading = self.location.headingDegrees {
            return normalizeDegrees(heading)
        }

        return nil
    }

    private func nearestBoundaryApproach(to location: CLLocation) -> (
        boundaryID: UUID,
        distanceMeters: CLLocationDistance,
        isHeadingTowardFence: Bool
    )? {
        guard let travelDegrees = currentTravelDirectionDegrees(from: location) else { return nil }

        let user = location.coordinate
        var bestBoundaryID: UUID?
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        var bestBearingToFence = 0.0

        for boundary in importedBoundaries where boundary.isVisible && boundary.category == .boundaries {
            for ring in boundary.rings {
                let coords = ring.map(\.clCoordinate)
                guard coords.count >= 2 else { continue }

                for index in 0..<coords.count {
                    let a = coords[index]
                    let b = coords[(index + 1) % coords.count]

                    let candidate = nearestPointOnSegment(
                        from: user,
                        segmentStart: a,
                        segmentEnd: b
                    )

                    if candidate.distanceMeters < bestDistance {
                        bestDistance = candidate.distanceMeters
                        bestBearingToFence = bearingDegrees(from: user, to: candidate.coordinate)
                        bestBoundaryID = boundary.id
                    }
                }
            }
        }

        guard let bestBoundaryID else { return nil }

        let delta = abs(shortestSignedDegrees(from: travelDegrees, to: bestBearingToFence))
        let isHeadingTowardFence = delta <= fenceWarningHeadingToleranceDegrees

        return (
            boundaryID: bestBoundaryID,
            distanceMeters: bestDistance,
            isHeadingTowardFence: isHeadingTowardFence
        )
    }

    private func nearestPointOnSegment(
        from point: CLLocationCoordinate2D,
        segmentStart a: CLLocationCoordinate2D,
        segmentEnd b: CLLocationCoordinate2D
    ) -> (coordinate: CLLocationCoordinate2D, distanceMeters: CLLocationDistance) {
        let originLatRadians = point.latitude * .pi / 180.0
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = max(1.0, cos(originLatRadians) * 111_320.0)

        func toLocalXY(_ c: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: (c.longitude - point.longitude) * metersPerDegLon,
                y: (c.latitude - point.latitude) * metersPerDegLat
            )
        }

        func toCoordinate(_ p: CGPoint) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: point.latitude + (p.y / metersPerDegLat),
                longitude: point.longitude + (p.x / metersPerDegLon)
            )
        }

        let p = CGPoint(x: 0, y: 0)
        let p1 = toLocalXY(a)
        let p2 = toLocalXY(b)

        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared <= 0.0001 {
            let distance = hypot(p1.x - p.x, p1.y - p.y)
            return (a, distance)
        }

        let t = max(0, min(1, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lengthSquared))
        let nearest = CGPoint(x: p1.x + t * dx, y: p1.y + t * dy)
        let distance = hypot(nearest.x, nearest.y)

        return (toCoordinate(nearest), distance)
    }

    // MARK: - Direction helpers

    private func currentFacingDegrees(from location: CLLocation) -> Double {
        if let heading = self.location.headingDegrees {
            return normalizeDegrees(heading)
        }

        if location.course >= 0, location.speed > 0.7 {
            return normalizeDegrees(location.course)
        }

        return 0
    }

    private func bearingDegrees(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi

        return normalizeDegrees(degrees)
    }

    private func normalizeDegrees(_ value: Double) -> Double {
        var v = value.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }

    private func shortestSignedDegrees(from: Double, to: Double) -> Double {
        var diff = (to - from).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff
    }


    private enum MapBottomPanelDetent {
        case collapsed
        case large
    }
}

private struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Close")
    }
}

    extension Notification.Name {
    static let musterQuickZoomRequested = Notification.Name("muster_quick_zoom_requested")
    static let musterStepZoomRequested = Notification.Name("muster_step_zoom_requested")
}
