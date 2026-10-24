/// The boundary of a geometry under a boundary node rule: JTS's `BoundaryOp`.
/// A line's boundary is its endpoints (none when closed, under the default
/// rule), lines' boundary the endpoints that end an odd number of them,
/// sorted.
public struct BoundaryOp {
    let geom: Geometry
    let rule: BoundaryNodeRule

    public init(_ geom: Geometry, _ rule: BoundaryNodeRule = .mod2) {
        self.geom = geom
        self.rule = rule
    }

    public static func getBoundary(_ g: Geometry, _ rule: BoundaryNodeRule = .mod2) -> Geometry {
        BoundaryOp(g, rule).getBoundary()
    }

    public static func hasBoundary(_ geom: Geometry, _ rule: BoundaryNodeRule) -> Bool {
        if geom.isEmpty() { return false }
        switch geom.getDimension() {
        case Dimension.p: return false
        case Dimension.l: return !getBoundary(geom, rule).isEmpty()
        default: return true
        }
    }

    public func getBoundary() -> Geometry {
        if let l = geom as? LineString { return boundaryLineString(l) }
        if let ml = geom as? MultiLineString { return boundaryMultiLineString(ml) }
        return geom.getBoundary()
    }

    func boundaryMultiLineString(_ mLine: MultiLineString) -> Geometry {
        if geom.isEmpty() { return geom.factory.createMultiPoint() }
        let pts = computeBoundaryCoordinates(mLine)
        if pts.count == 1 { return geom.factory.createPoint(pts[0]) }
        return geom.factory.createMultiPointFromCoords(pts)
    }

    func computeBoundaryCoordinates(_ mLine: MultiLineString) -> [Coordinate] {
        // A TreeMap in JTS: the endpoints in coordinate order.
        var counts: [Coordinate: Int] = [:]
        for g in mLine.geometries {
            let line = g as! LineString
            if line.getNumPoints() == 0 { continue }
            counts[line.points[0], default: 0] += 1
            counts[line.points[line.points.count - 1], default: 0] += 1
        }
        return counts.keys.sorted { $0.compareTo($1) < 0 }.filter { rule.isInBoundary(counts[$0]!) }
    }

    func boundaryLineString(_ line: LineString) -> Geometry {
        if geom.isEmpty() { return geom.factory.createMultiPoint() }
        if line.isClosed() {
            if rule.isInBoundary(2) { return line.getStartPoint()! }
            return geom.factory.createMultiPoint()
        }
        return geom.factory.createMultiPoint([line.getStartPoint()!, line.getEndPoint()!])
    }
}
