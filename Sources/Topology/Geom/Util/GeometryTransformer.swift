/// Rebuilds a geometry component by component, each step a method a
/// subclass may override: JTS's `GeometryTransformer`, with GEOS 3.13's
/// rules (it prunes empty members of collections and keeps a collection's
/// type, and a polygon whose rings are not all rings becomes the geometry
/// of its parts). Coordinates come back nil where GEOS returns a null
/// sequence, which makes an empty component.
class GeometryTransformer {
    @exclusivity(unchecked) var factory: GeometryFactory = .default
    @exclusivity(unchecked) var inputGeom: Geometry?
    @exclusivity(unchecked) var pruneEmptyGeometry = true
    @exclusivity(unchecked) var preserveGeometryCollectionType = true
    @exclusivity(unchecked) var preserveType = false
    @exclusivity(unchecked) var skipTransformedInvalidInteriorRings = false

    func transform(_ inputGeom: Geometry) throws -> Geometry {
        self.inputGeom = inputGeom
        factory = inputGeom.factory
        switch inputGeom {
        case let p as Point: return try transformPoint(p, nil)
        case let m as MultiPoint: return try transformMultiPoint(m, nil)
        case let r as LinearRing: return try transformLinearRing(r, nil)
        case let l as LineString: return try transformLineString(l, nil)
        case let m as MultiLineString: return try transformMultiLineString(m, nil)
        case let p as Polygon: return try transformPolygon(p, nil)
        case let m as MultiPolygon: return try transformMultiPolygon(m, nil)
        case let c as GeometryCollection: return try transformGeometryCollection(c, nil)
        default: throw IllegalArgumentException("Unknown Geometry subtype.")
        }
    }

    func transformCoordinates(_ coords: [Coordinate], _ parent: Geometry) throws -> [Coordinate]? { coords }

    func transformPoint(_ geom: Point, _ parent: Geometry?) throws -> Geometry {
        factory.createPoint(try transformCoordinates(geom.coordinates, geom) ?? [])
    }

    func transformMultiPoint(_ geom: MultiPoint, _ parent: Geometry?) throws -> Geometry {
        var transGeomList: [Geometry] = []
        for p in geom.geometries {
            let g = try transformPoint(p as! Point, geom)
            if g.isEmpty() { continue }
            transGeomList.append(g)
        }
        if transGeomList.isEmpty { return factory.createMultiPoint() }
        return factory.buildGeometry(transGeomList)
    }

    func transformLinearRing(_ geom: LinearRing, _ parent: Geometry?) throws -> Geometry {
        let seq = try transformCoordinates(geom.points, geom) ?? []
        if seq.count > 0 && seq.count < 4 && !preserveType { return factory.createLineString(seq) }
        return factory.createLinearRing(seq)
    }

    func transformLineString(_ geom: LineString, _ parent: Geometry?) throws -> Geometry {
        factory.createLineString(try transformCoordinates(geom.points, geom) ?? [])
    }

    func transformMultiLineString(_ geom: MultiLineString, _ parent: Geometry?) throws -> Geometry {
        var transGeomList: [Geometry] = []
        for l in geom.geometries {
            let g = try transformLineString(l as! LineString, geom)
            if g.isEmpty() { continue }
            transGeomList.append(g)
        }
        if transGeomList.isEmpty { return factory.createMultiLineString() }
        return factory.buildGeometry(transGeomList)
    }

    func transformPolygon(_ geom: Polygon, _ parent: Geometry?) throws -> Geometry {
        var isAllValidLinearRings = true
        let shell = try transformLinearRing(geom.shell, geom)
        if !(shell is LinearRing) || shell.isEmpty() { isAllValidLinearRings = false }
        var holes: [LinearRing] = []
        for h in geom.holes {
            let hole = try transformLinearRing(h, geom)
            if hole.isEmpty() { continue }
            if let r = hole as? LinearRing {
                holes.append(r)
            } else {
                if skipTransformedInvalidInteriorRings { continue }
                isAllValidLinearRings = false
            }
        }
        if isAllValidLinearRings { return factory.createPolygon(shell as? LinearRing, holes) }
        return factory.buildGeometry([shell] + holes)
    }

    func transformMultiPolygon(_ geom: MultiPolygon, _ parent: Geometry?) throws -> Geometry {
        var transGeomList: [Geometry] = []
        for p in geom.geometries {
            let g = try transformPolygon(p as! Polygon, geom)
            if g.isEmpty() { continue }
            transGeomList.append(g)
        }
        if transGeomList.isEmpty { return factory.createMultiPolygon() }
        return factory.buildGeometry(transGeomList)
    }

    func transformGeometryCollection(_ geom: GeometryCollection, _ parent: Geometry?) throws -> Geometry {
        var transGeomList: [Geometry] = []
        for g in geom.geometries {
            let t = try transform(g)
            if pruneEmptyGeometry && t.isEmpty() { continue }
            transGeomList.append(t)
        }
        if preserveGeometryCollectionType { return factory.createGeometryCollection(transGeomList) }
        return factory.buildGeometry(transGeomList)
    }
}

/// JTS's `GeometryEditor` with its `NoOpGeometryOperation`, as GEOS 3.13
/// edits: a copy in another factory, without the empty members of
/// collections and the empty holes of polygons.
enum GeometryEditor {
    static func copy(_ g: Geometry, _ factory: GeometryFactory) -> Geometry {
        switch g {
        case let c as GeometryCollection:
            let members = c.geometries.map { copy($0, factory) }.filter { !$0.isEmpty() }
            switch c {
            case is MultiPoint: return factory.createMultiPoint(members.map { $0 as! Point })
            case is MultiLineString: return factory.createMultiLineString(members.map { $0 as! LineString })
            case is MultiPolygon: return factory.createMultiPolygon(members.map { $0 as! Polygon })
            default: return factory.createGeometryCollection(members)
            }
        case let p as Polygon:
            if p.isEmpty() { return factory.createPolygon() }
            return factory.createPolygon(factory.createLinearRing(p.shell.points),
                                         p.holes.filter { !$0.isEmpty() }.map { factory.createLinearRing($0.points) })
        default:
            return factory.createGeometry(g)
        }
    }
}
