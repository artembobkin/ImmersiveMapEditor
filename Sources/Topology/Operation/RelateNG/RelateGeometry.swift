/// A geometry as RelateNG sees it: its real dimension (a zero-length line is
/// a point, an empty geometry has none), which kinds of element it has, its
/// point locator, and its edges as segment strings: JTS's `RelateGeometry`.
final class RelateGeometry {
    static let geomA = true
    static let geomB = false

    let geom: Geometry
    let isPrepared: Bool
    let envelope: Envelope
    @exclusivity(unchecked) private(set) var dimension: Int
    @exclusivity(unchecked) private var uniquePoints: Set<Coordinate>?
    private let boundaryNodeRule: BoundaryNodeRule
    @exclusivity(unchecked) private var locator: RelatePointLocator?
    @exclusivity(unchecked) private var elementId = 0
    @exclusivity(unchecked) private var hasPoints = false
    @exclusivity(unchecked) private var hasLines = false
    @exclusivity(unchecked) private var hasAreas = false
    @exclusivity(unchecked) private var isLineZeroLen = false
    let isEmpty: Bool

    init(_ input: Geometry, _ isPrepared: Bool = false, _ bnRule: BoundaryNodeRule = .ogcSFS) {
        geom = input
        envelope = input.getEnvelopeInternal()
        self.isPrepared = isPrepared
        boundaryNodeRule = bnRule
        isEmpty = input.isEmpty()
        dimension = input.getDimension()
        // GEOS decides on a zero-length line by the geometry's own dimension,
        // before the elements are looked at (JTS after).
        isLineZeroLen = dimension == Dimension.l && RelateGeometry.isZeroLength(input)
        analyzeDimensions()
    }

    private func analyzeDimensions() {
        if isEmpty { return }
        if geom is Point || geom is MultiPoint {
            hasPoints = true
            dimension = Dimension.p
            return
        }
        if geom is LineString || geom is MultiLineString {
            hasLines = true
            dimension = Dimension.l
            return
        }
        if geom is Polygon || geom is MultiPolygon {
            hasAreas = true
            dimension = Dimension.a
            return
        }
        geom.applyGeometries { elem in
            if elem.isEmpty() { return }
            if elem is Point {
                hasPoints = true
                if dimension < Dimension.p { dimension = Dimension.p }
            }
            if elem is LineString {
                hasLines = true
                if dimension < Dimension.l { dimension = Dimension.l }
            }
            if elem is Polygon {
                hasAreas = true
                if dimension < Dimension.a { dimension = Dimension.a }
            }
        }
    }

    private static func isZeroLength(_ geom: Geometry) -> Bool {
        var zero = true
        geom.applyGeometries { elem in
            if let line = elem as? LineString, !isZeroLength(line) { zero = false }
        }
        return zero
    }

    private static func isZeroLength(_ line: LineString) -> Bool {
        if line.points.count >= 2 {
            let p0 = line.points[0]
            for p in line.points where !p0.equals2D(p) { return false }
        }
        return true
    }

    func hasDimension(_ dim: Int) -> Bool {
        switch dim {
        case Dimension.p: return hasPoints
        case Dimension.l: return hasLines
        case Dimension.a: return hasAreas
        default: return false
        }
    }

    /// The dimension of the non-empty elements, a zero-length line a point.
    var dimensionReal: Int {
        if isEmpty { return Dimension.false }
        if dimension == 1 && isLineZeroLen { return Dimension.p }
        if hasAreas { return Dimension.a }
        if hasLines { return Dimension.l }
        return Dimension.p
    }

    var hasEdges: Bool { hasLines || hasAreas }

    private func getLocator() -> RelatePointLocator {
        if let locator { return locator }
        let l = RelatePointLocator(geom, isPrepared, boundaryNodeRule)
        locator = l
        return l
    }

    func isNodeInArea(_ nodePt: Coordinate, _ parentPolygonal: Geometry?) -> Bool {
        getLocator().locateNodeWithDim(nodePt, parentPolygonal) == DimensionLocation.areaInterior
    }

