import SwiftUI
import CoreLocation

/// Persistent autosteer geometry built only when track/mode/width changes.
/// This cache is intentionally independent from GPS ticks.
struct AutosteerGuidanceGeometryCache: Equatable {
    struct LocalLine: Equatable {
        let origin: CGPoint
        let direction: CGVector
        let normal: CGVector
    }

    let anchor: CLLocationCoordinate2D
    let baseLine: LocalLine
    let workingWidthMeters: Double
    let signature: String

    static func build(
        endpoints: (CLLocationCoordinate2D, CLLocationCoordinate2D)?,
        anchor userCoordinate: CLLocationCoordinate2D,
        workingWidthMeters: Double,
        signature: String
    ) -> AutosteerGuidanceGeometryCache? {
        guard workingWidthMeters > 0,
              let endpoints,
              let line = localLine(from: endpoints, anchor: userCoordinate) else {
            return nil
        }

        return AutosteerGuidanceGeometryCache(
            anchor: userCoordinate,
            baseLine: line,
            workingWidthMeters: workingWidthMeters,
            signature: signature
        )
    }

    private static func localLine(
        from endpoints: (CLLocationCoordinate2D, CLLocationCoordinate2D),
        anchor: CLLocationCoordinate2D
    ) -> LocalLine? {
        let a = localPoint(endpoints.0, anchor: anchor)
        let b = localPoint(endpoints.1, anchor: anchor)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return nil }

        let ux = dx / length
        let uy = dy / length
        return LocalLine(
            origin: a,
            direction: CGVector(dx: ux, dy: uy),
            normal: CGVector(dx: -uy, dy: ux)
        )
    }

    func offsetLineOrigin(offsetIndex: Int) -> CGPoint {
        CGPoint(
            x: baseLine.origin.x + (Double(offsetIndex) * workingWidthMeters * baseLine.normal.dx),
            y: baseLine.origin.y + (Double(offsetIndex) * workingWidthMeters * baseLine.normal.dy)
        )
    }

    func localPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        Self.localPoint(coordinate, anchor: anchor)
    }

    private static func localPoint(_ coordinate: CLLocationCoordinate2D, anchor: CLLocationCoordinate2D) -> CGPoint {
        let earthRadiusM = 6_378_137.0
        let latitudeRadians = anchor.latitude * .pi / 180
        let metersPerDegreeLat = earthRadiusM * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(latitudeRadians)

        return CGPoint(
            x: (coordinate.longitude - anchor.longitude) * metersPerDegreeLon,
            y: (coordinate.latitude - anchor.latitude) * metersPerDegreeLat
        )
    }
}

/// Per-tick motion state. Updated from GPS/heading without touching cached geometry.
struct AutosteerProjection {
    let vehicleWorldPoint: CGPoint
    let headingRadians: Double
    let pixelsPerMeter: CGFloat
    let vehicleScreenPoint: CGPoint

    func project(world point: CGPoint) -> CGPoint {
        let translatedX = point.x - vehicleWorldPoint.x
        let translatedY = point.y - vehicleWorldPoint.y

        let cosH = cos(-headingRadians)
        let sinH = sin(-headingRadians)
        let rotatedX = (translatedX * cosH) - (translatedY * sinH)
        let rotatedY = (translatedX * sinH) + (translatedY * cosH)

        return CGPoint(
            x: vehicleScreenPoint.x + (rotatedX * pixelsPerMeter),
            y: vehicleScreenPoint.y - (rotatedY * pixelsPerMeter)
        )
    }
}

/// Deterministic guidance drawing. Uses cached geometry + per-tick transform only.
struct AutosteerGuidanceRenderer {
    var leftRightLineCount: Int = 8

    func draw(
        in context: GraphicsContext,
        size: CGSize,
        cache: AutosteerGuidanceGeometryCache,
        projection: AutosteerProjection,
        lockedLineIndex: Int?
    ) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

