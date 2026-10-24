/// Line strings: JTS's `MultiLineString`.
public final class MultiLineString: GeometryCollection {
    override var typeCode: TypeCode { .multiLineString }
    override public func getGeometryType() -> String { "MultiLineString" }
    override public func getDimension() -> Int { 1 }
    override public func hasDimension(_ dim: Int) -> Bool { dim == 1 }
    override public func getBoundaryDimension() -> Int { isClosed() ? Dimension.false : 0 }

    public func isClosed() -> Bool {
        if isEmpty() { return false }
        return geometries.allSatisfy { ($0 as! LineString).isClosed() }
    }

    override public func getBoundary() -> Geometry { BoundaryOp(self).getBoundary() }
    override func copyInternal() -> Geometry { MultiLineString(geometries.map { $0.copy() }, factory: factory) }
    override func reverseInternal() -> Geometry { MultiLineString(geometries.map { $0.reverse() }, factory: factory) }
}
