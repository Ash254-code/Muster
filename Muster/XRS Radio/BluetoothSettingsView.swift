import SwiftUI

struct BluetoothSettingsView: View {
    @EnvironmentObject private var ble: BLERadioDebugger

    var body: some View {
        List {

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connection")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let name = ble.connectedPeripheralName, ble.isConnected {
                            Text(name)
                                .font(.headline)
                                .foregroundStyle(.green)
                        } else {
                            Text("Not Connected")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if ble.isConnected {
                        Button("Disconnect") {
                            ble.disconnect()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if ble.isConnected, let name = ble.connectedPeripheralName {
                Section("Current Radio") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.headline)

                            Text("These settings are saved per paired radio.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("Force Location Updates", isOn: $ble.forceLocationUpdatesEnabled)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Update Frequency")
                                Spacer()
                                Text("\(Int(ble.forceLocationUpdateIntervalMinutes)) min")
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospaced())
                            }

                            Slider(
                                value: $ble.forceLocationUpdateIntervalMinutes,
                                in: 1...15,
                                step: 1
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Pulse Length")
                                Spacer()
                                Text(String(format: "%.2f sec", ble.forceLocationUpdatePulseSeconds))
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospaced())
                            }

                            Slider(
                                value: $ble.forceLocationUpdatePulseSeconds,
                                in: 0.05...1.0,
                                step: 0.05
                            )
                        }

                        HStack {
                            Button("Test Pulse") {
                                ble.sendForceLocationPulse()
                            }
                            .buttonStyle(.borderedProminent)

                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !ble.savedRadios.isEmpty {
                Section("My Radios") {
                    ForEach(ble.savedRadios) { radio in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(radio.displayName)
                                    .font(.headline)

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

                            if let last = radio.lastConnectedAt {
                                Text("Last connected: \(last.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Button("Reconnect") {
                                    if let match = ble.discoveredPeripherals.first(where: {
                                        $0.identifier == radio.identifier
                                    }) {
                                        ble.connect(to: match.peripheral)
                                    } else {
                                        ble.startScan()
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Forget") {
                                    ble.forgetSavedRadio(radio)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Button {
                    ble.startScan()
                } label: {
                    Label("Add New Radio", systemImage: "plus.circle.fill")
                }
            }

            if ble.isScanning || !ble.discoveredPeripherals.isEmpty {
                Section("Available Radios") {
                    if ble.discoveredPeripherals.isEmpty {
                        Text("Scanning…")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ble.discoveredPeripherals) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name)
                                        .font(.headline)

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

                                Text("Signal: \(item.rssi)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Button(
                                        ble.isSavedRadio(item.identifier) ? "Reconnect" : "Connect"
                                    ) {
                                        ble.connect(to: item.peripheral)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Spacer()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bluetooth")
    }
}
