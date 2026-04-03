import SwiftUI

struct MenuSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    private var previousSessions: [MusterSession] {
        app.muster.previousSessions
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Map Visibility") {
                    Toggle(isOn: previousTracksVisibleBinding) {
                        Label("Show Previous Tracks", systemImage: "eye")
                    }

                    if previousSessions.isEmpty == false {
                        HStack(spacing: 12) {
                            Button {
                                app.muster.showAllPreviousSessionsOnMap()
                            } label: {
                                Label("Show All", systemImage: "eye")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                app.muster.hideAllPreviousSessionsOnMap()
                            } label: {
                                Label("Hide All", systemImage: "eye.slash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Previous Musters") {
                    if previousSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No previous musters")
                                .font(.headline)

                            Text("Start a new muster and it will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(previousSessions) { session in
                            HStack(spacing: 12) {
                                Button {
                                    app.muster.activeSessionID = session.id
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(session.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        Text(
                                            session.startedAt.formatted(
                                                date: .abbreviated,
                                                time: .shortened
                                            )
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                        if let detail = sessionDetailText(for: session) {
                                            Text(detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    app.muster.toggleSessionVisibilityOnMap(sessionID: session.id)
                                } label: {
                                    Image(systemName: session.isVisibleOnMap ? "eye.fill" : "eye.slash.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(
                                            app.muster.showPreviousTracksOnMap
                                            ? (session.isVisibleOnMap ? .blue : .secondary)
                                            : .secondary
                                        )
                                        .frame(width: 34, height: 34)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(session.isVisibleOnMap ? "Hide track on map" : "Show track on map")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        app.muster.startSmartSession()
                        dismiss()
                    } label: {
                        Label("New Muster", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Previous Musters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
    }

    private var previousTracksVisibleBinding: Binding<Bool> {
        Binding(
            get: { app.muster.showPreviousTracksOnMap },
            set: { app.muster.setPreviousTracksVisible($0) }
        )
    }

    private func sessionDetailText(for session: MusterSession) -> String? {
        let minutes = Int(session.duration / 60)
        guard minutes > 0 else { return nil }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "Duration: \(hours)h \(remainingMinutes)m"
        } else {
            return "Duration: \(remainingMinutes)m"
        }
    }
}
