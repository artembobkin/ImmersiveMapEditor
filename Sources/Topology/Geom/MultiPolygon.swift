/// Polygons: JTS's `MultiPolygon`.
public final class MultiPolygon: GeometryCollection {
    override var typeCode: TypeCode { .multiPolygon }
    override public func getGeometryType() -> String { "MultiPolygon" }
    override public func getDimension() -> Int { 2 }
    override public func hasDimension(_ dim: Int) -> Bool { dim == 2 }
    override public func getBoundaryDimension() -> Int { 1 }

    override public func getBoundary() -> Geometry {
        if isEmpty() { return factory.createMultiLineString() }
        var rings: [LineString] = []
        for g in geometries {
            let b = g.getBoundary()
            for j in 0..<b.getNumGeometries() { rings.append(b.getGeometryN(j) as! LineString) }
        }
        return factory.createMultiLineString(rings)
    }

    override func copyInternal() -> Geometry { MultiPolygon(geometries.map { $0.copy() }, factory: factory) }
    override func reverseInternal() -> Geometry { MultiPolygon(geometries.map { $0.reverse() }, factory: factory) }
}
