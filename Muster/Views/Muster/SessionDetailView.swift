import SwiftUI
import CoreLocation
import UIKit

// Shared keys (must match MapMainView / SettingsView)
private let kRingCountKey = "rings_count"              // Int
private let kRingSpacingKey = "rings_spacing_m"        // Double
private let kRingColorKey = "rings_color"              // String
private let kRingDistanceLabelsEnabledKey = "rings_distance_labels_enabled" // Bool
private let kMapOrientationKey = "map_orientation"     // String: "headsUp" | "northUp"

struct SessionDetailView: View {
    @EnvironmentObject private var app: AppState
    let sessionID: UUID

    @StateObject private var location = LocationService()
    @State private var followUser = true
    @State private var showMarkerSheet = false
    @State private var metersPerPoint: Double = 1.0
    @State private var showArrivedBanner = false
    @State private var fitRadiosNonce: Int = 0

    @State private var selectedSessionMarker: MusterMarker?
    @State private var selectedMapMarker: MapMarker?
    @State private var showSessionMarkerActions = false
    @State private var showMapMarkerActions = false

    // Persisted ring + orientation settings
    @AppStorage(kRingCountKey) private var ringCount: Int = 4
    @AppStorage(kRingSpacingKey) private var ringSpacingM: Double = 100
    @AppStorage(kRingColorKey) private var ringColorRaw: String = "blue"
    @AppStorage(kRingDistanceLabelsEnabledKey) private var ringDistanceLabelsEnabled: Bool = true
    @AppStorage(kMapOrientationKey) private var orientationRaw: String = "headsUp"

    // Trigger to force recenter in MKMapView
    @State private var recenterNonce: Int = 0

    // Go To / Destination
    @State private var gotoTarget: MusterMarker? = nil

    private var session: MusterSession? {
        app.muster.sessions.first(where: { $0.id == sessionID })
    }

    // =========================================================
    // MARK: - Layers
    // =========================================================

