import SwiftUI

struct MusterView: View {
    @EnvironmentObject private var app: AppState
    @State private var showMissingMapSetPrompt = false
    @State private var showMapSetsSheet = false
    @State private var startMapSetCreationFlowOnOpen = false
    @State private var pendingTrackName = ""
    @State private var showNewTrackNamePrompt = false

    private var sortedSessions: [MusterSession] {
        app.muster.sessions.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {

                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Muster")
                                    .font(.title2.weight(.semibold))
                                Text("Start a session, record a track, drop markers.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                pendingTrackName = app.muster.makeSmartSessionName()
                                showNewTrackNamePrompt = true
                            } label: {
                                Label("New Muster", systemImage: "plus")
                            }
                            .buttonStyle(GlassButtonStyle())
                        }
                    }

                    if let active = app.muster.activeSession {
                        NavigationLink {
                            SessionDetailView(sessionID: active.id)
                        } label: {
                            GlassCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(active.name)
                                            .font(.headline)

                                        Text("Tap to open live map")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 12) {
                        ForEach(sortedSessions) { session in
                            NavigationLink {
                                SessionDetailView(sessionID: session.id)
                            } label: {
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(session.name)
                                                .font(.headline)

                                            Spacer()

                                            Text(session.isActive ? "Recording" : "Done")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(
                                            session.startedAt.formatted(
                                                date: .abbreviated,
                                                time: .shortened
                                            )
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
            }
            .navigationTitle("Muster")
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
        .alert("New Track", isPresented: $showNewTrackNamePrompt) {
            TextField("Track name", text: $pendingTrackName)
            Button("Cancel", role: .cancel) {}
            Button("Start") {
                if app.muster.startSession(name: pendingTrackName) == false {
                    showMissingMapSetPrompt = true
                }
            }
        } message: {
            Text("Choose a track name.")
        }
        .onChange(of: showMapSetsSheet) { _, isPresented in
            if isPresented == false {
                startMapSetCreationFlowOnOpen = false
            }
        }
    }
}
