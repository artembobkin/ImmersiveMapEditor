/// The rectangle of least area around a geometry: JTS's
/// `MinimumAreaRectangle`, by rotating calipers over the convex hull.
public struct MinimumAreaRectangle {
    let inputGeom: Geometry
    let isConvex: Bool

    public init(_ inputGeom: Geometry, isConvex: Bool = false) {
        self.inputGeom = inputGeom
        self.isConvex = isConvex
    }

    public static func getMinimumRectangle(_ geom: Geometry) -> Geometry { MinimumAreaRectangle(geom).getMinimumRectangle() }

    public func getMinimumRectangle() -> Geometry {
        if inputGeom.isEmpty() { return inputGeom.factory.createPolygon() }
        if isConvex { return computeConvex(inputGeom) }
        let (hull, raised) = NonFinite.watch { ConvexHull(inputGeom).getConvexHull() }
        // GEOS's hull has thrown on a non-finite point (`NonFinite`): the
        // calipers would index past the ring, and the result is discarded.
        if raised { return inputGeom.factory.createPolygon() }
        return computeConvex(hull)
    }

    func computeConvex(_ convexGeom: Geometry) -> Geometry {
        let pts = (convexGeom as? Polygon)?.shell.points ?? convexGeom.getCoordinates()
        if pts.count == 1 { return inputGeom.factory.createPoint(pts[0]) }
        if pts.count == 2 || pts.count == 3 { return computeMaximumLine(pts, inputGeom.factory) }
        return computeConvexRing(pts)
    }

    func computeConvexRing(_ ring: [Coordinate]) -> Polygon {
        var minArea = Double.greatestFiniteMagnitude
        var minBase = -1, minDiam = -1, minLeft = -1, minRight = -1
        var diameterIndex = 1
        var leftSideIndex = 1
        var rightSideIndex = -1
        for i in 0..<(ring.count - 1) {
            let segBase = LineSegment(ring[i], ring[i + 1])
            diameterIndex = findFurthestVertex(ring, segBase, diameterIndex, 0)
            let diamPt = ring[diameterIndex]
            let diamBasePt = segBase.project(diamPt)
            let segDiam = LineSegment(diamBasePt, diamPt)
            leftSideIndex = findFurthestVertex(ring, segDiam, leftSideIndex, 1)
            if i == 0 { rightSideIndex = diameterIndex }
            rightSideIndex = findFurthestVertex(ring, segDiam, rightSideIndex, -1)
            let rectWidth = segDiam.distancePerpendicular(ring[leftSideIndex]) + segDiam.distancePerpendicular(ring[rightSideIndex])
            let rectArea = segDiam.getLength() * rectWidth
            if rectArea < minArea {
                minArea = rectArea
                minBase = i
                minDiam = diameterIndex
                minLeft = leftSideIndex
                minRight = rightSideIndex
            }
        }
        // No rectangle has an area below the largest double only where the
        // hull has an infinite or NaN point: GEOS then reads before its ring
        // (undefined behaviour, not compared); the port fails instead.
        if minBase < 0 {
            NonFinite.raise()
            return inputGeom.factory.createPolygon()
        }
        return Rectangle.createFromSidePts(ring[minBase], ring[minBase + 1], ring[minDiam], ring[minLeft], ring[minRight],
                                           inputGeom.factory)
    }

    func findFurthestVertex(_ pts: [Coordinate], _ baseSeg: LineSegment, _ startIndex: Int, _ orient: Int) -> Int {
        var maxDistance = MinimumAreaRectangle.orientedDistance(baseSeg, pts[startIndex], orient)
        var nextDistance = maxDistance
        var maxIndex = startIndex
        var nextIndex = maxIndex
        while MinimumAreaRectangle.isFurtherOrEqual(nextDistance, maxDistance, orient) {
            maxDistance = nextDistance
            maxIndex = nextIndex
            nextIndex = MinimumAreaRectangle.nextIndex(pts, maxIndex)
            if nextIndex == startIndex { break }
            nextDistance = MinimumAreaRectangle.orientedDistance(baseSeg, pts[nextIndex], orient)
        }
        return maxIndex
    }

    static func isFurtherOrEqual(_ d1: Double, _ d2: Double, _ orient: Int) -> Bool {
        switch orient {
        case 0: return abs(d1) >= abs(d2)
        case 1: return d1 >= d2
        default: return d1 <= d2
        }
    }

    static func orientedDistance(_ seg: LineSegment, _ p: Coordinate, _ orient: Int) -> Double {
        let dist = seg.distancePerpendicularOriented(p)
        return orient == 0 ? abs(dist) : dist
    }

    static func nextIndex(_ ring: [Coordinate], _ index: Int) -> Int {
        let i = index + 1
        return i >= ring.count - 1 ? 0 : i
    }
}
