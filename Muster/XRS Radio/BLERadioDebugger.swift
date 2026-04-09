import Foundation
import CoreBluetooth
import Combine
import CoreLocation

struct SavedRadio: Identifiable, Codable, Equatable {
    let id: UUID
    let identifier: UUID
    var displayName: String
    var lastConnectedAt: Date?

    init(identifier: UUID, name: String) {
        self.id = UUID()
        self.identifier = identifier
        self.displayName = name
        self.lastConnectedAt = nil
    }
}

@MainActor
final class BLERadioDebugger: NSObject, ObservableObject {

    static let shared = BLERadioDebugger()

    enum ParserMode: String, CaseIterable, Identifiable {
        case strict
        case tolerant
        case aggressive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .strict: return "Strict"
            case .tolerant: return "Tolerant"
            case .aggressive: return "Aggressive"
            }
        }
    }

    struct PeripheralItem: Identifiable {
        let id: UUID
        let peripheral: CBPeripheral
        let name: String
        let rssi: Int
        let identifier: UUID
    }

    @Published var discoveredPeripherals: [PeripheralItem] = []
    @Published var logText: String = ""
    @Published var serviceSummary: [String] = []
    @Published var isScanning: Bool = false
    @Published var connectedPeripheralName: String?
    @Published var writableCharacteristics: [CBCharacteristic] = []
    @Published var decodedContacts: [XRSRadioContact] = []
    @Published var isConnected: Bool = false
    @Published var savedRadios: [SavedRadio] = []

    @Published var forceLocationUpdatesEnabled: Bool = false {
        didSet { handleForceLocationSettingsChanged() }
    }

    @Published var forceLocationUpdateIntervalMinutes: Double = 2 {
        didSet { handleForceLocationSettingsChanged() }
    }

    @Published var forceLocationUpdatePulseSeconds: Double = 0.35 {
        didSet { handleForceLocationSettingsChanged() }
    }

    @Published var parserMode: ParserMode = .strict {
        didSet {
            UserDefaults.standard.set(parserMode.rawValue, forKey: Self.parserModeKey)
            appendLog("Parser mode set to \(parserMode.title)")
        }
    }

    @Published var showAllIncomingData: Bool = false {
        didSet {
            UserDefaults.standard.set(showAllIncomingData, forKey: Self.showAllIncomingDataKey)
            appendLog("All incoming data logging \(showAllIncomingData ? "enabled" : "disabled")")
        }
    }

    var onDecodedContact: ((XRSRadioContact) -> Void)?
    var onTransmitActivity: (() -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onReceiveActivity: (() -> Void)?

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var seenPeripherals: [UUID: PeripheralItem] = [:]
    private var lastDiscoveryPublishAt: Date = .distantPast

    // Rolling raw text buffer per characteristic
    private var textBufferByCharacteristic: [CBUUID: String] = [:]

    // Dedupe / parsed state
    private var lastCompleteMessage: String?
    private var lastCompleteMessageAt: Date = .distantPast
    private var lastParsedFingerprintAt: [String: Date] = [:]
    private var contactByName: [String: XRSRadioContact] = [:]
    private var recentMessageFingerprints: [String: Date] = [:]

    private var shouldAutoReconnect = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttemptCount = 0
    private var forceLocationUpdateTimer: Timer?
    private var isApplyingForceLocationSettings = false

    private let pttCommandCharacteristicUUID = "49535343-1E4D-4BD9-BA61-23C647249616"

    private var lastConnectedPeripheralID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.lastPeripheralIDKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.lastPeripheralIDKey)
        }
    }

    private var currentConnectedRadioID: UUID? {
        connectedPeripheral?.identifier
    }

    private static let lastPeripheralIDKey = "bleradiodebugger.lastPeripheralID"
    private static let parserModeKey = "bleradiodebugger.parserMode"
    private static let savedRadiosKey = "bleradiodebugger.savedRadios"
    private static let showAllIncomingDataKey = "bleradiodebugger.showAllIncomingData"

    override init() {
        if let raw = UserDefaults.standard.string(forKey: Self.parserModeKey) {
            switch raw {
            case "strict":
                parserMode = .strict
            case "relaxed":
                parserMode = .tolerant
            case "superRelaxed":
                parserMode = .aggressive
            default:
                if let saved = ParserMode(rawValue: raw) {
                    parserMode = saved
                }
            }
        }

        showAllIncomingData = UserDefaults.standard.bool(forKey: Self.showAllIncomingDataKey)

        super.init()
        loadSavedRadios()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else {
            appendLog("Bluetooth not ready: \(centralStateString(central.state))")
            return
        }

        seenPeripherals.removeAll()
        discoveredPeripherals.removeAll()
        lastDiscoveryPublishAt = .distantPast
        appendLog("Starting scan...")
        isScanning = true

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        discoveredPeripherals = sortedPeripheralItems(Array(seenPeripherals.values))
        isScanning = false
        appendLog("Stopped scan.")
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        shouldAutoReconnect = true
        cancelPendingReconnect()
        reconnectAttemptCount = 0
        lastConnectedPeripheralID = peripheral.identifier

        let name = peripheral.name ?? "Unknown"
        saveRadio(identifier: peripheral.identifier, name: name)

        appendLog("Connecting to \(name)...")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: self.connectionOptions)
    }

    func disconnect() {
        shouldAutoReconnect = false
        cancelPendingReconnect()

        guard let peripheral = connectedPeripheral else { return }
        appendLog("Disconnecting from \(peripheral.name ?? "Unknown")...")
        central.cancelPeripheralConnection(peripheral)
    }

    func isSavedRadio(_ id: UUID) -> Bool {
        savedRadios.contains(where: { $0.identifier == id })
    }

    func saveRadio(identifier: UUID, name: String) {
        if let index = savedRadios.firstIndex(where: { $0.identifier == identifier }) {
            savedRadios[index].displayName = name
            savedRadios[index].lastConnectedAt = Date()
        } else {
            var radio = SavedRadio(identifier: identifier, name: name)
            radio.lastConnectedAt = Date()
            savedRadios.append(radio)
        }

        persistSavedRadios()
    }

    func forgetSavedRadio(_ radio: SavedRadio) {
        savedRadios.removeAll { $0.id == radio.id }
        if lastConnectedPeripheralID == radio.identifier {
            lastConnectedPeripheralID = nil
        }
        persistSavedRadios()
        discoveredPeripherals = sortedPeripheralItems(Array(seenPeripherals.values))
    }

    func clearLog() {
        logText = ""
    }

    func sendPTTPress() {
        sendASCII("AT+WGPTT=1\r\n", characteristicUUID: pttCommandCharacteristicUUID)
    }

    func sendPTTRelease() {
        sendASCII("AT+WGPTT=0\r\n", characteristicUUID: pttCommandCharacteristicUUID)
    }

    func sendForceLocationPulse() {
        let pulse = normalizedPulseSeconds(forceLocationUpdatePulseSeconds)

        appendLog("Force location pulse start (\(String(format: "%.2f", pulse)) sec)")
        sendPTTPress()

        DispatchQueue.main.asyncAfter(deadline: .now() + pulse) { [weak self] in
            guard let self else { return }
            self.sendPTTRelease()
            self.appendLog("Force location pulse end")
        }
    }

    func sendHex(_ hex: String, characteristicUUID: String? = nil) {
        guard let peripheral = connectedPeripheral, isConnected else {
            appendLog("No connected peripheral")
            return
        }

        let targetCharacteristic: CBCharacteristic?
        if let characteristicUUID, !characteristicUUID.isEmpty {
            targetCharacteristic = writableCharacteristics.first(where: {
                $0.uuid.uuidString.caseInsensitiveCompare(characteristicUUID) == .orderedSame
            })
        } else {
            targetCharacteristic = writableCharacteristics.first
        }

        guard let characteristic = targetCharacteristic else {
            appendLog("No writable characteristic found")
            return
        }

        let clean = hex
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else {
            appendLog("Empty hex payload")
            return
        }

        guard clean.count.isMultiple(of: 2) else {
            appendLog("Invalid hex length")
            return
        }

        var data = Data()
        var index = clean.startIndex

        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            let byteString = clean[index..<next]

            guard let byte = UInt8(byteString, radix: 16) else {
                appendLog("Invalid hex byte: \(byteString)")
                return
            }

            data.append(byte)
            index = next
        }

        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse

        onTransmitActivity?()
        peripheral.writeValue(data, for: characteristic, type: writeType)
        appendTransmissionLog(
            title: "TX \(characteristic.uuid.uuidString)",
            body: hex
        )
    }

    func sendASCII(_ text: String, characteristicUUID: String? = nil) {
        guard let peripheral = connectedPeripheral, isConnected else {
            appendLog("No connected peripheral")
            return
        }

        let targetCharacteristic: CBCharacteristic?
        if let characteristicUUID, !characteristicUUID.isEmpty {
            targetCharacteristic = writableCharacteristics.first(where: {
                $0.uuid.uuidString.caseInsensitiveCompare(characteristicUUID) == .orderedSame
            })
        } else {
            targetCharacteristic = writableCharacteristics.first
        }

        guard let characteristic = targetCharacteristic else {
            appendLog("No writable characteristic found")
            return
        }

        guard let data = text.data(using: .utf8) else {
            appendLog("Failed to encode ASCII")
            return
        }

        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.write) ? .withResponse : .withoutResponse

        onTransmitActivity?()
        peripheral.writeValue(data, for: characteristic, type: writeType)
        appendTransmissionLog(
            title: "TX ASCII \(characteristic.uuid.uuidString)",
            body: text
        )
    }

    func reconnectLastKnownPeripheralIfPossible() {
        guard central.state == .poweredOn else { return }
        guard let id = lastConnectedPeripheralID else { return }
        guard connectedPeripheral == nil else { return }
        shouldAutoReconnect = true

        let restored = central.retrievePeripherals(withIdentifiers: [id])
        if let peripheral = restored.first {
            appendLog("Reconnecting to last paired radio: \(peripheral.name ?? "Unknown")")
            connectedPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: self.connectionOptions)
            return
        }

        appendLog("Last paired radio not immediately available. Scanning for it now...")
        startScan()
    }

    // MARK: - Per-radio force location settings

    private func perRadioForceLocationEnabledKey(for radioID: UUID) -> String {
        "bleradiodebugger.forceLocation.enabled.\(radioID.uuidString)"
    }

    private func perRadioForceLocationIntervalKey(for radioID: UUID) -> String {
        "bleradiodebugger.forceLocation.intervalMinutes.\(radioID.uuidString)"
    }

    private func perRadioForceLocationPulseKey(for radioID: UUID) -> String {
        "bleradiodebugger.forceLocation.pulseSeconds.\(radioID.uuidString)"
    }

    private func normalizedIntervalMinutes(_ value: Double) -> Double {
        min(max(value.rounded(), 1), 15)
    }

    private func normalizedPulseSeconds(_ value: Double) -> Double {
        min(max((value * 20).rounded() / 20, 0.05), 1.0)
    }

    private func handleForceLocationSettingsChanged() {
        guard !isApplyingForceLocationSettings else { return }

        let normalizedInterval = normalizedIntervalMinutes(forceLocationUpdateIntervalMinutes)
        let normalizedPulse = normalizedPulseSeconds(forceLocationUpdatePulseSeconds)

        let needsNormalization =
            forceLocationUpdateIntervalMinutes != normalizedInterval ||
            forceLocationUpdatePulseSeconds != normalizedPulse

        if needsNormalization {
            isApplyingForceLocationSettings = true
            forceLocationUpdateIntervalMinutes = normalizedInterval
            forceLocationUpdatePulseSeconds = normalizedPulse
            isApplyingForceLocationSettings = false
        }

        persistForceLocationSettings()
        restartForceLocationUpdateTimerIfNeeded()
    }

    private func loadForceLocationSettingsForCurrentRadio() {
        guard let radioID = currentConnectedRadioID else {
            isApplyingForceLocationSettings = true
            forceLocationUpdatesEnabled = false
            forceLocationUpdateIntervalMinutes = 2
            forceLocationUpdatePulseSeconds = 0.35
            isApplyingForceLocationSettings = false
            return
        }

        let enabledKey = perRadioForceLocationEnabledKey(for: radioID)
        let intervalKey = perRadioForceLocationIntervalKey(for: radioID)
        let pulseKey = perRadioForceLocationPulseKey(for: radioID)

        let enabled: Bool
        if UserDefaults.standard.object(forKey: enabledKey) != nil {
            enabled = UserDefaults.standard.bool(forKey: enabledKey)
        } else {
            enabled = false
        }

        let storedInterval = UserDefaults.standard.double(forKey: intervalKey)
        let interval = storedInterval > 0 ? storedInterval : 2

        let storedPulse = UserDefaults.standard.double(forKey: pulseKey)
        let pulse = storedPulse > 0 ? storedPulse : 0.35

        isApplyingForceLocationSettings = true
        forceLocationUpdatesEnabled = enabled
        forceLocationUpdateIntervalMinutes = normalizedIntervalMinutes(interval)
        forceLocationUpdatePulseSeconds = normalizedPulseSeconds(pulse)
        isApplyingForceLocationSettings = false

        appendLog(
            "Loaded force location settings: " +
            "enabled=\(forceLocationUpdatesEnabled), " +
            "interval=\(Int(forceLocationUpdateIntervalMinutes)) min, " +
            "pulse=\(String(format: "%.2f", forceLocationUpdatePulseSeconds)) sec"
        )
    }

    private func persistForceLocationSettings() {
        guard let radioID = currentConnectedRadioID else { return }

        UserDefaults.standard.set(
            forceLocationUpdatesEnabled,
            forKey: perRadioForceLocationEnabledKey(for: radioID)
        )
        UserDefaults.standard.set(
            normalizedIntervalMinutes(forceLocationUpdateIntervalMinutes),
            forKey: perRadioForceLocationIntervalKey(for: radioID)
        )
        UserDefaults.standard.set(
            normalizedPulseSeconds(forceLocationUpdatePulseSeconds),
            forKey: perRadioForceLocationPulseKey(for: radioID)
        )
    }

    private func restartForceLocationUpdateTimerIfNeeded() {
        stopForceLocationUpdateTimer()

        guard isConnected else { return }
        guard forceLocationUpdatesEnabled else { return }

        let intervalMinutes = normalizedIntervalMinutes(forceLocationUpdateIntervalMinutes)
        let intervalSeconds = intervalMinutes * 60

        appendLog("Force location timer started (\(Int(intervalMinutes)) min)")

        forceLocationUpdateTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sendForceLocationPulse()
        }
    }

    private func stopForceLocationUpdateTimer() {
        if forceLocationUpdateTimer != nil {
            appendLog("Force location timer stopped")
        }
        forceLocationUpdateTimer?.invalidate()
        forceLocationUpdateTimer = nil
    }

    private func sortedPeripheralItems(_ items: [PeripheralItem]) -> [PeripheralItem] {
        items.sorted { lhs, rhs in
            let lhsSaved = isSavedRadio(lhs.identifier)
            let rhsSaved = isSavedRadio(rhs.identifier)

            if lhsSaved != rhsSaved {
                return lhsSaved && !rhsSaved
            }

            if lhs.rssi != rhs.rssi {
                return lhs.rssi > rhs.rssi
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func loadSavedRadios() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedRadiosKey) else { return }
        guard let decoded = try? JSONDecoder().decode([SavedRadio].self, from: data) else {
            appendLog("Failed to decode saved radios. Clearing saved list.")
            UserDefaults.standard.removeObject(forKey: Self.savedRadiosKey)
            return
        }

        savedRadios = decoded
    }

    private func persistSavedRadios() {
        guard let data = try? JSONEncoder().encode(savedRadios) else {
            appendLog("Failed to encode saved radios.")
            return
        }
        UserDefaults.standard.set(data, forKey: Self.savedRadiosKey)
    }

    // MARK: - Internal state helpers

    private func resetSessionState(clearConnectionIdentity: Bool) {
        serviceSummary.removeAll()
        writableCharacteristics.removeAll()
        textBufferByCharacteristic.removeAll()
        lastCompleteMessage = nil
        lastCompleteMessageAt = .distantPast
        lastParsedFingerprintAt.removeAll()
        recentMessageFingerprints.removeAll()
        contactByName.removeAll()
        decodedContacts.removeAll()

        if clearConnectionIdentity {
            stopForceLocationUpdateTimer()
            connectedPeripheralName = nil
            connectedPeripheral = nil
        }
    }

    private var connectionOptions: [String: Any] {
        [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnConnectionKey: true
        ]
    }

    private func updateConnectionState(_ connected: Bool) {
        if isConnected == connected { return }
        isConnected = connected
        onConnectionChanged?(connected)
    }

    private func cancelPendingReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    private func scheduleReconnect(reason: String) {
        guard shouldAutoReconnect else { return }
        guard central.state == .poweredOn else { return }
        guard let peripheral = connectedPeripheral else {
            reconnectLastKnownPeripheralIfPossible()
            return
        }

        cancelPendingReconnect()

        reconnectAttemptCount += 1
        let delay = min(pow(2.0, Double(max(reconnectAttemptCount - 1, 0))), 8.0)
        appendLog("Scheduling reconnect (attempt \(reconnectAttemptCount), \(String(format: "%.1f", delay))s) due to \(reason)")

        let workItem = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral else { return }
            guard self.shouldAutoReconnect else { return }
            guard self.central.state == .poweredOn else { return }
            guard !self.isConnected else { return }

            self.appendLog("Auto-reconnect attempt \(self.reconnectAttemptCount) to \(peripheral.name ?? "Unknown")")
            peripheral.delegate = self
            self.central.connect(peripheral, options: self.connectionOptions)
        }

        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func appendLog(_ line: String) {
        let ts = Self.timestampFormatter.string(from: Date())
        let entry = "[\(ts)] \(line)\n"
        logText = entry + logText
    }

    private func appendTransmissionLog(title: String, body: String) {
        let ts = Self.timestampFormatter.string(from: Date())
        let entry = """
        [\(ts)] \(title)
        \(body)
        --------------------------------

        """
        logText = entry + logText
    }

    private func propertyString(_ props: CBCharacteristicProperties) -> String {
        var out: [String] = []
        if props.contains(.read) { out.append("read") }
        if props.contains(.write) { out.append("write") }
        if props.contains(.writeWithoutResponse) { out.append("writeNoResp") }
        if props.contains(.notify) { out.append("notify") }
        if props.contains(.indicate) { out.append("indicate") }
        return out.joined(separator: ",")
    }

    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    private func parserModeTag(_ mode: ParserMode? = nil) -> String {
        switch mode ?? parserMode {
        case .strict: return "STRICT"
        case .tolerant: return "TOLERANT"
        case .aggressive: return "AGGRESSIVE"
        }
    }

    private func centralStateString(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknownFuture"
        }
    }

    private func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: - Chunk assembly

    private func appendIncomingText(_ text: String, for characteristic: CBCharacteristic) {
        let key = characteristic.uuid
        var buffer = textBufferByCharacteristic[key, default: ""]
        buffer += text
        buffer = normalizeTransportDelimiters(in: buffer)

        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            handleCompletedTransportLine(line, characteristic: characteristic)
        }

        while let range = nextCandidateRange(in: buffer) {
            let candidate = String(buffer[range])
            buffer.removeSubrange(range)
            handleCandidate(candidate, characteristic: characteristic)
        }

        if buffer.count > 2400 {
            let keep = usefulTail(of: buffer, maxLength: 900)
            appendLog("Buffer trimmed for \(characteristic.uuid.uuidString)")
            buffer = keep
        }

        textBufferByCharacteristic[key] = buffer
    }

    private func normalizeTransportDelimiters(in text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\\0D\\0A", with: "\n")
        s = s.replacingOccurrences(of: "\\r\\n", with: "\n")
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        s = s.replacingOccurrences(of: "\0", with: "")
        return s
    }

    private func handleCompletedTransportLine(_ rawLine: String, characteristic: CBCharacteristic) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        let messages = extractRadioMessages(from: line)
        if messages.isEmpty {
            handleCandidate(line, characteristic: characteristic)
        } else {
            for message in messages {
                handleCandidate(message, characteristic: characteristic)
            }
        }
    }

    private func extractRadioMessages(from line: String) -> [String] {
        let prefixes = ["+WGRMLOC:", "+WGRXLOC:", "+WGPTT:", "$PP", "$GPGGA"]
        var starts: [String.Index] = []

        for prefix in prefixes {
            var searchStart = line.startIndex
            while searchStart < line.endIndex,
                  let range = line.range(of: prefix, range: searchStart..<line.endIndex) {
                starts.append(range.lowerBound)
                searchStart = range.upperBound
            }
        }

        starts = Array(Set(starts)).sorted()

        if starts.isEmpty {
            if line.contains("@")
                || hasEmbeddedDecimalCoordinates(line, mode: parserMode)
                || hasEmbeddedNMEACoordinates(line, mode: parserMode) {
                return [line]
            }
            return []
        }

        var messages: [String] = []

        for i in starts.indices {
            let start = starts[i]
            let end = (i + 1 < starts.count) ? starts[i + 1] : line.endIndex
            let segment = String(line[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                messages.append(segment)
            }
        }

        return messages
    }

    private func nextCandidateRange(in buffer: String) -> Range<String.Index>? {
        guard let starIndex = buffer.firstIndex(of: "*") else { return nil }

        let hex1 = buffer.index(after: starIndex)
        guard hex1 < buffer.endIndex else { return nil }

        let hex2 = buffer.index(after: hex1)
        guard hex2 < buffer.endIndex else { return nil }

        guard isHexChar(buffer[hex1]), isHexChar(buffer[hex2]) else {
            return nil
        }

        var end = buffer.index(after: hex2)
        while end < buffer.endIndex {
            let ch = buffer[end]
            if ch == "\"" || ch == "\n" {
                end = buffer.index(after: end)
            } else {
                break
            }
        }

        let head = String(buffer[..<starIndex])

        var startOffset: Int?

        if let offset = lastPrefixOffset(in: head) {
            startOffset = offset
        } else if let offset = lastDecimalCoordinateStart(in: head) {
            startOffset = offset
        } else if let offset = lastAtNameOffset(in: head) {
            startOffset = offset
        }

        guard let finalOffset = startOffset else { return nil }
        let start = buffer.index(buffer.startIndex, offsetBy: finalOffset)
        return start..<end
    }

    private func lastPrefixOffset(in text: String) -> Int? {
        let preferredPrefixes = ["+WGRMLOC:", "+WGRXLOC:", "+WGPTT:"]
        for prefix in preferredPrefixes {
            if let range = text.range(of: prefix, options: .backwards) {
                return text.distance(from: text.startIndex, to: range.lowerBound)
            }
        }

        let fallbackPrefixes = ["$PP", "$GPGGA"]
        var best: Int?

        for prefix in fallbackPrefixes {
            if let range = text.range(of: prefix, options: .backwards) {
                let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                if best == nil || offset > best! {
                    best = offset
                }
            }
        }

        return best
    }

    private func lastDecimalCoordinateStart(in text: String) -> Int? {
        let pattern = #"[-+]?\d{1,3}\.\d+\s*,\s*[-+]?\d{1,3}\.\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: nsRange).last,
              let range = Range(match.range, in: text) else {
            return nil
        }

        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    private func lastAtNameOffset(in text: String) -> Int? {
        guard let range = text.range(of: "@", options: .backwards) else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    private func usefulTail(of text: String, maxLength: Int) -> String {
        let prefixes = ["+WGRMLOC:", "+WGRXLOC:", "+WGPTT:", "$PP", "$GPGGA", "@"]
        var keepStart: String.Index?

        for prefix in prefixes {
            if let range = text.range(of: prefix, options: .backwards) {
                if keepStart == nil || range.lowerBound > keepStart! {
                    keepStart = range.lowerBound
                }
            }
        }

        if let keepStart {
            let suffix = String(text[keepStart...])
            return suffix.count > maxLength ? String(suffix.suffix(maxLength)) : suffix
        }

        return String(text.suffix(maxLength))
    }

    private func handleCandidate(_ rawCandidate: String, characteristic: CBCharacteristic) {
        let message = normalizeRadioMessage(rawCandidate)
        guard !message.isEmpty else { return }

        let now = Date()

        if showAllIncomingData {
            appendTransmissionLog(
                title: "CANDIDATE \(characteristic.uuid.uuidString)",
                body: message
            )
        }

        if let lastSeen = recentMessageFingerprints[message],
           now.timeIntervalSince(lastSeen) < 0.75,
           !showAllIncomingData {
            return
        }

        recentMessageFingerprints[message] = now
        pruneRecentMessageFingerprints(now: now)

        if lastCompleteMessage == message,
           now.timeIntervalSince(lastCompleteMessageAt) < 1.0,
           !showAllIncomingData {
            return
        }

        lastCompleteMessage = message
        lastCompleteMessageAt = now

        appendTransmissionLog(
            title: "MSG \(characteristic.uuid.uuidString)",
            body: message
        )
        parseCompletedMessage(message)
    }

    private func pruneRecentMessageFingerprints(now: Date) {
        recentMessageFingerprints = recentMessageFingerprints.filter {
            now.timeIntervalSince($0.value) < 10
        }
    }

    private func isHexChar(_ ch: Character) -> Bool {
        ch.isHexDigit
    }

    // MARK: - Parsing

    private func parseCompletedMessage(_ rawMessage: String) {
        let normalized = normalizeRadioMessage(rawMessage)
        guard !normalized.isEmpty else { return }

        if isClearlyJunk(normalized, mode: parserMode) {
            appendLog("[\(parserModeTag())] IGNORED partial/junk: \(normalized)")
            return
        }

        if let contact = parseContact(from: normalized, rawMessage: rawMessage, mode: parserMode) {
            upsertDecodedContact(contact)
        } else {
            appendLog("[\(parserModeTag())] UNPARSED candidate: \(normalized)")
        }
    }

    private func normalizeRadioMessage(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: "\\0D\\0A", with: "")
        s = s.replacingOccurrences(of: "\\r\\n", with: "")
        s = s.replacingOccurrences(of: "\r", with: "")
        s = s.replacingOccurrences(of: "\n", with: "")
        s = s.replacingOccurrences(of: "\"", with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        while s.hasPrefix("D\\0A") || s.hasPrefix("\\0A") {
            if s.hasPrefix("D\\0A") {
                s.removeFirst(4)
            } else if s.hasPrefix("\\0A") {
                s.removeFirst(3)
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while s.contains(",,") {
            s = s.replacingOccurrences(of: ",,", with: ",")
        }

        s = s.replacingOccurrences(of: "\"\"", with: "\"")

        return s
    }

    private func isClearlyJunk(_ text: String, mode: ParserMode) -> Bool {
        let lower = text.lowercased()

        if lower == "ing*57" || lower == "g*57" || lower == "ing*6e" || lower == "g*6e" {
            return true
        }

        if mode == .strict {
            if lower.hasPrefix("ing*") || lower.hasPrefix("g*") {
                return true
            }
        }

        let hasSignalPrefix =
            text.contains("+WGRMLOC:") ||
            text.contains("+WGRXLOC:") ||
            text.contains("+WGPTT:") ||
            text.contains("$PP") ||
            text.contains("$GPGGA")

        let hasDecimalCoords = hasEmbeddedDecimalCoordinates(text, mode: mode)
        let hasNMEACoords = hasEmbeddedNMEACoordinates(text, mode: mode)
        let hasNameStatus = hasNameStatusPayload(text, mode: mode)

        switch mode {
        case .strict:
            return !hasSignalPrefix && !hasDecimalCoords && !hasNMEACoords && !hasNameStatus

        case .tolerant:
            if hasSignalPrefix || hasDecimalCoords || hasNMEACoords || hasNameStatus {
                return false
            }
            return text.count < 6

        case .aggressive:
            if hasSignalPrefix || hasDecimalCoords || hasNMEACoords || hasNameStatus {
                return false
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func parseContact(from message: String, rawMessage: String, mode: ParserMode) -> XRSRadioContact? {
        if let parsed = parseWGRMLOCStyleMessage(message, rawMessage: rawMessage, mode: mode) {
            return parsed
        }

        if let parsed = parsePPStyleMessage(message, rawMessage: rawMessage, mode: mode) {
            return parsed
        }

        if let parsed = parseEmbeddedDecimalCoordinates(message, rawMessage: rawMessage, mode: mode) {
            return parsed
        }

        if let parsed = parseEmbeddedNMEACoordinates(message, rawMessage: rawMessage, mode: mode) {
            return parsed
        }

        if let parsed = parseStatusOnlyMessage(message, rawMessage: rawMessage, mode: mode) {
            return parsed
        }

        if mode == .aggressive,
           let parsed = parseLooseCoordinatePair(message, rawMessage: rawMessage) {
            return parsed
        }

        return nil
    }

    private func parseWGRMLOCStyleMessage(_ message: String, rawMessage: String, mode: ParserMode) -> XRSRadioContact? {
        guard message.contains("+WGRMLOC:") || message.contains("+WGRXLOC:") else { return nil }

        if let parsed = parseDirectWGRMLOCCoordinates(message, rawMessage: rawMessage) {
            return parsed
        }

        if let embedded = parseEmbeddedDecimalCoordinates(message, rawMessage: rawMessage, mode: mode) {
            return embedded
        }

        if let embedded = parseEmbeddedNMEACoordinates(message, rawMessage: rawMessage, mode: mode) {
            return embedded
        }

        if mode != .strict,
           let statusOnly = parseStatusOnlyMessage(message, rawMessage: rawMessage, mode: mode) {
            return statusOnly
        }

        return nil
    }

    private func parsePPStyleMessage(_ message: String, rawMessage: String, mode: ParserMode) -> XRSRadioContact? {
        guard message.contains("$PP") else { return nil }

        if let embedded = parseEmbeddedDecimalCoordinates(message, rawMessage: rawMessage, mode: mode) {
            return embedded
        }

        if let embedded = parseEmbeddedNMEACoordinates(message, rawMessage: rawMessage, mode: mode) {
            return embedded
        }

        if mode != .strict,
           let statusOnly = parseStatusOnlyMessage(message, rawMessage: rawMessage, mode: mode) {
            return statusOnly
        }

        return nil
    }

    private func parseDirectWGRMLOCCoordinates(_ message: String, rawMessage: String) -> XRSRadioContact? {
        guard let range = message.range(of: "+WGRMLOC:") ?? message.range(of: "+WGRXLOC:") else {
            return nil
        }

        let tail = String(message[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = tail.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return nil }

        for i in 0..<(parts.count - 1) {
            let a = parts[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let b = parts[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)

            guard let lat = Double(a),
                  let lon = Double(b),
                  isLikelyLatitude(lat),
                  isLikelyLongitude(lon),
                  abs(lat) > 10,
                  abs(lon) > 50 else {
                continue
            }

            let (name, status) = extractNameAndStatus(from: message, mode: .strict)
            let parsedName = name.isEmpty ? fallbackContactName(from: message, mode: .strict) : name
            let finalName = preferredContactName(parsed: parsedName, existing: nil)

            appendLog("WGRMLOC parse lat=\(String(format: "%.5f", lat)) lon=\(String(format: "%.5f", lon)) name=\(finalName)")

            return makeContact(
                name: finalName,
                status: status,
                latitude: lat,
                longitude: lon,
                rawMessage: rawMessage
            )
        }

        return nil
    }

    private func parseEmbeddedDecimalCoordinates(_ message: String, rawMessage: String, mode: ParserMode) -> XRSRadioContact? {
        let pattern = #"([-+]?\d{1,3}\.\d+)\s*,\s*([-+]?\d{1,3}\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsRange = NSRange(message.startIndex..., in: message)
        let matches = regex.matches(in: message, range: nsRange)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let latRange = Range(match.range(at: 1), in: message),
                  let lonRange = Range(match.range(at: 2), in: message),
                  let lat = Double(message[latRange]),
                  let lon = Double(message[lonRange]) else {
                continue
            }

            let looksValid: Bool
            switch mode {
            case .strict:
                looksValid = isLikelyLatitude(lat) &&
                             isLikelyLongitude(lon) &&
                             abs(lat) > 10 &&
                             abs(lon) > 50
            case .tolerant:
                looksValid = isLikelyLatitude(lat) &&
                             isLikelyLongitude(lon)
            case .aggressive:
                looksValid = abs(lat) <= 90 && abs(lon) <= 180
            }

            guard looksValid else { continue }

            let (name, status) = extractNameAndStatus(from: message, mode: mode)
            let parsedName = name.isEmpty ? fallbackContactName(from: message, mode: mode) : name
            let finalName = cleanCandidateName(parsedName)

            appendLog("[\(parserModeTag(mode))] Decimal parse lat=\(String(format: "%.5f", lat)) lon=\(String(format: "%.5f", lon)) name=\(finalName)")

            return makeContact(
                name: finalName,
                status: status,
                latitude: lat,
                longitude: lon,
                rawMessage: rawMessage
            )
        }

        return nil
    }

    private func parseEmbeddedNMEACoordinates(_ message: String, rawMessage: String, mode: ParserMode) -> XRSRadioContact? {
        let parts = message
            .replacingOccurrences(of: "\"", with: "")
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard parts.count >= 4 else { return nil }

        for i in 0..<(parts.count - 3) {
            let latRaw = parts[i]
            let latHem = parts[i + 1].uppercased()
            let lonRaw = parts[i + 2]
            let lonHem = parts[i + 3].uppercased()

            guard (latHem == "N" || latHem == "S"),
                  (lonHem == "E" || lonHem == "W") else { continue }

            guard let lat = nmeaToDecimal(latRaw, hemisphere: latHem, isLatitude: true),
                  let lon = nmeaToDecimal(lonRaw, hemisphere: lonHem, isLatitude: false) else { continue }

            let looksValid: Bool
            switch mode {
            case .strict:
                looksValid = isLikelyLatitude(lat) && isLikelyLongitude(lon)
            case .tolerant, .aggressive:
                looksValid = abs(lat) <= 90 && abs(lon) <= 180
            }

            guard looksValid else { continue }

            let (name, status) = extractNameAndStatus(from: message, mode: mode)
            let parsedName = name.isEmpty ? fallbackContactName(from: message, mode: mode) : name
            let finalName = cleanCandidateName(parsedName)

            appendLog("[\(parserModeTag(mode))] NMEA parse lat=\(String(format: "%.5f", lat)) lon=\(String(format: "%.5f", lon)) name=\(finalName)")

            return makeContact(
                name: finalName,
                status: status,
                latitude: lat,
                longitude: lon,
                rawMessage: rawMessage
            )
        }

        return nil
    }

    private func parseStatusOnlyMessage(_ message: String, rawMessage: String, mode: ParserMode) -> XRSRadioContact? {
        let (parsedName, status) = extractNameAndStatus(from: message, mode: mode)
        guard isUsableContactName(parsedName, mode: mode) else { return nil }

        let key = parsedName.lowercased()
        if let existing = contactByName[key] {
            let finalName = preferredContactName(parsed: parsedName, existing: existing.name)

            appendLog("[\(parserModeTag(mode))] Status-only update name=\(finalName)\(status.map { " status=\($0)" } ?? "")")
            return XRSRadioContact(
                id: existing.id,
                name: finalName,
                status: status ?? existing.status,
                lat: existing.lat,
                lon: existing.lon,
                updatedAt: Date(),
                rawMessage: rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        appendLog("[\(parserModeTag(mode))] Status-only update ignored until location known for \(parsedName)")
        return nil
    }

    private func parseLooseCoordinatePair(_ message: String, rawMessage: String) -> XRSRadioContact? {
        let pattern = #"[-+]?\d{1,3}(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsRange = NSRange(message.startIndex..., in: message)
        let matches = regex.matches(in: message, range: nsRange)

        let numbers: [Double] = matches.compactMap { match in
            guard let range = Range(match.range, in: message) else { return nil }
            return Double(message[range])
        }

        guard numbers.count >= 2 else { return nil }

        for i in 0..<(numbers.count - 1) {
            let a = numbers[i]
            let b = numbers[i + 1]

            guard abs(a) <= 90, abs(b) <= 180 else { continue }

            let (name, status) = extractNameAndStatus(from: message, mode: .aggressive)
            let parsedName = name.isEmpty ? fallbackContactName(from: message, mode: .aggressive) : name

            appendLog("[SUPER] Loose parse lat=\(String(format: "%.5f", a)) lon=\(String(format: "%.5f", b)) name=\(parsedName)")

            return makeContact(
                name: parsedName,
                status: status,
                latitude: a,
                longitude: b,
                rawMessage: rawMessage
            )
        }

        return nil
    }

    private func hasEmbeddedDecimalCoordinates(_ message: String, mode: ParserMode) -> Bool {
        let pattern = #"([-+]?\d{1,3}\.\d+)\s*,\s*([-+]?\d{1,3}\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }

        let nsRange = NSRange(message.startIndex..., in: message)
        for match in regex.matches(in: message, range: nsRange) {
            guard match.numberOfRanges >= 3,
                  let latRange = Range(match.range(at: 1), in: message),
                  let lonRange = Range(match.range(at: 2), in: message),
                  let lat = Double(message[latRange]),
                  let lon = Double(message[lonRange]) else {
                continue
            }

            switch mode {
            case .strict:
                if isLikelyLatitude(lat),
                   isLikelyLongitude(lon),
                   abs(lat) > 10,
                   abs(lon) > 50 {
                    return true
                }
            case .tolerant, .aggressive:
                if abs(lat) <= 90, abs(lon) <= 180 {
                    return true
                }
            }
        }

        return false
    }

    private func hasEmbeddedNMEACoordinates(_ message: String, mode: ParserMode) -> Bool {
        let parts = message
            .replacingOccurrences(of: "\"", with: "")
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard parts.count >= 4 else { return false }

        for i in 0..<(parts.count - 3) {
            let latHem = parts[i + 1].uppercased()
            let lonHem = parts[i + 3].uppercased()
            if (latHem == "N" || latHem == "S") &&
                (lonHem == "E" || lonHem == "W") {
                return true
            }
        }

        return false
    }

    private func hasNameStatusPayload(_ text: String, mode: ParserMode) -> Bool {
        let extracted = extractNameAndStatus(from: text, mode: mode).name
        return !cleanCandidateName(extracted).isEmpty
    }

    private func extractNameAndStatus(from text: String, mode: ParserMode) -> (name: String, status: String?) {
        var payload = text

        if let starIndex = payload.firstIndex(of: "*") {
            payload = String(payload[..<starIndex])
        }

        payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        payload = payload.replacingOccurrences(of: "\"", with: "")

        if let atIndex = payload.firstIndex(of: "@") {
            let afterAt = String(payload[payload.index(after: atIndex)...])

            if let hashIndex = afterAt.firstIndex(of: "#") {
                let rawName = String(afterAt[..<hashIndex])
                let rawStatus = String(afterAt[afterAt.index(after: hashIndex)...])

                let name = cleanCandidateName(rawName)
                let status = cleanCandidateStatus(rawStatus)

                return (isUsableContactName(name, mode: mode) ? name : "", status)
            }

            let name = cleanCandidateName(afterAt)
            return (isUsableContactName(name, mode: mode) ? name : "", nil)
        }

        return extractLooseNameAndStatus(from: payload, mode: mode)
    }

    private func extractLooseNameAndStatus(from text: String, mode: ParserMode) -> (name: String, status: String?) {
        let cleaned = text
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var patterns: [String] = [
            #"(?i)\bname\s*[:=]\s*([A-Za-z0-9][A-Za-z0-9 _-]{1,39})(?:\s*#\s*([^\r\n,]+))?"#,
            #"(?i)\buser\s*[:=]\s*([A-Za-z0-9][A-Za-z0-9 _-]{1,39})(?:\s*#\s*([^\r\n,]+))?"#,
            #"(?i)\bfrom\s*[:=]\s*([A-Za-z0-9][A-Za-z0-9 _-]{1,39})(?:\s*#\s*([^\r\n,]+))?"#,
            #"(?i)\bcaller\s*[:=]\s*([A-Za-z0-9][A-Za-z0-9 _-]{1,39})(?:\s*#\s*([^\r\n,]+))?"#
        ]

        if mode != .strict {
            patterns.append(#"@([A-Za-z0-9][A-Za-z0-9 _-]{1,39})(?:\s*#\s*([^\r\n,]+))?"#)
        }

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)

            guard
                let match = regex.firstMatch(in: cleaned, options: [], range: nsRange),
                match.numberOfRanges >= 2,
                let nameRange = Range(match.range(at: 1), in: cleaned)
            else {
                continue
            }

            let name = cleanCandidateName(String(cleaned[nameRange]))

            var status: String? = nil
            if match.numberOfRanges >= 3,
               match.range(at: 2).location != NSNotFound,
               let statusRange = Range(match.range(at: 2), in: cleaned) {
                status = cleanCandidateStatus(String(cleaned[statusRange]))
            }

            if isUsableContactName(name, mode: mode) {
                return (name, status)
            }
        }

        return ("", nil)
    }

    private func isUsableContactName(_ value: String, mode: ParserMode) -> Bool {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= (mode == .aggressive ? 1 : 2) else { return false }

        let lowered = s.lowercased()
        let bad: Set<String> = [
            "r",
            "radio",
            "radio contact",
            "unknown",
            "null",
            "n/a",
            "-"
        ]

        if bad.contains(lowered) { return false }

        if mode == .strict {
            return s.rangeOfCharacter(from: .letters) != nil
        }

        return true
    }

    private func preferredContactName(parsed: String, existing: String?) -> String {
        let cleanParsed = cleanCandidateName(parsed)
        let cleanExisting = cleanCandidateName(existing ?? "")

        let parsedOK = isUsableContactName(cleanParsed, mode: .tolerant)
        let existingOK = isUsableContactName(cleanExisting, mode: .tolerant)

        if parsedOK && existingOK {
            if cleanParsed.caseInsensitiveCompare(cleanExisting) == .orderedSame {
                return cleanExisting
            }
            return cleanParsed.count >= cleanExisting.count ? cleanParsed : cleanExisting
        }

        if parsedOK { return cleanParsed }
        if existingOK { return cleanExisting }

        return "Radio Contact"
    }

    private func fallbackContactName(from message: String, mode: ParserMode) -> String {
        if let atIndex = message.firstIndex(of: "@") {
            var tail = String(message[message.index(after: atIndex)...])

            if let hashIndex = tail.firstIndex(of: "#") {
                tail = String(tail[..<hashIndex])
            }

            if let commaIndex = tail.firstIndex(of: ",") {
                tail = String(tail[..<commaIndex])
            }

            let cleaned = cleanCandidateName(tail)
            if isUsableContactName(cleaned, mode: mode) { return cleaned }
        }

        let fallback = extractLooseNameAndStatus(from: message, mode: mode).name
        if isUsableContactName(fallback, mode: mode) { return fallback }

        return mode == .aggressive ? "Unknown Radio" : "Radio Contact"
    }

    private func cleanCandidateName(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)

        s = s.replacingOccurrences(of: "\"", with: "")
        s = s.replacingOccurrences(of: "\\0D\\0A", with: "")
        s = s.replacingOccurrences(of: "\\r\\n", with: "")
        s = s.replacingOccurrences(of: "\r", with: "")
        s = s.replacingOccurrences(of: "\n", with: "")
        s = s.replacingOccurrences(of: ";", with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }

        return s
    }

    private func cleanCandidateStatus(_ value: String) -> String? {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)

        s = s.replacingOccurrences(of: "\"", with: "")
        s = s.replacingOccurrences(of: "\\0D\\0A", with: "")
        s = s.replacingOccurrences(of: "\\r\\n", with: "")
        s = s.replacingOccurrences(of: "\r", with: "")
        s = s.replacingOccurrences(of: "\n", with: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        return s.isEmpty ? nil : s
    }

    private func nmeaToDecimal(_ value: String, hemisphere: String, isLatitude: Bool) -> Double? {
        guard let raw = Double(value) else { return nil }

        let divisor = isLatitude ? 100.0 : 100.0
        let degrees = floor(raw / divisor)
        let minutes = raw - (degrees * divisor)

        guard minutes >= 0, minutes < 60 else { return nil }

        var decimal = degrees + minutes / 60.0
        if hemisphere == "S" || hemisphere == "W" {
            decimal = -decimal
        }

        return decimal
    }

    private func makeContact(
        name: String,
        status: String?,
        latitude: Double,
        longitude: Double,
        rawMessage: String
    ) -> XRSRadioContact {
        let trimmedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalStatus = (trimmedStatus?.isEmpty == true) ? nil : trimmedStatus

        let parsedName = cleanCandidateName(name)

        let existing = contactByName.values.first(where: {
            abs($0.lat - latitude) < 0.0001 && abs($0.lon - longitude) < 0.0001
        })

        let finalName = preferredContactName(parsed: parsedName, existing: existing?.name)
        let key = finalName.lowercased()

        let keyedExisting = contactByName[key]

        return XRSRadioContact(
            id: keyedExisting?.id ?? existing?.id ?? stableID(for: finalName),
            name: finalName,
            status: finalStatus ?? keyedExisting?.status ?? existing?.status,
            lat: latitude,
            lon: longitude,
            updatedAt: Date(),
            rawMessage: rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func upsertDecodedContact(_ contact: XRSRadioContact) {
        let key = contact.name.lowercased()

        let finalContact: XRSRadioContact
        if let existing = contactByName[key] {
            finalContact = XRSRadioContact(
                id: existing.id,
                name: contact.name,
                status: contact.status ?? existing.status,
                lat: contact.lat,
                lon: contact.lon,
                updatedAt: contact.updatedAt,
                rawMessage: contact.rawMessage
            )
        } else {
            finalContact = contact
        }

        let fingerprint =
            "\(finalContact.name.lowercased())|" +
            "\(String(format: "%.5f", finalContact.lat))|" +
            "\(String(format: "%.5f", finalContact.lon))|" +
            "\(finalContact.status ?? "")"

        let now = Date()

        if let lastSeen = lastParsedFingerprintAt[fingerprint],
           now.timeIntervalSince(lastSeen) < 1.0 {
            return
        }

        lastParsedFingerprintAt[fingerprint] = now
        contactByName[key] = finalContact

        decodedContacts = Array(contactByName.values).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        appendLog(
            "CONTACT \(finalContact.name): " +
            "\(String(format: "%.5f", finalContact.lat)), " +
            "\(String(format: "%.5f", finalContact.lon))" +
            "\(finalContact.status.map { " [\($0)]" } ?? "")"
        )

        onDecodedContact?(finalContact)
    }

    private func isLikelyLatitude(_ value: Double) -> Bool {
        value >= -90 && value <= 90
    }

    private func isLikelyLongitude(_ value: Double) -> Bool {
        value >= -180 && value <= 180
    }

    private func stableID(for name: String) -> UUID {
        let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = cleaned.utf8.reduce(UInt64(1469598103934665603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1099511628211
        }

        let a = UInt32((hash >> 32) & 0xffffffff)
        let b = UInt16((hash >> 16) & 0xffff)
        let c = UInt16(hash & 0xffff)
        let d = UInt16((hash >> 48) & 0xffff)
        let e = UInt64(hash & 0xffffffffffff)

        let uuidString = String(format: "%08X-%04X-%04X-%04X-%012llX", a, b, c, d, e)
        return UUID(uuidString: uuidString) ?? UUID()
    }
}

// MARK: - CBCentralManagerDelegate
extension BLERadioDebugger: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.appendLog("Central state = \(self.centralStateString(central.state))")

            if central.state == .poweredOn {
                self.reconnectLastKnownPeripheralIfPossible()
            } else {
                self.stopForceLocationUpdateTimer()
                self.updateConnectionState(false)
                self.connectedPeripheralName = nil
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let name =
                peripheral.name ??
                (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ??
                "Unknown Device"

            let item = PeripheralItem(
                id: peripheral.identifier,
                peripheral: peripheral,
                name: name,
                rssi: RSSI.intValue,
                identifier: peripheral.identifier
            )

            self.seenPeripherals[peripheral.identifier] = item

            if self.isSavedRadio(peripheral.identifier),
               let index = self.savedRadios.firstIndex(where: { $0.identifier == peripheral.identifier }) {
                self.savedRadios[index].displayName = name
                self.persistSavedRadios()
            }

            let now = Date()
            if now.timeIntervalSince(self.lastDiscoveryPublishAt) >= 5.0 {
                self.discoveredPeripherals = self.sortedPeripheralItems(Array(self.seenPeripherals.values))
                self.lastDiscoveryPublishAt = now
            }

            if self.shouldAutoReconnect,
               self.connectedPeripheral == nil,
               self.lastConnectedPeripheralID == peripheral.identifier {
                self.appendLog("Auto-reconnecting to \(name)...")
                self.connectedPeripheral = peripheral
                peripheral.delegate = self
                central.connect(peripheral, options: self.connectionOptions)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            let name = peripheral.name ?? "Unknown"

            self.connectedPeripheral = peripheral
            self.connectedPeripheralName = name
            self.cancelPendingReconnect()
            self.reconnectAttemptCount = 0
            self.updateConnectionState(true)
            self.lastConnectedPeripheralID = peripheral.identifier
            self.saveRadio(identifier: peripheral.identifier, name: name)

            self.appendLog("Connected to \(name)")
            self.resetSessionState(clearConnectionIdentity: false)
            self.loadForceLocationSettingsForCurrentRadio()
            self.restartForceLocationUpdateTimerIfNeeded()

            peripheral.delegate = self
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.appendLog("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
            self.stopForceLocationUpdateTimer()
            self.updateConnectionState(false)
            self.connectedPeripheralName = nil
            self.connectedPeripheral = nil
            self.scheduleReconnect(reason: "failed connect")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.appendLog("Disconnected from \(peripheral.name ?? "Unknown")")
            if let error {
                self.appendLog("Disconnect error: \(error.localizedDescription)")
            }

            if let active = self.connectedPeripheral,
               active.identifier != peripheral.identifier,
               self.isConnected {
                self.appendLog("Ignoring disconnect callback for inactive peripheral \(peripheral.name ?? "Unknown")")
                return
            }

            self.resetSessionState(clearConnectionIdentity: true)
            self.stopForceLocationUpdateTimer()
            self.updateConnectionState(false)
            self.connectedPeripheral = peripheral
            self.scheduleReconnect(reason: "disconnect")
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLERadioDebugger: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.appendLog("Service discovery failed: \(error.localizedDescription)")
                return
            }

            guard let services = peripheral.services else {
                self.appendLog("No services found.")
                return
            }

            self.appendLog("Discovered \(services.count) services")

            for service in services {
                let line = "Service: \(service.uuid.uuidString)"
                self.serviceSummary.append(line)
                self.appendLog(line)
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.appendLog("Characteristic discovery failed for \(service.uuid.uuidString): \(error.localizedDescription)")
                return
            }

            guard let chars = service.characteristics else { return }

            for ch in chars {
                let props = self.propertyString(ch.properties)
                let line = "  Char: \(ch.uuid.uuidString) [\(props)]"
                self.serviceSummary.append(line)
                self.appendLog(line)

                if ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                    if !self.writableCharacteristics.contains(where: { $0.uuid == ch.uuid }) {
                        self.writableCharacteristics.append(ch)
                    }
                }

                if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                    self.appendLog("  -> subscribing to \(ch.uuid.uuidString)")
                    peripheral.setNotifyValue(true, for: ch)
                }

                if ch.properties.contains(.read) {
                    peripheral.readValue(for: ch)
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.appendLog("Notify state failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            } else {
                self.appendLog("Notify \(characteristic.isNotifying ? "ON" : "OFF") for \(characteristic.uuid.uuidString)")
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.appendLog("Value update failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
                return
            }

            guard let data = characteristic.value else {
                self.appendLog("Value update with nil data for \(characteristic.uuid.uuidString)")
                return
            }

            self.onReceiveActivity?()

            let hex = self.hexString(from: data)

            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                self.appendTransmissionLog(
                    title: "RX \(characteristic.uuid.uuidString)",
                    body: """
                    HEX: \(hex)
                    TXT: \(text)
                    """
                )
                self.appendIncomingText(text, for: characteristic)
            } else {
                self.appendTransmissionLog(
                    title: "RX \(characteristic.uuid.uuidString)",
                    body: "HEX: \(hex)"
                )
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.appendLog("Write failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            } else {
                self.appendLog("Write OK for \(characteristic.uuid.uuidString)")
            }
        }
    }
}
