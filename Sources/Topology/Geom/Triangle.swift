/// A triangle's centres: JTS's `Triangle`, the in-centre the buffer uses.
/// The weighted sums are fused as GEOS's compiler fuses them (`Fused.swift`).
public struct Triangle {
    public var p0: Coordinate
    public var p1: Coordinate
    public var p2: Coordinate

    public init(_ p0: Coordinate, _ p1: Coordinate, _ p2: Coordinate) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
    }

    /// The centre of the inscribed circle: the vertices weighted by the
    /// lengths of the sides opposite them.
    public func inCentre() -> Coordinate {
        let len0 = p1.distance(p2)
        let len1 = p0.distance(p2)
        let len2 = p0.distance(p1)
        let circum = len0 + len1 + len2
        let inCentreX = fusedAdd(len2, p2.x, fusedAdd(len0, p0.x, len1 * p1.x)) / circum
        let inCentreY = fusedAdd(len2, p2.y, fusedAdd(len0, p0.y, len1 * p1.y)) / circum
        return Coordinate(inCentreX, inCentreY)
    }
}
