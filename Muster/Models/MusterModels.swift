import Foundation
import CoreLocation

// =========================================================
// MARK: - Shared Coordinate Helpers
// =========================================================

struct CodableCoordinate: Codable, Hashable {
    var lat: Double
    var lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.lat = coordinate.latitude
        self.lon = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// =========================================================
// MARK: - Marker Template Models
// =========================================================

struct MarkerTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var description: String
    var emoji: String

    var displayTitle: String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Marker" : trimmed
    }
}

// =========================================================
// MARK: - Global Map Marker
// =========================================================

struct MapMarker: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var lat: Double
    var lon: Double

    /// Link back to the template if it still exists
    var templateID: UUID? = nil

    /// Snapshots so old markers still display correctly if template changes later
    var templateDescription: String
    var emoji: String

    /// User-entered name for this specific placed marker
    var name: String

    /// Marker belongs to a specific map set and is shown only when that set is selected.
    var mapSetID: UUID? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        let fallback = templateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "Marker" : fallback
    }
}

// =========================================================
// MARK: - Imported Map Data Models
// =========================================================

enum ImportedFileFormat: String, Codable, CaseIterable, Hashable {
    case geojson
    case gpx
    case kml
    case kmz
    case unknown

    var title: String {
        rawValue.uppercased()
    }
}

enum ImportedGeometryKind: String, Codable, CaseIterable, Hashable {
    case point
    case lineString
    case polygon
    case multiPolygon
}

// =========================================================
// MARK: - Import Colour Presets
// =========================================================

enum ImportColorPreset: String, Codable, CaseIterable, Hashable, Identifiable {
    case orange
    case amber
    case yellow
    case lime
    case green
    case mint
    case teal
    case cyan
    case sky
    case blue
    case indigo
    case purple
    case pink
    case red
    case brown
    case gray
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orange: return "Orange"
        case .amber: return "Amber"
        case .yellow: return "Yellow"
        case .lime: return "Lime"
        case .green: return "Green"
        case .mint: return "Mint"
        case .teal: return "Teal"
        case .cyan: return "Cyan"
        case .sky: return "Sky"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .brown: return "Brown"
        case .gray: return "Gray"
        case .black: return "Black"
        }
    }

    /// Strong line / outline colour
    var strokeHex: String {
        switch self {
        case .orange: return "#FF9500"
        case .amber:  return "#FFB300"
        case .yellow: return "#FFD60A"
        case .lime:   return "#9ACD32"
        case .green:  return "#34C759"
        case .mint:   return "#00C7BE"
        case .teal:   return "#30B0C7"
        case .cyan:   return "#32ADE6"
        case .sky:    return "#64D2FF"
        case .blue:   return "#0A84FF"
        case .indigo: return "#5856D6"
        case .purple: return "#AF52DE"
        case .pink:   return "#FF2D55"
        case .red:    return "#FF3B30"
        case .brown:  return "#A2845E"
        case .gray:   return "#8E8E93"
        case .black:  return "#1C1C1E"
        }
    }

    /// Soft translucent fill for polygons
    var fillHex: String {
        switch self {
        case .orange: return "#FF950033"
        case .amber:  return "#FFB30033"
        case .yellow: return "#FFD60A33"
        case .lime:   return "#9ACD3233"
        case .green:  return "#34C75933"
        case .mint:   return "#00C7BE33"
        case .teal:   return "#30B0C733"
        case .cyan:   return "#32ADE633"
        case .sky:    return "#64D2FF33"
        case .blue:   return "#0A84FF33"
        case .indigo: return "#5856D633"
        case .purple: return "#AF52DE33"
        case .pink:   return "#FF2D5533"
        case .red:    return "#FF3B3033"
        case .brown:  return "#A2845E33"
        case .gray:   return "#8E8E9333"
        case .black:  return "#1C1C1E33"
        }
    }

    static var allPaletteOptions: [ImportColorPreset] {
        allCases
    }
}

// =========================================================
// MARK: - Import Categories / Styling / Filtering
// =========================================================

