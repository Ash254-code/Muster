import ActivityKit
import Foundation
import CoreLocation

struct GoToMarkerAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {

        enum PresentationMode: String, Codable, Hashable {
            case goTo
            case recording
        }

        var distanceMeters: Double
        var relativeBearingDegrees: Double
        var arrived: Bool

        // Temporary radio override shown in Dynamic Island / Live Activity.
        var radioUser: String?
        var radioDistanceMeters: Double?
        var radioRelativeBearingDegrees: Double?

        // Recording mode support.
        var presentationMode: PresentationMode = .goTo
        var recordingActive: Bool = false
        var recordingDistanceMeters: Double? = nil
    }

    var markerName: String
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
