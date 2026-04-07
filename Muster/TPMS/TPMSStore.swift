import Foundation
import Combine

private let kTPMSStoreSensorsKey = "tpms_store_sensors_v1"
private let kTPMSStoreActiveAlertKey = "tpms_store_active_alert_v1"

enum TPMSWheelPosition: String, CaseIterable, Identifiable, Codable {
    case frontLeft
    case frontRight
    case rearLeft
    case rearRight
    case spare1
    case spare2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frontLeft: return "Front Left"
        case .frontRight: return "Front Right"
        case .rearLeft: return "Rear Left"
        case .rearRight: return "Rear Right"
        case .spare1: return "Spare 1"
        case .spare2: return "Spare 2"
        }
    }

    var shortTitle: String {
        switch self {
        case .frontLeft: return "FL"
        case .frontRight: return "FR"
        case .rearLeft: return "RL"
        case .rearRight: return "RR"
        case .spare1: return "S1"
        case .spare2: return "S2"
        }
    }
}

enum TPMSAlertType: String, Codable {
    case lowPressure
    case highPressure
}

struct TPMSAlert: Identifiable, Codable, Equatable {
    let id: UUID
    let sensorID: String
    let position: TPMSWheelPosition
    let type: TPMSAlertType
    let pressurePSI: Double
    let message: String
    let triggeredAt: Date

    init(
        id: UUID = UUID(),
        sensorID: String,
        position: TPMSWheelPosition,
        type: TPMSAlertType,
        pressurePSI: Double,
        triggeredAt: Date = Date()
    ) {
        self.id = id
        self.sensorID = sensorID
        self.position = position
        self.type = type
        self.pressurePSI = pressurePSI
        self.triggeredAt = triggeredAt

        switch type {
        case .lowPressure:
            self.message = "\(position.shortTitle) Tyre Pressure Low"
        case .highPressure:
            self.message = "\(position.shortTitle) Tyre Pressure High"
        }
    }
}

struct TPMSSensor: Identifiable, Codable, Equatable {
    let id: UUID
    var sensorID: String
    var name: String
    var assignedPosition: TPMSWheelPosition
    var pressurePSI: Double?
    var temperatureC: Double?
    var batteryPercent: Int?
    var lastUpdatedAt: Date?
    var lastSeenAt: Date?
    var isConnected: Bool
    var lastAlertType: TPMSAlertType?

    init(
        id: UUID = UUID(),
        sensorID: String,
        name: String,
        assignedPosition: TPMSWheelPosition,
        pressurePSI: Double? = nil,
        temperatureC: Double? = nil,
        batteryPercent: Int? = nil,
        lastUpdatedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        isConnected: Bool = false,
        lastAlertType: TPMSAlertType? = nil
    ) {
        self.id = id
        self.sensorID = sensorID
        self.name = name
        self.assignedPosition = assignedPosition
        self.pressurePSI = pressurePSI
        self.temperatureC = temperatureC
        self.batteryPercent = batteryPercent
        self.lastUpdatedAt = lastUpdatedAt
        self.lastSeenAt = lastSeenAt
        self.isConnected = isConnected
        self.lastAlertType = lastAlertType
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? sensorID : trimmedName
    }
}

struct TPMSDecodedReading {
    var sensorID: String
    var pressurePSI: Double?
    var temperatureC: Double?
    var batteryPercent: Int?
    var timestamp: Date

    init(
        sensorID: String,
        pressurePSI: Double? = nil,
        temperatureC: Double? = nil,
        batteryPercent: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.sensorID = sensorID
        self.pressurePSI = pressurePSI
        self.temperatureC = temperatureC
        self.batteryPercent = batteryPercent
        self.timestamp = timestamp
    }
}

@MainActor
final class TPMSStore: ObservableObject {
    @Published private(set) var sensors: [TPMSSensor] = []
    @Published var activeAlert: TPMSAlert?

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var pairedSensorCount: Int {
        sensors.count
    }

    var maxSensors: Int {
        6
    }

    func sensor(for position: TPMSWheelPosition) -> TPMSSensor? {
        sensors.first(where: { $0.assignedPosition == position })
    }

    func sensor(withSensorID sensorID: String) -> TPMSSensor? {
        sensors.first(where: { $0.sensorID.caseInsensitiveCompare(sensorID) == .orderedSame })
    }

    func isPositionAssigned(_ position: TPMSWheelPosition) -> Bool {
        sensor(for: position) != nil
    }