    private var mapLayer: some View {
        MapViewRepresentable(
            followUser: $followUser,
            activeTrackPoints: session?.points ?? [],
            previousSessions: [],
            markers: session?.markers ?? [],
            mapMarkers: app.muster.mapMarkers,
            xrsContacts: app.xrs.allContacts,
            xrsTrailGroups: app.xrs.allContacts.compactMap { contact in
                let coords = app.xrs.trailPoints(for: contact.name).map(\.coordinate)
                return coords.count >= 2 ? coords : nil
            },
            xrsTrailColorRaw: UserDefaults.standard.string(forKey: "xrs_radio_trail_color") ?? "blue",
            importedBoundaries: app.muster.visibleImportedBoundaries,
            importedTracks: app.muster.visibleImportedTracks,
            importedMarkers: app.muster.visibleImportedMarkers,
            userLocation: location.lastLocation,
            userHeadingDegrees: location.headingDegrees,
            ringCount: ringCount,
            ringSpacingMeters: ringSpacingM,
            ringColorRaw: ringColorRaw,
            ringDistanceLabelsEnabled: ringDistanceLabelsEnabled,
            orientationRaw: $orientationRaw,
            mapStyleRaw: .constant("standard"),
            recenterNonce: $recenterNonce,
            fitRadiosNonce: $fitRadiosNonce,
            metersPerPoint: $metersPerPoint,
            activeTrackAppearanceRaw: .constant("altitude"),
            headsUpPitchDegrees: 45,
            headsUpUserVerticalOffset: 10,
            headsUpBottomObstructionHeight: 0,
            destinationCoordinate: gotoTarget?.coordinate,
            activeDestinationMarkerID: gotoTarget?.id,
            onRequestGoToMarker: { marker in
                gotoTarget = marker
            },
            onArriveAtDestination: {
                gotoTarget = nil
                showArrivedBanner = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showArrivedBanner = false
                }

                UINotificationFeedbackGenerator().notificationOccurred(.success)
            },
            onLongPressAtCoordinate: { _ in },
            onTapSessionMarker: { marker in
                gotoTarget = marker
            },
            onTapMapMarker: { _ in },
            onTapImportedMarker: { _ in },
            onLongPressSessionMarker: { marker in
                selectedMapMarker = nil
                selectedSessionMarker = marker
                showSessionMarkerActions = true
            },
            onLongPressMapMarker: { marker in
                selectedSessionMarker = nil
                selectedMapMarker = marker
                showMapMarkerActions = true
            }
        )
        .ignoresSafeArea()
    }

    private var overlayLayer: some View {
        VStack(spacing: 10) {
            GlassPill {
                HStack(spacing: 10) {
                    Text(session?.isActive == true ? "Recording" : "Idle")
                        .font(.headline)

                    Spacer()

                    if let loc = location.lastLocation {
                        Text(String(format: "acc %.0fm", loc.horizontalAccuracy))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No GPS")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            destinationPill

            if let s = session {
                GlassCard {
                    SessionStatsPanel(session: s)
                }
            }

            GlassCard {
                HStack(spacing: 10) {
                    quickMarkerButton("Gate", "door.left.hand.open", .gate)
                    quickMarkerButton("Yard", "square.grid.2x2.fill", .yard)
                    quickMarkerButton("Water", "drop.fill", .water)
                    quickMarkerButton("Issue", "exclamationmark.triangle.fill", .issue)

                    Button {
                        showMarkerSheet = true
                    } label: {
                        Label("Note", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }

            GlassCard {
                HStack(spacing: 10) {
                    Button {
                        followUser.toggle()
                        if followUser { recenterNonce &+= 1 }
                    } label: {
                        Label(
                            followUser ? "Following" : "Free",
                            systemImage: followUser ? "location.fill" : "location"
                        )
                    }
                    .buttonStyle(GlassButtonStyle())

                    Spacer()

                    Button {
                        recenterNonce &+= 1
                    } label: {
                        Label("Center", systemImage: "scope")
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button {
                        showMarkerSheet = true
                    } label: {
                        Label("Marker", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(GlassButtonStyle())

                    if session?.isActive == true {
                        Button(role: .destructive) {
                            app.muster.stopActiveSession()
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
            }

            if let err = location.lastError {
                GlassPill {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            overlayLayer

            if showArrivedBanner {
                VStack {
                    GlassPill {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)

                            Text("Arrived at Target")
                                .font(.headline)
                        }
                    }
                    .padding(.top, 12)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showArrivedBanner)
        .navigationTitle(session?.name ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMarkerSheet) {
            MarkerSheet(
                templates: app.muster.markerTemplates
            ) { template, name in
                guard let coordinate = location.lastLocation?.coordinate else { return }

                app.muster.addMapMarker(
                    coordinate: coordinate,
                    templateID: template.id,
                    name: name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                )

                showMarkerSheet = false
            }
            .environmentObject(app)
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            selectedSessionMarker?.displayTitle ?? "Marker",
            isPresented: $showSessionMarkerActions,
            titleVisibility: .visible
        ) {
            Button("Go to") {
                if let marker = selectedSessionMarker {
                    gotoTarget = marker
                }
            }

            Button("Delete", role: .destructive) {
                guard let marker = selectedSessionMarker else { return }
                deleteSessionMarker(marker)
                selectedSessionMarker = nil
            }

            Button("Cancel", role: .cancel) {
                selectedSessionMarker = nil
            }
        }
        .confirmationDialog(
            selectedMapMarker?.displayTitle ?? "Marker",
            isPresented: $showMapMarkerActions,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let marker = selectedMapMarker else { return }
                deleteMapMarker(marker)
                selectedMapMarker = nil
            }

            Button("Cancel", role: .cancel) {
                selectedMapMarker = nil
            }
        }
        .onAppear {
            location.start()
            if session?.isActive == true {
                app.muster.activeSessionID = sessionID
            }
        }
        .onDisappear {
            location.stop()
        }
        .onChange(of: location.lastLocation) { _, newLoc in
            guard let loc = newLoc else { return }
            if session?.isActive == true {
                app.muster.activeSessionID = sessionID
                app.muster.considerRecording(location: loc)
            }
        }
    }

    // =========================================================
    // MARK: - Destination pill
    // =========================================================

    @ViewBuilder
    private var destinationPill: some View {
        if let target = gotoTarget,
           let userLoc = location.lastLocation {

            let targetLoc = CLLocation(latitude: target.lat, longitude: target.lon)
            let distanceM = userLoc.distance(from: targetLoc)

            let gpsSpeed = userLoc.speed
            let speed = gpsSpeed > 0.5 ? gpsSpeed : 1.39
            let etaSec = distanceM / max(0.5, speed)

            let distanceText: String = {
                if distanceM >= 1000 {
                    return String(format: "%.2f km", distanceM / 1000.0)
                }
                return String(format: "%.0f m", distanceM)
            }()

            let etaText: String = formatETA(seconds: etaSec)

            GlassPill {
                HStack(spacing: 10) {
                    Image(systemName: target.type.symbol)
                        .font(.headline)

                    Text("To \(target.displayTitle)")
                        .font(.headline)

                    Spacer()

                    Text(distanceText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("ETA \(etaText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        gotoTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            EmptyView()
        }
    }

    private func formatETA(seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60

        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(max(1, m))m"
    }

    // =========================================================
    // MARK: - Quick marker helper
    // =========================================================

    private func quickMarkerButton(_ title: String, _ system: String, _ type: MarkerType) -> some View {
        Button {
            guard let c = location.lastLocation?.coordinate else { return }
            app.muster.activeSessionID = sessionID
            app.muster.dropMarker(at: c, type: type, note: nil)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label(title, systemImage: system)
        }
        .buttonStyle(GlassButtonStyle())
    }

    // =========================================================
    // MARK: - Marker deletion helpers
    // =========================================================

    private func deleteSessionMarker(_ marker: MusterMarker) {
        guard var session = session else { return }
        session.markers.removeAll { $0.id == marker.id }

        if let index = app.muster.sessions.firstIndex(where: { $0.id == session.id }) {
            app.muster.sessions[index] = session
        }
    }

    private func deleteMapMarker(_ marker: MapMarker) {
        app.muster.mapMarkers.removeAll { $0.id == marker.id }
    }
}
