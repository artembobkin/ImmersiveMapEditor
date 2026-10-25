/// Triangulates a polygon of one ring (its holes joined into it) by
/// clipping ears: JTS's `PolygonEarClipper`. The ring is clockwise and
/// closed; the triangles come in the order they are clipped.
struct PolygonEarClipper {
    static let noVertexIndex = -1

    static func triangulate(_ polyShell: [Coordinate]) throws -> [Tri] {
        // A shell collapsed to one point: GEOS reads past it (undefined
        // behaviour) and gives no triangles, as here.
        if polyShell.count < 3 { return [] }
        var clipper = PolygonEarClipper(polyShell)
        return try clipper.compute()
    }

    var isFlatCornersSkipped = false
    let vertex: [Coordinate]
    var vertexNext: [Int]
    var vertexSize: Int
    var vertexFirst = 0
    var cornerIndex = [0, 1, 2]
    var vertexCoordIndex: VertexSequencePackedRtree

    init(_ polyShell: [Coordinate]) {
        vertex = polyShell
        vertexSize = polyShell.count - 1
        var next = (0..<vertexSize).map { $0 + 1 }
        next[vertexSize - 1] = 0
        vertexNext = next
        vertexCoordIndex = VertexSequencePackedRtree(polyShell)
    }

    mutating func compute() throws -> [Tri] {
        var triList: [Tri] = []
        var cornerScanCount = 0
        var corner = fetchCorner()
        while true {
            if !PolygonEarClipper.isConvex(corner) {
                let isCornerRemoved = PolygonEarClipper.isCornerInvalid(corner) || (isFlatCornersSkipped && PolygonEarClipper.isFlat(corner))
                if isCornerRemoved { removeCorner() }
                cornerScanCount += 1
                if cornerScanCount > 2 * vertexSize { throw IllegalStateException("Unable to find a convex corner") }
            } else if isValidEar(cornerIndex[1], corner) {
                triList.append(Tri(corner[0], corner[1], corner[2]))
                removeCorner()
                cornerScanCount = 0
            }
            if cornerScanCount > 2 * vertexSize { throw IllegalStateException("Unable to find a valid ear") }
            if vertexSize < 3 { return triList }
            if vertexSize >= 3 {
                cornerIndex[0] = vertexNext[cornerIndex[0]]
                cornerIndex[1] = vertexNext[cornerIndex[0]]
                cornerIndex[2] = vertexNext[cornerIndex[1]]
                corner = fetchCorner()
            }
        }
    }

    /// Whether the corner is an ear: no other vertex inside it, or only
    /// one at its apex which leaves it valid.
    private func isValidEar(_ cornerIndex: Int, _ corner: [Coordinate]) -> Bool {
        let intApexIndex = findIntersectingVertex(cornerIndex, corner)
        if intApexIndex == PolygonEarClipper.noVertexIndex { return true }
        if vertex[intApexIndex].equals2D(corner[1]) { return isValidEarScan(cornerIndex, corner) }
        return false
    }

    private func findIntersectingVertex(_ cornerIndex: Int, _ corner: [Coordinate]) -> Int {
        var cornerEnv = Envelope(corner[0], corner[1])
        cornerEnv.expandToInclude(corner[2])
        var dupApexIndex = PolygonEarClipper.noVertexIndex
        for vertIndex in vertexCoordIndex.query(cornerEnv) {
            if vertIndex == cornerIndex || vertIndex == vertex.count - 1 || isRemoved(vertIndex) { continue }
            let v = vertex[vertIndex]
            if v.equals2D(corner[1]) {
                dupApexIndex = vertIndex
            } else if v.equals2D(corner[0]) || v.equals2D(corner[2]) {
                continue
            } else if Triangle.intersects(corner[0], corner[1], corner[2], v) {
                return vertIndex
            }
        }
        return dupApexIndex
    }

    /// Scans the ring for another vertex at the apex whose edges enter the
    /// corner (the ear would then cross them).
    private func isValidEarScan(_ cornerIndex: Int, _ corner: [Coordinate]) -> Bool {
        let cornerAngle = Angle.angleBetweenOriented(corner[0], corner[1], corner[2])
        var currIndex = vertexNext[vertexFirst]
        var prevIndex = vertexFirst
        for _ in 0..<vertexSize {
            let vPrev = vertex[prevIndex]
            let v = vertex[currIndex]
            if currIndex != cornerIndex && v.equals2D(corner[1]) {
                let vNext = vertex[vertexNext[currIndex]]
                let aOut = Angle.angleBetweenOriented(corner[0], corner[1], vNext)
                let aIn = Angle.angleBetweenOriented(corner[0], corner[1], vPrev)
                if aOut > 0 && aOut < cornerAngle { return false }
                if aIn > 0 && aIn < cornerAngle { return false }
                if aOut == 0 && aIn == cornerAngle { return false }
            }
            prevIndex = currIndex
            currIndex = vertexNext[currIndex]
        }
        return true
    }

    private mutating func removeCorner() {
        let cornerApexIndex = cornerIndex[1]
        if vertexFirst == cornerApexIndex { vertexFirst = vertexNext[cornerApexIndex] }
        vertexNext[cornerIndex[0]] = vertexNext[cornerApexIndex]
        vertexCoordIndex.remove(cornerApexIndex)
        vertexNext[cornerApexIndex] = PolygonEarClipper.noVertexIndex
        vertexSize -= 1
        cornerIndex[1] = vertexNext[cornerIndex[0]]
        cornerIndex[2] = vertexNext[cornerIndex[1]]
    }

