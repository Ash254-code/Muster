import SwiftUI
import CoreLocation

struct CurrentTrackView: View {
    let session: MusterSession?
    let currentLocation: CLLocation?

    @Environment(\.dismiss) private var dismiss

    private var points: [TrackPoint] {
        session?.points ?? []
    }

    private var hasTrack: Bool {
        points.count >= 2
    }

    private var totalDistanceMeters: CLLocationDistance {
        guard points.count >= 2 else { return 0 }

        var total: CLLocationDistance = 0
        for index in 1..<points.count {
            let previous = CLLocation(
                latitude: points[index - 1].lat,
                longitude: points[index - 1].lon
            )
            let current = CLLocation(
                latitude: points[index].lat,
                longitude: points[index].lon
            )
            total += current.distance(from: previous)
        }
        return total
    }

    private var elapsedTime: TimeInterval {
        guard let session else { return 0 }
        let end = session.endedAt ?? Date()
        return max(0, end.timeIntervalSince(session.startedAt))
    }

    private var pointAltitudes: [Double] {
        points.compactMap(\.elevationM)
    }

    private var currentElevationText: String {
        if let currentLocation {
            return "\(Int(currentLocation.altitude.rounded())) m"
        }

        if let last = points.last?.elevationM {
            return "\(Int(last.rounded())) m"
        }

        return "—"
    }

