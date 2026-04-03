import SwiftUI

struct BluetoothSettingsView: View {
    @EnvironmentObject private var ble: BLERadioDebugger

    var body: some View {
        List {

            // MARK: - Status
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

            // MARK: - Known Radios
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

            // MARK: - Add New
            Section {
                Button {
                    ble.startScan()
                } label: {
                    Label("Add New Radio", systemImage: "plus.circle.fill")
                }
            }

            // MARK: - Scanning Results
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