    func addOrReplaceSensor(
        sensorID: String,
        name: String,
        position: TPMSWheelPosition
    ) {
        let cleanSensorID = sensorID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanSensorID.isEmpty else { return }

        if let existingIndex = sensors.firstIndex(where: {
            $0.sensorID.caseInsensitiveCompare(cleanSensorID) == .orderedSame
        }) {
            sensors[existingIndex].name = cleanName
            sensors[existingIndex].assignedPosition = position
            save()
            return
        }

        if let existingPositionIndex = sensors.firstIndex(where: {
            $0.assignedPosition == position
        }) {
            sensors.remove(at: existingPositionIndex)
        }

        guard sensors.count < maxSensors || isPositionAssigned(position) else { return }

        sensors.append(
            TPMSSensor(
                sensorID: cleanSensorID,
                name: cleanName,
                assignedPosition: position
            )
        )
        sortSensors()
        save()
    }

    func removeSensor(id: UUID) {
        sensors.removeAll { $0.id == id }
        save()
    }

    func removeSensor(sensorID: String) {
        sensors.removeAll {
            $0.sensorID.caseInsensitiveCompare(sensorID) == .orderedSame
        }
        save()
    }

    func reassignSensor(id: UUID, to newPosition: TPMSWheelPosition) {
        guard let sourceIndex = sensors.firstIndex(where: { $0.id == id }) else { return }

        if let targetIndex = sensors.firstIndex(where: {
            $0.assignedPosition == newPosition && $0.id != id
        }) {
            let oldPosition = sensors[sourceIndex].assignedPosition
            sensors[targetIndex].assignedPosition = oldPosition
        }

        sensors[sourceIndex].assignedPosition = newPosition
        sortSensors()
        save()
    }

    func clearAllSensors() {
        sensors.removeAll()
        activeAlert = nil
        save()
    }

    func updatePressure(
        sensorID: String,
        pressurePSI: Double,
        timestamp: Date = Date()
    ) {
        guard let index = sensors.firstIndex(where: {
            $0.sensorID.caseInsensitiveCompare(sensorID) == .orderedSame
        }) else { return }

        sensors[index].pressurePSI = pressurePSI
        sensors[index].lastUpdatedAt = timestamp
        sensors[index].lastSeenAt = timestamp
        sensors[index].isConnected = true
        save()
    }

    func updateConnectionState(
        sensorID: String,
        isConnected: Bool,
        timestamp: Date = Date()
    ) {
        guard let index = sensors.firstIndex(where: {
            $0.sensorID.caseInsensitiveCompare(sensorID) == .orderedSame
        }) else { return }

        sensors[index].isConnected = isConnected
        if isConnected {
            sensors[index].lastSeenAt = timestamp
        }
        save()
    }

    func updateReading(
        sensorID: String,
        pressurePSI: Double?,
        temperatureC: Double? = nil,
        batteryPercent: Int? = nil,
        timestamp: Date = Date(),
        lowThresholdPSI: Double,
        highThresholdPSI: Double,
        alertsEnabled: Bool
    ) {
        guard let index = sensors.firstIndex(where: {
            $0.sensorID.caseInsensitiveCompare(sensorID) == .orderedSame
        }) else { return }

        if let pressurePSI {
            sensors[index].pressurePSI = pressurePSI
        }

        if let temperatureC {
            sensors[index].temperatureC = temperatureC
        }

        if let batteryPercent {
            sensors[index].batteryPercent = min(max(batteryPercent, 0), 100)
        }

        sensors[index].lastUpdatedAt = timestamp
        sensors[index].lastSeenAt = timestamp
        sensors[index].isConnected = true

        evaluateAlert(
            sensorIndex: index,
            lowThresholdPSI: lowThresholdPSI,
            highThresholdPSI: highThresholdPSI,
            alertsEnabled: alertsEnabled
        )

        save()
    }

    func ingestMockReading(
        sensorID: String,
        pressurePSI: Double,
        lowThresholdPSI: Double,
        highThresholdPSI: Double,
        alertsEnabled: Bool
    ) {
        updateReading(
            sensorID: sensorID,
            pressurePSI: pressurePSI,
            temperatureC: nil,
            batteryPercent: nil,
            timestamp: Date(),
            lowThresholdPSI: lowThresholdPSI,
            highThresholdPSI: highThresholdPSI,
            alertsEnabled: alertsEnabled
        )
    }

    func ingestDecodedReading(
        _ reading: TPMSDecodedReading,
        lowThresholdPSI: Double,
        highThresholdPSI: Double,
        alertsEnabled: Bool
    ) {
        updateReading(
            sensorID: reading.sensorID,
            pressurePSI: reading.pressurePSI,
            temperatureC: reading.temperatureC,
            batteryPercent: reading.batteryPercent,
            timestamp: reading.timestamp,
            lowThresholdPSI: lowThresholdPSI,
            highThresholdPSI: highThresholdPSI,
            alertsEnabled: alertsEnabled
        )
    }

