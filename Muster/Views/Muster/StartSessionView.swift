import SwiftUI

struct StartSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @State private var showMissingMapSetPrompt = false
    @State private var showMapSetsSheet = false

    private var previewName: String {
        app.muster.makeSmartSessionName()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New Tack")
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
                        if app.muster.startSmartSession() {
                            dismiss()
                        } else {
                            showMissingMapSetPrompt = true
                        }
                    } label: {
                        Label("Start", systemImage: "record.circle")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(14)
            .navigationTitle("New Track")
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog(
            "Map Set Required",
            isPresented: $showMissingMapSetPrompt,
            titleVisibility: .visible
        ) {
            Button("Create New Map Set") {
                _ = app.muster.createMapSet()
            }
            Button("Select Map Set From List") {
                showMapSetsSheet = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New track can’t be started without a Map Set selected.")
        }
        .sheet(isPresented: $showMapSetsSheet) {
            MapSetsSheetView()
                .environmentObject(app)
        }
    }
}
