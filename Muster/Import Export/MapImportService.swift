import Foundation
import CoreLocation

enum MapImportError: LocalizedError {
    case unsupportedFileType(String)
    case unsupportedKMZ
    case invalidGeoJSON
    case invalidKML
    case invalidGPX
    case emptyImport
    case unreadableText

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext)"
        case .unsupportedKMZ:
            return "KMZ import is not supported yet. Please unzip the KMZ and import the KML file inside it."
        case .invalidGeoJSON:
            return "This GeoJSON file could not be read."
        case .invalidKML:
            return "This KML file could not be read."
        case .invalidGPX:
            return "This GPX file could not be read."
        case .emptyImport:
            return "No boundaries, markers, or tracks were found in that file."
        case .unreadableText:
            return "Could not read the file contents."
        }
    }
}

enum MapImportService {

    static func importFile(from url: URL, data: Data) throws -> ImportedMapFile {
        let ext = url.pathExtension.lowercased()

        let parsedFile: ImportedMapFile

        switch ext {
        case "geojson", "json":
            parsedFile = try parseGeoJSON(fileName: url.lastPathComponent, data: data)

        case "gpx":
            parsedFile = try parseGPX(fileName: url.lastPathComponent, data: data)

        case "kml":
            parsedFile = try parseKML(fileName: url.lastPathComponent, data: data)

        case "kmz":
            throw MapImportError.unsupportedKMZ

        default:
            throw MapImportError.unsupportedFileType(ext)
        }

        let file = addingMergedPropertyLayerIfNeeded(to: parsedFile)

        guard file.hasContent else {
            throw MapImportError.emptyImport
        }

        return file
    }

    static func suggestedCategories(for _: ImportedMapFile) -> [ImportCategory] {
        return [.boundaries, .tracks, .other]
    }
    // MARK: - GeoJSON

    private static func parseGeoJSON(fileName: String, data: Data) throws -> ImportedMapFile {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MapImportError.invalidGeoJSON
        }

        var boundaries: [ImportedBoundary] = []
        var markers: [ImportedMarker] = []
        var tracks: [ImportedTrack] = []

        if let type = (root["type"] as? String)?.lowercased() {
            switch type {
            case "featurecollection":
                let features = root["features"] as? [[String: Any]] ?? []
                for feature in features {
                    parseGeoJSONFeature(
                        feature,
                        intoBoundaries: &boundaries,
                        markers: &markers,
                        tracks: &tracks
                    )
                }

            case "feature":
                parseGeoJSONFeature(
                    root,
                    intoBoundaries: &boundaries,
                    markers: &markers,
                    tracks: &tracks
                )

            case "point", "linestring", "polygon", "multipolygon":
                let wrapped: [String: Any] = [
                    "type": "Feature",
                    "geometry": root,
                    "properties": [:]
                ]
                parseGeoJSONFeature(
                    wrapped,
                    intoBoundaries: &boundaries,
                    markers: &markers,
                    tracks: &tracks
                )

            default:
                throw MapImportError.invalidGeoJSON
            }
        } else {
            throw MapImportError.invalidGeoJSON
        }

