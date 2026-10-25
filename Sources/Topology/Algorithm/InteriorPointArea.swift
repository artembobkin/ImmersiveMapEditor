/// The interior point of polygons: on a horizontal scan line between the
/// vertices nearest the middle of the envelope, the middle of the widest
/// section inside, of the polygon where it is widest.
struct InteriorPointArea {
    var interiorPoint: Coordinate?
    var maxWidth = -1.0

    static func avg(_ a: Double, _ b: Double) -> Double { (a + b) / 2.0 }

    init(_ g: Geometry) { process(g) }

    mutating func process(_ geom: Geometry) {
        if geom.isEmpty() { return }
        if let poly = geom as? Polygon {
            processPolygon(poly)
        } else if let gc = geom as? GeometryCollection {
            for g in gc.geometries { process(g) }
        }
    }

    mutating func processPolygon(_ polygon: Polygon) {
        var p = InteriorPointPolygon(polygon)
        p.process()
        if p.interiorSectionWidth > maxWidth {
            maxWidth = p.interiorSectionWidth
            interiorPoint = p.interiorPoint
        }
    }

    struct InteriorPointPolygon {
        let polygon: Polygon
        let interiorPointY: Double
        var interiorSectionWidth = 0.0
        var interiorPoint: Coordinate?

        init(_ polygon: Polygon) {
            self.polygon = polygon
            interiorPointY = ScanLineYOrdinateFinder.getScanLineY(polygon)
        }

        mutating func process() {
            if polygon.isEmpty() { return }
            interiorPoint = polygon.getCoordinate()
            var crossings: [Double] = []
            scanRing(polygon.shell, &crossings)
            for h in polygon.holes { scanRing(h, &crossings) }
            findBestMidpoint(&crossings)
        }

        func scanRing(_ ring: LinearRing, _ crossings: inout [Double]) {
            if !InteriorPointPolygon.intersectsHorizontalLine(ring.getEnvelopeInternal(), interiorPointY) { return }
            let seq = ring.points
            if seq.count < 2 { return }
            for i in 1..<seq.count { addEdgeCrossing(seq[i - 1], seq[i], interiorPointY, &crossings) }
        }

        func addEdgeCrossing(_ p0: Coordinate, _ p1: Coordinate, _ scanY: Double, _ crossings: inout [Double]) {
            if !InteriorPointPolygon.intersectsHorizontalLine(p0, p1, scanY) { return }
            if !InteriorPointPolygon.isEdgeCrossingCounted(p0, p1, scanY) { return }
            crossings.append(InteriorPointPolygon.intersection(p0, p1, scanY))
        }

        mutating func findBestMidpoint(_ crossings: inout [Double]) {
            if crossings.isEmpty { return }
            // JTS asserts an even number of crossings here. GEOS 3.13 does not
            // (its assertion is commented out) and reads the pairs on, past the
            // end where the number is odd, which only a non-finite coordinate
            // makes (undefined behaviour, not compared). The port reads the
            // whole pairs. The sort is GEOS's `std::sort`, which places equal
            // zeros of either sign and NaN crossings as GEOS does.
            CxxAlgorithms.sortDoubles(&crossings)
            var i = 0
            while i + 1 < crossings.count {
                let x1 = crossings[i], x2 = crossings[i + 1]
                let width = x2 - x1
                if width > interiorSectionWidth {
                    interiorSectionWidth = width
                    interiorPoint = Coordinate(InteriorPointArea.avg(x1, x2), interiorPointY)
                }
                i += 2
            }
        }

        static func isEdgeCrossingCounted(_ p0: Coordinate, _ p1: Coordinate, _ scanY: Double) -> Bool {
            let y0 = p0.y, y1 = p1.y
            if y0 == y1 { return false }
            if y0 == scanY && y1 < scanY { return false }
            if y1 == scanY && y0 < scanY { return false }
            return true
        }

        static func intersection(_ p0: Coordinate, _ p1: Coordinate, _ y: Double) -> Double {
            let x0 = p0.x, x1 = p1.x
            if x0 == x1 { return x0 }
            let segDX = x1 - x0
            let segDY = p1.y - p0.y
            let m = segDY / segDX
            return x0 + ((y - p0.y) / m)
        }

        static func intersectsHorizontalLine(_ env: Envelope, _ y: Double) -> Bool {
            if y < env.minY { return false }
            if y > env.maxY { return false }
            return true
        }

        static func intersectsHorizontalLine(_ p0: Coordinate, _ p1: Coordinate, _ y: Double) -> Bool {
            if p0.y > y && p1.y > y { return false }
            if p0.y < y && p1.y < y { return false }
            return true
        }
    }

    /// The y of the scan line: midway between the vertices nearest the
    /// middle of the envelope, below and above it.
    struct ScanLineYOrdinateFinder {
        var hiY: Double
        var loY: Double
        let centreY: Double

        static func getScanLineY(_ poly: Polygon) -> Double {
            var f = ScanLineYOrdinateFinder(poly)
            f.process(poly.shell)
            for h in poly.holes { f.process(h) }
            return InteriorPointArea.avg(f.hiY, f.loY)
        }

        init(_ poly: Polygon) {
            let env = poly.getEnvelopeInternal()
            hiY = env.maxY
            loY = env.minY
            centreY = InteriorPointArea.avg(loY, hiY)
        }

        mutating func process(_ line: LineString) {
            for p in line.points { updateInterval(p.y) }
        }

        mutating func updateInterval(_ y: Double) {
            if y <= centreY {
                if y > loY { loY = y }
            } else if y > centreY {
                if y < hiY { hiY = y }
            }
        }
    }
}
