/// Points: JTS's `MultiPoint`.
public final class MultiPoint: GeometryCollection {
    override var typeCode: TypeCode { .multiPoint }
    override public func getGeometryType() -> String { "MultiPoint" }
    override public func getDimension() -> Int { 0 }
    override public func hasDimension(_ dim: Int) -> Bool { dim == 0 }
    override public func getBoundaryDimension() -> Int { Dimension.false }
    override public func getBoundary() -> Geometry { factory.createGeometryCollection() }
    override func copyInternal() -> Geometry { MultiPoint(geometries.map { $0.copy() }, factory: factory) }
    override func reverseInternal() -> Geometry { MultiPoint(geometries.map { $0.copy() }, factory: factory) }
    func getCoordinate(_ n: Int) -> Coordinate? { (geometries[n] as! Point).getCoordinate() }
}
