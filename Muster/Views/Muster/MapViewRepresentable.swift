import SwiftUI
import MapKit
import CoreLocation

// =====================================================
// MARK: - MapViewRepresentable (generic)
// =====================================================
// This avoids conflicts with your existing Marker / MarkerType / MusterMarker.
// You provide:
// - points: [CLLocationCoordinate2D]
// - markers: [Marker] (YOUR type)
// - markerInfo: closure mapping YOUR Marker -> coordinate/title/subtitle/glyph/tint
// =====================================================

struct MapViewRepresentable<Marker>: UIViewRepresentable {

    @Binding var followUser: Bool

    let points: [CLLocationCoordinate2D]
    let markers: [Marker]
    let userLocation: CLLocation?

    /// Map your marker model to display values.
    let markerInfo: (Marker) -> (coordinate: CLLocationCoordinate2D,
                                 title: String?,
                                 subtitle: String?,
                                 glyph: String?,
                                 tint: UIColor?)

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = .none
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {

        // Follow user
        if followUser, let loc = userLocation?.coordinate {
            let region = MKCoordinateRegion(
                center: loc,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
            if context.coordinator.lastCentered == nil ||
                context.coordinator.distance(from: context.coordinator.lastCentered!, to: loc) > 5 {
                map.setRegion(region, animated: true)
                context.coordinator.lastCentered = loc
            }
        }

        // Path
        map.removeOverlays(map.overlays)
        if points.count >= 2 {
            let line = MKPolyline(coordinates: points, count: points.count)
            map.addOverlay(line)
        }

        // Marker annotations
        let existing = map.annotations.compactMap { $0 as? AnyMarkerAnnotation }
        map.removeAnnotations(existing)

        let anns: [AnyMarkerAnnotation] = markers.map {
            let info = markerInfo($0)
            return AnyMarkerAnnotation(
                coordinate: info.coordinate,
                title: info.title,
                subtitle: info.subtitle,
                glyph: info.glyph,
                tint: info.tint
            )
        }
        map.addAnnotations(anns)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastCentered: CLLocationCoordinate2D?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                r.lineWidth = 4
                r.alpha = 0.9
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? AnyMarkerAnnotation else { return nil }

            let id = "marker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: ann, reuseIdentifier: id)

            view.annotation = ann

            view.canShowCallout = true
            if let tint = ann.tint { view.markerTintColor = tint }
            if let glyph = ann.glyph, !glyph.isEmpty { view.glyphText = glyph }

            return view
        }

        func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
            CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        }
    }
}

// =====================================================
// MARK: - AnyMarkerAnnotation
// =====================================================

final class AnyMarkerAnnotation: NSObject, MKAnnotation {

    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let glyph: String?
    let tint: UIColor?

    init(coordinate: CLLocationCoordinate2D,
         title: String?,
         subtitle: String?,
         glyph: String?,
         tint: UIColor?) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.glyph = glyph
        self.tint = tint
        super.init()
    }
}
