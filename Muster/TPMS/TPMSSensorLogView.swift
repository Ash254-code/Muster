import SwiftUI

struct TPMSSensorLogView: View {
    @EnvironmentObject private var tpmsBluetooth: TPMSBluetoothManager

    let sensorID: String
    let sensorName: String

    var body: some View {
        List {
            if tpmsBluetooth.logEntries(for: sensorID).isEmpty {
                Text("No log entries for this sensor yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tpmsBluetooth.logEntries(for: sensorID)) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(sensorName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    tpmsBluetooth.clearLog(for: sensorID)
                }
            }
        }
    }
}
