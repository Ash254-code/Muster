import SwiftUI

struct TPMSDashboardView: View {
    @EnvironmentObject private var tpmsStore: TPMSStore
    @EnvironmentObject private var tpmsBluetooth: TPMSBluetoothManager

    private enum VehicleMode: String, CaseIterable, Identifiable {
        case motorbike
        case car

        var id: String { rawValue }

        var title: String {
            switch self {
            case .motorbike: return "Motorbike"
            case .car: return "Car"
            }
        }
    }

    private enum TyrePosition: String, Identifiable, CaseIterable {
        case frontLeft
        case frontRight
        case rearLeft
        case rearRight
        case front
        case rear
        case spare1
        case spare2

        var id: String { rawValue }

        var shortLabel: String {
            switch self {
            case .frontLeft: return "FL"
            case .frontRight: return "FR"
            case .rearLeft: return "RL"
            case .rearRight: return "RR"
            case .front: return "Front"
            case .rear: return "Rear"
            case .spare1: return "Spare 1"
            case .spare2: return "Spare 2"
            }
        }

        var title: String {
            switch self {
            case .frontLeft: return "Front Left"
            case .frontRight: return "Front Right"
            case .rearLeft: return "Rear Left"
            case .rearRight: return "Rear Right"
            case .front: return "Front"
            case .rear: return "Rear"
            case .spare1: return "Spare 1"
            case .spare2: return "Spare 2"
            }
        }
    }

    private struct TyreReading: Identifiable {
        let id = UUID()
        let position: TyrePosition
        let pressurePSI: Int?
        let temperatureC: Int?
        let isAlerting: Bool
        let isConnected: Bool
    }

    @State private var pairedSensorCount: Int = 4
    @State private var forceVehicleMode: VehicleMode? = nil
    @State private var showSettings = false

    private var resolvedVehicleMode: VehicleMode {
        if let forceVehicleMode { return forceVehicleMode }
        return pairedSensorCount == 2 ? .motorbike : .car
    }

    private var roadTyres: [TyreReading] {
        switch resolvedVehicleMode {
        case .motorbike:
            return [
                TyreReading(position: .front, pressurePSI: 34, temperatureC: 38, isAlerting: false, isConnected: true),
                TyreReading(position: .rear, pressurePSI: 40, temperatureC: 41, isAlerting: false, isConnected: true)
            ]

        case .car:
            let readings: [TyreReading] = [
                TyreReading(position: .frontLeft, pressurePSI: 32, temperatureC: 39, isAlerting: false, isConnected: true),
                TyreReading(position: .frontRight, pressurePSI: 31, temperatureC: 40, isAlerting: false, isConnected: true),
                TyreReading(position: .rearLeft, pressurePSI: 29, temperatureC: 43, isAlerting: true, isConnected: true),
                TyreReading(position: .rearRight, pressurePSI: 33, temperatureC: 41, isAlerting: false, isConnected: true)
            ]
            return Array(readings.prefix(min(pairedSensorCount, 4)))
        }
    }

    private var spareTyres: [TyreReading] {
        guard pairedSensorCount > 4 else { return [] }

        let spares: [TyreReading] = [
            TyreReading(position: .spare1, pressurePSI: 36, temperatureC: 31, isAlerting: false, isConnected: true),
            TyreReading(position: .spare2, pressurePSI: 35, temperatureC: 30, isAlerting: false, isConnected: true)
        ]

        let spareCount = min(max(pairedSensorCount - 4, 0), 2)
        return Array(spares.prefix(spareCount))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                vehicleLayoutCard

                if !spareTyres.isEmpty {
                    sparesCard
                }

                pairedSensorsCard
                demoControlsCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("TPMS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("TPMS Settings")
            }
        }
        .navigationDestination(isPresented: $showSettings) {
            TPMSSettingsView()
                .environmentObject(tpmsStore)
                .environmentObject(tpmsBluetooth)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tyre Pressures")
                        .font(.title3.weight(.semibold))

                    Text("Last updated just now")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 10) {
                statPill(
                    title: "Paired",
                    value: "\(pairedSensorCount)",
                    systemImage: "sensor.tag.radiowaves.forward"
                )

                statPill(
                    title: "Mode",
                    value: resolvedVehicleMode.title,
                    systemImage: resolvedVehicleMode == .car ? "car.fill" : "motorcycle"
                )
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func statPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var vehicleLayoutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live Layout")
                    .font(.headline.weight(.semibold))
                Spacer()
            }

            if resolvedVehicleMode == .car {
                carDashboardLayout
            } else {
                motorbikeDashboardLayout
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var carDashboardLayout: some View {
        HStack(spacing: 12) {
            VStack(spacing: 10) {
                tyrePanel(for: tyre(at: .frontLeft))
                tyrePanel(for: tyre(at: .rearLeft))
            }
            .frame(maxWidth: .infinity)

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 112, height: 214)

                carSilhouetteModern
            }
            .frame(width: 124)

            VStack(spacing: 10) {
                tyrePanel(for: tyre(at: .frontRight))
                tyrePanel(for: tyre(at: .rearRight))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var motorbikeDashboardLayout: some View {
        HStack(spacing: 14) {
            VStack(spacing: 10) {
                tyrePanel(for: tyre(at: .front))
                tyrePanel(for: tyre(at: .rear))
            }
            .frame(maxWidth: .infinity)

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 112, height: 214)

                motorbikeSilhouetteModern
            }
            .frame(width: 124)
        }
    }

