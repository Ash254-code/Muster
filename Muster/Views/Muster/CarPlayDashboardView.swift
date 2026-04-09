import SwiftUI
import CoreLocation

struct CarPlayDashboardView: View {
    @EnvironmentObject private var app: AppState

    private var activeSession: MusterSession? {
        app.muster.activeSession
    }

    private var activeTrackDistanceText: String {
        guard let session = activeSession else { return "0.0 km" }
        let metres = totalDistanceMeters(points: session.points)
        let kilometres = max(0, metres / 1000)
        return String(format: "%.1f km", kilometres)
    }

    private var markerCountText: String {
        let count = activeSession?.markers.count ?? 0
        return "\(count)"
    }

    private var radioStatusText: String {
        app.xrs.isConnected ? "Connected" : "Offline"
    }

    private var radioStatusColor: Color {
        app.xrs.isConnected ? .green : .orange
    }

    private var contactCountText: String {
        "\(app.xrs.allContacts.count)"
    }

    private var dayDistanceText: String {
        app.muster.kilometresForDayText
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.1, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                statsGrid
                sessionActionButton
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Muster")
                .font(.system(size: 42, weight: .bold, design: .rounded))

            Text(activeSession?.name ?? "No active track")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                carPlayStatCard(title: "Track", value: activeTrackDistanceText, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                carPlayStatCard(title: "Markers", value: markerCountText, systemImage: "mappin.and.ellipse")
            }

            HStack(spacing: 12) {
                carPlayStatCard(title: "Today", value: dayDistanceText, systemImage: "calendar")
                carPlayStatCard(title: "Radio", value: radioStatusText, subtitle: "\(contactCountText) contacts", systemImage: "dot.radiowaves.left.and.right", accent: radioStatusColor)
            }
        }
    }

    @ViewBuilder
    private func carPlayStatCard(
        title: String,
        value: String,
        subtitle: String? = nil,
        systemImage: String,
        accent: Color = .blue
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.7), lineWidth: 2)
        )
    }


    private func totalDistanceMeters(points: [TrackPoint]) -> Double {
        guard points.count > 1 else { return 0 }

        var total: Double = 0
        for index in 1..<points.count {
            let previous = CLLocation(latitude: points[index - 1].lat, longitude: points[index - 1].lon)
            let current = CLLocation(latitude: points[index].lat, longitude: points[index].lon)
            total += previous.distance(from: current)
        }

        return total
    }

    private var sessionActionButton: some View {
        Button {
            if activeSession != nil {
                app.muster.stopActiveSession()
            } else {
                _ = app.muster.startSession(name: "CarPlay Session")
            }
        } label: {
            Text(activeSession == nil ? "Start Session" : "Stop Session")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(activeSession == nil ? Color.green : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(activeSession == nil && !app.muster.canStartMusterOrTrack)
        .opacity(activeSession == nil && !app.muster.canStartMusterOrTrack ? 0.45 : 1)
    }
}

#Preview {
    CarPlayDashboardView()
        .environmentObject(AppState())
}