    func ingestAdvertisement(
        sensorID: String,
        manufacturerData: Data?,
        serviceData: Data?,
        lowThresholdPSI: Double,
        highThresholdPSI: Double,
        alertsEnabled: Bool
    ) {
        let decoded = decodeAdvertisement(
            sensorID: sensorID,
            manufacturerData: manufacturerData,
            serviceData: serviceData
        )

        guard let decoded else { return }

        ingestDecodedReading(
            decoded,
            lowThresholdPSI: lowThresholdPSI,
            highThresholdPSI: highThresholdPSI,
            alertsEnabled: alertsEnabled
        )
    }

    func clearActiveAlert() {
        activeAlert = nil
        save()
    }

    private func evaluateAlert(
        sensorIndex: Int,
        lowThresholdPSI: Double,
        highThresholdPSI: Double,
        alertsEnabled: Bool
    ) {
        guard alertsEnabled else {
            sensors[sensorIndex].lastAlertType = nil
            activeAlert = nil
            return
        }

        guard let pressure = sensors[sensorIndex].pressurePSI else {
            sensors[sensorIndex].lastAlertType = nil
            return
        }

        let newAlertType: TPMSAlertType?
        if pressure < lowThresholdPSI {
            newAlertType = .lowPressure
        } else if pressure > highThresholdPSI {
            newAlertType = .highPressure
        } else {
            newAlertType = nil
        }

        if let newAlertType {
            if sensors[sensorIndex].lastAlertType != newAlertType {
                sensors[sensorIndex].lastAlertType = newAlertType
                activeAlert = TPMSAlert(
                    sensorID: sensors[sensorIndex].sensorID,
                    position: sensors[sensorIndex].assignedPosition,
                    type: newAlertType,
                    pressurePSI: pressure
                )
            }
        } else {
            sensors[sensorIndex].lastAlertType = nil
            if activeAlert?.sensorID.caseInsensitiveCompare(sensors[sensorIndex].sensorID) == .orderedSame {
                activeAlert = nil
            }
        }
    }

    private func decodeAdvertisement(
        sensorID: String,
        manufacturerData: Data?,
        serviceData: Data?
    ) -> TPMSDecodedReading? {
        if let manufacturerData,
           let decoded = decodeGenericPressurePayload(
                sensorID: sensorID,
                payload: manufacturerData
           ) {
            return decoded
        }

        if let serviceData,
           let decoded = decodeGenericPressurePayload(
                sensorID: sensorID,
                payload: serviceData
           ) {
            return decoded
        }

        return nil
    }

    private func decodeGenericPressurePayload(
        sensorID: String,
        payload: Data
    ) -> TPMSDecodedReading? {
        guard payload.count >= 2 else { return nil }

        let bytes = [UInt8](payload)

        if payload.count >= 4 {
            let rawPressure = Int(bytes[0]) | (Int(bytes[1]) << 8)
            let pressurePSI = Double(rawPressure) / 10.0

            var temperatureC: Double?
            if payload.count >= 5 {
                temperatureC = Double(Int(bytes[2])) - 40.0
            }

            var batteryPercent: Int?
            if payload.count >= 6 {
                batteryPercent = Int(bytes[3])
            }

            if pressurePSI > 0, pressurePSI < 200 {
                return TPMSDecodedReading(
                    sensorID: sensorID,
                    pressurePSI: pressurePSI,
                    temperatureC: temperatureC,
                    batteryPercent: batteryPercent
                )
            }
        }

        return nil
    }

    private func sortSensors() {
        sensors.sort { lhs, rhs in
            wheelSortIndex(lhs.assignedPosition) < wheelSortIndex(rhs.assignedPosition)
        }
    }

    private func wheelSortIndex(_ position: TPMSWheelPosition) -> Int {
        switch position {
        case .frontLeft: return 0
        case .frontRight: return 1
        case .rearLeft: return 2
        case .rearRight: return 3
        case .spare1: return 4
        case .spare2: return 5
        }
    }

    private func load() {
        if let sensorData = defaults.data(forKey: kTPMSStoreSensorsKey),
           let decodedSensors = try? decoder.decode([TPMSSensor].self, from: sensorData) {
            sensors = decodedSensors
            sortSensors()
        } else {
            sensors = []
        }

        if let alertData = defaults.data(forKey: kTPMSStoreActiveAlertKey),
           let decodedAlert = try? decoder.decode(TPMSAlert.self, from: alertData) {
            activeAlert = decodedAlert
        } else {
            activeAlert = nil
        }
    }

    private func save() {
        if let sensorData = try? encoder.encode(sensors) {
            defaults.set(sensorData, forKey: kTPMSStoreSensorsKey)
        }

        if let activeAlert,
           let alertData = try? encoder.encode(activeAlert) {
            defaults.set(alertData, forKey: kTPMSStoreActiveAlertKey)
        } else {
            defaults.removeObject(forKey: kTPMSStoreActiveAlertKey)
        }
    }
}