        return ImportedMapFile(
            fileName: fileName,
            format: .geojson,
            boundaries: boundaries,
            markers: markers,
            tracks: tracks
        )
    }

    private static func parseGeoJSONFeature(
        _ feature: [String: Any],
        intoBoundaries boundaries: inout [ImportedBoundary],
        markers: inout [ImportedMarker],
        tracks: inout [ImportedTrack]
    ) {
        guard let geometry = feature["geometry"] as? [String: Any],
              let type = (geometry["type"] as? String)?.lowercased() else { return }

        let props = feature["properties"] as? [String: Any] ?? [:]
        let name = geoJSONString(props["name"]) ??
            geoJSONString(props["title"]) ??
            geoJSONString(props["label"]) ??
            defaultName(for: type)

        switch type {
        case "point":
            guard let coords = geometry["coordinates"] as? [Double],
                  coords.count >= 2 else { return }

            markers.append(
                ImportedMarker(
                    name: name,
                    markerType: geoJSONString(props["markerType"]) ?? geoJSONString(props["type"]),
                    note: geoJSONString(props["note"]) ?? geoJSONString(props["description"]),
                    emoji: geoJSONString(props["emoji"]),
                    lat: coords[1],
                    lon: coords[0],
                    isVisible: true
                )
            )

        case "linestring":
            guard let rawCoords = geometry["coordinates"] as? [[Double]] else { return }

            let points = rawCoords.compactMap { pair -> CodableCoordinate? in
                guard pair.count >= 2 else { return nil }
                return CodableCoordinate(lat: pair[1], lon: pair[0])
            }

            guard points.count > 1 else { return }

            tracks.append(
                ImportedTrack(
                    name: name,
                    points: points,
                    startedAt: nil,
                    endedAt: nil,
                    isVisible: true
                )
            )

        case "polygon":
            guard let rawRings = geometry["coordinates"] as? [[[Double]]] else { return }

            let rings = rawRings.compactMap { ring in
                let coords = ring.compactMap { pair -> CodableCoordinate? in
                    guard pair.count >= 2 else { return nil }
                    return CodableCoordinate(lat: pair[1], lon: pair[0])
                }
                return coords.count >= 3 ? coords : nil
            }

            guard !rings.isEmpty else { return }

            boundaries.append(
                ImportedBoundary(
                    name: name,
                    geometryKind: .polygon,
                    rings: rings,
                    strokeHex: geoJSONString(props["stroke"]),
                    fillHex: geoJSONString(props["fill"]),
                    isVisible: true
                )
            )

        case "multipolygon":
            guard let rawPolygons = geometry["coordinates"] as? [[[[Double]]]] else { return }

            var allRings: [[CodableCoordinate]] = []
            for polygon in rawPolygons {
                for ring in polygon {
                    let coords = ring.compactMap { pair -> CodableCoordinate? in
                        guard pair.count >= 2 else { return nil }
                        return CodableCoordinate(lat: pair[1], lon: pair[0])
                    }
                    if coords.count >= 3 {
                        allRings.append(coords)
                    }
                }
            }

            guard !allRings.isEmpty else { return }

            boundaries.append(
                ImportedBoundary(
                    name: name,
                    geometryKind: .multiPolygon,
                    rings: allRings,
                    strokeHex: geoJSONString(props["stroke"]),
                    fillHex: geoJSONString(props["fill"]),
                    isVisible: true
                )
            )

        default:
            break
        }
    }

    private static func geoJSONString(_ value: Any?) -> String? {
        value as? String
    }

    // MARK: - GPX

    private static func parseGPX(fileName: String, data: Data) throws -> ImportedMapFile {
        let parser = GPXImportParser(data: data)
        let result = parser.parse()

        guard result.success else {
            throw MapImportError.invalidGPX
        }

        return ImportedMapFile(
            fileName: fileName,
            format: .gpx,
            boundaries: [],
            markers: result.markers,
            tracks: result.tracks
        )
    }

    // MARK: - KML

    private static func parseKML(fileName: String, data: Data) throws -> ImportedMapFile {
        let parser = KMLImportParser(data: data)
        let result = parser.parse()

        guard result.success else {
            throw MapImportError.invalidKML
        }

        return ImportedMapFile(
            fileName: fileName,
            format: .kml,
            boundaries: result.boundaries,
            markers: result.markers,
            tracks: result.tracks
        )
    }

    // MARK: - Auto Merged Property Layer

    private static func addingMergedPropertyLayerIfNeeded(to file: ImportedMapFile) -> ImportedMapFile {
        let eligibleBoundaries = file.boundaries.filter { !$0.rings.isEmpty }

        guard eligibleBoundaries.count >= 2 else {
            return file
        }

        var mergedRings: [[CodableCoordinate]] = []
        mergedRings.reserveCapacity(
            eligibleBoundaries.reduce(0) { $0 + $1.rings.count }
        )

        for boundary in eligibleBoundaries {
            for ring in boundary.rings where ring.count >= 3 {
                mergedRings.append(ring)
            }
        }

        guard !mergedRings.isEmpty else {
            return file
        }

        let mergedBoundary = ImportedBoundary(
            name: mergedPropertyLayerName(for: file.fileName, boundaries: eligibleBoundaries),
            geometryKind: .multiPolygon,
            rings: mergedRings,
            strokeHex: eligibleBoundaries.first?.strokeHex,
            fillHex: eligibleBoundaries.first?.fillHex,
            isVisible: false
        )

        return ImportedMapFile(
            id: file.id,
            importedAt: file.importedAt,
            fileName: file.fileName,
            format: file.format,
            assignedCategory: file.assignedCategory,
            boundaries: file.boundaries + [mergedBoundary],
            markers: file.markers,
            tracks: file.tracks,
            isVisible: file.isVisible
        )
    }

    private static func mergedPropertyLayerName(for fileName: String, boundaries: [ImportedBoundary]) -> String {
        let baseName = fileName
            .replacingOccurrences(of: ".geojson", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".kml", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".kmz", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !baseName.isEmpty {
            return "\(baseName) – Property"
        }

        return "Property – Merged"
    }

    // MARK: - Helpers

    private static func defaultName(for type: String) -> String {
        switch type {
        case "point":
            return "Marker"
        case "linestring":
            return "Track"
        case "polygon", "multipolygon":
            return "Boundary"
        default:
            return "Imported Item"
        }
    }
}