enum ImportCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case boundaries
    case tracks
    case waterPoints
    case yards
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boundaries: return "Boundaries"
        case .tracks: return "Tracks"
        case .waterPoints: return "Water Points"
        case .yards: return "Yards"
        case .other: return "Other"
        }
    }

    var defaultIcon: String {
        switch self {
        case .boundaries: return "◻️"
        case .tracks: return "🛣️"
        case .waterPoints: return "💧"
        case .yards: return "🔸"
        case .other: return "📍"
        }
    }

    var defaultStrokeHex: String? {
        switch self {
        case .boundaries:
            return ImportColorPreset.orange.strokeHex
        case .tracks:
            return "#1E3A8A"
        case .waterPoints, .yards, .other:
            return nil
        }
    }

    var defaultFillHex: String? {
        switch self {
        case .boundaries:
            return ImportColorPreset.orange.fillHex
        case .tracks, .waterPoints, .yards, .other:
            return nil
        }
    }

    var defaultPreset: ImportColorPreset? {
        switch self {
        case .boundaries:
            return .orange
        case .tracks:
            return .blue
        case .waterPoints, .yards, .other:
            return nil
        }
    }

    var availableColorPresets: [ImportColorPreset] {
        supportsColor ? ImportColorPreset.allPaletteOptions : []
    }

    var supportsColor: Bool {
        switch self {
        case .boundaries, .tracks:
            return true
        case .waterPoints, .yards, .other:
            return false
        }
    }

    var isMarkerCategory: Bool {
        switch self {
        case .waterPoints, .yards, .other:
            return true
        case .boundaries, .tracks:
            return false
        }
    }
}

struct ImportCategoryStyle: Codable, Hashable {
    var category: ImportCategory
    var icon: String
    var strokeHex: String? = nil
    var fillHex: String? = nil

    init(
        category: ImportCategory,
        icon: String? = nil,
        strokeHex: String? = nil,
        fillHex: String? = nil
    ) {
        self.category = category
        self.icon = icon ?? category.defaultIcon
        self.strokeHex = strokeHex ?? category.defaultStrokeHex
        self.fillHex = fillHex ?? category.defaultFillHex
    }

    init(
        category: ImportCategory,
        icon: String? = nil,
        preset: ImportColorPreset
    ) {
        self.category = category
        self.icon = icon ?? category.defaultIcon

        if category.supportsColor {
            self.strokeHex = preset.strokeHex
            self.fillHex = (category == .boundaries) ? preset.fillHex : nil
        } else {
            self.strokeHex = nil
            self.fillHex = nil
        }
    }

    var resolvedStrokeHex: String? {
        strokeHex ?? category.defaultStrokeHex
    }

    var resolvedFillHex: String? {
        fillHex ?? category.defaultFillHex
    }

    mutating func applyColorPreset(_ preset: ImportColorPreset) {
        guard category.supportsColor else { return }
        strokeHex = preset.strokeHex
        fillHex = (category == .boundaries) ? preset.fillHex : nil
    }

    mutating func resetToCategoryDefaultStyle() {
        icon = category.defaultIcon
        strokeHex = category.defaultStrokeHex
        fillHex = category.defaultFillHex
    }

    var selectedPreset: ImportColorPreset? {
        guard category.supportsColor else { return nil }

        return ImportColorPreset.allCases.first {
            $0.strokeHex.caseInsensitiveCompare(resolvedStrokeHex ?? "") == .orderedSame
        }
    }
}

struct ImportCategoryVisibility: Codable, Hashable {
    var boundaries: Bool = true
    var tracks: Bool = true
    var waterPoints: Bool = true
    var yards: Bool = true
    var other: Bool = true

    func isVisible(_ category: ImportCategory) -> Bool {
        switch category {
        case .boundaries: return boundaries
        case .tracks: return tracks
        case .waterPoints: return waterPoints
        case .yards: return yards
        case .other: return other
        }
    }

