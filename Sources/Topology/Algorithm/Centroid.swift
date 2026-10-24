/// The centroid of a geometry: JTS's `Centroid`. Of its highest dimension
/// only: the area's centroid by triangles from a base point, else the
/// lines' by segment midpoints weighted by length, else the points' mean.
public struct Centroid {
    private var areaBasePt: Coordinate?
    private var areasum2 = 0.0
    private var cg3 = Coordinate(0, 0)
    private var lineCentSum = Coordinate(0, 0)
    private var totalLength = 0.0
    private var ptCount = 0
    private var ptCentSum = Coordinate(0, 0)

    public static func getCentroid(_ geom: Geometry) -> Coordinate? { Centroid(geom).getCentroid() }

    public init(_ geom: Geometry) { add(geom) }

    private mutating func add(_ geom: Geometry) {
        if geom.isEmpty() { return }
        if geom is Point {
            addPoint(geom.getCoordinate()!)
        } else if geom is LineString {
            addLineSegments(geom.getCoordinates())
        } else if let poly = geom as? Polygon {
            add(poly)
        } else if let gc = geom as? GeometryCollection {
            for g in gc.geometries { add(g) }
        }
    }

    public func getCentroid() -> Coordinate? {
        if abs(areasum2) > 0.0 {
            return Coordinate(cg3.x / 3 / areasum2, cg3.y / 3 / areasum2)
        } else if totalLength > 0.0 {
            return Coordinate(lineCentSum.x / totalLength, lineCentSum.y / totalLength)
        } else if ptCount > 0 {
            return Coordinate(ptCentSum.x / Double(ptCount), ptCentSum.y / Double(ptCount))
        }
        return nil
    }

    private mutating func add(_ poly: Polygon) {
        addShell(poly.shell.points)
        for h in poly.holes { addHole(h.points) }
    }

    private mutating func addShell(_ pts: [Coordinate]) {
        if !pts.isEmpty { areaBasePt = pts[0] }
        let isPositiveArea = !Orientation.isCCW(pts)
        if pts.count > 1 {
            for i in 0..<(pts.count - 1) { addTriangle(areaBasePt!, pts[i], pts[i + 1], isPositiveArea) }
        }
        addLineSegments(pts)
    }

    private mutating func addHole(_ pts: [Coordinate]) {
        let isPositiveArea = Orientation.isCCW(pts)
        if pts.count > 1 {
            for i in 0..<(pts.count - 1) { addTriangle(areaBasePt!, pts[i], pts[i + 1], isPositiveArea) }
        }
        addLineSegments(pts)
    }

    private mutating func addTriangle(_ p0: Coordinate, _ p1: Coordinate, _ p2: Coordinate, _ isPositiveArea: Bool) {
        let sign = isPositiveArea ? 1.0 : -1.0
        let c = Centroid.centroid3(p0, p1, p2)
        let area2 = Centroid.area2(p0, p1, p2)
        // cg3 += sign * area2 * c, areasum2 += sign * area2: fused, as GEOS.
        cg3.x = fusedAdd(sign * area2, c.x, cg3.x)
        cg3.y = fusedAdd(sign * area2, c.y, cg3.y)
        areasum2 = fusedAdd(sign, area2, areasum2)
    }

    private static func centroid3(_ p1: Coordinate, _ p2: Coordinate, _ p3: Coordinate) -> Coordinate {
        Coordinate(p1.x + p2.x + p3.x, p1.y + p2.y + p3.y)
    }

    /// Twice the signed area of a triangle.
    private static func area2(_ p1: Coordinate, _ p2: Coordinate, _ p3: Coordinate) -> Double {
        fusedSub(p2.x - p1.x, p3.y - p1.y, (p3.x - p1.x) * (p2.y - p1.y))
    }

    private mutating func addLineSegments(_ pts: [Coordinate]) {
        var lineLen = 0.0
        if pts.count > 1 {
            for i in 0..<(pts.count - 1) {
                let segmentLen = pts[i].distance(pts[i + 1])
                if segmentLen == 0.0 { continue }
                lineLen += segmentLen
                let midx = (pts[i].x + pts[i + 1].x) / 2
                lineCentSum.x = fusedAdd(segmentLen, midx, lineCentSum.x)
                let midy = (pts[i].y + pts[i + 1].y) / 2
                lineCentSum.y = fusedAdd(segmentLen, midy, lineCentSum.y)
            }
        }
        totalLength += lineLen
        if lineLen == 0.0 && !pts.isEmpty { addPoint(pts[0]) }
    }

    private mutating func addPoint(_ pt: Coordinate) {
        ptCount += 1
        ptCentSum.x += pt.x
        ptCentSum.y += pt.y
    }
}
