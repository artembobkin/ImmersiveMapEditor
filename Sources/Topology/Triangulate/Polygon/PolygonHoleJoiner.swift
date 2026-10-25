/// Joins the holes of a polygon into its shell by cuts to shell vertices,
/// giving one ring the ear clipper can triangulate: JTS's
/// `PolygonHoleJoiner`, with `PolygonNoder`, as GEOS 3.13 runs them: the
/// rings are always replaced by their noded coordinates (so repeated points
/// go, JTS replaces only the rings that got nodes), the holes are sorted
/// with libc++'s `std::sort`, and the search for a joinable vertex stops at
/// the first vertex of the ring instead of failing.
struct PolygonHoleJoiner {
    static func join(_ polygon: Polygon) throws -> [Coordinate] {
        var joiner = PolygonHoleJoiner(polygon)
        return try joiner.compute()
    }

    let inputPolygon: Polygon
    var shellRing: [Coordinate] = []
    var holeRings: [[Coordinate]] = []
    var isHoleTouchingHint: [Bool] = []
    var joinedRing: [Coordinate] = []
    /// The points of the joined ring, sorted and unique (GEOS's `std::set`).
    var joinedPts: [Coordinate] = []
    var boundaryIntersector: MCIndexSegmentSetMutualIntersector?

    init(_ polygon: Polygon) { inputPolygon = polygon }

    mutating func compute() throws -> [Coordinate] {
        extractOrientedRings(inputPolygon)
        if !holeRings.isEmpty { nodeRings() }
        joinedRing = shellRing
        if !holeRings.isEmpty { try joinHoles() }
        return joinedRing
    }

    private mutating func extractOrientedRings(_ polygon: Polygon) {
        shellRing = PolygonHoleJoiner.extractOrientedRing(polygon.shell, true)
        var holes = polygon.holes
        CxxAlgorithms.sort(&holes) { $0.getEnvelopeInternal().compareTo($1.getEnvelopeInternal()) < 0 }
        holeRings = holes.map { PolygonHoleJoiner.extractOrientedRing($0, false) }
    }

    private static func extractOrientedRing(_ ring: LinearRing, _ isCW: Bool) -> [Coordinate] {
        let pts = ring.points
        let isRingCW = !Orientation.isCCW(pts)
        return isCW == isRingCW ? pts : pts.reversed()
    }

    /// Nodes the rings against each other (a hole touching the shell or
    /// another hole gets a node there) and notes which holes touch.
    private mutating func nodeRings() {
        var nodedRings = [NodedSegmentString(shellRing, 0)]
        for (i, h) in holeRings.enumerated() { nodedRings.append(NodedSegmentString(h, i + 1)) }
        let nodeAdder = NodeAdder(holeRings.count)
        let noder = MCIndexNoder(nodeAdder)
        noder.computeNodes(nodedRings)
        shellRing = nodedRings[0].getNodedCoordinates()
        for i in 0..<holeRings.count { holeRings[i] = nodedRings[i + 1].getNodedCoordinates() }
        isHoleTouchingHint = nodeAdder.isHoleTouching
    }

    /// Adds a node where two rings touch at a point inside a segment of
    /// one, and records the holes that touch (JTS's `PolygonNoder.NodeAdder`).
    final class NodeAdder: SegmentIntersector {
        @exclusivity(unchecked) var li = RobustLineIntersector()
        @exclusivity(unchecked) var isHoleTouching: [Bool]

        init(_ holeCount: Int) { isHoleTouching = Array(repeating: false, count: holeCount) }

        override func processIntersections(_ ss0: SegmentString, _ segIndex0: Int, _ ss1: SegmentString, _ segIndex1: Int) {
            if ss0 === ss1 { return }
            let p00 = ss0.getCoordinate(segIndex0), p01 = ss0.getCoordinate(segIndex0 + 1)
            let p10 = ss1.getCoordinate(segIndex1), p11 = ss1.getCoordinate(segIndex1 + 1)
            li.computeIntersection(p00, p01, p10, p11)
            if li.getIntersectionNum() == 1 {
                addTouch(ss0)
                addTouch(ss1)
                let intPt = li.getIntersection(0)
                if li.isInteriorIntersection(0) {
                    (ss0 as! NodedSegmentString).addIntersection(intPt, segIndex0)
                } else if li.isInteriorIntersection(1) {
                    (ss1 as! NodedSegmentString).addIntersection(intPt, segIndex1)
                }
            }
        }

