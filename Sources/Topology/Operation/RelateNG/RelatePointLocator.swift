/// Locates points in a geometry of any kind for RelateNG, with the
/// dimension of the element they are in: polygons first, then lines (their
/// boundary by the rule), then points: JTS's `RelatePointLocator`. A
/// prepared geometry indexes its polygons.
final class RelatePointLocator {
    private let geom: Geometry
    private let isPrepared: Bool
    private let boundaryRule: BoundaryNodeRule
    @exclusivity(unchecked) private var adjEdgeLocator: AdjacentEdgeLocator?
    @exclusivity(unchecked) private var points: Set<Coordinate>?
    @exclusivity(unchecked) private var lines: [LineString]?
    @exclusivity(unchecked) private var polygons: [Geometry]?
    @exclusivity(unchecked) private var polyLocator: [PointOnGeometryLocator?] = []
    @exclusivity(unchecked) private var lineBoundary: LinearBoundary?
    private let isEmpty: Bool

    init(_ geom: Geometry, _ isPrepared: Bool = false, _ bnRule: BoundaryNodeRule = .ogcSFS) {
        self.geom = geom
        self.isPrepared = isPrepared
        boundaryRule = bnRule
        isEmpty = geom.isEmpty()
        extractElements(geom)
        if let lines { lineBoundary = LinearBoundary(lines, boundaryRule) }
        if let polygons { polyLocator = [PointOnGeometryLocator?](repeating: nil, count: polygons.count) }
    }

    var hasBoundary: Bool { lineBoundary!.hasBoundary }

    private func extractElements(_ geom: Geometry) {
        if geom.isEmpty() { return }
        if let pt = geom as? Point {
            if points == nil { points = [] }
            points!.insert(pt.getCoordinate()!)
        } else if let line = geom as? LineString {
            if lines == nil { lines = [] }
            lines!.append(line)
        } else if geom is Polygon || geom is MultiPolygon {
            if polygons == nil { polygons = [] }
            polygons!.append(geom)
        } else if let gc = geom as? GeometryCollection {
            for g in gc.geometries { extractElements(g) }
        }
    }

    func locate(_ p: Coordinate) -> Int { DimensionLocation.location(locateWithDim(p)) }

    /// A line's end: on a polygon, or on the lines' boundary or interior.
    func locateLineEndWithDim(_ p: Coordinate) -> Int {
        if polygons != nil {
            let locPoly = locateOnPolygons(p, false, nil)
            if locPoly != Location.exterior { return DimensionLocation.locationArea(locPoly) }
        }
        return lineBoundary!.isBoundary(p) ? DimensionLocation.lineBoundary : DimensionLocation.lineInterior
    }

    func locateNode(_ p: Coordinate, _ parentPolygonal: Geometry?) -> Int {
        DimensionLocation.location(locateNodeWithDim(p, parentPolygonal))
    }

    func locateNodeWithDim(_ p: Coordinate, _ parentPolygonal: Geometry?) -> Int { locateWithDim(p, true, parentPolygonal) }

    func locateWithDim(_ p: Coordinate) -> Int { locateWithDim(p, false, nil) }

    /// A node of a polygonal geometry is on its boundary, as nodes are
    /// where its edges cross.
    private func locateWithDim(_ p: Coordinate, _ isNode: Bool, _ parentPolygonal: Geometry?) -> Int {
        if isEmpty { return DimensionLocation.exterior }
        if isNode && (geom is Polygon || geom is MultiPolygon) { return DimensionLocation.areaBoundary }
        return computeDimLocation(p, isNode, parentPolygonal)
    }

    private func computeDimLocation(_ p: Coordinate, _ isNode: Bool, _ parentPolygonal: Geometry?) -> Int {
        if polygons != nil {
            let locPoly = locateOnPolygons(p, isNode, parentPolygonal)
            if locPoly != Location.exterior { return DimensionLocation.locationArea(locPoly) }
        }
        if lines != nil {
            let locLine = locateOnLines(p, isNode)
            if locLine != Location.exterior { return DimensionLocation.locationLine(locLine) }
        }
        if let points, points.contains(p) { return DimensionLocation.locationPoint(Location.interior) }
        return DimensionLocation.exterior
    }

    private func locateOnLines(_ p: Coordinate, _ isNode: Bool) -> Int {
        if let lineBoundary, lineBoundary.isBoundary(p) { return Location.boundary }
        // A node of the lines that is not on their boundary is in their interior.
        if isNode { return Location.interior }
        for line in lines! {
            if !line.getEnvelopeInternal().intersects(p) { continue }
            if PointLocation.isOnLine(p, line.points) { return Location.interior }
        }
        return Location.exterior
    }

    private func locateOnPolygons(_ p: Coordinate, _ isNode: Bool, _ parentPolygonal: Geometry?) -> Int {
        var numBdy = 0
        for i in 0..<polygons!.count {
            let loc = locateOnPolygonal(p, isNode, parentPolygonal, i)
            if loc == Location.interior { return Location.interior }
            if loc == Location.boundary { numBdy += 1 }
        }
        if numBdy == 1 { return Location.boundary }
        if numBdy > 1 {
            // On the boundaries of several polygons, adjacent ones perhaps.
            if adjEdgeLocator == nil { adjEdgeLocator = AdjacentEdgeLocator(geom) }
            return adjEdgeLocator!.locate(p)
        }
        return Location.exterior
    }

    private func locateOnPolygonal(_ p: Coordinate, _ isNode: Bool, _ parentPolygonal: Geometry?, _ index: Int) -> Int {
        let polygonal = polygons![index]
        if isNode && parentPolygonal === polygonal { return Location.boundary }
        return getLocator(index).locate(p)
    }

    private func getLocator(_ index: Int) -> PointOnGeometryLocator {
        if let l = polyLocator[index] { return l }
        let polygonal = polygons![index]
        let l: PointOnGeometryLocator = isPrepared ? IndexedPointInAreaLocator(polygonal) : SimplePointInAreaLocator(polygonal)
        polyLocator[index] = l
        return l
    }
}
