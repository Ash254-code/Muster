import Foundation
import CoreBluetooth
import Combine

struct TPMSDiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    var peripheralIdentifier: UUID
    var name: String
    var rssi: Int
    var lastSeenAt: Date
    var manufacturerData: Data?
    var serviceData: [CBUUID: Data]
    var localName: String?
    var isConnectable: Bool?
    var sensorIDGuess: String

    init(
        peripheralIdentifier: UUID,
        name: String,
        rssi: Int,
        lastSeenAt: Date = Date(),
        manufacturerData: Data? = nil,
        serviceData: [CBUUID: Data] = [:],
        localName: String? = nil,
        isConnectable: Bool? = nil,
        sensorIDGuess: String? = nil
    ) {
        self.id = peripheralIdentifier
        self.peripheralIdentifier = peripheralIdentifier
        self.name = name
        self.rssi = rssi
        self.lastSeenAt = lastSeenAt
        self.manufacturerData = manufacturerData
        self.serviceData = serviceData
        self.localName = localName
        self.isConnectable = isConnectable
        self.sensorIDGuess = sensorIDGuess ?? peripheralIdentifier.uuidString.uppercased()
    }

    var displayName: String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }

        if let localName {
            let trimmed = localName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return "Unknown Sensor"
    }

    var hasPayload: Bool {
        manufacturerData != nil || !serviceData.isEmpty
    }
}

struct TPMSBluetoothLogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), message: String) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
    }
}

@MainActor
final class TPMSBluetoothManager: NSObject, ObservableObject {
    @Published private(set) var isBluetoothPoweredOn: Bool = false
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var discoveredDevices: [TPMSDiscoveredDevice] = []
    @Published private(set) var connectedPeripheralIDs: Set<UUID> = []
    @Published private(set) var visibleLog: [TPMSBluetoothLogEntry] = []

    private let tpmsStore: TPMSStore
    private var centralManager: CBCentralManager!
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private let maxVisibleLogEntries = 250
    private let maxPerSensorLogEntries = 150

    // Keyed by saved sensorID / candidate sensorID
    private var sensorLogs: [String: [TPMSBluetoothLogEntry]] = [:]

    init(tpmsStore: TPMSStore) {
        self.tpmsStore = tpmsStore
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            appendVisibleLog("Scan not started: Bluetooth is not powered on.")
            return
        }
        guard !isScanning else { return }

