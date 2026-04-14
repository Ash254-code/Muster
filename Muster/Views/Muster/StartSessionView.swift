import SwiftUI

struct StartSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @State private var showMissingMapSetPrompt = false
    @State private var showMapSetsSheet = false
    @State private var startMapSetCreationFlowOnOpen = false
    @State private var pendingTrackName = ""

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

                        TextField("Track name", text: $pendingTrackName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
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
                        if app.muster.startSession(name: pendingTrackName) {
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
            app.muster.mapSets.isEmpty ? "No Map Sets Yet" : "Map Set Required",
            isPresented: $showMissingMapSetPrompt,
            titleVisibility: .visible
        ) {
            Button("Create New Map Set") {
                startMapSetCreationFlowOnOpen = true
                showMapSetsSheet = true
            }
            if app.muster.mapSets.isEmpty == false {
                Button("Select Map Set From List") {
                    startMapSetCreationFlowOnOpen = false
                    showMapSetsSheet = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                app.muster.mapSets.isEmpty
                ? "Create a map set before starting your first track."
                : "New track can’t be started without a Map Set selected."
            )
        }
        .sheet(isPresented: $showMapSetsSheet) {
            MapSetsSheetView(startInCreateFlow: startMapSetCreationFlowOnOpen)
                .environmentObject(app)
        }
        .onAppear {
            pendingTrackName = app.muster.makeSmartSessionName()
        }
        .onChange(of: showMapSetsSheet) { _, isPresented in
            if isPresented == false {
                startMapSetCreationFlowOnOpen = false
            }
        }
    }
}
