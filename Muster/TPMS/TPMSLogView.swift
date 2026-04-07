import SwiftUI

struct TPMSLogView: View {
    @EnvironmentObject private var tpmsBluetooth: TPMSBluetoothManager

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }

    var body: some View {
        List {
            if tpmsBluetooth.visibleLog.isEmpty {
                Text("No TPMS log entries yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tpmsBluetooth.visibleLog) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timeFormatter.string(from: entry.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("TPMS Live Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    tpmsBluetooth.clearVisibleLog()
                }
            }
        }
    }
}