    private func tyre(at position: TyrePosition) -> TyreReading? {
        (roadTyres + spareTyres).first(where: { $0.position == position })
    }

    @ViewBuilder
    private func tyrePanel(for tyre: TyreReading?) -> some View {
        let isAlerting = tyre?.isAlerting ?? false
        let isConnected = tyre?.isConnected ?? false

        let backgroundColor: Color = {
            if !isConnected { return Color(.systemBackground).opacity(0.92) }
            return isAlerting ? Color.red.opacity(0.14) : Color.green.opacity(0.14)
        }()

        let borderColor: Color = {
            if !isConnected { return Color.primary.opacity(0.08) }
            return isAlerting ? Color.red.opacity(0.50) : Color.green.opacity(0.50)
        }()

        let valueColor: Color = {
            if !isConnected { return .primary }
            return isAlerting ? .red : .green
        }()

        VStack(alignment: .leading, spacing: 8) {
            Text(tyre?.position.title ?? "Not Set")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(tyre?.pressurePSI.map { "\($0) psi" } ?? "-- psi")
                .font(.headline.weight(.bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(tyre?.temperatureC.map { UnitFormatting.formattedTemperature(Double($0), includeUnit: true) } ?? "--°")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !isConnected {
                Text("Offline")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var sparesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spares")
                .font(.headline.weight(.semibold))

            VStack(spacing: 10) {
                ForEach(spareTyres) { tyre in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill((tyre.isAlerting ? Color.red : Color.blue).opacity(0.12))
                                .frame(width: 34, height: 34)

                            Image(systemName: "tirepressure")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tyre.isAlerting ? .red : .blue)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(tyre.position.shortLabel)
                                .font(.subheadline.weight(.semibold))

                            Text(detailText(for: tyre))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if tyre.isAlerting {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var pairedSensorsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paired Sensors")
                .font(.headline.weight(.semibold))

            VStack(spacing: 10) {
                ForEach(roadTyres + spareTyres) { tyre in
                    HStack(spacing: 12) {
                        Text(tyre.position.shortLabel)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 60, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tyre.position.title)
                                .font(.footnote.weight(.medium))

                            Text(detailText(for: tyre))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Circle()
                            .fill(tyre.isAlerting ? .red : (tyre.isConnected ? .green : .secondary.opacity(0.4)))
                            .frame(width: 10, height: 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var demoControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Demo Layout")
                .font(.headline.weight(.semibold))

            Text("Temporary controls so we can see how the page looks with different sensor counts.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                demoButton("Bike") {
                    pairedSensorCount = 2
                    forceVehicleMode = nil
                }

                demoButton("Car") {
                    pairedSensorCount = 4
                    forceVehicleMode = nil
                }

                demoButton("Car + 2 Spares") {
                    pairedSensorCount = 6
                    forceVehicleMode = nil
                }
            }

            HStack(spacing: 10) {
                demoButton("Force Bike") {
                    forceVehicleMode = .motorbike
                    if pairedSensorCount < 2 { pairedSensorCount = 2 }
                }

                demoButton("Force Car") {
                    forceVehicleMode = .car
                    if pairedSensorCount < 4 { pairedSensorCount = 4 }
                }

                demoButton("Auto") {
                    forceVehicleMode = nil
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func demoButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
    }

    private func detailText(for tyre: TyreReading) -> String {
        let pressure = tyre.pressurePSI.map { "\($0) psi" } ?? "-- psi"
        let temp = tyre.temperatureC.map { UnitFormatting.formattedTemperature(Double($0), includeUnit: true) } ?? "--°"
        return "\(pressure) • \(temp)"
    }

    private var carSilhouetteModern: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.16),
                            Color.primary.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 60, height: 158)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.55))
                .frame(width: 40, height: 58)
                .offset(y: -28)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                .frame(width: 34, height: 50)
                .offset(y: -28)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.16))
                .frame(width: 15, height: 34)
                .offset(x: -39, y: -42)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.16))
                .frame(width: 15, height: 34)
                .offset(x: 39, y: -42)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.16))
                .frame(width: 15, height: 34)
                .offset(x: -39, y: 42)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.16))
                .frame(width: 15, height: 34)
                .offset(x: 39, y: 42)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 18, height: 6)
                .offset(y: -72)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 18, height: 6)
                .offset(y: 72)
        }
    }

    private var motorbikeSilhouetteModern: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 7)
                .frame(width: 40, height: 40)
                .offset(y: -62)

            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 7)
                .frame(width: 40, height: 40)
                .offset(y: 62)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 22, height: 110)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 14, height: 44)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 46, height: 8)
                .rotationEffect(.degrees(-24))
                .offset(x: 12, y: -32)

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 38, height: 8)
                .rotationEffect(.degrees(24))
                .offset(x: -8, y: 18)
        }
    }
}

#Preview {
    let store = TPMSStore()

    NavigationStack {
        TPMSDashboardView()
            .environmentObject(store)
            .environmentObject(TPMSBluetoothManager(tpmsStore: store))
    }
}