    mutating func setVisible(_ visible: Bool, for category: ImportCategory) {
        switch category {
        case .boundaries: boundaries = visible
        case .tracks: tracks = visible
        case .waterPoints: waterPoints = visible
        case .yards: yards = visible
        case .other: other = visible
        }
    }
}

struct CustomImportCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var icon: String
    var isVisibleByDefault: Bool = true
}

extension Array where Element == ImportCategoryStyle {
    static var `default`: [ImportCategoryStyle] {
        ImportCategory.allCases.map { category in
            if let preset = category.defaultPreset {
                return ImportCategoryStyle(category: category, preset: preset)
            } else {
                return ImportCategoryStyle(category: category)
            }
        }
    }

    func style(for category: ImportCategory) -> ImportCategoryStyle {
        first(where: { $0.category == category }) ?? {
            if let preset = category.defaultPreset {
                return ImportCategoryStyle(category: category, preset: preset)
            } else {
                return ImportCategoryStyle(category: category)
            }
        }()
    }
}

// =========================================================
// MARK: - Imported Items
// =========================================================

struct ImportedBoundary: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// Name from source file if available
    var name: String

    /// Category used by map filters / styling
    var category: ImportCategory = .boundaries

    /// Original geometry kind from file
    var geometryKind: ImportedGeometryKind = .polygon

    /// For a single polygon this is one ring.
    /// For multi-polygons this can contain multiple outer rings.
    /// Keeping it simple for v1: each inner array is a ring to draw.
    var rings: [[CodableCoordinate]]

    /// Optional styling saved from source / future app editing
    var strokeHex: String? = nil
    var fillHex: String? = nil

    /// Visibility toggle
    var isVisible: Bool = true

    /// Optional grouping in a named map set
    var mapSetID: UUID? = nil

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Boundary" : trimmed
    }

    var allCoordinates: [CLLocationCoordinate2D] {
        rings.flatMap { $0.map(\.clCoordinate) }
    }
}

struct ImportedMarker: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var name: String

    /// Category used by map filters / styling.
    /// Imported points should generally be assigned to:
    /// - .waterPoints
    /// - .yards
    /// - .other
    var category: ImportCategory = .other

    var markerType: String? = nil
    var note: String? = nil
    var emoji: String? = nil

    var lat: Double
    var lon: Double

    var isVisible: Bool = true

    /// Optional grouping in a named map set
    var mapSetID: UUID? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        let fallback = markerType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? "Imported Marker" : fallback
    }
}

struct ImportedTrack: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var name: String

    /// Category used by map filters / styling
    var category: ImportCategory = .tracks

    var points: [CodableCoordinate]

    /// Source metadata if available
    var startedAt: Date? = nil
    var endedAt: Date? = nil

    var isVisible: Bool = true

    /// Tracks are required to belong to a map set.
    /// Legacy imports may decode with nil and should be normalized in the store.
    var mapSetID: UUID? = nil

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Imported Track" : trimmed
    }

    var coordinates: [CLLocationCoordinate2D] {
        points.map(\.clCoordinate)
    }

    var hasTrack: Bool {
        !points.isEmpty
    }
}

struct MapSet: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var lastUsedAt: Date? = nil
    var name: String

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Map Set" : trimmed
    }
}

