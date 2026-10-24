/// The minimum width of a geometry and the rectangle of that width around
/// it: JTS's `MinimumDiameter`, by rotating calipers over the convex hull.
public struct MinimumDiameter {
    let inputGeom: Geometry
    let isConvex: Bool
    var convexHullPts: [Coordinate] = []
    var minBaseSeg: LineSegment? = LineSegment()
    var minWidthPt: Coordinate?
    var minPtIndex = 0
    var minWidth = 0.0
    var computed = false

    public init(_ inputGeom: Geometry, isConvex: Bool = false) {
        self.inputGeom = inputGeom
        self.isConvex = isConvex
    }

    public static func getMinimumRectangle(_ geom: Geometry) -> Geometry {
        var m = MinimumDiameter(geom)
        return m.getMinimumRectangle()
    }

    public static func getMinimumDiameter(_ geom: Geometry) -> Geometry {
        var m = MinimumDiameter(geom)
        return m.getDiameter()
    }

    public mutating func getLength() -> Double {
        computeMinimumDiameter()
        return minWidth
    }

    public mutating func getDiameter() -> LineString {
        computeMinimumDiameter()
        guard let w = minWidthPt else { return inputGeom.factory.createLineString() }
        return inputGeom.factory.createLineString([minBaseSeg!.project(w), w])
    }

    mutating func computeMinimumDiameter() {
        if computed { return }
        computed = true
        if isConvex {
            computeWidthConvex(inputGeom)
        } else {
            computeWidthConvex(ConvexHull(inputGeom).getConvexHull())
        }
    }

    mutating func computeWidthConvex(_ convexGeom: Geometry) {
        convexHullPts = (convexGeom as? Polygon)?.shell.points ?? convexGeom.getCoordinates()
        if convexHullPts.isEmpty {
            minWidth = 0.0
            minWidthPt = nil
            minBaseSeg = nil
        } else if convexHullPts.count == 1 {
            minWidth = 0.0
            minWidthPt = convexHullPts[0]
            minBaseSeg = LineSegment(convexHullPts[0], convexHullPts[0])
        } else if convexHullPts.count == 2 || convexHullPts.count == 3 {
            minWidth = 0.0
            minWidthPt = convexHullPts[0]
            minBaseSeg = LineSegment(convexHullPts[0], convexHullPts[1])
        } else {
            computeConvexRingMinDiameter(convexHullPts)
        }
    }

    mutating func computeConvexRingMinDiameter(_ pts: [Coordinate]) {
        minWidth = Double.greatestFiniteMagnitude
        var currMaxIndex = 1
        for i in 0..<(pts.count - 1) {
            let seg = LineSegment(pts[i], pts[i + 1])
            currMaxIndex = findMaxPerpDistance(pts, seg, currMaxIndex)
        }
    }

    mutating func findMaxPerpDistance(_ pts: [Coordinate], _ seg: LineSegment, _ startIndex: Int) -> Int {
        var maxPerpDistance = seg.distancePerpendicular(pts[startIndex])
        var nextPerpDistance = maxPerpDistance
        var maxIndex = startIndex
        var nextIndex = maxIndex
        while nextPerpDistance >= maxPerpDistance {
            maxPerpDistance = nextPerpDistance
            maxIndex = nextIndex
            nextIndex = MinimumDiameter.nextIndex(pts, maxIndex)
            if nextIndex == startIndex { break }
            nextPerpDistance = seg.distancePerpendicular(pts[nextIndex])
        }
        if maxPerpDistance < minWidth {
            minPtIndex = maxIndex
            minWidth = maxPerpDistance
            minWidthPt = pts[minPtIndex]
            minBaseSeg = seg
        }
        return maxIndex
    }

    static func nextIndex(_ pts: [Coordinate], _ index: Int) -> Int {
        let i = index + 1
        return i >= pts.count ? 0 : i
    }

    public mutating func getMinimumRectangle() -> Geometry {
        computeMinimumDiameter()
        let f = inputGeom.factory
        guard let base = minBaseSeg else { return f.createPolygon() }
        if minWidth == 0.0 {
            if base.p0.equals2D(base.p1) { return f.createPoint(base.p0) }
            return computeMaximumLine(convexHullPts, f)
        }
        let dx = base.p1.x - base.p0.x
        let dy = base.p1.y - base.p0.y
        var minPara = Double.greatestFiniteMagnitude, maxPara = -Double.greatestFiniteMagnitude
        var minPerp = Double.greatestFiniteMagnitude, maxPerp = -Double.greatestFiniteMagnitude
        for p in convexHullPts {
            let paraC = MinimumDiameter.computeC(dx, dy, p)
            if paraC > maxPara { maxPara = paraC }
            if paraC < minPara { minPara = paraC }
            let perpC = MinimumDiameter.computeC(-dy, dx, p)
            if perpC > maxPerp { maxPerp = perpC }
            if perpC < minPerp { minPerp = perpC }
        }
        let maxPerpLine = Rectangle.createLineForStandardEquation(-dx, -dy, maxPerp)
        let minPerpLine = Rectangle.createLineForStandardEquation(-dx, -dy, minPerp)
        let maxParaLine = Rectangle.createLineForStandardEquation(-dy, dx, maxPara)
        let minParaLine = Rectangle.createLineForStandardEquation(-dy, dx, minPara)
        let p0 = maxParaLine.lineIntersection(maxPerpLine)!
        let p1 = minParaLine.lineIntersection(maxPerpLine)!
        let p2 = minParaLine.lineIntersection(minPerpLine)!
        let p3 = maxParaLine.lineIntersection(minPerpLine)!
        return f.createPolygon(f.createLinearRing([p0, p1, p2, p3, p0]))
    }

    static func computeC(_ a: Double, _ b: Double, _ p: Coordinate) -> Double { fusedSub(a, p.y, b * p.x) }
}
