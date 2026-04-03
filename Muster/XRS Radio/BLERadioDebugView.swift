import SwiftUI

struct BLERadioDebugView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var ble: BLERadioDebugger

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
}