        discoveredDevices.removeAll()
        appendVisibleLog("Started BLE scan.")

        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ]

        centralManager.scanForPeripherals(withServices: nil, options: options)
        isScanning = true
    }

    func stopScan() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        appendVisibleLog("Stopped BLE scan.")
    }

    func clearDiscoveredDevices() {
        discoveredDevices.removeAll()
        appendVisibleLog("Cleared discovered BLE devices.")
    }

    func clearVisibleLog() {
        visibleLog.removeAll()
    }

    func logEntries(for sensorID: String) -> [TPMSBluetoothLogEntry] {
        let key = normalizedLogKey(sensorID)
        return sensorLogs[key] ?? []
    }

    func clearLog(for sensorID: String) {
        let key = normalizedLogKey(sensorID)
        sensorLogs[key] = []
        appendVisibleLog("Cleared log for \(key).")
    }

    func peripheral(for discoveredDevice: TPMSDiscoveredDevice) -> CBPeripheral? {
        peripheralsByID[discoveredDevice.peripheralIdentifier]
    }

    func connect(_ discoveredDevice: TPMSDiscoveredDevice) {
        guard let peripheral = peripheralsByID[discoveredDevice.peripheralIdentifier] else {
            appendVisibleLog("Connect failed: peripheral not found for \(discoveredDevice.displayName).")
            appendSensorLog(
                "Connect failed: peripheral not found.",
                sensorID: normalizedSensorIDGuess(for: discoveredDevice)
            )
            return
        }

        let sensorID = normalizedSensorIDGuess(for: discoveredDevice)
        appendVisibleLog("Connecting to \(discoveredDevice.displayName) (\(sensorID)).")
        appendSensorLog("Connecting to peripheral \(peripheral.identifier.uuidString.uppercased()).", sensorID: sensorID)
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(_ discoveredDevice: TPMSDiscoveredDevice) {
        guard let peripheral = peripheralsByID[discoveredDevice.peripheralIdentifier] else {
            appendVisibleLog("Disconnect failed: peripheral not found for \(discoveredDevice.displayName).")
            appendSensorLog(
                "Disconnect failed: peripheral not found.",
                sensorID: normalizedSensorIDGuess(for: discoveredDevice)
            )
            return
        }

        let sensorID = normalizedSensorIDGuess(for: discoveredDevice)
        appendVisibleLog("Disconnecting from \(discoveredDevice.displayName) (\(sensorID)).")
        appendSensorLog("Disconnect requested.", sensorID: sensorID)
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func saveDiscoveredDeviceToStore(
        _ discoveredDevice: TPMSDiscoveredDevice,
        name: String,
        position: TPMSWheelPosition
    ) {
        let chosenID = normalizedSensorIDGuess(for: discoveredDevice)
        let savedName = name.isEmpty ? discoveredDevice.displayName : name

        tpmsStore.addOrReplaceSensor(
            sensorID: chosenID,
            name: savedName,
            position: position
        )

        appendVisibleLog("Saved \(savedName) as \(position.title) using sensor ID \(chosenID).")
        appendSensorLog("Saved to \(position.title) as \(savedName).", sensorID: chosenID)
    }

    private func normalizedSensorIDGuess(for discoveredDevice: TPMSDiscoveredDevice) -> String {
        let clean = discoveredDevice.sensorIDGuess.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            return clean.uppercased()
        }
        return discoveredDevice.peripheralIdentifier.uuidString.uppercased()
    }

    private func normalizedLogKey(_ sensorID: String) -> String {
        sensorID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func upsertDiscoveredDevice(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool

        debugLogAdvertisement(
            peripheral: peripheral,
            localName: localName,
            rssi: rssi.intValue,
            manufacturerData: manufacturerData,
            serviceData: serviceData
        )

        let fallbackName = peripheral.name ?? localName ?? "Unknown Sensor"
        let sensorIDGuess = makeSensorIDGuess(
            peripheralID: peripheral.identifier,
            localName: localName,
            manufacturerData: manufacturerData,
            serviceData: serviceData
        )

        let newDevice = TPMSDiscoveredDevice(
            peripheralIdentifier: peripheral.identifier,
            name: fallbackName,
            rssi: rssi.intValue,
            lastSeenAt: Date(),
            manufacturerData: manufacturerData,
            serviceData: serviceData,
            localName: localName,
            isConnectable: isConnectable,
            sensorIDGuess: sensorIDGuess
        )

        let isFirstTimeSeen = peripheralsByID[peripheral.identifier] == nil
        peripheralsByID[peripheral.identifier] = peripheral

        if let existingIndex = discoveredDevices.firstIndex(where: { $0.peripheralIdentifier == peripheral.identifier }) {
            discoveredDevices[existingIndex] = mergeDiscoveredDevices(
                existing: discoveredDevices[existingIndex],
                incoming: newDevice
            )
        } else {
            discoveredDevices.append(newDevice)
        }

        let sensorID = normalizedSensorIDGuess(for: newDevice)
        let payloadText = newDevice.hasPayload ? "payload" : "no payload"

        if isFirstTimeSeen {
            appendVisibleLog("Discovered \(newDevice.displayName) RSSI \(newDevice.rssi) • \(payloadText) • \(sensorID)")
        }

        appendSensorLog(
            "Seen RSSI \(newDevice.rssi) • \(payloadText) • name \(newDevice.displayName)",
            sensorID: sensorID
        )

        if let manufacturerData {
            appendSensorLog(
                "Manufacturer data: \(hexString(from: manufacturerData))",
                sensorID: sensorID
            )
        } else {
            appendSensorLog("Manufacturer data: none", sensorID: sensorID)
        }

        if serviceData.isEmpty {
            appendSensorLog("Service data: none", sensorID: sensorID)
        } else {
            for (uuid, data) in serviceData.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                appendSensorLog(
                    "Service \(uuid.uuidString): \(hexString(from: data))",
                    sensorID: sensorID
                )
            }
        }

        sortDiscoveredDevices()
        feedPayloadIntoStore(for: newDevice)
    }

    private func mergeDiscoveredDevices(
        existing: TPMSDiscoveredDevice,
        incoming: TPMSDiscoveredDevice
    ) -> TPMSDiscoveredDevice {
        TPMSDiscoveredDevice(
            peripheralIdentifier: incoming.peripheralIdentifier,
            name: incoming.name.isEmpty ? existing.name : incoming.name,
            rssi: incoming.rssi,
            lastSeenAt: incoming.lastSeenAt,
            manufacturerData: incoming.manufacturerData ?? existing.manufacturerData,
            serviceData: incoming.serviceData.isEmpty ? existing.serviceData : incoming.serviceData,
            localName: incoming.localName ?? existing.localName,
            isConnectable: incoming.isConnectable ?? existing.isConnectable,
            sensorIDGuess: incoming.sensorIDGuess.isEmpty ? existing.sensorIDGuess : incoming.sensorIDGuess
        )
    }

    private func sortDiscoveredDevices() {
        discoveredDevices.sort { lhs, rhs in
            if lhs.hasPayload != rhs.hasPayload {
                return lhs.hasPayload && !rhs.hasPayload
            }

            if lhs.rssi != rhs.rssi {
                return lhs.rssi > rhs.rssi
            }

            return lhs.lastSeenAt > rhs.lastSeenAt
        }
    }

    private func feedPayloadIntoStore(for device: TPMSDiscoveredDevice) {
        let knownSensorIDs = Set(tpmsStore.sensors.map { $0.sensorID.uppercased() })
        let candidateSensorID = normalizedSensorIDGuess(for: device)

        guard knownSensorIDs.contains(candidateSensorID) else { return }

        let firstServicePayload = device.serviceData.values.first

        appendSensorLog("Matched to saved sensor.", sensorID: candidateSensorID)

        if let manufacturerData = device.manufacturerData {
            appendSensorLog(
                "Feeding manufacturer payload: \(hexString(from: manufacturerData))",
                sensorID: candidateSensorID
            )
        } else {
            appendSensorLog("Feeding manufacturer payload: none", sensorID: candidateSensorID)
        }

        if let firstServicePayload {
            appendSensorLog(
                "Feeding first service payload: \(hexString(from: firstServicePayload))",
                sensorID: candidateSensorID
            )
        } else {
            appendSensorLog("Feeding first service payload: none", sensorID: candidateSensorID)
        }

        tpmsStore.ingestAdvertisement(
            sensorID: candidateSensorID,
            manufacturerData: device.manufacturerData,
            serviceData: firstServicePayload,
            lowThresholdPSI: currentLowThreshold(),
            highThresholdPSI: currentHighThreshold(),
            alertsEnabled: currentAlertsEnabled()
        )

        appendVisibleLog("Fed payload into TPMS store for \(device.displayName) (\(candidateSensorID)).")

        if let updated = tpmsStore.sensor(withSensorID: candidateSensorID) {
            if let pressure = updated.pressurePSI {
                appendSensorLog(
                    String(format: "Decoded pressure now %.1f psi", pressure),
                    sensorID: candidateSensorID
                )
            } else {
                appendSensorLog("No pressure decoded yet.", sensorID: candidateSensorID)
            }
        }
    }

    private func currentLowThreshold() -> Double {
        let value = UserDefaults.standard.double(forKey: "tpms_low_pressure")
        return value == 0 ? 26 : value
    }

    private func currentHighThreshold() -> Double {
        let value = UserDefaults.standard.double(forKey: "tpms_high_pressure")
        return value == 0 ? 44 : value
    }

    private func currentAlertsEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: "tpms_alerts_enabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "tpms_alerts_enabled")
    }

    private func makeSensorIDGuess(
        peripheralID: UUID,
        localName: String?,
        manufacturerData: Data?,
        serviceData: [CBUUID: Data]
    ) -> String {
        if let manufacturerData,
           let guess = guessSensorIDFromPayload(manufacturerData) {
            return guess
        }

        for payload in serviceData.values {
            if let guess = guessSensorIDFromPayload(payload) {
                return guess
            }
        }

        if let localName {
            let trimmed = localName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.uppercased()
            }
        }

        return peripheralID.uuidString.uppercased()
    }

    private func guessSensorIDFromPayload(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        let bytes = [UInt8](data)

        if data.count >= 8 {
            let suffix = bytes.suffix(4).map { String(format: "%02X", $0) }.joined()
            return "TPMS-\(suffix)"
        }

        if data.count >= 4 {
            let suffix = bytes.map { String(format: "%02X", $0) }.joined()
            return "TPMS-\(suffix)"
        }

        return nil
    }

    private func debugLogAdvertisement(
        peripheral: CBPeripheral,
        localName: String?,
        rssi: Int,
        manufacturerData: Data?,
        serviceData: [CBUUID: Data]
    ) {
        let displayName = (peripheral.name ?? localName ?? "Unknown Sensor").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = displayName.isEmpty ? "Unknown Sensor" : displayName

        print("📡 BLE Device: \(resolvedName)")
        print("   UUID: \(peripheral.identifier.uuidString.uppercased())")
        print("   RSSI: \(rssi)")

        if let manufacturerData {
            print("🔵 Manufacturer Data: \(hexString(from: manufacturerData))")
        } else {
            print("🔵 Manufacturer Data: none")
        }

        if serviceData.isEmpty {
            print("🟢 Service Data: none")
        } else {
            for (uuid, data) in serviceData.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                print("🟢 Service \(uuid.uuidString): \(hexString(from: data))")
            }
        }
    }

    private func appendVisibleLog(_ message: String) {
        visibleLog.insert(
            TPMSBluetoothLogEntry(message: message),
            at: 0
        )

        if visibleLog.count > maxVisibleLogEntries {
            visibleLog = Array(visibleLog.prefix(maxVisibleLogEntries))
        }
    }

    private func appendSensorLog(_ message: String, sensorID: String) {
        let key = normalizedLogKey(sensorID)
        var entries = sensorLogs[key] ?? []
        entries.insert(TPMSBluetoothLogEntry(message: message), at: 0)

        if entries.count > maxPerSensorLogEntries {
            entries = Array(entries.prefix(maxPerSensorLogEntries))
        }

        sensorLogs[key] = entries
    }

    private func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}