// MARK: - GPX Parser

private final class GPXImportParser: NSObject, XMLParserDelegate {

    struct Result {
        var success: Bool = false
        var markers: [ImportedMarker] = []
        var tracks: [ImportedTrack] = []
    }

    private let parser: XMLParser
    private var result = Result()

    private var currentText = ""

    private var currentWaypointName: String?
    private var currentWaypointLat: Double?
    private var currentWaypointLon: Double?

    private var currentTrackName: String?
    private var currentTrackPoints: [CodableCoordinate] = []

    private var elementStack: [String] = []

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() -> Result {
        result.success = parser.parse()
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "wpt":
            currentWaypointName = nil
            currentWaypointLat = Double(attributeDict["lat"] ?? "")
            currentWaypointLon = Double(attributeDict["lon"] ?? "")

        case "trk":
            currentTrackName = nil
            currentTrackPoints = []

        case "trkpt":
            if let lat = Double(attributeDict["lat"] ?? ""),
               let lon = Double(attributeDict["lon"] ?? "") {
                currentTrackPoints.append(CodableCoordinate(lat: lat, lon: lon))
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "name" {
            let parent = parentElementName
            if parent == "wpt" {
                currentWaypointName = trimmed
            } else if parent == "trk" {
                currentTrackName = trimmed
            }
        }

        switch elementName {
        case "wpt":
            if let lat = currentWaypointLat, let lon = currentWaypointLon {
                result.markers.append(
                    ImportedMarker(
                        name: (currentWaypointName?.isEmpty == false ? currentWaypointName! : "Waypoint"),
                        markerType: "Waypoint",
                        note: nil,
                        emoji: nil,
                        lat: lat,
                        lon: lon,
                        isVisible: true
                    )
                )
            }

            currentWaypointName = nil
            currentWaypointLat = nil
            currentWaypointLon = nil

        case "trk":
            if currentTrackPoints.count > 1 {
                result.tracks.append(
                    ImportedTrack(
                        name: (currentTrackName?.isEmpty == false ? currentTrackName! : "GPX Track"),
                        points: currentTrackPoints,
                        startedAt: nil,
                        endedAt: nil,
                        isVisible: true
                    )
                )
            }

            currentTrackName = nil
            currentTrackPoints = []

        default:
            break
        }

        _ = elementStack.popLast()
        currentText = ""
    }

    private var parentElementName: String? {
        guard elementStack.count >= 2 else { return nil }
        return elementStack[elementStack.count - 2]
    }
}

// MARK: - KML Parser

private final class KMLImportParser: NSObject, XMLParserDelegate {