        private func addTouch(_ ss: SegmentString) {
            let holeIndex = ss.getData() as! Int
            if holeIndex > 0 { isHoleTouching[holeIndex - 1] = true }
        }

        override func isDone() -> Bool { false }
    }

    private mutating func joinHoles() throws {
        var polySegStrings: [SegmentString] = [BasicSegmentString(shellRing, nil)]
        for h in holeRings { polySegStrings.append(BasicSegmentString(h, nil)) }
        boundaryIntersector = MCIndexSegmentSetMutualIntersector(polySegStrings)
        joinedPts = []
        for p in joinedRing { insertJoinedPt(p) }
        for i in 0..<holeRings.count { try joinHole(i, holeRings[i]) }
    }

    /// The index of the first joined point not less than `p`.
    private func lowerBound(_ p: Coordinate) -> Int {
        var lo = 0, hi = joinedPts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if joinedPts[mid].compareTo(p) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The index of the first joined point greater than `p`.
    private func upperBound(_ p: Coordinate) -> Int {
        var lo = 0, hi = joinedPts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if p.compareTo(joinedPts[mid]) < 0 { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    private mutating func insertJoinedPt(_ p: Coordinate) {
        let i = lowerBound(p)
        if i < joinedPts.count && joinedPts[i].compareTo(p) == 0 { return }
        joinedPts.insert(p, at: i)
    }

    private func containsJoinedPt(_ p: Coordinate) -> Bool {
        let i = lowerBound(p)
        return i < joinedPts.count && joinedPts[i].compareTo(p) == 0
    }

    private mutating func joinHole(_ index: Int, _ holeCoords: [Coordinate]) throws {
        if isHoleTouchingHint[index] {
            if try joinTouchingHole(holeCoords) { return }
        }
        try joinNonTouchingHole(holeCoords)
    }

    private mutating func joinTouchingHole(_ holeCoords: [Coordinate]) throws -> Bool {
        guard let holeTouchIndex = holeCoords.firstIndex(where: { containsJoinedPt($0) }) else { return false }
        let joinPt = holeCoords[holeTouchIndex]
        let holeSegPt = holeCoords[PolygonHoleJoiner.prev(holeTouchIndex, holeCoords.count)]
        let joinIndex = try findJoinIndex(joinPt, holeSegPt)
        addJoinedHole(joinIndex, holeCoords, holeTouchIndex)
        return true
    }

    private mutating func joinNonTouchingHole(_ holeCoords: [Coordinate]) throws {
        // A hole collapsed to one point (all its points repeated) has no
        // lowest left vertex: GEOS reads past the hole there (undefined
        // behaviour) and ends failing to find a join index, as here.
        if holeCoords.count <= 1 { throw IllegalStateException("Unable to find shell join index with interior join line") }
        let holeJoinIndex = PolygonHoleJoiner.findLowestLeftVertexIndex(holeCoords)
        let holeJoinCoord = holeCoords[holeJoinIndex]
        let joinCoord = try findJoinableVertex(holeJoinCoord)
        let joinIndex = try findJoinIndex(joinCoord, holeJoinCoord)
        addJoinedHole(joinIndex, holeCoords, holeJoinIndex)
    }

    /// The vertex of the joined ring left of the hole's lowest left vertex
    /// (the nearest in order first) that a cut can reach without crossing
    /// the boundary.
    private func findJoinableVertex(_ holeJoinCoord: Coordinate) throws -> Coordinate {
        var it = upperBound(holeJoinCoord)
        while true {
            guard it < joinedPts.count else { throw IllegalStateException("Unable to find joinable vertex") }
            if joinedPts[it].x != holeJoinCoord.x { break }
            it += 1
        }
        repeat {
            guard it > 0 else { throw IllegalStateException("Unable to find joinable vertex") }
            it -= 1
        } while intersectsBoundary(holeJoinCoord, joinedPts[it]) && it != 0
        return joinedPts[it]
    }

    private func findJoinIndex(_ joinCoord: Coordinate, _ holeJoinCoord: Coordinate) throws -> Int {
        for i in 0..<(joinedRing.count - 1) where joinCoord.equals2D(joinedRing[i]) {
            if isLineInterior(joinedRing, i, holeJoinCoord) { return i }
        }
        throw IllegalStateException("Unable to find shell join index with interior join line")
    }

    private func isLineInterior(_ ring: [Coordinate], _ ringIndex: Int, _ linePt: Coordinate) -> Bool {
        let nodePt = ring[ringIndex]
        let shell0 = ring[PolygonHoleJoiner.prev(ringIndex, ring.count)]
        let shell1 = ring[PolygonHoleJoiner.next(ringIndex, ring.count)]
        return PolygonNodeTopology.isInteriorSegment(nodePt, shell0, shell1, linePt)
    }

    private static func prev(_ i: Int, _ size: Int) -> Int { i == 0 ? size - 2 : i - 1 }

    private static func next(_ i: Int, _ size: Int) -> Int {
        let next = i + 1
        if size < 2 || next > size - 2 { return 0 }
        return next
    }

    private mutating func addJoinedHole(_ joinIndex: Int, _ holeCoords: [Coordinate], _ holeJoinIndex: Int) {
        let joinPt = joinedRing[joinIndex]
        let holeJoinPt = holeCoords[holeJoinIndex]
        let isVertexTouch = joinPt.equals2D(holeJoinPt)
        // The section of the hole: from its join point round to it, and
        // back to the shell's join point when the hole does not touch it.
        var section: [Coordinate] = []
        if !isVertexTouch { section.append(holeCoords[holeJoinIndex]) }
        let holeSize = holeCoords.count - 1
        var index = holeJoinIndex
        for _ in 0..<holeSize {
            index = (index + 1) % holeSize
            section.append(holeCoords[index])
        }
        if !isVertexTouch { section.append(joinPt) }
        joinedRing.insert(contentsOf: section, at: joinIndex + 1)
        for p in section { insertJoinedPt(p) }
    }

    private static func findLowestLeftVertexIndex(_ coords: [Coordinate]) -> Int {
        var lowestLeftCoord: Coordinate?
        var lowestLeftIndex = -1
        for i in 0..<(coords.count - 1) where lowestLeftCoord == nil || coords[i].compareTo(lowestLeftCoord!) < 0 {
            lowestLeftCoord = coords[i]
            lowestLeftIndex = i
        }
        return lowestLeftIndex
    }

    private func intersectsBoundary(_ p0: Coordinate, _ p1: Coordinate) -> Bool {
        let segInt = InteriorIntersectionDetector()
        boundaryIntersector!.process([BasicSegmentString([p0, p1], nil)], segInt)
        return segInt.hasIntersection
    }

    /// Whether a segment meets the boundary other than at a common end point.
    final class InteriorIntersectionDetector: SegmentIntersector {
        @exclusivity(unchecked) var li = RobustLineIntersector()
        @exclusivity(unchecked) private(set) var hasIntersection = false

        override func processIntersections(_ ss0: SegmentString, _ segIndex0: Int, _ ss1: SegmentString, _ segIndex1: Int) {
            let p00 = ss0.getCoordinate(segIndex0), p01 = ss0.getCoordinate(segIndex0 + 1)
            let p10 = ss1.getCoordinate(segIndex1), p11 = ss1.getCoordinate(segIndex1 + 1)
            li.computeIntersection(p00, p01, p10, p11)
            if li.getIntersectionNum() == 0 { return }
            if li.getIntersectionNum() == 1 {
                if li.isInteriorIntersection() { hasIntersection = true }
            } else {
                // Two intersections: collinear.
                hasIntersection = true
            }
        }

        override func isDone() -> Bool { hasIntersection }
    }
}

/// The constrained Delaunay triangulation of the polygons of a geometry:
/// JTS's `ConstrainedDelaunayTriangulator`, as `GEOSConstrainedDelaunayTriangulation`
/// runs it (an empty input or polygon gives no triangles). Each polygon's
/// holes are joined into its shell, the ring is clipped into ears, and the
/// triangles are flipped towards Delaunay; the result is a collection of
/// the triangles, polygon by polygon.
public enum ConstrainedDelaunayTriangulator {
    public static func triangulate(_ geom: Geometry) throws -> GeometryCollection {
        try NonFinite.scope { try compute(geom) }
    }

    static func compute(_ geom: Geometry) throws -> GeometryCollection {
        let factory = geom.factory
        if geom.isEmpty() { return factory.createGeometryCollection() }
        var polys: [Polygon] = []
        geom.applyGeometries { if let p = $0 as? Polygon { polys.append(p) } }
        var result: [Geometry] = []
        for poly in polys where !poly.isEmpty() {
            let polyShell = try PolygonHoleJoiner.join(poly)
            let triList = try PolygonEarClipper.triangulate(polyShell)
            try TriangulationBuilder.build(triList)
            TriDelaunayImprover.improve(triList)
            for tri in triList { result.append(tri.toPolygon(factory)) }
        }
        return factory.createGeometryCollection(result)
    }
}