extension TPMSBluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.isBluetoothPoweredOn = (central.state == .poweredOn)

            let stateText: String
            switch central.state {
            case .unknown: stateText = "unknown"
            case .resetting: stateText = "resetting"
            case .unsupported: stateText = "unsupported"
            case .unauthorized: stateText = "unauthorized"
            case .poweredOff: stateText = "powered off"
            case .poweredOn: stateText = "powered on"
            @unknown default: stateText = "unknown future state"
            }

            self.appendVisibleLog("Bluetooth state changed: \(stateText).")

            if central.state != .poweredOn {
                self.isScanning = false
                self.connectedPeripheralIDs.removeAll()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            self.upsertDiscoveredDevice(
                peripheral: peripheral,
                advertisementData: advertisementData,
                rssi: RSSI
            )
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectedPeripheralIDs.insert(peripheral.identifier)
            self.tpmsStore.updateConnectionState(
                sensorID: peripheral.identifier.uuidString.uppercased(),
                isConnected: true,
                timestamp: Date()
            )

            let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false) ? name! : "Unknown Sensor"
            let peripheralID = peripheral.identifier.uuidString.uppercased()

            self.appendVisibleLog("Connected to \(resolvedName) (\(peripheralID)).")
            self.appendSensorLog("Connected to peripheral.", sensorID: peripheralID)

            for sensor in self.tpmsStore.sensors {
                if sensor.sensorID.uppercased() == peripheralID {
                    self.appendSensorLog("Connected to saved sensor entry \(sensor.displayName).", sensorID: sensor.sensorID)
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.connectedPeripheralIDs.remove(peripheral.identifier)
            self.tpmsStore.updateConnectionState(
                sensorID: peripheral.identifier.uuidString.uppercased(),
                isConnected: false,
                timestamp: Date()
            )

            let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false) ? name! : "Unknown Sensor"
            let peripheralID = peripheral.identifier.uuidString.uppercased()

            if let error {
                self.appendVisibleLog("Disconnected from \(resolvedName) with error: \(error.localizedDescription)")
                self.appendSensorLog("Disconnected with error: \(error.localizedDescription)", sensorID: peripheralID)
            } else {
                self.appendVisibleLog("Disconnected from \(resolvedName).")
                self.appendSensorLog("Disconnected.", sensorID: peripheralID)
            }

            for sensor in self.tpmsStore.sensors {
                if sensor.sensorID.uppercased() == peripheralID {
                    if let error {
                        self.appendSensorLog("Saved sensor disconnected with error: \(error.localizedDescription)", sensorID: sensor.sensorID)
                    } else {
                        self.appendSensorLog("Saved sensor disconnected.", sensorID: sensor.sensorID)
                    }
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.connectedPeripheralIDs.remove(peripheral.identifier)

            let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false) ? name! : "Unknown Sensor"
            let peripheralID = peripheral.identifier.uuidString.uppercased()

            if let error {
                self.appendVisibleLog("Failed to connect to \(resolvedName): \(error.localizedDescription)")
                self.appendSensorLog("Failed to connect: \(error.localizedDescription)", sensorID: peripheralID)
            } else {
                self.appendVisibleLog("Failed to connect to \(resolvedName).")
                self.appendSensorLog("Failed to connect.", sensorID: peripheralID)
            }
        }
    }
}