    private var currentPositionText: String {
        let coordinate: CLLocationCoordinate2D?

        if let currentLocation {
            coordinate = currentLocation.coordinate
        } else {
            coordinate = points.last?.coordinate
        }

        guard let coordinate else { return "—" }

        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private var altitudeGainMeters: Double {
        guard points.count >= 2 else { return 0 }

        var gain: Double = 0
        for index in 1..<points.count {
            guard let previous = points[index - 1].elevationM,
                  let current = points[index].elevationM else { continue }

            let delta = current - previous
            if delta > 0 {
                gain += delta
            }
        }
        return gain
    }

    private var altitudeLossMeters: Double {
        guard points.count >= 2 else { return 0 }

        var loss: Double = 0
        for index in 1..<points.count {
            guard let previous = points[index - 1].elevationM,
                  let current = points[index].elevationM else { continue }

            let delta = current - previous
            if delta < 0 {
                loss += abs(delta)
            }
        }
        return loss
    }

    private var segmentSpeedsKmh: [Double] {
        guard points.count >= 2 else { return [] }

        var result: [Double] = []

        for index in 1..<points.count {
            let previousPoint = points[index - 1]
            let currentPoint = points[index]

            let previous = CLLocation(latitude: previousPoint.lat, longitude: previousPoint.lon)
            let current = CLLocation(latitude: currentPoint.lat, longitude: currentPoint.lon)

            let distance = current.distance(from: previous)
            let dt = currentPoint.t.timeIntervalSince(previousPoint.t)

            guard dt > 0 else { continue }

            let metersPerSecond = distance / dt
            let kmh = max(0, metersPerSecond * 3.6)
            result.append(kmh)
        }

        return result
    }

    private var averageSpeedKmh: Double {
        let hours = elapsedTime / 3600
        guard hours > 0 else { return 0 }
        return (totalDistanceMeters / 1000) / hours
    }

    private var maxSpeedKmh: Double {
        segmentSpeedsKmh.max() ?? 0
    }

    private var movingTime: TimeInterval {
        guard points.count >= 2 else { return 0 }

        var total: TimeInterval = 0

        for index in 1..<points.count {
            let previousPoint = points[index - 1]
            let currentPoint = points[index]

            let previous = CLLocation(latitude: previousPoint.lat, longitude: previousPoint.lon)
            let current = CLLocation(latitude: currentPoint.lat, longitude: currentPoint.lon)

            let distance = current.distance(from: previous)
            let dt = currentPoint.t.timeIntervalSince(previousPoint.t)

            guard dt > 0 else { continue }

            let metersPerSecond = distance / dt
            if metersPerSecond >= 0.5 {
                total += dt
            }
        }

        return total
    }

    private var stoppedTime: TimeInterval {
        max(0, elapsedTime - movingTime)
    }

    private var movingAverageSpeedKmh: Double {
        let hours = movingTime / 3600
        guard hours > 0 else { return 0 }
        return (totalDistanceMeters / 1000) / hours
    }

    private var paceText: String {
        let distanceKm = totalDistanceMeters / 1000
        guard distanceKm > 0 else { return "—" }

        let secondsPerKm = elapsedTime / distanceKm
        guard secondsPerKm.isFinite else { return "—" }

        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    private var totalDistanceText: String {
        if totalDistanceMeters >= 1000 {
            return String(format: "%.2f km", totalDistanceMeters / 1000)
        } else {
            return "\(Int(totalDistanceMeters.rounded())) m"
        }
    }

    private var elapsedTimeText: String {
        formatDuration(elapsedTime)
    }

    private var movingTimeText: String {
        formatDuration(movingTime)
    }

    private var stoppedTimeText: String {
        formatDuration(stoppedTime)
    }

    private var avgSpeedText: String {
        String(format: "%.1f km/h", averageSpeedKmh)
    }

    private var movingAvgSpeedText: String {
        String(format: "%.1f km/h", movingAverageSpeedKmh)
    }

    private var maxSpeedText: String {
        String(format: "%.1f km/h", maxSpeedKmh)
    }

    private var altitudeDifferenceText: String {
        let delta = altitudeGainMeters - altitudeLossMeters
        let rounded = Int(delta.rounded())

        if rounded > 0 {
            return "+\(rounded) m"
        } else if rounded < 0 {
            return "\(rounded) m"
        } else {
            return "0 m"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if session == nil {
                    VStack(spacing: 14) {
                        Text("Current Track")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("No active session.")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            titleBlock

                            if hasTrack {
                                currentStatsCard
                                profilesCard
                            } else {
                                emptyTrackCard
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                topBar
            }
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Track")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(session?.name.isEmpty == false ? session!.name : "Ride Summary")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.22))
                        .frame(width: 48, height: 48)

                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [
                    .black.opacity(0.95),
                    .black.opacity(0.75),
                    .black.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 56)

            statHero(
                title: "Current Track",
                value: totalDistanceText,
                details: [
                    ("Current GPS Position", currentPositionText),
                    ("Current Elevation", currentElevationText)
                ]
            )
        }
    }

    private var currentStatsCard: some View {
        sectionCard(title: "Current Stats") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    statCard(title: "Elapsed Time", value: elapsedTimeText)
                    statCard(title: "Moving Time", value: movingTimeText)
                }

                HStack(spacing: 10) {
                    statCard(title: "Avg Speed", value: avgSpeedText)
                    statCard(title: "Max Speed", value: maxSpeedText)
                }

                HStack(spacing: 10) {
                    statCard(title: "Pace", value: paceText)
                    statCard(title: "Moving Avg", value: movingAvgSpeedText)
                }

                HStack(spacing: 10) {
                    statCard(title: "Stopped Time", value: stoppedTimeText)
                    statCard(title: "Altitude Diff", value: altitudeDifferenceText)
                }
            }
        }
    }

    private var profilesCard: some View {
        sectionCard(title: "Profiles") {
            VStack(spacing: 14) {
                compactChartSection(
                    title: "Elevation Profile",
                    values: pointAltitudes
                )

                compactChartSection(
                    title: "Speed Profile",
                    values: segmentSpeedsKmh
                )
            }
        }
    }

    private var emptyTrackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not enough track data yet")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Start moving and this page will fill with distance, speed, elevation, and ride summary data.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func compactChartSection(title: String, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if values.count >= 2 {
                ProfileChart(values: values)
                    .frame(height: 170)

                HStack {
                    Text("Start")
                    Spacer()
                    Text("Finish")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("Not enough data")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func statHero(
        title: String,
        value: String,
        details: [(String, String)] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if !details.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(details.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.0)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))

                            Text(item.1)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 78, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

private struct ProfileChart: View {
    let values: [Double]

    private var sampledValues: [Double] {
        guard values.count > 2 else { return values }

        let targetCount = min(32, max(12, values.count / 6))
        guard targetCount < values.count else { return values }

        var result: [Double] = []
        result.reserveCapacity(targetCount)

        for index in 0..<targetCount {
            let start = Int((Double(index) / Double(targetCount)) * Double(values.count))
            let end = Int((Double(index + 1) / Double(targetCount)) * Double(values.count))
            let safeEnd = max(start + 1, end)
            let bucket = Array(values[start..<min(safeEnd, values.count)])

            if bucket.isEmpty {
                result.append(values[min(start, values.count - 1)])
            } else {
                let average = bucket.reduce(0, +) / Double(bucket.count)
                result.append(average)
            }
        }

        return result
    }

    private var smoothedValues: [Double] {
        let source = sampledValues
        guard source.count >= 3 else { return source }

        return source.indices.map { index in
            let lower = max(0, index - 1)
            let upper = min(source.count - 1, index + 1)
            let window = source[lower...upper]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    private var normalizedValues: [Double] {
        let source = smoothedValues

        guard let minValue = source.min(),
              let maxValue = source.max() else { return [] }

        let range = max(maxValue - minValue, 0.0001)
        return source.map { ($0 - minValue) / range }
    }

    var body: some View {
        GeometryReader { geo in
            let points = normalizedValues
            let width = geo.size.width
            let height = geo.size.height
            let lineColor = Color.blue

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black.opacity(0.28))

                if points.count >= 2 {
                    Path { path in
                        for index in points.indices {
                            let x = width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                            let y = height * (1 - CGFloat(points[index]))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }

                        path.addLine(to: CGPoint(x: width, y: height))
                        path.addLine(to: CGPoint(x: 0, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                lineColor.opacity(0.30),
                                lineColor.opacity(0.08),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        for index in points.indices {
                            let x = width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                            let y = height * (1 - CGFloat(points[index]))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                let previousX = width * CGFloat(index - 1) / CGFloat(max(points.count - 1, 1))
                                let previousY = height * (1 - CGFloat(points[index - 1]))
                                let midX = (previousX + x) / 2

                                path.addCurve(
                                    to: CGPoint(x: x, y: y),
                                    control1: CGPoint(x: midX, y: previousY),
                                    control2: CGPoint(x: midX, y: y)
                                )
                            }
                        }
                    }
                    .stroke(
                        lineColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: lineColor.opacity(0.35), radius: 4, x: 0, y: 0)
                }
            }
        }
    }
}