        let activeIndex = lockedLineIndex ?? 0
        let indexRange = (activeIndex - leftRightLineCount)...(activeIndex + leftRightLineCount)
        let screenSpanMeters = Double(hypot(size.width, size.height) / projection.pixelsPerMeter)
        let halfLength = max(120, screenSpanMeters)

        for index in indexRange {
            let origin = cache.offsetLineOrigin(offsetIndex: index)
            let direction = cache.baseLine.direction
            let start = CGPoint(
                x: origin.x - (halfLength * direction.dx),
                y: origin.y - (halfLength * direction.dy)
            )
            let end = CGPoint(
                x: origin.x + (halfLength * direction.dx),
                y: origin.y + (halfLength * direction.dy)
            )

            var linePath = Path()
            linePath.move(to: projection.project(world: start))
            linePath.addLine(to: projection.project(world: end))

            let isLocked = index == activeIndex
            context.stroke(
                linePath,
                with: .color(isLocked ? .green : .white.opacity(0.45)),
                style: StrokeStyle(lineWidth: isLocked ? 3 : 1.5, lineCap: .round)
            )
        }

        let vehiclePath = Path(ellipseIn: CGRect(x: projection.vehicleScreenPoint.x - 6, y: projection.vehicleScreenPoint.y - 6, width: 12, height: 12))
        context.fill(vehiclePath, with: .color(.yellow))
    }
}

struct AutosteerGuidanceView: View {
    let isActive: Bool
    let referenceLine: (CLLocationCoordinate2D, CLLocationCoordinate2D)?
    let userCoordinate: CLLocationCoordinate2D?
    let headingDegrees: Double?
    let workingWidthMeters: Double
    let lockedLineIndex: Int?
    let geometrySignature: String

    @State private var geometryCache: AutosteerGuidanceGeometryCache?
    private let renderer = AutosteerGuidanceRenderer()

    var body: some View {
        GeometryReader { geo in
            Canvas(opaque: true, rendersAsynchronously: true) { context, size in
                guard let cache = geometryCache,
                      let userCoordinate else {
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                    return
                }

                let heading = headingDegrees ?? 0
                let vehicleWorldPoint = cache.localPoint(for: userCoordinate)
                let pixelsPerMeter = max(1.2, min(10, geo.size.width / 110))
                let projection = AutosteerProjection(
                    vehicleWorldPoint: vehicleWorldPoint,
                    headingRadians: heading * .pi / 180,
                    pixelsPerMeter: pixelsPerMeter,
                    vehicleScreenPoint: CGPoint(x: size.width * 0.5, y: size.height * 0.58)
                )

                renderer.draw(
                    in: context,
                    size: size,
                    cache: cache,
                    projection: projection,
                    lockedLineIndex: lockedLineIndex
                )
            }
            .background(Color.black)
            .onAppear { rebuildGeometryCacheIfNeeded() }
            .onChange(of: geometrySignature) { _, _ in rebuildGeometryCacheIfNeeded() }
            .onChange(of: workingWidthMeters) { _, _ in rebuildGeometryCacheIfNeeded() }
            .onChange(of: referenceLine?.0.latitude) { _, _ in rebuildGeometryCacheIfNeeded() }
            .onChange(of: referenceLine?.0.longitude) { _, _ in rebuildGeometryCacheIfNeeded() }
            .onChange(of: referenceLine?.1.latitude) { _, _ in rebuildGeometryCacheIfNeeded() }
            .onChange(of: referenceLine?.1.longitude) { _, _ in rebuildGeometryCacheIfNeeded() }
            .onChange(of: isActive) { _, becameActive in
                if becameActive { rebuildGeometryCacheIfNeeded() }
            }
        }
        .ignoresSafeArea(edges: .all)
        .accessibilityIdentifier("autosteer_guidance_canvas")
    }

    private func rebuildGeometryCacheIfNeeded() {
        guard isActive,
              let userCoordinate else {
            geometryCache = nil
            return
        }

        geometryCache = AutosteerGuidanceGeometryCache.build(
            endpoints: referenceLine,
            anchor: userCoordinate,
            workingWidthMeters: workingWidthMeters,
            signature: geometrySignature
        )
    }
}
