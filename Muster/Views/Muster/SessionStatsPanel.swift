import SwiftUI
import CoreLocation

struct SessionStatsPanel: View {
    let session: MusterSession
    let now: Date = Date()

    var body: some View {
        let stats = SessionStats.compute(for: session, now: now)

        HStack(spacing: 10) {
            statChip(title: "Distance", value: stats.distanceText)
            statChip(title: "Duration", value: stats.durationText)
            statChip(title: "Avg", value: stats.avgSpeedText)
            statChip(title: "Markers", value: stats.markersText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Computation

struct SessionStats: Equatable {
    var distanceMeters: Double
    var durationSeconds: Double
    var markersCount: Int

    var distanceText: String {
        guard distanceMeters > 0 else { return "—" }
        return UnitFormatting.formattedDistance(distanceMeters, decimalsIfLarge: 2)
    }

    var durationText: String {
        guard durationSeconds > 0 else { return "—" }
        let total = Int(durationSeconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var avgSpeedText: String {
        guard durationSeconds > 0, distanceMeters > 0 else { return "—" }
        let mps = distanceMeters / durationSeconds
        return UnitFormatting.formattedSpeed(fromMetersPerSecond: mps, decimals: 1)
    }

    var markersText: String { "\(markersCount)" }

    static func compute(for session: MusterSession, now: Date) -> SessionStats {
        let pts = session.points.sorted(by: { $0.t < $1.t })
        let distance = Self.totalDistanceMeters(points: pts)
        let duration = Self.durationSeconds(points: pts, session: session, now: now)
        return SessionStats(
            distanceMeters: distance,
            durationSeconds: duration,
            markersCount: session.markers.count
        )
    }

    private static func totalDistanceMeters(points: [TrackPoint]) -> Double {
        guard points.count >= 2 else { return 0 }

        var total: Double = 0
        var prev = CLLocation(latitude: points[0].lat, longitude: points[0].lon)

        for p in points.dropFirst() {
            let cur = CLLocation(latitude: p.lat, longitude: p.lon)
            total += cur.distance(from: prev)
            prev = cur
        }
        return total
    }

    private static func durationSeconds(points: [TrackPoint], session: MusterSession, now: Date) -> Double {
        if let first = points.first?.t {
            let end = (session.isActive ? now : (points.last?.t ?? now))
            return max(0, end.timeIntervalSince(first))
        } else {
            // No points yet: show time since started if active, otherwise 0
            if session.isActive {
                return max(0, now.timeIntervalSince(session.startedAt))
            }
            return 0
        }
    }
}
