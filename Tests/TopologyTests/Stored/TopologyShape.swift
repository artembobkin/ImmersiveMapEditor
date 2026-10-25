import Topology

/// `Topology`'s geometries as `Shape`s, to compare them with GEOS's, and
/// back (a shape read into the port exactly).
extension Shape {
    init(_ g: Topology.Geometry) {
        func flat(_ c: [Coordinate]) -> [Double] { c.flatMap { [$0.x, $0.y] } }
        switch g {
        case let p as Point: self.init(kind: .point, coordinates: flat(p.coordinates))
        case let r as LinearRing: self.init(kind: .linearRing, coordinates: flat(r.points))
        case let l as LineString: self.init(kind: .lineString, coordinates: flat(l.points))
        case let p as Polygon:
            self.init(kind: .polygon, parts: p.isEmpty() ? [] : ([p.shell] + p.holes).map { Shape(kind: .linearRing, coordinates: flat($0.points)) })
        case let m as MultiPoint: self.init(kind: .multiPoint, parts: m.geometries.map(Shape.init))
        case let m as MultiLineString: self.init(kind: .multiLineString, parts: m.geometries.map(Shape.init))
        case let m as MultiPolygon: self.init(kind: .multiPolygon, parts: m.geometries.map(Shape.init))
        case let c as GeometryCollection: self.init(kind: .geometryCollection, parts: c.geometries.map(Shape.init))
        default: fatalError("unknown geometry")
        }
    }

    /// The shape as a geometry of the port.
    func topology(_ f: GeometryFactory = .default) -> Topology.Geometry {
        func coords(_ c: [Double]) -> [Coordinate] { stride(from: 0, to: c.count, by: 2).map { Coordinate(c[$0], c[$0 + 1]) } }
        switch kind {
        case .point: return f.createPoint(coords(coordinates))
        case .lineString: return f.createLineString(coords(coordinates))
        case .linearRing: return f.createLinearRing(coords(coordinates))
        case .polygon:
            guard let shell = parts.first else { return f.createPolygon() }
            return f.createPolygon(f.createLinearRing(coords(shell.coordinates)), parts.dropFirst().map { f.createLinearRing(coords($0.coordinates)) })
        case .multiPoint: return f.createMultiPoint(parts.map { $0.topology(f) as! Point })
        case .multiLineString: return f.createMultiLineString(parts.map { $0.topology(f) as! LineString })
        case .multiPolygon: return f.createMultiPolygon(parts.map { $0.topology(f) as! Polygon })
        case .geometryCollection: return f.createGeometryCollection(parts.map { $0.topology(f) })
        }
    }
}
