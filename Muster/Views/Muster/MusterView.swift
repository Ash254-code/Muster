import SwiftUI

struct MusterView: View {
    @EnvironmentObject private var app: AppState

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
                                app.muster.startSmartSession()
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
    }
}