    struct Result {
        var success: Bool = false
        var boundaries: [ImportedBoundary] = []
        var markers: [ImportedMarker] = []
        var tracks: [ImportedTrack] = []
    }

    private let parser: XMLParser
    private var result = Result()

    private var currentText = ""
    private var elementStack: [String] = []

    private var insidePlacemark = false
    private var placemarkName: String?
    private var pointCoordinatesText: String?
    private var lineCoordinatesText: String?
    private var polygonCoordinatesText: [String] = []

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() -> Result {
        result.success = parser.parse()
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        elementStack.append(elementName)
        currentText = ""

        if elementName == "Placemark" {
            insidePlacemark = true
            placemarkName = nil
            pointCoordinatesText = nil
            lineCoordinatesText = nil
            polygonCoordinatesText = []
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if insidePlacemark {
            if elementName == "name", parentElementName == "Placemark" {
                placemarkName = trimmed
            }

            if elementName == "coordinates" {
                if elementStack.contains("Point") {
                    pointCoordinatesText = trimmed
                } else if elementStack.contains("LineString") {
                    lineCoordinatesText = trimmed
                } else if elementStack.contains("Polygon") {
                    polygonCoordinatesText.append(trimmed)
                }
            }

            if elementName == "Placemark" {
                flushPlacemark()
                insidePlacemark = false
            }
        }

        _ = elementStack.popLast()
        currentText = ""
    }

    private func flushPlacemark() {
        let name = (placemarkName?.isEmpty == false ? placemarkName! : "Placemark")

        if let pointCoordinatesText,
           let coord = parseSingleKMLCoordinate(pointCoordinatesText) {
            result.markers.append(
                ImportedMarker(
                    name: name,
                    markerType: "Placemark",
                    note: nil,
                    emoji: nil,
                    lat: coord.lat,
                    lon: coord.lon,
                    isVisible: true
                )
            )
            return
        }

        if let lineCoordinatesText {
            let coords = parseKMLCoordinateList(lineCoordinatesText)
            if coords.count > 1 {
                result.tracks.append(
                    ImportedTrack(
                        name: name,
                        points: coords,
                        startedAt: nil,
                        endedAt: nil,
                        isVisible: true
                    )
                )
                return
            }
        }

        if !polygonCoordinatesText.isEmpty {
            let rings = polygonCoordinatesText
                .map(parseKMLCoordinateList)
                .filter { $0.count >= 3 }

            if !rings.isEmpty {
                result.boundaries.append(
                    ImportedBoundary(
                        name: name,
                        geometryKind: .polygon,
                        rings: rings,
                        strokeHex: nil,
                        fillHex: nil,
                        isVisible: true
                    )
                )
            }
        }
    }

    private var parentElementName: String? {
        guard elementStack.count >= 2 else { return nil }
        return elementStack[elementStack.count - 2]
    }

    private func parseSingleKMLCoordinate(_ string: String) -> CodableCoordinate? {
        parseKMLCoordinateList(string).first
    }

    private func parseKMLCoordinateList(_ string: String) -> [CodableCoordinate] {
        string
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .compactMap { token in
                let parts = token.split(separator: ",").map(String.init)
                guard parts.count >= 2,
                      let lon = Double(parts[0]),
                      let lat = Double(parts[1]) else { return nil }
                return CodableCoordinate(lat: lat, lon: lon)
            }
    }
}

// MARK: - Utility
