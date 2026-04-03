import Foundation
import CoreLocation

enum MarkerType: String, Codable, CaseIterable, Identifiable {
    case mob, gate, water, hazard, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mob: return "Mob"
        case .gate: return "Gate"
        case .water: return "Water"
        case .hazard: return "Hazard"
        case .custom: return "Custom"
        }
    }
}

struct TrackPoint: Codable, Identifiable {
    let id: UUID
    let t: Date
    let lat: Double
    let lon: Double
    let speed: Double
    let course: Double
    let accuracy: Double

    init(location: CLLocation) {
        self.id = UUID()
        self.t = Date()
        self.lat = location.coordinate.latitude
        self.lon = location.coordinate.longitude
        self.speed = max(0, location.speed) // m/s (can be -1)
        self.course = location.course       // degrees (can be -1)
        self.accuracy = location.horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct Marker: Codable, Identifiable {
    let id: UUID
    let t: Date
    let lat: Double
    let lon: Double
    let type: MarkerType
    let note: String?

    init(coordinate: CLLocationCoordinate2D, type: MarkerType, note: String?) {
        self.id = UUID()
        self.t = Date()
        self.lat = coordinate.latitude
        self.lon = coordinate.longitude
        self.type = type
        self.note = note
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct MusterSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var points: [TrackPoint]
    var markers: [Marker]

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.startedAt = Date()
        self.endedAt = nil
        self.points = []
        self.markers = []
    }

    var isActive: Bool { endedAt == nil }
}