    private func isRemoved(_ vertexIndex: Int) -> Bool { vertexNext[vertexIndex] == PolygonEarClipper.noVertexIndex }

    private func fetchCorner() -> [Coordinate] { [vertex[cornerIndex[0]], vertex[cornerIndex[1]], vertex[cornerIndex[2]]] }

    private static func isConvex(_ pts: [Coordinate]) -> Bool { Orientation.index(pts[0], pts[1], pts[2]) == Orientation.clockwise }
    private static func isFlat(_ pts: [Coordinate]) -> Bool { Orientation.index(pts[0], pts[1], pts[2]) == Orientation.collinear }

    private static func isCornerInvalid(_ pts: [Coordinate]) -> Bool {
        pts[1].equals2D(pts[0]) || pts[1].equals2D(pts[2]) || pts[0].equals2D(pts[2])
    }
}

/// Improves a triangulation towards Delaunay by flipping the diagonals of
/// convex quadrilaterals whose triangles fail the in-circle test: JTS's
/// `TriDelaunayImprover`, with GEOS 3.13's in-circle test.
enum TriDelaunayImprover {
    static let maxIteration = 200

    static func improve(_ triList: [Tri]) {
        for _ in 0..<maxIteration where improveScan(triList) == 0 { return }
    }

    private static func improveScan(_ triList: [Tri]) -> Int {
        var improveCount = 0
        if triList.isEmpty { return 0 }
        for i in 0..<(triList.count - 1) {
            let tri = triList[i]
            for j in 0..<3 where improveNonDelaunay(tri, j) { improveCount += 1 }
        }
        return improveCount
    }

    private static func improveNonDelaunay(_ tri: Tri, _ index: Int) -> Bool {
        guard let tri1 = tri.getAdjacent(index) else { return false }
        let index1 = tri1.getIndex(tri)
        let adj0 = tri.getCoordinate(index)
        let adj1 = tri.getCoordinate(Tri.next(index))
        let opp0 = tri.getCoordinate(Tri.oppVertex(index))
        let opp1 = tri1.getCoordinate(Tri.oppVertex(index1))
        if !isConvex(adj0, adj1, opp0, opp1) { return false }
        if !isDelaunay(adj0, adj1, opp0, opp1) {
            tri.flip(index)
            return true
        }
        return false
    }

    private static func isConvex(_ adj0: Coordinate, _ adj1: Coordinate, _ opp0: Coordinate, _ opp1: Coordinate) -> Bool {
        let dir0 = Orientation.index(opp0, adj0, opp1)
        let dir1 = Orientation.index(opp1, adj1, opp0)
        return dir0 == dir1
    }

    private static func isDelaunay(_ adj0: Coordinate, _ adj1: Coordinate, _ opp0: Coordinate, _ opp1: Coordinate) -> Bool {
        if isInCircle(adj0, adj1, opp0, opp1) { return false }
        if isInCircle(adj1, adj0, opp1, opp0) { return false }
        return true
    }

    private static func isInCircle(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate, _ p: Coordinate) -> Bool {
        TrianglePredicate.isInCircleNormalized(a, c, b, p) == Location.interior
    }
}

/// The in-circle test of a point against a triangle: GEOS 3.13's
/// `TrianglePredicate::isInCircleNormalized`, which JTS's `isInCircleRobust`
/// calls there. It is not JTS's: it compares the two sums of the
/// determinant's terms (in `long double`, which is `double` on arm64), with
/// clang's fused products, and gives the location of the point.
enum TrianglePredicate {
    static func isInCircleNormalized(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate, _ p: Coordinate) -> Int {
        let adx = a.x - p.x, ady = a.y - p.y
        let bdx = b.x - p.x, bdy = b.y - p.y
        let cdx = c.x - p.x, cdy = c.y - p.y
        let bdxcdy = bdx * cdy
        let cdxbdy = cdx * bdy
        let alift = fusedAdd(adx, adx, ady * ady)
        let cdxady = cdx * ady
        let adxcdy = adx * cdy
        let blift = fusedAdd(bdx, bdx, bdy * bdy)
        let adxbdy = adx * bdy
        let bdxady = bdx * ady
        let clift = fusedAdd(cdx, cdx, cdy * cdy)
        let sumA = fusedAdd(clift, adxbdy, fusedAdd(alift, bdxcdy, blift * cdxady))
        let sumB = fusedAdd(clift, bdxady, fusedAdd(alift, cdxbdy, blift * adxcdy))
        if sumA < sumB { return Location.exterior }
        if sumA == sumB { return Location.boundary }
        return Location.interior
    }
}

extension Triangle {
    /// Whether a triangle contains or touches a point.
    static func intersects(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate, _ p: Coordinate) -> Bool {
        let exteriorIndex = Orientation.index(a, b, c) == Orientation.counterclockwise ? Orientation.clockwise : Orientation.counterclockwise
        if exteriorIndex == Orientation.index(a, b, p) { return false }
        if exteriorIndex == Orientation.index(b, c, p) { return false }
        if exteriorIndex == Orientation.index(c, a, p) { return false }
        return true
    }
}
