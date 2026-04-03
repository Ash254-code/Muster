import SwiftUI

struct StartSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    private var previewName: String {
        app.muster.makeSmartSessionName()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New Muster")
                            .font(.title2.weight(.semibold))

                        Text("A smart name will be created automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(previewName)
                            .font(.headline)
                    }
                }

                Spacer()

                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(GlassButtonStyle())

                    Spacer()

                    Button {
                        app.muster.startSmartSession()
                        dismiss()
                    } label: {
                        Label("Start", systemImage: "record.circle")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(14)
            .navigationTitle("New Muster")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
