import SwiftUI

struct BLERadioDebugView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var ble: BLERadioDebugger

    private let pttCharacteristicUUID = "49535343-1E4D-4BD9-BA61-23C647249616"

    @State private var pulseDurationSeconds: Double = 0.35
    @State private var pressCommand: String = "AT+WGPTT=1\r\n"
    @State private var releaseCommand: String = "AT+WGPTT=0\r\n"

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(ble.isScanning ? "Stop Scan" : "Start Scan") {
                        ble.isScanning ? ble.stopScan() : ble.startScan()
                    }
                    .buttonStyle(.borderedProminent)

                    if let name = ble.connectedPeripheralName {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Not connected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                List {
                    if !ble.savedRadios.isEmpty {
                        Section("Known Radios") {
                            ForEach(ble.savedRadios) { radio in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .center, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(radio.displayName)
                                                .font(.headline)

                                            Text(radio.identifier.uuidString)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if ble.connectedPeripheralName == radio.displayName && ble.isConnected {
                                            Text("Connected")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.green.opacity(0.15))
                                                .foregroundStyle(.green)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        if let lastConnectedAt = radio.lastConnectedAt {
                                            Text("Last connected: \(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    HStack {
                                        Button("Forget") {
                                            ble.forgetSavedRadio(radio)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.red)

                                        Spacer()
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section("Parser Mode") {
                        Picker("Parser Mode", selection: $ble.parserMode) {
                            ForEach(BLERadioDebugger.ParserMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading, spacing: 6) {
                            switch ble.parserMode {
                            case .strict:
                                Text("Strict")
                                    .font(.subheadline.weight(.semibold))
                                Text("Current behaviour. Best for avoiding bad decodes, but may miss messy transmissions.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                            case .tolerant:
                                Text("Tolerant")
                                    .font(.subheadline.weight(.semibold))
                                Text("Looser parsing for spacing, formatting, and coordinate extraction. Good field-test mode.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                            case .aggressive:
                                Text("Agressive")
                                    .font(.subheadline.weight(.semibold))
                                Text("Best-effort parsing. May recover more transmissions, but has the highest risk of false positives.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)

                        Toggle("Show all incoming data", isOn: $ble.showAllIncomingData)

                        Text("When enabled, every incoming candidate is shown in the log and duplicate suppression is disabled so you can confirm what the radio is actually sending.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Discovered Devices") {
                        if ble.discoveredPeripherals.isEmpty {
                            Text(ble.isScanning ? "Scanning…" : "No devices found")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(ble.discoveredPeripherals) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .center, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.headline)

                                            Text(item.identifier.uuidString)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if ble.isSavedRadio(item.identifier) {
                                            Text("Saved")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.15))
                                                .foregroundStyle(.blue)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    HStack {
                                        Text("RSSI: \(item.rssi)")
                                            .font(.caption)

                                        Spacer()

                                        Button(ble.isSavedRadio(item.identifier) ? "Reconnect" : "Connect") {
                                            ble.connect(to: item.peripheral)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if ble.isConnected {
                        Section("PTT Test") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Command Characteristic")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(pttCharacteristicUUID)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)

                                Text("Working pair confirmed: AT+WGPTT=1 starts TX, AT+WGPTT=0 stops TX.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Direct Controls")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    Button("PTT ON") {
                                        ble.sendASCII("AT+WGPTT=1\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("PTT OFF") {
                                        ble.sendASCII("AT+WGPTT=0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }

                                HStack(spacing: 10) {
                                    Button("PTT ON 1,0") {
                                        ble.sendASCII("AT+WGPTT=1,0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("PTT OFF 0,0") {
                                        ble.sendASCII("AT+WGPTT=0,0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Adjustable Pulse")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Press Command")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    TextField("Press command", text: $pressCommand, axis: .vertical)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .font(.system(.body, design: .monospaced))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Release Command")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    TextField("Release command", text: $releaseCommand, axis: .vertical)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .font(.system(.body, design: .monospaced))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Pulse Duration")
                                        Spacer()
                                        Text(String(format: "%.2f s", pulseDurationSeconds))
                                            .foregroundStyle(.secondary)
                                            .font(.caption.monospaced())
                                    }

                                    Slider(value: $pulseDurationSeconds, in: 0.10...3.00, step: 0.05)
                                }

                                HStack(spacing: 10) {
                                    Button("Send Press") {
                                        ble.sendASCII(pressCommand, characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Send Release") {
                                        ble.sendASCII(releaseCommand, characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)

                                    Button("Pulse") {
                                        sendPulse()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Quick Pulse Presets")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    Button("0.20s") { pulseDurationSeconds = 0.20 }
                                        .buttonStyle(.bordered)

                                    Button("0.35s") { pulseDurationSeconds = 0.35 }
                                        .buttonStyle(.bordered)

                                    Button("0.50s") { pulseDurationSeconds = 0.50 }
                                        .buttonStyle(.bordered)
                                }

                                HStack(spacing: 10) {
                                    Button("0.75s") { pulseDurationSeconds = 0.75 }
                                        .buttonStyle(.bordered)

                                    Button("1.00s") { pulseDurationSeconds = 1.00 }
                                        .buttonStyle(.bordered)

                                    Button("1.50s") { pulseDurationSeconds = 1.50 }
                                        .buttonStyle(.bordered)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("One-Tap Pulse Tests")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    Button("Pulse 0.20s") {
                                        pulseDurationSeconds = 0.20
                                        sendPulse()
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Pulse 0.35s") {
                                        pulseDurationSeconds = 0.35
                                        sendPulse()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                HStack(spacing: 10) {
                                    Button("Pulse 0.50s") {
                                        pulseDurationSeconds = 0.50
                                        sendPulse()
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Pulse 0.75s") {
                                        pulseDurationSeconds = 0.75
                                        sendPulse()
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack(spacing: 10) {
                                    Button("Pulse 1.00s") {
                                        pulseDurationSeconds = 1.00
                                        sendPulse()
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Pulse 1.50s") {
                                        pulseDurationSeconds = 1.50
                                        sendPulse()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Query / Handshake")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    Button("AT Plain") {
                                        ble.sendASCII("AT\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("AT ?") {
                                        ble.sendASCII("AT+WGPTT?\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack(spacing: 10) {
                                    Button("AT =?") {
                                        ble.sendASCII("AT+WGPTT=?\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("AT Help") {
                                        ble.sendASCII("AT+WGPTT\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Alternative Values")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    Button("AT 2") {
                                        ble.sendASCII("AT+WGPTT=2\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("AT 2,0") {
                                        ble.sendASCII("AT+WGPTT=2,0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack(spacing: 10) {
                                    Button("AT 2,15") {
                                        ble.sendASCII("AT+WGPTT=2,15\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("AT 3") {
                                        ble.sendASCII("AT+WGPTT=3\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack(spacing: 10) {
                                    Button("AT 3,0") {
                                        ble.sendASCII("AT+WGPTT=3,0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("AT -1") {
                                        ble.sendASCII("AT+WGPTT=-1\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Emergency Stop Attempts")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    Button("STOP 0") {
                                        ble.sendASCII("AT+WGPTT=0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)

                                    Button("STOP 0,0") {
                                        ble.sendASCII("AT+WGPTT=0,0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }

                                HStack(spacing: 10) {
                                    Button("STOP 2") {
                                        ble.sendASCII("AT+WGPTT=2\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)

                                    Button("Disconnect") {
                                        ble.disconnect()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Legacy Tests")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    Button("PTT 1,0") {
                                        ble.sendASCII("+WGPTT: 1,0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("PTT 0,0") {
                                        ble.sendASCII("+WGPTT: 0,0\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack(spacing: 10) {
                                    Button("PTT 2,15") {
                                        ble.sendASCII("+WGPTT: 2,15\r\n", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Send Hex 1,0") {
                                        ble.sendHex("2B 57 47 50 54 54 3A 20 31 2C 30 0D 0A", characteristicUUID: pttCharacteristicUUID)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    if !ble.decodedContacts.isEmpty {
                        Section("Decoded Contacts") {
                            ForEach(ble.decodedContacts) { contact in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(contact.name)
                                            .font(.headline)

                                        Spacer()

                                        Text(contact.lastHeard, style: .time)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(String(format: "%.5f, %.5f", contact.lat, contact.lon))
                                        .font(.caption.monospaced())

                                    if let status = contact.status,
                                       !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(status)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if !ble.serviceSummary.isEmpty {
                        Section("Services / Characteristics") {
                            ForEach(ble.serviceSummary, id: \.self) { line in
                                Text(line)
                                    .font(.caption.monospaced())
                            }
                        }
                    }

                    Section("Live Log") {
                        ScrollView {
                            Text(ble.logText.isEmpty ? "No data yet" : ble.logText)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 260)
                    }
                }
            }
            .padding(.top, 8)
            .navigationTitle("Radio BLE Debug")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Clear Log") {
                        ble.clearLog()
                    }

                    if ble.connectedPeripheralName != nil {
                        Button("Disconnect") {
                            ble.disconnect()
                        }
                    }
                }
            }
        }
    }

    private func sendPulse() {
        ble.sendASCII(pressCommand, characteristicUUID: pttCharacteristicUUID)

        DispatchQueue.main.asyncAfter(deadline: .now() + pulseDurationSeconds) {
            ble.sendASCII(releaseCommand, characteristicUUID: pttCharacteristicUUID)
        }
    }
}