struct ImportedMapFile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var importedAt: Date = Date()

    /// Original filename user imported
    var fileName: String

    /// File extension / parser source
    var format: ImportedFileFormat = .unknown

    /// Category chosen during import.
    /// This acts as the file's primary category and should usually match
    /// the child items contained within it.
    var assignedCategory: ImportCategory = .other
    var assignedCustomCategoryID: UUID? = nil

    /// One imported file can contain many items
    var boundaries: [ImportedBoundary] = []
    var markers: [ImportedMarker] = []
    var tracks: [ImportedTrack] = []

    /// Toggle whole imported file on/off
    var isVisible: Bool = true

    var displayTitle: String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Imported File" : trimmed
    }

    var itemCount: Int {
        boundaries.count + markers.count + tracks.count
    }

    var hasContent: Bool {
        itemCount > 0
    }

    var categoriesPresent: [ImportCategory] {
        var set = Set<ImportCategory>()
        boundaries.forEach { set.insert($0.category) }
        markers.forEach { set.insert($0.category) }
        tracks.forEach { set.insert($0.category) }

        if set.isEmpty {
            set.insert(assignedCategory)
        }

        return ImportCategory.allCases.filter { set.contains($0) }
    }

    func applyingAssignedCategoryToChildren() -> ImportedMapFile {
        var copy = self

        switch assignedCategory {
        case .boundaries:
            copy.boundaries = copy.boundaries.map {
                var boundary = $0
                boundary.category = .boundaries
                return boundary
            }

        case .tracks:
            copy.tracks = copy.tracks.map {
                var track = $0
                track.category = .tracks
                return track
            }

        case .waterPoints, .yards, .other:
            copy.markers = copy.markers.map {
                var marker = $0
                marker.category = assignedCategory
                return marker
            }
        }

        return copy
    }
}

// =========================================================
// MARK: - Session Models
// =========================================================

struct MusterSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var mapSetID: UUID? = nil

    var isActive: Bool = true

    /// Controls whether this completed session should render as a faded
    /// historical track on the main map.
    ///
    /// Active sessions are expected to render regardless of this flag.
    var isVisibleOnMap: Bool = true

    var points: [TrackPoint] = []
    var markers: [MusterMarker] = []

    var sortDate: Date {
        startedAt
    }

    var duration: TimeInterval {
        let end = endedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt))
    }

    var hasTrack: Bool {
        !points.isEmpty
    }

    var elevationRange: ClosedRange<Double>? {
        let values = points.compactMap(\.elevationM)
        guard let min = values.min(), let max = values.max() else { return nil }
        return min...max
    }
}

struct TrackPoint: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var t: Date = Date()
    var lat: Double
    var lon: Double
    var acc: Double

    /// Elevation in meters above sea level.
    /// Optional so older saved sessions can decode without it.
    var elevationM: Double? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct MusterMarker: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var t: Date = Date()
    var lat: Double
    var lon: Double
    var type: MarkerType
    var note: String? = nil

    /// Optional sheep count estimate.
    /// Only used for sheep pins.
    ///
    /// Values are stored as:
    /// - 1...99 exact buckets used by the UI
    /// - 100 means "100+"
    ///
    /// Optional so older saved data still decodes cleanly.
    var sheepCountEstimate: Int? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var displayTitle: String {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return type.title
    }
}

// =========================================================
// MARK: - Marker Type
// =========================================================

enum MarkerType: String, Codable, CaseIterable, Hashable {
    case gate
    case water
    case yard
    case issue
    case note
    case sheepPin

    var title: String {
        switch self {
        case .sheepPin:
            switch UserDefaults.standard.string(forKey: "sheep_pin_icon") ?? "sheep" {
            case "cattle":
                return "Cattle Pin"
            case "flag":
                return "Flag Pin"
            case "target":
                return "Target Pin"
            case "bell":
                return "Bell Pin"
            case "pin":
                return "Pin"
            default:
                return "Sheep Pin"
            }

        default:
            return rawValue.capitalized
        }
    }

    var glyph: String {
        switch self {
        case .gate: return "G"
        case .water: return "W"
        case .yard: return "Y"
        case .issue: return "!"
        case .note: return "•"
        case .sheepPin:
            switch UserDefaults.standard.string(forKey: "sheep_pin_icon") ?? "sheep" {
            case "cattle": return "🐄"
            case "flag": return "🚩"
            case "target": return "🎯"
            case "bell": return "🔔"
            case "pin": return "📍"
            default: return "🐑"
            }
        }
    }

    var symbol: String {
        switch self {
        case .gate: return "door.left.hand.open"
        case .water: return "drop.fill"
        case .yard: return "square.grid.2x2.fill"
        case .issue: return "exclamationmark.triangle.fill"
        case .note: return "square.and.pencil"

        // Sheep pin uses glyph instead of SF Symbol
        case .sheepPin: return ""
        }
    }
}
