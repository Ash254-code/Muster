import Foundation
import UIKit
import Combine
import CoreLocation

@MainActor
final class BatteryDiagnosticsStore: ObservableObject {

    enum ImpactLevel: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
    }

    @Published private(set) var batteryLevelPercent: Int?
    @Published private(set) var batteryState: UIDevice.BatteryState = .unknown
    @Published private(set) var isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    private var cancellables = Set<AnyCancellable>()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()

        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification))
            .sink { [weak self] _ in
                self?.refreshBattery()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                self?.refreshPower()
            }
            .store(in: &cancellables)

        _ = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.refreshThermal()
            }
            .store(in: &cancellables)
    }

    deinit {
        // deinit is nonisolated; schedule main-actor mutation safely
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    func refresh() {
        refreshBattery()
        refreshPower()
        refreshThermal()
    }

    private func refreshBattery() {
        let level = UIDevice.current.batteryLevel
        batteryLevelPercent = level < 0 ? nil : Int((level * 100).rounded())
        batteryState = UIDevice.current.batteryState
    }

    private func refreshPower() {
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func refreshThermal() {
        thermalState = ProcessInfo.processInfo.thermalState
    }

    var batteryStateText: String {
        switch batteryState {
        case .unknown: return "Unknown"
        case .unplugged: return "On Battery"
        case .charging: return "Charging"
        case .full: return "Full"
        @unknown default: return "Unknown"
        }
    }

    var thermalStateText: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    func estimatedImpact(
        location: LocationService?,
        followUser: Bool,
        mapIs3D: Bool,
        keepScreenAwake: Bool,
        sensitivity: Double,
        includeHeading: Bool,
        includeBackground: Bool
    ) -> ImpactLevel {

        var score = 0.0

        if let location {
            if location.isUpdating { score += 1.0 }

            let accuracy = location.adminDesiredAccuracy
            if accuracy <= kCLLocationAccuracyBestForNavigation {
                score += 2.4
            } else if accuracy <= kCLLocationAccuracyBest {
                score += 1.9
            } else if accuracy <= kCLLocationAccuracyNearestTenMeters {
                score += 1.2
            } else {
                score += 0.6
            }

            let filter = location.adminDistanceFilter
            if filter <= 2 { score += 2.0 }
            else if filter <= 5 { score += 1.3 }
            else if filter <= 10 { score += 0.8 }
            else { score += 0.3 }

            if includeHeading && location.adminHeadingUpdatesEnabled {
                score += 1.1
            }

            if includeBackground && location.adminBackgroundUpdatesEnabled {
                score += 1.4
            }

            if !location.adminPausesAutomatically {
                score += 0.8
            }
        }

        if followUser { score += 0.7 }
        if mapIs3D { score += 1.0 }
        if keepScreenAwake { score += 1.2 }
        if isLowPowerModeEnabled { score += 0.4 }

        switch thermalState {
        case .fair:
            score += 0.5
        case .serious:
            score += 1.2
        case .critical:
            score += 2.0
        case .nominal:
            break
        @unknown default:
            break
        }

        score *= max(0.5, min(2.0, sensitivity))

        if score < 4.0 { return .low }
        if score < 7.5 { return .medium }
        return .high
    }
}
