import SwiftUI

struct BluetoothSettingsView: View {
    @EnvironmentObject private var ble: BLERadioDebugger

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GlassCard {
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
                            .buttonStyle(GlassButtonStyle())
                        }
                    }
                }

                if ble.isConnected, let name = ble.connectedPeripheralName {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current Radio")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

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
                                Slider(value: $ble.forceLocationUpdateIntervalMinutes, in: 1...15, step: 1)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Pulse Length")
                                    Spacer()
                                    Text(String(format: "%.2f sec", ble.forceLocationUpdatePulseSeconds))
                                        .foregroundStyle(.secondary)
                                        .font(.caption.monospaced())
                                }
                                Slider(value: $ble.forceLocationUpdatePulseSeconds, in: 0.05...1.0, step: 0.05)
                            }

                            HStack {
                                Button("Test Pulse") { ble.sendForceLocationPulse() }
                                    .buttonStyle(GlassButtonStyle())
                                Spacer()
                            }
                        }
                    }
                }

                if !ble.savedRadios.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("My Radios")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

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
                                                .background(.thinMaterial, in: Capsule())
                                                .foregroundStyle(.green)
                                        }
                                    }

                                    if let last = radio.lastConnectedAt {
                                        Text("Last connected: \(last.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack(spacing: 10) {
                                        Button("Reconnect") {
                                            if let match = ble.discoveredPeripherals.first(where: {
                                                $0.identifier == radio.identifier
                                            }) {
                                                ble.connect(to: match.peripheral)
                                            } else {
                                                ble.startScan()
                                            }
                                        }
                                        .buttonStyle(GlassButtonStyle())

                                        Button("Forget") { ble.forgetSavedRadio(radio) }
                                            .buttonStyle(GlassButtonStyle())
                                            .tint(.red)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }

                Button {
                    ble.startScan()
                } label: {
                    Label("Add New Radio", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())

                if ble.isScanning || !ble.discoveredPeripherals.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Available Radios")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

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
                                                    .background(.thinMaterial, in: Capsule())
                                                    .foregroundStyle(.blue)
                                            }
                                        }

                                        Text("Signal: \(item.rssi)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        HStack {
                                            Button(ble.isSavedRadio(item.identifier) ? "Reconnect" : "Connect") {
                                                ble.connect(to: item.peripheral)
                                            }
                                            .buttonStyle(GlassButtonStyle())
                                            Spacer()
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .navigationTitle("Bluetooth")
    }
}