    func locateLineEndWithDim(_ p: Coordinate) -> Int { getLocator().locateLineEndWithDim(p) }
    func locateAreaVertex(_ pt: Coordinate) -> Int { locateNode(pt, nil) }
    func locateNode(_ pt: Coordinate, _ parentPolygonal: Geometry?) -> Int { getLocator().locateNode(pt, parentPolygonal) }
    func locateWithDim(_ pt: Coordinate) -> Int { getLocator().locateWithDim(pt) }

    /// Whether its edges may cross each other (lines, or several polygons
    /// in a collection), so it must be noded against itself.
    var isSelfNodingRequired: Bool {
        if geom is Point || geom is MultiPoint || geom is Polygon || geom is MultiPolygon { return false }
        if hasAreas && geom.getNumGeometries() == 1 { return false }
        return true
    }

    var isPolygonal: Bool { geom is Polygon || geom is MultiPolygon }
    var hasBoundary: Bool { getLocator().hasBoundary }

    func getUniquePoints() -> Set<Coordinate> {
        if let uniquePoints { return uniquePoints }
        var set = Set<Coordinate>()
        geom.applyComponents { c in
            if let l = c as? LineString, let p = l.points.first { set.insert(p) }
            if let pt = c as? Point, let p = pt.getCoordinate() { set.insert(p) }
        }
        uniquePoints = set
        return set
    }

    /// The points that are not covered by lines or areas of the geometry.
    func getEffectivePoints() -> [Point] {
        var ptListAll: [Point] = []
        geom.applyComponents { if let p = $0 as? Point { ptListAll.append(p) } }
        if dimensionReal <= Dimension.p { return ptListAll }
        return ptListAll.filter { p in
            guard let c = p.getCoordinate() else { return false }
            return DimensionLocation.dimension(locateWithDim(c)) == Dimension.p
        }
    }

    func extractSegmentStrings(_ isA: Bool, _ env: Envelope?) -> [RelateSegmentString] {
        var segStrings: [RelateSegmentString] = []
        extractSegmentStrings(isA, env, geom, &segStrings)
        return segStrings
    }

    private func extractSegmentStrings(_ isA: Bool, _ env: Envelope?, _ geom: Geometry, _ segStrings: inout [RelateSegmentString]) {
        let parentPolygonal = geom as? MultiPolygon
        for i in 0..<geom.getNumGeometries() {
            let g = geom.getGeometryN(i)
            if g is GeometryCollection {
                extractSegmentStrings(isA, env, g, &segStrings)
            } else {
                extractSegmentStringsFromAtomic(isA, g, parentPolygonal, env, &segStrings)
            }
        }
    }

    private func extractSegmentStringsFromAtomic(_ isA: Bool, _ geom: Geometry, _ parentPolygonal: MultiPolygon?, _ env: Envelope?,
                                                 _ segStrings: inout [RelateSegmentString]) {
        if geom.isEmpty() { return }
        let doExtract = env == nil || env!.intersects(geom.getEnvelopeInternal())
        if !doExtract { return }
        elementId += 1
        if let line = geom as? LineString {
            segStrings.append(RelateSegmentString.createLine(line.points, isA, elementId, self))
        } else if let poly = geom as? Polygon {
            let parentPoly: Geometry = parentPolygonal ?? poly
            extractRingToSegmentString(isA, poly.shell, 0, env, parentPoly, &segStrings)
            for (i, hole) in poly.holes.enumerated() {
                extractRingToSegmentString(isA, hole, i + 1, env, parentPoly, &segStrings)
            }
        }
    }

    private func extractRingToSegmentString(_ isA: Bool, _ ring: LinearRing, _ ringId: Int, _ env: Envelope?,
                                            _ parentPoly: Geometry, _ segStrings: inout [RelateSegmentString]) {
        if ring.isEmpty() { return }
        if let env, !env.intersects(ring.getEnvelopeInternal()) { return }
        // Shells clockwise, holes counter-clockwise: the area on the right.
        let pts = RelateGeometry.orient(ring.points, ringId == 0)
        segStrings.append(RelateSegmentString.createRing(pts, isA, elementId, ringId, parentPoly, self))
    }

    static func orient(_ pts: [Coordinate], _ orientCW: Bool) -> [Coordinate] {
        orientCW == Orientation.isCCW(pts) ? pts.reversed() : pts
    }
}
