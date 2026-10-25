/// A collection of geometries: JTS's `GeometryCollection`, the base of the
/// multi-geometries.
public class GeometryCollection: Geometry {
    @exclusivity(unchecked) public internal(set) var geometries: [Geometry]

    init(_ geometries: [Geometry], factory: GeometryFactory) {
        self.geometries = geometries
        super.init(factory: factory)
    }

    override var typeCode: TypeCode { .geometryCollection }
    override public func getGeometryType() -> String { "GeometryCollection" }

    override public func getCoordinate() -> Coordinate? {
        for g in geometries where !g.isEmpty() { return g.getCoordinate() }
        return nil
    }

    override public func getCoordinates() -> [Coordinate] { geometries.flatMap { $0.getCoordinates() } }
    override public func isEmpty() -> Bool { geometries.allSatisfy { $0.isEmpty() } }

    override public func getDimension() -> Int {
        var d = Dimension.false
        for g in geometries { d = max(d, g.getDimension()) }
        return d
    }

    override public func hasDimension(_ dim: Int) -> Bool { geometries.contains { $0.hasDimension(dim) } }

    override public func getBoundaryDimension() -> Int {
        var d = Dimension.false
        for g in geometries { d = max(d, g.getBoundaryDimension()) }
        return d
    }

    override public func getNumGeometries() -> Int { geometries.count }
    override public func getGeometryN(_ n: Int) -> Geometry { geometries[n] }
    override public func getNumPoints() -> Int { geometries.reduce(0) { $0 + $1.getNumPoints() } }

    override public func getBoundary() -> Geometry {
        preconditionFailure("Operation does not support GeometryCollection arguments")
    }

    override public func getArea() -> Double {
        var area = 0.0
        for g in geometries { area += g.getArea() }
        return area
    }

    override public func getLength() -> Double {
        var sum = 0.0
        for g in geometries { sum += g.getLength() }
        return sum
    }

    override public func equalsExact(_ other: Geometry, tolerance: Double) -> Bool {
        guard isEquivalentClass(other), let o = other as? GeometryCollection else { return false }
        if geometries.count != o.geometries.count { return false }
        for i in 0..<geometries.count where !geometries[i].equalsExact(o.geometries[i], tolerance: tolerance) {
            return false
        }
        return true
    }

    override public func applyComponents(_ f: (Geometry) -> Void) {
        f(self)
        for g in geometries { g.applyComponents(f) }
    }

    override public func applyGeometries(_ f: (Geometry) -> Void) {
        f(self)
        for g in geometries { g.applyGeometries(f) }
    }

    override func copyInternal() -> Geometry { GeometryCollection(geometries.map { $0.copy() }, factory: factory) }

    override public func normalize() {
        for g in geometries { g.normalize() }
        // GEOS sorts the members in descending order (JTS ascending).
        geometries = javaSorted(geometries) { $1.compareTo($0) }
    }

    override func computeEnvelopeInternal() -> Envelope {
        var e = Envelope()
        for g in geometries { e.expandToInclude(g.getEnvelopeInternal()) }
        return e
    }

    /// As JTS: both sides as sorted sets (equal members once), then compared
    /// member by member.
    override func compareToSameClass(_ other: Geometry) -> Int {
        func set(_ gs: [Geometry]) -> [Geometry] {
            var out: [Geometry] = []
            for g in javaSorted(gs, { $0.compareTo($1) }) where out.last.map({ $0.compareTo(g) != 0 }) ?? true {
                out.append(g)
            }
            return out
        }
        let a = set(geometries), b = set((other as! GeometryCollection).geometries)
        for (x, y) in zip(a, b) {
            let c = x.compareTo(y)
            if c != 0 { return c }
        }
        if a.count > b.count { return 1 }
        if b.count > a.count { return -1 }
        return 0
    }

    override func reverseInternal() -> Geometry { GeometryCollection(geometries.map { $0.reverse() }, factory: factory) }
}
