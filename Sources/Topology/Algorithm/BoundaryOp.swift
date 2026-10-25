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
        // GEOS's `std::map` (JTS: a TreeMap): the endpoints in coordinate
        // order, a NaN endpoint equivalent to any other as libc++'s tree
        // finds it (`CxxTree`).
        var counts = CxxTree<Coordinate, Int> { $0 < $1 }
        for g in mLine.geometries {
            let line = g as! LineString
            if line.getNumPoints() == 0 { continue }
            for c in [line.points[0], line.points[line.points.count - 1]] {
                let node = counts.insert(c, 0).0
                counts.modify(node) { $0 += 1 }
            }
        }
        return counts.inOrder().filter { rule.isInBoundary(counts.nodes[$0].value) }.map { counts.nodes[$0].key }
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
